-- =============================================================================
-- OPERALIA · 0009 · CHECKLISTS: EVIDENCIA A NIVEL CHECKLIST
-- -----------------------------------------------------------------------------
-- Si la plantilla tiene "Evidencia requerida", el checklist no se puede
-- completar sin al menos una foto: ya sea general del checklist
-- (entity_type 'checklist_run') o ligada a alguna de sus respuestas.
-- La vista v_checklist_runs agrega evidence_count para historial y tarjetas.
-- Re-ejecutable.
-- =============================================================================

-- 1) Nuevo tipo de entidad para evidencias generales del checklist.
alter table public.evidence_files drop constraint if exists evidence_files_entity_type_check;
alter table public.evidence_files add constraint evidence_files_entity_type_check check (entity_type in (
  'checklist_run','checklist_answer','task','receiving_order','price_change','shelf_tag',
  'order','expiration','support_ticket','product','supplier_visit','other'));

-- 2) Validación al completar.
create or replace function public.tg_checklist_run_evidence()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'completed' and old.status <> 'completed' and not public.is_system_context()
     and (select requires_evidence from public.checklist_templates where id = new.template_id)
     and not exists (
       select 1 from public.evidence_files ev
       where (ev.entity_type = 'checklist_run' and ev.entity_id = new.id)
          or (ev.entity_type = 'checklist_answer'
              and ev.entity_id in (select a.id from public.checklist_answers a where a.run_id = new.id))) then
    raise exception 'Este checklist requiere evidencia fotográfica antes de completarse';
  end if;
  return new;
end $$;

-- Nombre elegido para correr DESPUÉS de trg_checklist_run_rules (orden alfabético):
-- así primero se informa si faltan respuestas y después si falta la foto.
drop trigger if exists trg_checklist_run_evidence on public.checklist_runs;
drop trigger if exists trg_checklist_run_rules_evidence on public.checklist_runs;
create trigger trg_checklist_run_rules_evidence before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_evidence();

-- 3) Conteo de evidencias en la vista (columna agregada al final).
create or replace view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;

revoke all on public.v_checklist_runs from anon;
grant select on public.v_checklist_runs to authenticated;
