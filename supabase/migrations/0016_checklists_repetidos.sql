-- =============================================================================
-- OPERALIA · 0016 · CHECKLISTS QUE SE REPITEN VARIAS VECES AL DÍA (RONDAS)
-- -----------------------------------------------------------------------------
--   * checklist_templates.repeat_every_minutes (null = una vez al día; mínimo
--     30) y repeat_until (último inicio permitido; por defecto la hora de
--     cierre de la sucursal o, si no tiene, el end_time de la plantilla).
--   * checklist_runs: la restricción única pasa de (plantilla, sucursal, fecha)
--     a (plantilla, sucursal, fecha, hora de inicio). Cada ronda guarda
--     round_no y rounds_total («Ronda 3 de 6»).
--   * generate_checklist_runs crea una corrida por intervalo; cada ronda tiene
--     la misma duración que la ventana original (sin pasar de 23:59).
--   * Lo demás ya trabajaba por corrida: el marcado de vencidos usa el
--     scheduled_end de cada ronda, la cancelación (0010) aplica a una ronda y
--     la tarea automática (0013/0014) se liga a la respuesta de esa ronda.
-- Ejemplo en seed/0014_checklists_repetidos.sql. Re-ejecutable.
-- =============================================================================

alter table public.checklist_templates add column if not exists repeat_every_minutes integer;
alter table public.checklist_templates add column if not exists repeat_until time;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_repeat_chk
    check (repeat_every_minutes is null or repeat_every_minutes >= 30);
exception when duplicate_object then null; end $$;

alter table public.checklist_runs add column if not exists round_no integer not null default 1;
alter table public.checklist_runs add column if not exists rounds_total integer not null default 1;

-- Restricción única: se busca por columnas (el nombre real puede variar).
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.checklist_runs'::regclass and con.contype = 'u'
      and (select array_agg(att.attname::text order by att.attname) from pg_attribute att
           where att.attrelid = con.conrelid and att.attnum = any(con.conkey))
          = array['branch_id','scheduled_date','template_id']
  loop
    execute format('alter table public.checklist_runs drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'checklist_runs_template_branch_date_start_key') then
    alter table public.checklist_runs add constraint checklist_runs_template_branch_date_start_key
      unique (template_id, branch_id, scheduled_date, scheduled_start);
  end if;
end $$;

create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end, round_no, rounds_total)
  select t.company_id, t.id, b.id, t.department_id, p_date,
         r.starts_at::time,
         least(r.starts_at + (w.win_end - w.win_start), p_date + time '23:59')::time,
         r.n, r.total
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  cross join lateral public.checklist_window(t.schedule_anchor, t.start_time, t.end_time,
    t.start_offset_minutes, t.end_offset_minutes, b.opening_time, b.closing_time) w
  cross join lateral (
    select s.starts_at, s.n::int, count(*) over ()::int as total
    from generate_series(
           p_date + w.win_start,
           p_date + case when t.repeat_every_minutes is null then w.win_start
                         else greatest(w.win_start, coalesce(t.repeat_until, b.closing_time, t.end_time)) end,
           make_interval(mins => coalesce(t.repeat_every_minutes, 1440))
         ) with ordinality as s(starts_at, n)
    where s.starts_at < p_date + time '23:59'
  ) r
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

-- v_checklist_runs fija r.* al crearse: se recrea para incluir round_no/rounds_total
-- y la configuración de repetición de la plantilla.
drop view if exists public.v_checklist_runs;
create view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       t.repeat_every_minutes,
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
grant select on public.v_checklist_runs to authenticated;
