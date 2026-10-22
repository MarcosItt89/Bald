-- =============================================================================
-- OPERALIA · 0010 · NOTIFICACIONES DE PRUEBA + VÍNCULO DE CUENTA EXISTENTE
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

-- ─── 2. Dos notificaciones de prueba por departamento ───────────────────────
insert into public.notifications (company_id, department_id, type, title, body, link)
select d.company_id, d.id, v.type, v.title || ' · ' || d.name, v.body, v.link
from public.departments d
cross join (values
  ('info',      'Bienvenidos a Operalia', 'Desde hoy los checklists y tareas del área se registran aquí.', '/dashboard'),
  ('checklist', 'Recordatorio de checklist', 'Revisa los checklists pendientes de tu departamento antes de la hora límite.', '/checklists')
) as v(type, title, body, link)
where d.company_id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.notifications n
                  where n.department_id = d.id and n.employee_id is null and n.title = v.title || ' · ' || d.name);
