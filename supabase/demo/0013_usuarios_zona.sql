-- =============================================================================
-- OPERALIA · DEMO 0013 · USUARIOS DE ZONA
-- -----------------------------------------------------------------------------
-- Requiere seed/0013 (rol jefe_escaner y zonas). Re-ejecutable.
--   * jefe.escaner (zonas Centro y Norte) y escaner.norte, contraseña prueba123.
--     jefe.escaner NO ve la Sucursal Sur (zona Sur): ver pruebas en verificar.sql.
-- =============================================================================

-- Función temporal (copia de la de seed/0009) para crear empleado + cuenta.
create or replace function public._seed_user(
  p_username text, p_password text, p_full_name text, p_role text,
  p_branch_code text, p_dept_code text, p_position text, p_employee_code text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_company uuid := 'c0000000-0000-4000-8000-000000000001';
  v_email   text := lower(p_username) || '@operalia.local';
  v_emp     uuid;
  v_user    uuid;
begin
  -- 1) Empleado
  select id into v_emp from public.employees where lower(username) = lower(p_username);
  if v_emp is null then
    insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                  username, full_name, position, email)
    values (
      v_company,
      (select id from public.branches where company_id = v_company and code = p_branch_code),
      (select id from public.departments where company_id = v_company and code = p_dept_code),
      (select id from public.roles where company_id = v_company and code = p_role),
      p_employee_code, lower(p_username), p_full_name, p_position, v_email)
    returning id into v_emp;
  end if;

  -- 2) Cuenta de Supabase Auth (el trigger on_auth_user_created la liga al empleado)
  select id into v_user from auth.users where email = v_email;
  if v_user is null then
    v_user := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token)
    values (
      '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email,
      crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', lower(p_username), 'full_name', p_full_name),
      now(), now(), '', '', '', '');

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_user, v_user::text,
            jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
            'email', now(), now(), now());
  end if;

  -- 3) Asegurar el vínculo (por si el empleado se creó después que la cuenta)
  update public.employees set user_id = v_user where id = v_emp and user_id is null;
  return v_emp;
end $$;

select public._seed_user('jefe.escaner',  'prueba123', 'Raúl Jefe de Escáner', 'jefe_escaner', '001', 'ESC', 'Jefe de escáner (zonas Centro y Norte)', 'EMP-0015');
select public._seed_user('escaner.norte', 'prueba123', 'Diana Escáner Norte',  'escaner',      '002', 'ESC', 'Encargada de escáner',                   'EMP-0016');

drop function public._seed_user(text, text, text, text, text, text, text, text);

insert into public.employee_zones (employee_id, zone_id)
select e.id, z.id
from public.employees e
join public.zones z on z.company_id = e.company_id and z.code in ('CEN', 'NOR')
where e.username = 'jefe.escaner'
on conflict do nothing;
