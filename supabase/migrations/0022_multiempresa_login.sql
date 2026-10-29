-- =============================================================================
-- OPERALIA · 0022 · VARIAS EMPRESAS: CÓDIGO DE EMPRESA EN EL LOGIN
-- -----------------------------------------------------------------------------
--   * companies: code (único, [a-z0-9-]), status ('active' | 'suspended') y
--     plan. Solo se cambian desde el SQL Editor (modo sistema).
--   * El usuario es único por empresa: (company_id, lower(username)).
--   * Correo interno de Auth: usuario@<code>.operalia.local (antes
--     usuario@operalia.local). Se migran las cuentas existentes.
--   * handle_new_auth_user liga por usuario Y empresa; admin_set_password arma
--     el correo con el código de la empresa; request_password_reset recibe
--     (código de empresa, usuario).
--   * Empresa suspendida: las funciones auth_* devuelven null, así que RLS
--     corta todo el acceso sin borrar datos.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. EMPRESAS ────────────────────────────────────────────────────────────
alter table public.companies add column if not exists code text;
alter table public.companies add column if not exists status text not null default 'active';
alter table public.companies add column if not exists plan text not null default 'basico';

update public.companies set code = 'gatopelon'
 where id = 'c0000000-0000-4000-8000-000000000001' and code is null;
-- Cualquier otra empresa sin código recibe uno provisional (cámbialo en el SQL Editor).
update public.companies set code = 'empresa-' || left(id::text, 8) where code is null;
alter table public.companies alter column code set not null;

