-- =============================================================================
-- OPERALIA · SEMILLA 0014 · EJEMPLO DE CHECKLIST CON RONDAS
-- -----------------------------------------------------------------------------
-- «Ronda de carritos y canastillas» del departamento Cajas: cada 2 horas de
-- 08:00 a 20:00 (7 rondas de 2 h cada una). Requiere la migración 0016.
-- Re-ejecutable (no duplica por título).
-- =============================================================================

insert into public.checklist_templates
  (company_id, department_id, title, description, shift, start_time, end_time, frequency,
   requires_evidence, repeat_every_minutes, repeat_until)
select c.id, d.id, 'Ronda de carritos y canastillas',
       'Recolectar carritos del estacionamiento y acomodar canastillas en la entrada',
       'especial', '08:00', '10:00', 'daily', false, 120, '20:00'
from public.companies c
join public.departments d on d.company_id = c.id and d.code = 'CAJ'
where not exists (select 1 from public.checklist_templates t where t.company_id = c.id and t.title = 'Ronda de carritos y canastillas');

insert into public.checklist_questions (template_id, position, text, answer_type, is_required, requires_photo)
select t.id, q.pos, q.txt, q.typ, q.req, q.photo
from public.checklist_templates t
join (values
  (1, 'Carritos recolectados del estacionamiento', 'yes_no', true, false),
  (2, 'Canastillas acomodadas en la entrada', 'yes_no', true, false),
  (3, 'Carritos dañados encontrados (cantidad)', 'number', false, false),
  (4, 'Foto del área de carritos', 'photo', true, true)
) as q(pos, txt, typ, req, photo) on true
where t.title = 'Ronda de carritos y canastillas'
  and not exists (select 1 from public.checklist_questions x where x.template_id = t.id);

select public.generate_checklist_runs(id, public.company_today(id)) from public.companies;
