-- =============================================================================
-- OPERALIA · DEMO 0010 · NOTIFICACIONES DE PRUEBA
-- -----------------------------------------------------------------------------
-- Dos avisos por departamento para ver la campana con datos. Re-ejecutable.
-- =============================================================================

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
