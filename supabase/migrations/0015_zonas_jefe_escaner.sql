-- =============================================================================
-- OPERALIA · 0015 · ZONAS, ALCANCE 'zone' Y OFERTAS POR ZONA
-- -----------------------------------------------------------------------------
--   1. zones + branches.zone_id. Las zonas demo y la asignación de sucursales
--      están en seed/0013_zonas_jefe_escaner.sql.
--   2. Alcance de rol 'zone' + employee_zones: un rol 'zone' ve todas las
--      sucursales de sus zonas, y dentro de ellas solo su(s) departamento(s)
--      (igual que el alcance 'department').
--      Revisado contra 0005 y posteriores: can_access_branch, empleados,
--      notificaciones por departamento, tickets, cambios de precio y guardas
--      de empleados.
--   3. price_changes.zone_id: el cambio aplica a las sucursales de esa zona.
--   4. branch_prices: precio por sucursal. Antes cualquier cambio (aunque fuera
--      de una sola sucursal) cambiaba products.price para todas las tiendas.
--      Ahora un cambio de sucursal o zona guarda el precio en branch_prices;
--      uno de toda la empresa sigue cambiando products.price.
--      v_inventory muestra el precio efectivo de cada sucursal.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. ZONAS ───────────────────────────────────────────────────────────────
create table if not exists public.zones (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  code        text not null,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, code)
);
alter table public.branches add column if not exists zone_id uuid references public.zones(id) on delete set null;
create index if not exists branches_zone_idx on public.branches (zone_id);

drop trigger if exists trg_updated_at on public.zones;
create trigger trg_updated_at before update on public.zones
  for each row execute function public.tg_set_updated_at();

-- ─── 2. ALCANCE 'zone' ──────────────────────────────────────────────────────
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.roles'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%scope%'
  loop
    execute format('alter table public.roles drop constraint %I', c);
  end loop;
  alter table public.roles add constraint roles_scope_check check (scope in ('company','zone','branch','department','self'));
end $$;

create table if not exists public.employee_zones (
  employee_id uuid not null references public.employees(id) on delete cascade,
  zone_id     uuid not null references public.zones(id) on delete cascade,
  primary key (employee_id, zone_id)
);
create index if not exists employee_zones_zone_idx on public.employee_zones (zone_id);

-- Zonas del usuario actual (solo aplica a roles con alcance 'zone').
create or replace function public.auth_zone_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select ez.zone_id from public.employee_zones ez where ez.employee_id = public.auth_employee_id()
$$;

-- ¿Puede ver datos de esta sucursal?
--   company → cualquier sucursal de su empresa
--   zone    → las sucursales de sus zonas
--   demás   → solo la suya
create or replace function public.can_access_branch(p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_branch_id is null then false
    when public.auth_role_scope() = 'company' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id())
    when public.auth_role_scope() = 'zone' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id()
        and b.zone_id in (select public.auth_zone_ids()))
    else p_branch_id = public.auth_branch_id()
  end
$$;
-- can_access_department no cambia: 'zone' cae en la rama de departamento
-- (su departamento o los de employee_departments) después de validar la sucursal.

-- Notificaciones por departamento: el jefe de zona las recibe de sus sucursales.
create or replace function public.is_my_notification(p_employee_id uuid, p_department_id uuid, p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_employee_id is not null then p_employee_id = public.auth_employee_id()
    else (p_branch_id is null or p_branch_id = public.auth_branch_id()
          or (public.auth_role_scope() = 'zone' and public.can_access_branch(p_branch_id)))
     and (p_department_id = public.auth_department_id()
          or exists (select 1 from public.employee_departments ed
                     where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id))
  end
$$;

-- Tickets: el jefe de zona ve los de su departamento en sus sucursales.
create or replace function public.can_view_ticket(p_created_by uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.auth_employee_id()
      or public.has_permission('manage_tickets')
      or (public.auth_role_scope() in ('company','zone','branch','department')
          and public.can_access_department(p_branch_id, p_department_id))
$$;

-- Empleados: el jefe de zona ve (y, si tiene permiso, gestiona) a los de sus sucursales.
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (select public.auth_role_scope()) = 'company'
      or branch_id = (select public.auth_branch_id())
      or ((select public.auth_role_scope()) = 'zone' and public.can_access_branch(branch_id))
      or user_id = (select auth.uid())));
drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees'))
         and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(branch_id)))
  with check (company_id = (select public.auth_company_id()));

-- Guarda de empleados: solo un administrador asigna roles de empresa o de zona.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.tg_employee_guard()'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');  -- por si se instaló desde un archivo con CRLF
  if position('v_target_scope = ''zone''' in v_src) = 0 then
    v_src := replace(v_src,
      'if v_target_scope = ''company'' and public.auth_role_scope() <> ''company'' then',
      'if v_target_scope = ''zone'' and public.auth_role_scope() <> ''company'' then
    raise exception ''Solo un administrador puede asignar roles con alcance de zona'';
  end if;
  if v_target_scope = ''company'' and public.auth_role_scope() <> ''company'' then');
    v_src := replace(v_src,
      'if public.auth_role_scope() <> ''company'' and new.branch_id is distinct from public.auth_branch_id() then',
      'if public.auth_role_scope() <> ''company'' and not public.can_access_branch(new.branch_id) then');
    execute v_src;
  end if;
end $$;

-- Zonas y asignaciones: lectura en la empresa; escritura con manage_branches / manage_employees.
alter table public.zones enable row level security;
drop policy if exists zones_select on public.zones;
create policy zones_select on public.zones for select to authenticated
  using (company_id = (select public.auth_company_id()));
drop policy if exists zones_write on public.zones;
create policy zones_write on public.zones for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

alter table public.employee_zones enable row level security;
drop policy if exists employee_zones_select on public.employee_zones;
create policy employee_zones_select on public.employee_zones for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
drop policy if exists employee_zones_write on public.employee_zones;
create policy employee_zones_write on public.employee_zones for all to authenticated
  using ((select public.has_permission('manage_employees')) and (select public.auth_role_scope()) = 'company'
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_employees')) and (select public.auth_role_scope()) = 'company'
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id()))
         and exists (select 1 from public.zones z where z.id = zone_id and z.company_id = (select public.auth_company_id())));

grant select, insert, update, delete on public.zones, public.employee_zones to authenticated;
grant execute on function public.auth_zone_ids() to authenticated;

-- Perfil: incluye las zonas del usuario.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;

-- ─── 3. CAMBIOS DE PRECIO POR ZONA ──────────────────────────────────────────
alter table public.price_changes add column if not exists zone_id uuid references public.zones(id) on delete set null;
do $$ begin
  alter table public.price_changes add constraint price_changes_scope_chk check (zone_id is null or branch_id is null);
exception when duplicate_object then null; end $$;

drop policy if exists price_changes_select on public.price_changes;
create policy price_changes_select on public.price_changes for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (branch_id is null and zone_id is null)
      or public.can_access_branch(branch_id)
      or (select public.auth_role_scope()) = 'company'
      or zone_id in (select public.auth_zone_ids())
      or exists (select 1 from public.branches b where b.id = (select public.auth_branch_id()) and b.zone_id = price_changes.zone_id)));
drop policy if exists price_changes_insert on public.price_changes;
create policy price_changes_insert on public.price_changes for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
              and (
                    (branch_id is null and zone_id is null and (select public.auth_role_scope()) = 'company')
                 or (zone_id is not null and ((select public.auth_role_scope()) = 'company' or zone_id in (select public.auth_zone_ids())))
                 or (branch_id is not null and public.can_access_branch(branch_id))));

