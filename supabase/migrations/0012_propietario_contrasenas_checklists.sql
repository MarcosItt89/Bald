-- =============================================================================
-- OPERALIA · 0012 · PROPIETARIO, CONTRASEÑAS, CHECKLISTS DIARIOS
-- -----------------------------------------------------------------------------
-- Sin tablas nuevas. Incluye:
--   1. employees.is_owner: gatopelon es el administrador más alto.
--      Nadie más puede editarlo, y solo él gestiona a otros administradores.
--      El rol admin siempre tiene todos los permisos.
--   2. Contraseñas:
--      * admin_set_password: admin o gerente pone una contraseña temporal
--        (o crea la cuenta si el empleado no tiene); al entrar se pide cambiarla.
--      * request_password_reset: "Olvidé mi contraseña" desde el login avisa
--        al propietario, administradores y gerente de la sucursal.
--   3. pg_cron: genera los checklists de cada día automáticamente (cada hora).
--   4. (Movido a seed_company_base en 0023: 4 checklists nuevos.)
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. PROPIETARIO ─────────────────────────────────────────────────────────
alter table public.employees add column if not exists is_owner boolean not null default false;
create unique index if not exists employees_one_owner_idx on public.employees (company_id) where is_owner;

do $$
declare v_prev text;
begin
  if not exists (select 1 from public.employees where is_owner) then
    v_prev := public.set_bypass('on');
    update public.employees set is_owner = true where username = 'gatopelon';
    perform public.set_bypass(v_prev);
  end if;
end $$;

create or replace function public.auth_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.is_owner from public.employees e
                   where e.user_id = auth.uid() and e.status = 'active' limit 1), false)
$$;
grant execute on function public.auth_is_owner() to authenticated;

create or replace function public.tg_employee_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_admin_role boolean;
begin
  if public.is_system_context() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    if old.is_owner then raise exception 'La cuenta propietaria no se puede eliminar'; end if;
    return old;
  end if;

  if (tg_op = 'INSERT' and new.is_owner) or (tg_op = 'UPDATE' and new.is_owner is distinct from old.is_owner) then
    raise exception 'La propiedad de la cuenta solo se transfiere desde la base de datos';
  end if;

  if tg_op = 'UPDATE' and old.is_owner and old.user_id is distinct from auth.uid() then
    raise exception 'Solo el propietario puede modificar su propia cuenta';
  end if;

  select exists (select 1 from public.roles r where r.code = 'admin'
                 and (r.id = new.role_id or (tg_op = 'UPDATE' and r.id = old.role_id)))
    into v_admin_role;
  if v_admin_role and not public.auth_is_owner()
     and (tg_op = 'INSERT' or old.user_id is distinct from auth.uid()) then
    raise exception 'Solo el propietario puede dar de alta o modificar administradores';
  end if;

  return new;
end $$;

drop trigger if exists trg_employee_owner_guard on public.employees;
create trigger trg_employee_owner_guard before insert or update or delete on public.employees
  for each row execute function public.tg_employee_owner_guard();

create or replace function public.tg_admin_role_protect()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_context() then return case when tg_op = 'DELETE' then old else new end; end if;

  if tg_table_name = 'role_permissions' then
    if exists (select 1 from public.roles r where r.id = old.role_id and r.code = 'admin') then
      raise exception 'El rol Administrador siempre conserva todos los permisos';
    end if;
    return old;
  end if;

  if tg_table_name = 'employee_permissions' then
    if exists (select 1 from public.employees e where e.id = new.employee_id and e.is_owner) and not new.is_granted then
      raise exception 'No se pueden revocar permisos al propietario';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' and old.code = 'admin' then raise exception 'El rol Administrador no se puede eliminar'; end if;
  if tg_op = 'UPDATE' and old.code = 'admin' and (new.code <> old.code or new.scope <> old.scope) then
    raise exception 'El rol Administrador no se puede cambiar de código ni de alcance';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists trg_admin_role_permissions on public.role_permissions;
create trigger trg_admin_role_permissions before delete on public.role_permissions
  for each row execute function public.tg_admin_role_protect();
drop trigger if exists trg_owner_permissions on public.employee_permissions;
create trigger trg_owner_permissions before insert or update on public.employee_permissions
  for each row execute function public.tg_admin_role_protect();
drop trigger if exists trg_admin_role on public.roles;
create trigger trg_admin_role before update or delete on public.roles
  for each row execute function public.tg_admin_role_protect();

create or replace function public.tg_permission_to_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.role_permissions (role_id, permission_code)
  select r.id, new.code from public.roles r where r.code = 'admin'
  on conflict do nothing;
  return null;
end $$;
drop trigger if exists trg_permission_to_admin on public.permissions;
create trigger trg_permission_to_admin after insert on public.permissions
  for each row execute function public.tg_permission_to_admin();

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code from public.roles r cross join public.permissions p
where r.code = 'admin'
on conflict do nothing;

