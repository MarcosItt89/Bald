-- =============================================================================
-- OPERALIA · 0020 · HUECOS EN ANAQUEL (FALTANTES EN PISO)
-- -----------------------------------------------------------------------------
--   * shelf_gaps: el empleado escanea un producto que no está en piso.
--     report_shelf_gap(sucursal, producto) cruza con inventory.stock:
--       - hay existencia → tarea a Almacén «Surtir a piso: <producto>»
--         (tasks.source_type = 'shelf_gap') y aviso al departamento;
--       - no hay → sugiere pedido; create_order_from_shelf_gap lo crea.
--     Un mismo producto no abre dos huecos en la sucursal: si ya hay uno
--     abierto se suma el reporte (report_count).
--   * Se cierra solo: al completar la tarea o al recibir/cerrar el pedido.
--     Quien gestiona huecos también puede resolverlos o descartarlos.
--   * Permisos: report_shelf_gaps (reportar) y manage_shelf_gaps (ver los de
--     toda la sucursal y cerrarlos).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.shelf_gaps (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  branch_id         uuid not null references public.branches(id) on delete cascade,
  department_id     uuid references public.departments(id) on delete set null,
  product_id        uuid not null references public.products(id) on delete cascade,
  system_stock      numeric(12,3) not null default 0,  -- existencia al reportar
  has_stock         boolean not null,                  -- «hay en bodega, no en piso»
  status            text not null default 'open' check (status in ('open','resolved','dismissed')),
  task_id           uuid references public.tasks(id) on delete set null,
  order_id          uuid references public.orders(id) on delete set null,
  notes             text,
  report_count      integer not null default 1,
  reported_by       uuid references public.employees(id) on delete set null,
  reported_at       timestamptz not null default now(),
  last_reported_at  timestamptz not null default now(),
  resolved_by       uuid references public.employees(id) on delete set null,
  resolved_at       timestamptz,
  updated_at        timestamptz not null default now()
);
create unique index if not exists shelf_gaps_open_uidx on public.shelf_gaps (branch_id, product_id) where status = 'open';
create index if not exists shelf_gaps_branch_idx on public.shelf_gaps (branch_id, reported_at desc);

drop trigger if exists trg_updated_at on public.shelf_gaps;
create trigger trg_updated_at before update on public.shelf_gaps
  for each row execute function public.tg_set_updated_at();

insert into public.permissions (code, module, name, description) values
  ('report_shelf_gaps', 'Inventario', 'Reportar huecos en anaquel', 'Escanear productos que no están en piso'),
  ('manage_shelf_gaps', 'Inventario', 'Gestionar huecos en anaquel', 'Ver los huecos de la sucursal, resolverlos o descartarlos')
on conflict (code) do nothing;

-- ─── RLS ────────────────────────────────────────────────────────────────────
-- Solo lectura: se escriben con las funciones de abajo.
alter table public.shelf_gaps enable row level security;
drop policy if exists shelf_gaps_select on public.shelf_gaps;
create policy shelf_gaps_select on public.shelf_gaps for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
    reported_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_shelf_gaps')) and public.can_access_branch(branch_id))
    or ((select public.has_permission('view_reports')) and public.can_access_department(branch_id, department_id))));
grant select on public.shelf_gaps to authenticated;

-- «Surtir a piso» no lleva responsable: la puede cerrar cualquiera de Almacén
-- con manage_shelf_gaps (trg_task_rules le deja cambiar solo el estado).
drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = (select public.auth_employee_id())
      or ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id))
      or (source_type = 'shelf_gap' and (select public.has_permission('manage_shelf_gaps'))
          and public.can_access_department(branch_id, department_id)))
  with check (company_id = (select public.auth_company_id()));

