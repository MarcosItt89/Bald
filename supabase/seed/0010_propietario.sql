-- =============================================================================
-- OPERALIA · SEMILLA 0010 · PROPIETARIO DE GATO PELÓN
-- -----------------------------------------------------------------------------
-- Re-ejecutable. Sin datos personales ni cuentas con contraseña:
--   * chee: propietario de Gato Pelón (is_owner). Queda pre-registrado SIN
--     cuenta: la contraseña se pone desde la app (Empleados → chee → Crear
--     cuenta) o con admin_set_password.
--   * El administrador con correo real y el superadmin de la plataforma NO se
--     siembran aquí: se dan de alta a mano en cada ambiente (README → «Cuentas»,
--     «Nombrar al superadmin real»).
--   * El superadmin de PRUEBAS (usuario demo «gatopelon») está en
--     demo/0010_superadmin_demo.sql; instalacion-limpia.sql no lo trae.
-- =============================================================================

-- ─── chee, propietario de Gato Pelón ────────────────────────────────────────
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
