-- =============================================================================
-- OPERALIA · 0019 · CONTEO CÍCLICO DE INVENTARIO
-- -----------------------------------------------------------------------------
--   * cycle_count_plans: qué contar (sucursal + departamento o categoría,
--     opcionales), cada cuándo y cuántos productos por conteo.
--   * cycle_count_tasks: una tarea por plan y día con una lista corta
--     (cycle_count_items). Orden de prioridad:
--       1. productos con más diferencias en conteos de los últimos 90 días;
--       2. mayor rotación (salidas y mermas de los últimos 30 días);
--       3. los que llevan más tiempo sin contarse.
--     Se generan con generate_cycle_counts (lo llama run_daily_maintenance,
--     que pg_cron corre cada hora desde 0012).
--   * record_cycle_count(item, cantidad): conteo a ciegas. Registra un
--     movimiento 'count' (deja la existencia en lo contado) y guarda la
--     diferencia en piezas y en pesos (unit_cost de 0014).
--   * Permisos: perform_cycle_counts (contar) y manage_cycle_counts (planes).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.cycle_count_plans (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete set null,
  category         text,
  name             text not null,
  frequency        text not null default 'daily' check (frequency in ('daily','weekdays','weekly')),
  weekday          smallint check (weekday between 0 and 6),
  items_per_count  integer not null default 10 check (items_per_count between 1 and 100),
  is_active        boolean not null default true,
  created_by       uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (frequency <> 'weekly' or weekday is not null)
);

create table if not exists public.cycle_count_tasks (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  plan_id          uuid not null references public.cycle_count_plans(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete set null,
  scheduled_date   date not null,
  status           text not null default 'pending' check (status in ('pending','in_progress','completed','cancelled')),
  items_total      integer not null default 0,
  items_counted    integer not null default 0,
  items_with_diff  integer not null default 0,
  diff_value       numeric(12,2) not null default 0,
  started_at       timestamptz,
  completed_at     timestamptz,
  completed_by     uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (plan_id, scheduled_date)
);
create index if not exists cycle_count_tasks_branch_idx on public.cycle_count_tasks (branch_id, scheduled_date);

create table if not exists public.cycle_count_items (
  id                uuid primary key default gen_random_uuid(),
  task_id           uuid not null references public.cycle_count_tasks(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  position          integer not null,
  priority_reason   text not null check (priority_reason in ('differences','rotation','oldest')),
  expected_qty      numeric(12,3),
  counted_qty       numeric(12,3),
  difference        numeric(12,3),
  difference_value  numeric(12,2),
  movement_id       uuid references public.inventory_movements(id) on delete set null,
  counted_by        uuid references public.employees(id) on delete set null,
  counted_at        timestamptz,
  unique (task_id, product_id)
);
create index if not exists cycle_count_items_product_idx on public.cycle_count_items (product_id, counted_at);

do $$
declare t text;
begin
  foreach t in array array['cycle_count_plans','cycle_count_tasks'] loop
    execute format('drop trigger if exists trg_updated_at on public.%I', t);
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;
drop trigger if exists trg_actor on public.cycle_count_plans;
create trigger trg_actor before insert on public.cycle_count_plans
  for each row execute function public.tg_set_actor('created_by');

insert into public.permissions (code, module, name, description) values
  ('perform_cycle_counts', 'Inventario', 'Hacer conteos cíclicos', 'Contar los productos de las tareas de conteo del día'),
  ('manage_cycle_counts',  'Inventario', 'Planear conteos cíclicos', 'Crear planes de conteo cíclico y ver diferencias')
on conflict (code) do nothing;

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.cycle_count_plans enable row level security;
alter table public.cycle_count_tasks enable row level security;
alter table public.cycle_count_items enable row level security;

drop policy if exists cycle_plans_select on public.cycle_count_plans;
create policy cycle_plans_select on public.cycle_count_plans for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_department(branch_id, department_id));
drop policy if exists cycle_plans_write on public.cycle_count_plans;
create policy cycle_plans_write on public.cycle_count_plans for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_cycle_counts'))
         and public.can_access_branch(branch_id))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_cycle_counts'))
         and public.can_access_branch(branch_id));