-- ─── REPORTE ────────────────────────────────────────────────────────────────
create or replace function public.report_shelf_gap(p_branch_id uuid, p_product_id uuid, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prod    public.products%rowtype;
  v_inv     public.inventory%rowtype;
  v_gap     public.shelf_gaps%rowtype;
  v_stock   numeric := 0;
  v_alm     uuid;
  v_task    uuid;
  v_prev    text;
  v_repeat  boolean := false;
begin
  if not public.has_permission('report_shelf_gaps') or not public.can_access_branch(p_branch_id) then
    raise exception 'No puedes reportar huecos en esta sucursal';
  end if;
  select * into v_prod from public.products where id = p_product_id and company_id = public.auth_company_id();
  if not found then raise exception 'Producto no encontrado'; end if;

  select * into v_inv from public.inventory where branch_id = p_branch_id and product_id = p_product_id;
  v_stock := coalesce(v_inv.stock, 0);

  select * into v_gap from public.shelf_gaps
   where branch_id = p_branch_id and product_id = p_product_id and status = 'open' for update;
  if found then
    v_repeat := true;
    update public.shelf_gaps
       set report_count = report_count + 1, last_reported_at = now(), system_stock = v_stock,
           has_stock = has_stock or v_stock > 0,
           notes = coalesce(nullif(trim(p_notes), ''), notes)
     where id = v_gap.id returning * into v_gap;
  else
    insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock, notes, reported_by)
    values (v_prod.company_id, p_branch_id, v_prod.department_id, p_product_id, v_stock, v_stock > 0,
            nullif(trim(p_notes), ''), public.auth_employee_id())
    returning * into v_gap;
  end if;

  -- Hay existencia: tarea a Almacén (una sola por hueco).
  if v_stock > 0 and v_gap.task_id is null then
    select id into v_alm from public.departments where company_id = v_prod.company_id and code = 'ALM' and is_active;
    v_prev := public.set_bypass('on');
    insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, source_type, source_id)
    values (v_prod.company_id, p_branch_id, coalesce(v_alm, v_prod.department_id),
            left('Surtir a piso: ' || v_prod.name, 200),
            'Hueco en anaquel reportado. Sistema: ' || trim_scale(v_stock)::text || ' ' || v_prod.unit
              || coalesce(' · ubicación ' || nullif(trim(v_inv.location), ''), '') || ' · SKU ' || v_prod.sku || '.'
              || coalesce(E'\nNota: ' || nullif(trim(p_notes), ''), ''),
            'high', public.company_today(v_prod.company_id), 'shelf_gap', v_gap.id)
    on conflict (source_type, source_id) where source_id is not null
    do update set status = 'pending', completed_at = null, completion_notes = null
    returning id into v_task;
    update public.shelf_gaps set task_id = v_task where id = v_gap.id;
    insert into public.notifications (company_id, employee_id, department_id, branch_id, type, title, body, link)
    select v_prod.company_id, null, coalesce(v_alm, v_prod.department_id), p_branch_id, 'task',
           'Surtir a piso: ' || v_prod.name, 'Hay ' || trim_scale(v_stock)::text || ' ' || v_prod.unit
             || ' en sistema y no está en anaquel.', '/tasks'
    where coalesce(v_alm, v_prod.department_id) is not null;
    perform public.set_bypass(v_prev);
    v_gap.task_id := v_task;
  end if;

  return jsonb_build_object(
    'gap_id', v_gap.id, 'repeat', v_repeat, 'has_stock', v_stock > 0, 'stock', v_stock, 'unit', v_prod.unit,
    'product_name', v_prod.name, 'task_id', v_gap.task_id, 'order_id', v_gap.order_id,
    'suggested_qty', greatest(coalesce(v_inv.max_stock, 0) - v_stock, coalesce(v_inv.min_stock, 0), 1));
end $$;
revoke all on function public.report_shelf_gap(uuid, uuid, text) from public, anon;
grant execute on function public.report_shelf_gap(uuid, uuid, text) to authenticated;

