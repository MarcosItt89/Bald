-- =============================================================================
-- OPERALIA · SEMILLA 0010 · PROPIETARIO Y SUPERADMIN DE GATO PELÓN
-- -----------------------------------------------------------------------------
-- Re-ejecutable.
--   * marcos.yeran.guerra: administrador con correo real (se liga al crear su
--     cuenta en Supabase Auth).
--   * chee: propietario de Gato Pelón (is_owner). Queda pre-registrado SIN
--     cuenta: la contraseña se pone desde la app (Empleados → chee → Crear
--     cuenta) o con admin_set_password. Ver el diario 2026-10-27.
--   * gatopelon (usuario demo): deja de ser propietario y queda como
--     superadmin de la plataforma (platform_admins), si existe.
-- Las notificaciones de prueba están en
-- demo/0010_notificaciones_prueba.sql.
-- =============================================================================

-- ─── 1. Vincular la cuenta ya creada en Supabase Auth ───────────────────────
-- marcos.yeran.guerra@gmail.com → Administrador general, Administración,
-- Sucursal Centro. Si la cuenta aún no existe en Auth, el empleado queda
-- pre-registrado y se liga solo cuando se cree (trigger on_auth_user_created,
-- que empata el usuario "marcos.yeran.guerra" con la parte antes de la @).
insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                              username, full_name, position, email)
select c.id,
       (select id from public.branches    where company_id = c.id and code = '001'),
       (select id from public.departments where company_id = c.id and code = 'ADM'),
       (select id from public.roles       where company_id = c.id and code = 'admin'),
       'EMP-0100', 'marcos.yeran.guerra', 'Marcos Yerán Ramírez Guerra', 'Administrador general',
       'marcos.yeran.guerra@gmail.com'
from public.companies c
where c.id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.employees where lower(username) = 'marcos.yeran.guerra');

update public.employees e
   set user_id = u.id
  from auth.users u
 where lower(u.email) = 'marcos.yeran.guerra@gmail.com'
   and lower(e.username) = 'marcos.yeran.guerra'
   and e.user_id is null;

-- ─── 2. chee, propietario de Gato Pelón ─────────────────────────────────────
insert into public.employees (company_id, branch_id, department_id, role_id, employee_code, username, full_name, position)
select c.id,
       (select id from public.branches    where company_id = c.id and code = '001'),
       (select id from public.departments where company_id = c.id and code = 'ADM'),
       (select id from public.roles       where company_id = c.id and code = 'admin'),
       'EMP-0101', 'chee', 'Chee', 'Propietario'
from public.companies c
where c.id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.employees where company_id = c.id and lower(username) = 'chee');

-- Solo un propietario por empresa (índice employees_one_owner_idx de 0012):
-- primero se quita a los demás y luego se marca a chee. Modo sistema, porque
-- tg_employee_owner_guard solo permite transferirlo desde la base de datos.
do $$
declare v_prev text;
begin
  v_prev := public.set_bypass('on');
  update public.employees set is_owner = false
   where company_id = 'c0000000-0000-4000-8000-000000000001' and is_owner and lower(username) <> 'chee';
  update public.employees set is_owner = true
   where company_id = 'c0000000-0000-4000-8000-000000000001' and lower(username) = 'chee' and not is_owner;
  perform public.set_bypass(v_prev);
end $$;

-- ─── 3. gatopelon, superadmin de la plataforma ──────────────────────────────
-- Sigue siendo administrador dentro de Gato Pelón. Solo aplica si su cuenta
-- existe (la crea demo/0009).
insert into public.platform_admins (user_id)
select e.user_id from public.employees e
where e.company_id = 'c0000000-0000-4000-8000-000000000001' and lower(e.username) = 'gatopelon' and e.user_id is not null
on conflict do nothing;
