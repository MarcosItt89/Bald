-- =============================================================================
-- OPERALIA · 0017 · RECORDATORIO 30 MINUTOS ANTES DE QUE VENZA UN CHECKLIST
-- -----------------------------------------------------------------------------
--   * checklist_runs.reminded_at: el aviso se manda una sola vez por corrida
--     (por ronda, en los checklists que se repiten).
--   * send_checklist_reminders(empresa): corridas de hoy que siguen en
--     pending / in_progress / reopened, ya empezaron y vencen en ≤ 30 min
--     (hora de la empresa). Avisa:
--       - a su departamento en esa sucursal (notificación de departamento, 0008);
--       - a quien lo inició, si no es de ese departamento;
--       - si el checklist no tiene departamento, a los gerentes de la sucursal.
--   * pg_cron: job 'operalia-recordatorios' cada 5 minutos (el de 0012 corre
--     cada hora, demasiado espaciado para avisar 30 minutos antes).
--   * run_daily_maintenance también envía los recordatorios, así funciona
--     aunque pg_cron no esté activo (cuando alguien abre Checklists).
-- Re-ejecutable.
-- =============================================================================

alter table public.checklist_runs add column if not exists reminded_at timestamptz;
create index if not exists checklist_runs_reminder_idx on public.checklist_runs (company_id, scheduled_date)
  where reminded_at is null and status in ('pending','in_progress','reopened');

create or replace function public.send_checklist_reminders(p_company_id uuid, p_minutes int default 30)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_tz    text;
  v_today date;
  v_now   time;
  v_prev  text;
  v_count int := 0;
  r       record;
  g       record;
  v_title text;
  v_body  text;
begin
  select timezone into v_tz from public.companies where id = p_company_id;
  if v_tz is null then return 0; end if;
  v_today := (now() at time zone v_tz)::date;
  v_now   := (now() at time zone v_tz)::time;

  v_prev := public.set_bypass('on');
  for r in
    update public.checklist_runs cr
       set reminded_at = now()
     where cr.company_id = p_company_id
       and cr.scheduled_date = v_today
       and cr.status in ('pending','in_progress','reopened')
       and cr.reminded_at is null
       and cr.scheduled_start <= v_now
       and cr.scheduled_end > v_now
       and cr.scheduled_end - v_now <= make_interval(mins => p_minutes)
    returning cr.*
  loop
    select t.title || case when r.rounds_total > 1 then ' (ronda ' || r.round_no || ' de ' || r.rounds_total || ')' else '' end
      into v_title from public.checklist_templates t where t.id = r.template_id;
    v_body := 'Vence a las ' || to_char(r.scheduled_end, 'HH24:MI')
              || case when r.status = 'pending' then ' y aún no se inicia.' else ' y aún no se completa.' end;

    if r.department_id is not null then
      insert into public.notifications (company_id, employee_id, department_id, branch_id, type, title, body, link)
      values (r.company_id, null, r.department_id, r.branch_id, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
    else
      for g in
        select e.id from public.employees e join public.roles ro on ro.id = e.role_id
        where e.branch_id = r.branch_id and e.status = 'active' and ro.code = 'gerente'
      loop
        perform public.notify_employee(g.id, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
      end loop;
    end if;

    -- Quien lo inició y no pertenece a ese departamento (p. ej. un gerente).
    if r.started_by is not null and not exists (
         select 1 from public.employees e where e.id = r.started_by
           and (e.department_id = r.department_id
                or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = r.department_id))) then
      perform public.notify_employee(r.started_by, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
    end if;
    v_count := v_count + 1;
  end loop;
  perform public.set_bypass(v_prev);
  return v_count;
end $$;
revoke all on function public.send_checklist_reminders(uuid, int) from public, anon, authenticated;

-- El mantenimiento diario también envía los recordatorios (sin depender de pg_cron).
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');  -- por si se instaló desde un archivo con CRLF
  if position('send_checklist_reminders' in v_src) = 0 then
    v_src := replace(v_src,
      '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(',
      '  perform public.send_checklist_reminders(v_company);' || chr(10)
      || '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(');
    if position('send_checklist_reminders' in v_src) = 0 then
      raise exception 'No se pudo extender run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- pg_cron: cada 5 minutos (si la extensión está activa).
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'operalia-recordatorios';
  perform cron.schedule('operalia-recordatorios', '*/5 * * * *',
    'select public.send_checklist_reminders(id) from public.companies');
exception when others then
  raise notice 'pg_cron no disponible (%). Los recordatorios se enviarán cuando alguien abra Checklists.', sqlerrm;
end $$;