-- Sin existencia: pedido interno del departamento del producto.
create or replace function public.create_order_from_shelf_gap(p_gap_id uuid, p_quantity numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_gap   public.shelf_gaps%rowtype;
  v_name  text;
  v_order uuid;
begin
  select * into v_gap from public.shelf_gaps where id = p_gap_id for update;
  if not found or v_gap.company_id <> public.auth_company_id() then raise exception 'Hueco no encontrado'; end if;
  if not public.has_permission('create_orders') or not public.can_access_branch(v_gap.branch_id) then
    raise exception 'No puedes crear pedidos en esta sucursal';
  end if;
  if v_gap.status <> 'open' then raise exception 'Este hueco ya está cerrado'; end if;
  if v_gap.order_id is not null
     and exists (select 1 from public.orders o where o.id = v_gap.order_id and o.status not in ('rejected','cancelled')) then
    raise exception 'Este hueco ya tiene un pedido en curso';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Escribe la cantidad a pedir'; end if;

  select name into v_name from public.products where id = v_gap.product_id;
  insert into public.orders (company_id, branch_id, department_id, title, priority, notes)
  values (v_gap.company_id, v_gap.branch_id, v_gap.department_id, left('Faltante en anaquel: ' || v_name, 200), 'high',
          'Generado desde Huecos en anaquel: sin existencia en sistema.')
  returning id into v_order;
  insert into public.order_items (order_id, product_id, quantity) values (v_order, v_gap.product_id, p_quantity);
  update public.shelf_gaps set order_id = v_order where id = v_gap.id;
  return v_order;
end $$;
revoke all on function public.create_order_from_shelf_gap(uuid, numeric) from public, anon;
grant execute on function public.create_order_from_shelf_gap(uuid, numeric) to authenticated;

create or replace function public.close_shelf_gap(p_gap_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_gap  public.shelf_gaps%rowtype;
  v_prev text;
begin
  select * into v_gap from public.shelf_gaps where id = p_gap_id for update;
  if not found or v_gap.company_id <> public.auth_company_id() then raise exception 'Hueco no encontrado'; end if;
  if not public.has_permission('manage_shelf_gaps') or not public.can_access_branch(v_gap.branch_id) then
    raise exception 'No puedes cerrar huecos en esta sucursal';
  end if;
  if p_status not in ('resolved','dismissed') then raise exception 'Estado no válido'; end if;
  if v_gap.status <> 'open' then raise exception 'Este hueco ya está cerrado'; end if;
  update public.shelf_gaps set status = p_status, resolved_at = now(), resolved_by = public.auth_employee_id()
   where id = v_gap.id;
  -- La tarea «Surtir a piso» pendiente se cierra con el hueco.
  if v_gap.task_id is not null then
    v_prev := public.set_bypass('on');
    update public.tasks
       set status = case when p_status = 'resolved' then 'completed' else 'cancelled' end,
           completion_notes = case when p_status = 'resolved' then 'Hueco resuelto' else 'Hueco descartado' end
     where id = v_gap.task_id and status in ('pending','in_progress');
    perform public.set_bypass(v_prev);
  end if;
end $$;
revoke all on function public.close_shelf_gap(uuid, text) from public, anon;
grant execute on function public.close_shelf_gap(uuid, text) to authenticated;

-- ─── CIERRE AUTOMÁTICO ──────────────────────────────────────────────────────
-- Tarea completada → resuelto; tarea cancelada → descartado.
create or replace function public.tg_shelf_gap_task_done()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.source_type = 'shelf_gap' and new.status is distinct from old.status
     and new.status in ('completed','cancelled') then
    update public.shelf_gaps
       set status = case when new.status = 'completed' then 'resolved' else 'dismissed' end,
           resolved_at = now(), resolved_by = public.auth_employee_id()
     where id = new.source_id and status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists trg_shelf_gap_task_done on public.tasks;
create trigger trg_shelf_gap_task_done after update of status on public.tasks
  for each row execute function public.tg_shelf_gap_task_done();

-- Pedido recibido o cerrado → resuelto.
create or replace function public.tg_shelf_gap_order_done()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('received','closed') then
    update public.shelf_gaps set status = 'resolved', resolved_at = now(), resolved_by = public.auth_employee_id()
     where order_id = new.id and status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists trg_shelf_gap_order_done on public.orders;
create trigger trg_shelf_gap_order_done after update of status on public.orders
  for each row execute function public.tg_shelf_gap_order_done();

-- ─── VISTA ──────────────────────────────────────────────────────────────────
drop view if exists public.v_shelf_gaps;
create view public.v_shelf_gaps with (security_invoker = on) as
select g.*, p.sku, p.name as product_name, p.unit,
       (select string_agg(pb.barcode, ' ') from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       d.name as department_name, b.name as branch_name, i.location, i.stock as current_stock,
       er.full_name as reported_by_name, ev.full_name as resolved_by_name,
       t.status as task_status, o.folio as order_folio, o.status as order_status
from public.shelf_gaps g
join public.products p on p.id = g.product_id
join public.branches b on b.id = g.branch_id
left join public.departments d on d.id = g.department_id
left join public.inventory i on i.branch_id = g.branch_id and i.product_id = g.product_id
left join public.employees er on er.id = g.reported_by
left join public.employees ev on ev.id = g.resolved_by
left join public.tasks t on t.id = g.task_id
left join public.orders o on o.id = g.order_id;
grant select on public.v_shelf_gaps to authenticated;
