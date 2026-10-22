-- =============================================================================
-- OPERALIA · 0013 · PREGUNTAS CRÍTICAS, TAREA AUTOMÁTICA Y HORARIOS POR SUCURSAL
-- -----------------------------------------------------------------------------
--   1. checklist_questions.is_critical: seguridad y valores (alarma, efectivo,
--      salidas de emergencia, caducados en exhibición...).
--   2. Tarea automática: una respuesta «No» crea una tarea para el departamento
--      del checklist (prioridad high si la pregunta es crítica) y avisa al jefe
--      del departamento; si es crítica también al gerente de la sucursal.
--      Si la respuesta se corrige a otra cosa, la tarea pendiente se cancela.
--      tasks.source_type/source_id ligan la tarea con su origen (sin duplicar).
--   3. Horarios relativos a la sucursal: checklist_templates.schedule_anchor
--      ('fixed' | 'opening' | 'closing') + desfases en minutos. Si la sucursal
--      no tiene opening_time/closing_time se usan start_time/end_time.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. PREGUNTAS CRÍTICAS ──────────────────────────────────────────────────
alter table public.checklist_questions add column if not exists is_critical boolean not null default false;

-- ─── 2. TAREA AUTOMÁTICA POR RESPUESTA «NO» ─────────────────────────────────
alter table public.tasks add column if not exists source_type text;
alter table public.tasks add column if not exists source_id uuid;
create unique index if not exists tasks_source_uidx on public.tasks (source_type, source_id) where source_id is not null;

create or replace function public.tg_checklist_answer_task()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_run   public.checklist_runs%rowtype;
  v_q     public.checklist_questions%rowtype;
  v_title text;
  v_task  uuid;
  v_actor uuid := public.auth_employee_id();
  v_prev  text;
  r       record;
begin
  select * into v_q from public.checklist_questions where id = new.question_id;
  if v_q.answer_type <> 'yes_no' then return null; end if;

  -- Corrección: dejó de ser «No» → cancelar la tarea si nadie la ha tomado.
  if tg_op = 'UPDATE' and old.answer_value = 'no' and new.answer_value is distinct from 'no' then
    v_prev := public.set_bypass('on');
    update public.tasks set status = 'cancelled', completion_notes = 'Se corrigió la respuesta del checklist'
     where source_type = 'checklist_answer' and source_id = new.id and status = 'pending';
    perform public.set_bypass(v_prev);
    return null;
  end if;

  if new.answer_value is distinct from 'no' or (tg_op = 'UPDATE' and old.answer_value = 'no') then
    return null;
  end if;

  select * into v_run from public.checklist_runs where id = new.run_id;
  select title into v_title from public.checklist_templates where id = v_run.template_id;

  v_prev := public.set_bypass('on');
  insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, created_by, source_type, source_id)
  values (v_run.company_id, v_run.branch_id, v_run.department_id,
          left((case when v_q.is_critical then 'CRÍTICO: ' else '' end) || v_q.text, 200),
          'Respuesta «No» en «' || v_title || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || ').'
            || coalesce(E'\nComentario: ' || nullif(trim(new.comment), ''), ''),
          case when v_q.is_critical then 'high' else 'medium' end,
          v_run.scheduled_date, v_actor, 'checklist_answer', new.id)
  on conflict (source_type, source_id) where source_id is not null
  do update set status = 'pending', completion_notes = null, completed_at = null
  returning id into v_task;
  perform public.set_bypass(v_prev);

  -- Avisos: jefes del departamento (revisan checklists) y, si es crítica, gerentes.
  for r in
    select distinct e.id
    from public.employees e
    join public.roles ro on ro.id = e.role_id
    where e.company_id = v_run.company_id and e.status = 'active'
      and e.id is distinct from v_actor
      and (e.branch_id = v_run.branch_id or ro.scope = 'company')
      and (
        (ro.code <> 'admin'
         and exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'review_checklists')
         and (e.department_id = v_run.department_id
              or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = v_run.department_id)))
        or (v_q.is_critical and ro.code = 'gerente' and e.branch_id = v_run.branch_id)
      )
  loop
    perform public.notify_employee(r.id, 'task',
      case when v_q.is_critical then 'Falla crítica en checklist' else 'Falla en checklist' end,
      v_title || ': ' || v_q.text, '/tasks');
  end loop;
  return null;
end $$;

drop trigger if exists trg_checklist_answer_task on public.checklist_answers;
create trigger trg_checklist_answer_task after insert or update of answer_value on public.checklist_answers
  for each row execute function public.tg_checklist_answer_task();

-- ─── 3. HORARIOS RELATIVOS A LA APERTURA / CIERRE DE LA SUCURSAL ────────────
alter table public.checklist_templates add column if not exists schedule_anchor text not null default 'fixed';
alter table public.checklist_templates add column if not exists start_offset_minutes integer;
alter table public.checklist_templates add column if not exists end_offset_minutes integer;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_anchor_chk
    check (schedule_anchor in ('fixed','opening','closing')
           and (schedule_anchor = 'fixed' or (start_offset_minutes is not null and end_offset_minutes is not null
                                              and end_offset_minutes > start_offset_minutes)));
exception when duplicate_object then null; end $$;

-- Ventana de una plantilla en una sucursal. Sin cruzar medianoche:
-- un inicio antes de las 00:00 se recorta a 00:00 y un fin después, a 23:59.
create or replace function public.checklist_window(
  p_anchor text, p_start time, p_end time, p_start_off int, p_end_off int, p_opening time, p_closing time,
  out win_start time, out win_end time)
language plpgsql immutable as $$
declare
  v_base time := case p_anchor when 'opening' then p_opening when 'closing' then p_closing end;
  v_base_min int;
begin
  if p_anchor = 'fixed' or v_base is null then
    win_start := p_start; win_end := p_end; return;
  end if;
  v_base_min := extract(hour from v_base)::int * 60 + extract(minute from v_base)::int;
  win_start := time '00:00' + make_interval(mins => greatest(0, least(1439, v_base_min + p_start_off)));
  win_end   := time '00:00' + make_interval(mins => greatest(0, least(1439, v_base_min + p_end_off)));
  if win_end <= win_start then
    win_start := p_start; win_end := p_end;
  end if;
end $$;

create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end)
  select t.company_id, t.id, b.id, t.department_id, p_date, w.win_start, w.win_end
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  cross join lateral public.checklist_window(t.schedule_anchor, t.start_time, t.end_time,
    t.start_offset_minutes, t.end_offset_minutes, b.opening_time, b.closing_time) w
  where t.company_id = p_company_id and t.is_active
    -- Las rondas de un día se generan juntas; si ya hay corridas de ese día no se agregan más
    -- (así cambiar la hora o la repetición de una plantilla aplica desde el día siguiente).
    and not exists (select 1 from public.checklist_runs x
                    where x.template_id = t.id and x.branch_id = b.id and x.scheduled_date = p_date)
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;
revoke all on function public.generate_checklist_runs(uuid, date) from public, anon, authenticated;
