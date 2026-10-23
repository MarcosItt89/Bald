-- =============================================================================
-- OPERALIA · SEMILLA 0010 · CUENTA DEL PROPIETARIO
-- -----------------------------------------------------------------------------
-- Re-ejecutable. Pre-registra la cuenta del dueño y define al propietario.
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

-- ─── 2. Propietario de la empresa ───────────────────────────────────────────
-- La migración 0012 marca a gatopelon solo si ya existía. Si aún no hay
-- propietario: gatopelon cuando está instalada la demo; si no, esta cuenta.
do $$
declare v_prev text;
begin
  if not exists (select 1 from public.employees where company_id = 'c0000000-0000-4000-8000-000000000001' and is_owner) then
    v_prev := public.set_bypass('on');
    update public.employees set is_owner = true
     where id = (select id from public.employees
                  where company_id = 'c0000000-0000-4000-8000-000000000001'
                    and lower(username) in ('gatopelon', 'marcos.yeran.guerra')
                  order by lower(username) = 'gatopelon' desc limit 1);
    perform public.set_bypass(v_prev);
  end if;
end $$;