create or replace view public.v_employees with (security_invoker = on) as
select e.id, e.user_id, e.company_id, e.branch_id, e.department_id, e.role_id,
       e.employee_code, e.username, e.full_name, e.position, e.email, e.phone,
       e.status, e.hired_at, e.created_at, e.updated_at,
       (e.user_id is not null) as has_account,
       r.code as role_code, r.name as role_name, r.scope as role_scope,
       b.name as branch_name, d.name as department_name, d.color as department_color,
       e.is_owner
from public.employees e
join public.roles r on r.id = e.role_id
left join public.branches b on b.id = e.branch_id
left join public.departments d on d.id = e.department_id;
grant select on public.v_employees to authenticated;

-- ─── 2. CONTRASEÑAS ─────────────────────────────────────────────────────────
create or replace function public.admin_set_password(p_employee_id uuid, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  t       public.employees%rowtype;
  v_scope text;
  v_email text;
  v_user  uuid;
  v_prev  text;
  v_new   boolean := false;
begin
  if not public.has_permission('manage_employees') then
    raise exception 'No tienes permiso para gestionar contraseñas';
  end if;
  if coalesce(length(p_password), 0) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;

  select * into t from public.employees where id = p_employee_id and company_id = public.auth_company_id();
  if not found then raise exception 'Empleado no encontrado'; end if;
  if t.status <> 'active' then raise exception 'El empleado está inactivo'; end if;

  select r.scope into v_scope from public.roles r where r.id = t.role_id;
  if t.user_id = auth.uid() then
    raise exception 'Para tu propia cuenta usa "Cambiar contraseña" en tu menú';
  end if;
  if t.is_owner then raise exception 'La contraseña del propietario solo la cambia él mismo'; end if;
  if v_scope = 'company' and not public.auth_is_owner() then
    raise exception 'Solo el propietario restablece contraseñas de administradores, soporte o auditoría';
  end if;
  if public.auth_role_scope() <> 'company' and t.branch_id is distinct from public.auth_branch_id() then
    raise exception 'Solo puedes gestionar empleados de tu sucursal';
  end if;

  if t.user_id is null then
    v_prev := public.set_bypass('on');
    v_email := lower(t.username) || '@operalia.local';
    select id into v_user from auth.users where email = v_email;
    if v_user is null then
      v_user := gen_random_uuid();
      v_new := true;
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token)
      values (
        '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email,
        crypt(p_password, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('username', lower(t.username), 'full_name', t.full_name, 'must_change_password', true),
        now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_user, v_user::text,
              jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
              'email', now(), now(), now());
    end if;
    update public.employees set user_id = v_user, email = coalesce(email, v_email) where id = t.id;
    perform public.set_bypass(v_prev);
  else
    v_user := t.user_id;
  end if;

  if not v_new then
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"must_change_password": true}'::jsonb,
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_user;
  end if;

  update public.notifications set is_read = true
   where company_id = t.company_id and link = '/employees?reset=' || t.id and not is_read;

  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, new_data)
  values (t.company_id, 'employees', t.id::text, 'UPDATE', public.auth_employee_id(),
          jsonb_build_object('evento', case when v_new then 'cuenta_creada' else 'contrasena_restablecida' end, 'username', t.username));

  return jsonb_build_object('username', t.username, 'created', v_new);
end $$;
revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;

create or replace function public.clear_must_change_password()
returns void language sql security definer set search_path = public as $$
  update auth.users set raw_user_meta_data = raw_user_meta_data - 'must_change_password'
  where id = auth.uid()
$$;
revoke all on function public.clear_must_change_password() from public, anon;
grant execute on function public.clear_must_change_password() to authenticated;

create or replace function public.request_password_reset(p_username text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t   public.employees%rowtype;
  ag  record;
  v_link text;
begin
  select * into t from public.employees
   where lower(username) = lower(split_part(trim(coalesce(p_username, '')), '@', 1))
     and status = 'active' limit 1;
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
revoke all on function public.request_password_reset(text) from public;
grant execute on function public.request_password_reset(text) to anon, authenticated;

-- ─── 3. CHECKLISTS AUTOMÁTICOS CADA DÍA (pg_cron) ───────────────────────────
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.unschedule(jobid) from cron.job where jobname = 'operalia-mantenimiento';
  perform cron.schedule('operalia-mantenimiento', '5 * * * *',
    'select public.run_daily_maintenance(id) from public.companies');
exception when others then
  raise notice 'pg_cron no disponible (%). Actívalo en Database → Extensions y vuelve a ejecutar este archivo.', sqlerrm;
end $$;

-- ─── 4. CHECKLISTS NUEVOS ───────────────────────────────────────────────────
-- «Limpieza de cajas», «Recolección de carritos», «Recolección de devoluciones» y
-- «Revisión de tarimas y retornables» se siembran por empresa con
-- public.seed_company_base (migración 0023). La Sucursal Sur de Gato Pelón ya
-- se crea activa en seed/0008_catalogos.sql.
