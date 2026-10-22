-- =============================================================================
-- OPERALIA · 0002 · FUNCIONES AUXILIARES DE SEGURIDAD
-- -----------------------------------------------------------------------------
-- Objetivo: responder "¿quién es el usuario que hace la petición?" y "¿qué
-- puede ver/hacer?". Las usan las políticas RLS (0005), los triggers (0003) y
-- el frontend (vía supabase.rpc).
--
-- Todas son SECURITY DEFINER: se ejecutan con permisos del dueño para poder
-- leer employees/roles sin caer en recursión de RLS. Solo devuelven datos del
-- propio usuario (auth.uid()), así que no filtran información de otros.
--
-- auth.uid() es NULL cuando el SQL se ejecuta desde el SQL Editor / service
-- role (por ejemplo, al sembrar datos). Los triggers usan eso para saber que
-- están en "modo sistema" y no validar permisos.
-- =============================================================================

-- Empleado activo ligado a la sesión actual.
create or replace function public.auth_employee_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_company_id()
returns uuid language sql stable security definer set search_path = public as $$
  select company_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_branch_id()
returns uuid language sql stable security definer set search_path = public as $$
  select branch_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_department_id()
returns uuid language sql stable security definer set search_path = public as $$
  select department_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

-- Alcance del rol: 'company' | 'branch' | 'department' | 'self'.
create or replace function public.auth_role_scope()
returns text language sql stable security definer set search_path = public as $$
  select r.scope
  from public.employees e join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_code()
returns text language sql stable security definer set search_path = public as $$
  select r.code
  from public.employees e join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

-- Permisos efectivos = permisos del rol + concedidos al empleado − revocados.
create or replace function public.my_permissions()
returns setof text language sql stable security definer set search_path = public as $$
  with me as (
    select e.id, e.role_id from public.employees e
    where e.user_id = auth.uid() and e.status = 'active' limit 1
  )
  select rp.permission_code from public.role_permissions rp join me on me.role_id = rp.role_id
  where not exists (
    select 1 from public.employee_permissions ep
    where ep.employee_id = (select id from me)
      and ep.permission_code = rp.permission_code and not ep.is_granted)
  union
  select ep.permission_code from public.employee_permissions ep join me on me.id = ep.employee_id
  where ep.is_granted
$$;

create or replace function public.has_permission(p_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.my_permissions() as perm where perm = p_code)
$$;

-- ¿Puede ver datos de esta sucursal?
--   company → cualquier sucursal de su empresa; demás → solo la suya.
create or replace function public.can_access_branch(p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_branch_id is null then false
    when public.auth_role_scope() = 'company' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id())
    else p_branch_id = public.auth_branch_id()
  end
$$;

-- ¿Puede ver datos de este departamento en esta sucursal?
--   company/branch → basta con la sucursal.
--   department/self → su departamento o los asignados en employee_departments.
--   department_id null (registro general de la sucursal) → visible para la sucursal.
create or replace function public.can_access_department(p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when not public.can_access_branch(p_branch_id) then false
    when public.auth_role_scope() in ('company','branch') then true
    when p_department_id is null then true
    when p_department_id = public.auth_department_id() then true
    else exists (
      select 1 from public.employee_departments ed
      where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id)
  end
$$;

-- "Hoy" según la zona horaria de la empresa (evita desfases UTC en checklists).
create or replace function public.company_today(p_company_id uuid default null)
returns date language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce(
    (select timezone from public.companies where id = coalesce(p_company_id, public.auth_company_id())),
    'America/Tijuana'))::date
$$;

-- Perfil completo para el frontend en una sola llamada (supabase.rpc('get_my_profile')).
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
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

-- Solo usuarios autenticados pueden llamar estas funciones vía API.
do $$
declare fn text;
begin
  foreach fn in array array[
    'auth_employee_id()','auth_company_id()','auth_branch_id()','auth_department_id()',
    'auth_role_scope()','auth_role_code()','my_permissions()','has_permission(text)',
    'can_access_branch(uuid)','can_access_department(uuid, uuid)','company_today(uuid)',
    'get_my_profile()']
  loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Valores por defecto: company_id se llena solo con la empresa del usuario.
-- Así el frontend no tiene que enviarla (y RLS verifica que sea la suya).
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_name = c.table_name and tb.table_schema = c.table_schema
    where c.table_schema = 'public' and c.column_name = 'company_id'
      and tb.table_type = 'BASE TABLE' and c.table_name not in ('companies','audit_logs')
  loop
    execute format('alter table public.%I alter column company_id set default public.auth_company_id()', t);
  end loop;
end $$;