-- Tareas y renglones solo se leen; se escriben con las funciones de abajo.
drop policy if exists cycle_tasks_select on public.cycle_count_tasks;
create policy cycle_tasks_select on public.cycle_count_tasks for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_department(branch_id, department_id)
         and ((select public.has_permission('perform_cycle_counts')) or (select public.has_permission('manage_cycle_counts'))
              or (select public.has_permission('view_reports'))));
drop policy if exists cycle_items_select on public.cycle_count_items;
create policy cycle_items_select on public.cycle_count_items for select to authenticated
  using (exists (select 1 from public.cycle_count_tasks t where t.id = task_id
                 and t.company_id = (select public.auth_company_id())
                 and public.can_access_department(t.branch_id, t.department_id)));

grant select, insert, update, delete on public.cycle_count_plans to authenticated;
grant select on public.cycle_count_tasks, public.cycle_count_items to authenticated;

-- ─── GENERACIÓN ─────────────────────────────────────────────────────────────
create or replace function public.generate_cycle_counts(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  pl     record;
  v_task uuid;
  v_n    int;
  v_made int := 0;
begin
  for pl in
    select * from public.cycle_count_plans p
    where p.company_id = p_company_id and p.is_active
      and exists (select 1 from public.branches b where b.id = p.branch_id and b.status = 'active')
      and (p.frequency = 'daily'
        or (p.frequency = 'weekdays' and extract(isodow from p_date) < 6)
        or (p.frequency = 'weekly' and extract(dow from p_date) = p.weekday))
      and not exists (select 1 from public.cycle_count_tasks t where t.plan_id = p.id and t.scheduled_date = p_date)
  loop
    insert into public.cycle_count_tasks (company_id, plan_id, branch_id, department_id, scheduled_date)
    values (pl.company_id, pl.id, pl.branch_id, pl.department_id, p_date)
    on conflict (plan_id, scheduled_date) do nothing
    returning id into v_task;
    if v_task is null then continue; end if;

    insert into public.cycle_count_items (task_id, product_id, position, priority_reason)
    select v_task, c.product_id, row_number() over (order by c.diffs desc, c.rotation desc, c.last_counted_at nulls first, c.name),
           case when c.diffs > 0 then 'differences' when c.rotation > 0 then 'rotation' else 'oldest' end
    from (
      select i.product_id, p.name, i.last_counted_at,
             (select count(*) from public.cycle_count_items ci join public.cycle_count_tasks ct on ct.id = ci.task_id
               where ci.product_id = i.product_id and ct.branch_id = pl.branch_id
                 and ci.difference <> 0 and ci.counted_at > now() - interval '90 days') as diffs,
             coalesce((select sum(m.quantity) from public.inventory_movements m
               where m.product_id = i.product_id and m.branch_id = pl.branch_id
                 and m.movement_type in ('out','waste','transfer_out') and m.created_at > now() - interval '30 days'), 0) as rotation
      from public.inventory i
      join public.products p on p.id = i.product_id and p.status = 'active'
      where i.branch_id = pl.branch_id
        and (pl.department_id is null or p.department_id = pl.department_id)
        and (pl.category is null or p.category ilike pl.category)
        -- No repetir lo contado en los últimos 3 días.
        and (i.last_counted_at is null or i.last_counted_at < now() - interval '3 days')
      order by diffs desc, rotation desc, i.last_counted_at nulls first, p.name
      limit pl.items_per_count
    ) c;
    get diagnostics v_n = row_count;
    update public.cycle_count_tasks set items_total = v_n where id = v_task;
    v_made := v_made + 1;
  end loop;
  return v_made;
end $$;
revoke all on function public.generate_cycle_counts(uuid, date) from public, anon, authenticated;

-- ─── CAPTURA (conteo a ciegas) ──────────────────────────────────────────────
create or replace function public.record_cycle_count(p_item_id uuid, p_counted numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  it     public.cycle_count_items%rowtype;
  tk     public.cycle_count_tasks%rowtype;
  mv     public.inventory_movements%rowtype;
  v_diff numeric;
begin
  select * into it from public.cycle_count_items where id = p_item_id for update;
  if not found then raise exception 'Producto de conteo no encontrado'; end if;
  select * into tk from public.cycle_count_tasks where id = it.task_id for update;
  if tk.company_id <> public.auth_company_id() or not public.has_permission('perform_cycle_counts')
     or not public.can_access_department(tk.branch_id, tk.department_id) then
    raise exception 'No puedes capturar este conteo';
  end if;
  if tk.status in ('completed','cancelled') then raise exception 'Este conteo ya está cerrado'; end if;
  if p_counted is null or p_counted < 0 then raise exception 'Escribe la cantidad contada (0 o más)'; end if;

  insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity, reason, reference_type, reference_id)
  values (tk.company_id, tk.branch_id, it.product_id, 'count', p_counted, 'Conteo cíclico', 'cycle_count_item', it.id)
  returning * into mv;

  -- Si se recuenta, la diferencia se mide contra lo esperado del primer conteo.
  v_diff := p_counted - coalesce(it.expected_qty, mv.stock_before);
  update public.cycle_count_items
     set expected_qty = coalesce(expected_qty, mv.stock_before),
         counted_qty = p_counted, difference = v_diff,
         difference_value = round(v_diff * coalesce(mv.unit_cost, 0), 2),
         movement_id = mv.id, counted_by = public.auth_employee_id(), counted_at = now()
   where id = it.id;

  update public.cycle_count_tasks t
     set items_counted   = x.counted,
         items_with_diff = x.with_diff,
         diff_value      = x.value,
         status          = case when x.counted >= t.items_total then 'completed' else 'in_progress' end,
         started_at      = coalesce(t.started_at, now()),
         completed_at    = case when x.counted >= t.items_total then now() end,
         completed_by    = case when x.counted >= t.items_total then public.auth_employee_id() end
    from (select count(*) filter (where counted_at is not null) as counted,
                 count(*) filter (where difference <> 0) as with_diff,
                 coalesce(sum(difference_value), 0) as value
            from public.cycle_count_items where task_id = tk.id) x
   where t.id = tk.id;

  return jsonb_build_object('difference', v_diff, 'difference_value', round(v_diff * coalesce(mv.unit_cost, 0), 2));
end $$;
revoke all on function public.record_cycle_count(uuid, numeric) from public, anon;
grant execute on function public.record_cycle_count(uuid, numeric) to authenticated;

-- Conteo a ciegas: quien solo cuenta no ve existencia ni diferencias; con
-- manage_cycle_counts (o manage_inventory) se ven completas.
create or replace view public.v_cycle_count_items with (security_invoker = on) as
select ci.id, ci.task_id, ci.product_id, ci.position, ci.priority_reason, ci.counted_qty, ci.counted_at,
       p.sku, p.name as product_name, p.unit, p.category,
       (select string_agg(pb.barcode, ' ') from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       e.full_name as counted_by_name,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.expected_qty end as expected_qty,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.difference end as difference,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.difference_value end as difference_value
from public.cycle_count_items ci
join public.products p on p.id = ci.product_id
left join public.employees e on e.id = ci.counted_by;
grant select on public.v_cycle_count_items to authenticated;

create or replace view public.v_cycle_count_tasks with (security_invoker = on) as
select t.*, pl.name as plan_name, pl.category, b.name as branch_name, d.name as department_name,
       e.full_name as completed_by_name
from public.cycle_count_tasks t
join public.cycle_count_plans pl on pl.id = t.plan_id
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees e on e.id = t.completed_by;
grant select on public.v_cycle_count_tasks to authenticated;

-- El mantenimiento diario genera los conteos del día (pg_cron lo corre cada hora).
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure) into v_src;
  if position('generate_cycle_counts' in v_src) = 0 then
    v_src := replace(v_src,
      '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(',
      '  perform public.generate_cycle_counts(v_company, v_today);' || chr(10)
      || '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(');
    if position('generate_cycle_counts' in v_src) = 0 then
      raise exception 'No se pudo extender run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;