do $$ begin
  alter table public.companies add constraint companies_code_chk check (code ~ '^[a-z0-9-]+$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.companies add constraint companies_status_chk check (status in ('active','suspended'));
exception when duplicate_object then null; end $$;
create unique index if not exists companies_code_key on public.companies (code);

-- Código, estado y plan los administra la plataforma, no el cliente.
create or replace function public.tg_company_platform_guard()
returns trigger language plpgsql as $$
begin
  if not public.is_system_context()
     and (new.code, new.status, new.plan) is distinct from (old.code, old.status, old.plan) then
    raise exception 'El código, estado y plan de la empresa solo se cambian desde la plataforma';
  end if;
  return new;
end $$;
drop trigger if exists trg_company_platform_guard on public.companies;
create trigger trg_company_platform_guard before update on public.companies
  for each row execute function public.tg_company_platform_guard();

-- ─── 2. USUARIO ÚNICO POR EMPRESA ───────────────────────────────────────────
drop index if exists public.employees_username_lower_key;
create unique index if not exists employees_company_username_key on public.employees (company_id, lower(username));

-- ─── 3. CORREO INTERNO DE AUTH ──────────────────────────────────────────────
create or replace function public.employee_auth_email(p_company_id uuid, p_username text)
returns text language sql stable security definer set search_path = public as $$
  select lower(trim(p_username)) || '@' || c.code || '.operalia.local'
  from public.companies c where c.id = p_company_id
$$;
revoke all on function public.employee_auth_email(uuid, text) from public, anon, authenticated;

-- Liga la cuenta nueva con su empleado:
--   usuario@<code>.operalia.local → por usuario dentro de esa empresa;
--   correo real → por el correo registrado (o por usuario si es único).
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_local  text := lower(split_part(new.email, '@', 1));
  v_domain text := lower(split_part(new.email, '@', 2));
begin
  if v_domain like '%.operalia.local' then
    update public.employees e
       set user_id = new.id, email = coalesce(e.email, new.email)
      from public.companies c
     where c.id = e.company_id and c.code = left(v_domain, length(v_domain) - length('.operalia.local'))
       and lower(e.username) = v_local and e.user_id is null and e.status = 'active';
  elsif v_domain <> 'operalia.local' then
    update public.employees
       set user_id = new.id
     where lower(email) = lower(new.email) and user_id is null and status = 'active';
    if not found then
      update public.employees
         set user_id = new.id, email = coalesce(email, new.email)
       where lower(username) = v_local and user_id is null and status = 'active'
         and (select count(*) from public.employees x
               where lower(x.username) = v_local and x.user_id is null and x.status = 'active') = 1;
    end if;
  end if;
  -- usuario@operalia.local (formato anterior, sin empresa): no se liga.
  return new;
end $$;

-- admin_set_password (0012) arma el correo con el código de la empresa.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.admin_set_password(uuid, text)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');
  if position('employee_auth_email' in v_src) = 0 then
    v_src := replace(v_src, 'v_email := lower(t.username) || ''@operalia.local'';',
                            'v_email := public.employee_auth_email(t.company_id, t.username);');
    if position('employee_auth_email' in v_src) = 0 then
      raise exception 'No se pudo actualizar admin_set_password: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- «Olvidé mi contraseña» desde el login: ahora con el código de empresa.
drop function if exists public.request_password_reset(text);
create or replace function public.request_password_reset(p_company_code text, p_username text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t      public.employees%rowtype;
  ag     record;
  v_link text;
begin
  select e.* into t from public.employees e
  join public.companies c on c.id = e.company_id
  where c.code = lower(trim(coalesce(p_company_code, ''))) and c.status = 'active'
    and lower(e.username) = lower(split_part(trim(coalesce(p_username, '')), '@', 1))
    and e.status = 'active'
  limit 1;
  if not found then return; end if;

  v_link := '/employees?reset=' || t.id;
  if exists (select 1 from public.notifications
             where link = v_link and created_at > now() - interval '15 minutes') then
    return;
  end if;

  for ag in
    select distinct e.id from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = t.company_id and e.status = 'active' and e.id <> t.id
      and (e.is_owner
        or (r.code = 'admin' and not t.is_owner)
        or (exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'manage_employees')
            and r.scope = 'branch' and e.branch_id = t.branch_id
            and (select r2.scope from public.roles r2 where r2.id = t.role_id) not in ('company')))
  loop
    perform public.notify_employee(ag.id, 'password', 'Solicitud de contraseña: ' || t.full_name,
      '@' || t.username || ' olvidó su contraseña. Asígnale una temporal.', v_link);
  end loop;
end $$;
revoke all on function public.request_password_reset(text, text) from public;
grant execute on function public.request_password_reset(text, text) to anon, authenticated;

-- Migración de cuentas: usuario@operalia.local → usuario@<code>.operalia.local
-- (la empresa del empleado ligado; si la cuenta no está ligada, Gato Pelón).
do $$
declare v_prev text;
begin
  v_prev := public.set_bypass('on');
  update auth.users u
     set email = split_part(u.email, '@', 1) || '@'
                 || coalesce((select c.code from public.employees e join public.companies c on c.id = e.company_id
                               where e.user_id = u.id limit 1), 'gatopelon') || '.operalia.local',
         raw_user_meta_data = case when u.raw_user_meta_data ? 'email'
           then jsonb_set(u.raw_user_meta_data, '{email}', to_jsonb(split_part(u.email, '@', 1) || '@'
                 || coalesce((select c.code from public.employees e join public.companies c on c.id = e.company_id
                               where e.user_id = u.id limit 1), 'gatopelon') || '.operalia.local'))
           else u.raw_user_meta_data end,
         updated_at = now()
   where lower(u.email) like '%@operalia.local';

  update auth.identities i
     set identity_data = jsonb_set(i.identity_data, '{email}', to_jsonb(u.email)),
         updated_at = now()
    from auth.users u
   where u.id = i.user_id and i.provider = 'email'
     and lower(i.identity_data ->> 'email') like '%@operalia.local';

  update public.employees e
     set email = split_part(e.email, '@', 1) || '@' || c.code || '.operalia.local'
    from public.companies c
   where c.id = e.company_id and lower(e.email) like '%@operalia.local';
  perform public.set_bypass(v_prev);
end $$;

-- ─── 4. EMPRESA SUSPENDIDA = SIN ACCESO ─────────────────────────────────────
-- Todas las funciones auth_* parten del empleado de la sesión en una empresa activa.
create or replace function public.auth_employee_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_company_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.company_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_branch_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.branch_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_department_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.department_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_scope()
returns text language sql stable security definer set search_path = public as $$
  select r.scope
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_code()
returns text language sql stable security definer set search_path = public as $$
  select r.code
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.my_permissions()
returns setof text language sql stable security definer set search_path = public as $$
  with me as (
    select e.id, e.role_id from public.employees e
    join public.companies c on c.id = e.company_id and c.status = 'active'
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

create or replace function public.auth_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.is_owner from public.employees e
                   join public.companies c on c.id = e.company_id and c.status = 'active'
                   where e.user_id = auth.uid() and e.status = 'active' limit 1), false)
$$;

-- Perfil (0015) + código de empresa. Con la empresa suspendida no hay perfil.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name, 'company_code', c.code,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;