-- ─── 4. PRECIO POR SUCURSAL ─────────────────────────────────────────────────
create table if not exists public.branch_prices (
  branch_id       uuid not null references public.branches(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  company_id      uuid not null references public.companies(id) on delete cascade,
  price           numeric(12,2) not null check (price > 0),
  previous_price  numeric(12,2),
  price_change_id uuid references public.price_changes(id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (branch_id, product_id)
);
alter table public.branch_prices enable row level security;
drop policy if exists branch_prices_select on public.branch_prices;
create policy branch_prices_select on public.branch_prices for select to authenticated
  using (company_id = (select public.auth_company_id()));
grant select on public.branch_prices to authenticated;

-- Precio vigente de un producto en una sucursal.
create or replace function public.effective_price(p_product_id uuid, p_branch_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select bp.price from public.branch_prices bp where bp.branch_id = p_branch_id and bp.product_id = p_product_id),
                  (select p.price from public.products p where p.id = p_product_id))
$$;
grant execute on function public.effective_price(uuid, uuid) to authenticated;

-- old_price = precio vigente en el alcance del cambio.
create or replace function public.tg_price_change_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.branch_id is not null then
    new.old_price := public.effective_price(new.product_id, new.branch_id);
  else
    select price into new.old_price from public.products where id = new.product_id;
  end if;
  if new.old_price is null then raise exception 'Producto no encontrado'; end if;
  if new.new_price = new.old_price then
    raise exception 'El precio nuevo es igual al actual (%)', new.old_price;
  end if;
  new.status := 'scheduled';
  new.applied_at := null;
  return new;
end $$;

create or replace function public.apply_price_change(p_price_change_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  pc     public.price_changes%rowtype;
  v_prev text;
begin
  select * into pc from public.price_changes where id = p_price_change_id for update;
  if not found or pc.status <> 'scheduled' then return; end if;

  v_prev := public.set_bypass('on');

  if pc.branch_id is null and pc.zone_id is null then
    -- Toda la empresa: precio base del producto.
    update public.products
       set previous_price = price, price = pc.new_price, price_updated_at = now()
     where id = pc.product_id;
  else
    -- Sucursal o zona: precio propio de cada sucursal afectada.
    insert into public.branch_prices (branch_id, product_id, company_id, price, previous_price, price_change_id, updated_at)
    select b.id, pc.product_id, pc.company_id, pc.new_price, public.effective_price(pc.product_id, b.id), pc.id, now()
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and (b.id = pc.branch_id or b.zone_id = pc.zone_id)
    on conflict (branch_id, product_id) do update
      set previous_price = public.branch_prices.price, price = excluded.price,
          price_change_id = excluded.price_change_id, updated_at = now();
  end if;

  update public.price_changes set status = 'applied', applied_at = now() where id = pc.id;

  if pc.requires_tag then
    update public.shelf_tags st
       set status = 'rejected', rejection_reason = 'Reemplazada por un cambio de precio más reciente'
     where st.product_id = pc.product_id and st.status in ('pending','printed')
       and ((pc.branch_id is null and pc.zone_id is null) or st.branch_id = pc.branch_id
            or st.branch_id in (select b.id from public.branches b where b.zone_id = pc.zone_id));

    insert into public.shelf_tags (company_id, branch_id, product_id, price_change_id)
    select pc.company_id, b.id, pc.product_id, pc.id
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and ((pc.branch_id is null and pc.zone_id is null) or b.id = pc.branch_id or b.zone_id = pc.zone_id);
  end if;

  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.apply_price_change(uuid) from public, anon, authenticated;

-- v_inventory con el precio efectivo de cada sucursal y su zona.
drop view if exists public.v_inventory;
create view public.v_inventory with (security_invoker = on) as
select i.id, i.company_id, i.branch_id, i.product_id, i.stock, i.min_stock, i.max_stock,
       i.location, i.status, i.last_movement_at, i.last_counted_at, i.updated_at,
       p.sku, p.name as product_name, p.category, p.unit,
       coalesce(bp.price, p.price) as price,
       case when bp.price is not null then bp.previous_price else p.previous_price end as previous_price,
       coalesce(bp.updated_at, p.price_updated_at) as price_updated_at,
       p.department_id, p.controls_expiration, p.status as product_status,
       d.name as department_name, b.name as branch_name, b.zone_id,
       (bp.price is not null) as has_branch_price,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       exists (select 1 from public.shelf_tags st
               where st.product_id = p.id and st.branch_id = i.branch_id
                 and st.status in ('pending','printed','placed')) as has_pending_tag
from public.inventory i
join public.products p on p.id = i.product_id
join public.branches b on b.id = i.branch_id
left join public.branch_prices bp on bp.branch_id = i.branch_id and bp.product_id = i.product_id
left join public.departments d on d.id = p.department_id;
grant select on public.v_inventory to authenticated;

-- v_price_changes con la zona.
drop view if exists public.v_price_changes;
create view public.v_price_changes with (security_invoker = on) as
select pc.*, p.sku, p.name as product_name, b.name as branch_name, z.name as zone_name,
       e.full_name as created_by_name,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id) as tags_total,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id and st.status = 'validated') as tags_validated
from public.price_changes pc
join public.products p on p.id = pc.product_id
left join public.branches b on b.id = pc.branch_id
left join public.zones z on z.id = pc.zone_id
left join public.employees e on e.id = pc.created_by;
grant select on public.v_price_changes to authenticated;
