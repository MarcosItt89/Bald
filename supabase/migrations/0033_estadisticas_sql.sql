-- =============================================================================
-- OPERALIA · 0033 · ESTADÍSTICAS CALCULADAS EN LA BASE
-- -----------------------------------------------------------------------------
--   Antes, cada pestaña de Estadísticas descargaba filas y calculaba en el
--   navegador (con el tope de 1000 filas por consulta de Supabase, los
--   totales podían quedar cortos). Ahora una función por pestaña devuelve el
--   mismo JSON que armaba reportService.js:
--     report_summary · report_checklists · report_management · report_tasks
--     report_inventory · report_temperatures · report_receiving · report_support
--   * SECURITY INVOKER: leen con el RLS de quien consulta (mismas filas que
--     veía antes) y las secciones dependen de los mismos permisos.
--   * Días «locales» con la zona horaria de la empresa (companies.timezone).
--   * Filtros: p_branches (null = todas las visibles; un arreglo = esas),
--     p_dept (departamento), p_from / p_to y, donde aplica, el periodo
--     anterior (p_prev_from / p_prev_to / p_compare).
-- Re-ejecutable.
-- =============================================================================

-- ─── Índices para los cálculos ──────────────────────────────────────────────
-- Respuestas por pregunta (temperaturas, «No» más frecuentes, calificación de gerencia).
create index if not exists checklist_answers_question_idx on public.checklist_answers (question_id);
-- Tareas por fecha de cierre (Resumen y Tareas).
create index if not exists tasks_completed_idx on public.tasks (branch_id, completed_at) where completed_at is not null;

-- ─── Utilidades ─────────────────────────────────────────────────────────────
-- % redondeado (null si no hay base), como pct() del navegador.
create or replace function public.report_pct(p_part numeric, p_total numeric)
returns numeric language sql immutable as $$
  select case when coalesce(p_total, 0) = 0 then null else round(100.0 * p_part / p_total) end
$$;

-- { cur, prev, diff } entre periodos (diff con un decimal).
create or replace function public.report_delta(p_cur numeric, p_prev numeric)
returns jsonb language sql immutable as $$
  select jsonb_build_object('cur', p_cur, 'prev', p_prev,
    'diff', case when p_cur is not null and p_prev is not null then round((p_cur - p_prev) * 10) / 10 end)
$$;

-- Lunes de la semana.
create or replace function public.report_week(p_day date)
returns date language sql immutable as $$
  select p_day - (extract(isodow from p_day)::int - 1)
$$;

-- Zona horaria de la empresa de quien consulta.
create or replace function public.report_tz()
returns text language sql stable set search_path = public as $$
  select coalesce((select c.timezone from public.companies c where c.id = public.auth_company_id()), 'America/Tijuana')
$$;

-- Días del periodo (máximo 400) y semanas (máximo 60).
create or replace function public.report_days(p_from date, p_to date)
returns setof date language sql immutable as $$
  select d::date from generate_series(p_from, least(p_to, p_from + 399), interval '1 day') d
$$;
create or replace function public.report_weeks(p_from date, p_to date)
returns setof date language sql immutable as $$
  select w::date from generate_series(public.report_week(p_from), p_to, interval '7 days') w limit 60
$$;

-- Corridas de checklist del periodo (las usan Resumen y Checklists).
create or replace function public.report_runs(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns table (id uuid, template_id uuid, title text, shift text, status text, department_id uuid, department_name text,
               branch_id uuid, branch_name text, scheduled_date date, scheduled_start time, scheduled_end time,
               completed_at timestamptz, rounds_total int)
language sql stable set search_path = public as $$
  select r.id, r.template_id, t.title, t.shift, r.status, r.department_id, d.name, r.branch_id, b.name,
         r.scheduled_date, r.scheduled_start, r.scheduled_end, r.completed_at, coalesce(r.rounds_total, 1)
  from public.checklist_runs r
  join public.checklist_templates t on t.id = r.template_id
  join public.branches b on b.id = r.branch_id
  left join public.departments d on d.id = r.department_id
  where r.scheduled_date between p_from and p_to
    and (p_branches is null or r.branch_id = any (p_branches))
    and (p_dept is null or r.department_id = p_dept)
$$;

-- ─── RESUMEN ────────────────────────────────────────────────────────────────
create or replace function public.report_summary(
  p_branches uuid[], p_dept uuid, p_from date, p_to date,
  p_prev_from date default null, p_prev_to date default null, p_compare boolean default false)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  v_tz    text := public.report_tz();
  v_cmp   boolean := coalesce(p_compare, false) and p_prev_from is not null and p_prev_to is not null;
  v_start date := case when coalesce(p_compare, false) and p_prev_from is not null then p_prev_from else p_from end;
  v_kpis  jsonb := '{}';
  v_out   jsonb := '{}';
  a numeric; b numeric; c numeric; d numeric;
  v_daily jsonb;
  v_dept  jsonb;
begin
  -- Checklists (una sola lectura de las corridas para KPI, % diario y por departamento)
  if public.has_permission('fill_checklists') or public.has_permission('review_checklists') then
    with runs as materialized (
           select r.scheduled_date, r.status, r.department_id, r.department_name
           from public.report_runs(p_branches, p_dept, v_start, p_to) r),
         cur as (select * from runs where scheduled_date between p_from and p_to)
    select public.report_pct(count(*) filter (where status = 'completed'), count(*) filter (where status <> 'cancelled')),
           case when v_cmp then (select public.report_pct(count(*) filter (where status = 'completed'), count(*) filter (where status <> 'cancelled'))
                                   from runs where scheduled_date between p_prev_from and p_prev_to) end,
           (select coalesce(jsonb_agg(jsonb_build_object('day', dy, 'pct', g.pct) order by dy), '[]')
              from public.report_days(p_from, p_to) dy
              left join (select scheduled_date,
                                public.report_pct(count(*) filter (where status = 'completed'), count(*) filter (where status <> 'cancelled')) as pct
                         from cur group by scheduled_date) g on g.scheduled_date = dy),
           (select coalesce(jsonb_agg(x order by (x->>'pct')::numeric nulls first), '[]') from (
              select jsonb_build_object('id', department_id, 'name', coalesce(max(department_name), 'General'),
                       'total', count(*) filter (where status <> 'cancelled'),
                       'completed', count(*) filter (where status = 'completed'),
                       'pct', public.report_pct(count(*) filter (where status = 'completed'), count(*) filter (where status <> 'cancelled'))) x
              from cur group by department_id
              having count(*) filter (where status <> 'cancelled') > 0) s)
      into a, b, v_daily, v_dept
      from cur;
    v_kpis := v_kpis || jsonb_build_object('checklists', public.report_delta(a, b));
    v_out := v_out || jsonb_build_object('dailyChecklists', v_daily, 'checklistsByDept', v_dept);
  end if;

  -- Tareas
  if public.has_permission('view_tasks') or public.has_permission('manage_tasks') then
    with done as (
      select (t.completed_at at time zone v_tz)::date as day, t.due_date,
             extract(epoch from t.completed_at - t.created_at) / 3600 as hours
      from public.tasks t
      where t.status = 'completed' and t.completed_at is not null
        and (t.completed_at at time zone v_tz)::date between v_start and p_to
        and (p_branches is null or t.branch_id = any (p_branches))
        and (p_dept is null or t.department_id = p_dept))
    select public.report_pct(count(*) filter (where day between p_from and p_to and (due_date is null or day <= due_date)),
                             count(*) filter (where day between p_from and p_to)),
           round(avg(hours) filter (where day between p_from and p_to)::numeric, 1),
           case when v_cmp then public.report_pct(count(*) filter (where day between p_prev_from and p_prev_to and (due_date is null or day <= due_date)),
                                                  count(*) filter (where day between p_prev_from and p_prev_to)) end,
           case when v_cmp then round(avg(hours) filter (where day between p_prev_from and p_prev_to)::numeric, 1) end
      into a, b, c, d
      from done;
    v_kpis := v_kpis || jsonb_build_object('tasksOnTime', public.report_delta(a, c), 'taskHours', public.report_delta(b, d));
    -- Antigüedad de las tareas abiertas: lt1 · 1-3 · 4-7 · gt7 días.
    v_out := v_out || jsonb_build_object('openTasksByAge', (
      select coalesce(jsonb_object_agg(bucket, n), '{}') from (
        select case when age < 1 then 'lt1' when age <= 3 then '1-3' when age <= 7 then '4-7' else 'gt7' end as bucket, count(*) as n
        from (select floor(extract(epoch from now() - t.created_at) / 86400) as age
              from public.tasks t
              where t.status in ('pending', 'in_progress')
                and (p_branches is null or t.branch_id = any (p_branches))
                and (p_dept is null or t.department_id = p_dept)) s
        group by 1) g));
  end if;

  -- Evidencias rechazadas o con corrección
  if public.has_permission('review_evidence') or public.has_permission('upload_evidence') then
    select public.report_pct(count(*) filter (where day between p_from and p_to and status in ('rejected', 'correction_required')),
                             count(*) filter (where day between p_from and p_to)),
           case when v_cmp then public.report_pct(count(*) filter (where day between p_prev_from and p_prev_to and status in ('rejected', 'correction_required')),
                                                  count(*) filter (where day between p_prev_from and p_prev_to)) end
      into a, b
      from (select (e.created_at at time zone v_tz)::date as day, e.status from public.evidence_files e
            where (e.created_at at time zone v_tz)::date between v_start and p_to
              and (p_branches is null or e.branch_id = any (p_branches))) s;
    v_kpis := v_kpis || jsonb_build_object('evidenceRejected', public.report_delta(a, b));
  end if;

  -- Productos bajo mínimo (hoy)
  if public.has_permission('view_inventory') then
    select count(*) into a
      from public.inventory i join public.products p on p.id = i.product_id
     where i.status in ('low', 'critical', 'out_of_stock')
       and (p_branches is null or i.branch_id = any (p_branches))
       and (p_dept is null or p.department_id = p_dept);
    v_kpis := v_kpis || jsonb_build_object('lowStock', public.report_delta(a, null));
  end if;

  -- Recibos sin diferencias
  if public.has_permission('receive_products') then
    select public.report_pct(count(*) filter (where day between p_from and p_to and not has_differences),
                             count(*) filter (where day between p_from and p_to)),
           case when v_cmp then public.report_pct(count(*) filter (where day between p_prev_from and p_prev_to and not has_differences),
                                                  count(*) filter (where day between p_prev_from and p_prev_to)) end
      into a, b
      from (select (r.completed_at at time zone v_tz)::date as day, r.has_differences from public.receiving_orders r
            where r.status = 'completed' and r.completed_at is not null
              and (r.completed_at at time zone v_tz)::date between v_start and p_to
              and (p_branches is null or r.branch_id = any (p_branches))) s;
    v_kpis := v_kpis || jsonb_build_object('receiptsClean', public.report_delta(a, b));
  end if;

  return v_out || jsonb_build_object('kpis', v_kpis);
end $$;

-- ─── CHECKLISTS ─────────────────────────────────────────────────────────────
create or replace function public.report_checklists(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_tz text := public.report_tz();
begin
  return (
  with runs as (select * from public.report_runs(p_branches, p_dept, p_from, p_to)),
       valid as (select * from runs where status <> 'cancelled'),
       late as (
         select v.*, (v.status = 'overdue'
                      or (v.status = 'completed' and v.completed_at is not null
                          and v.completed_at > timezone(v_tz, v.scheduled_date + v.scheduled_end))) as is_late
         from valid v)
  select jsonb_build_object(
    'total', (select count(*) from runs),
    'status', (select jsonb_build_object(
        'completed', count(*) filter (where status = 'completed'),
        'overdue', count(*) filter (where status = 'overdue'),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'open', count(*) filter (where status in ('pending', 'in_progress', 'reopened'))) from runs),
    'byShift', (select coalesce(jsonb_agg(x order by x->>'shift'), '[]') from (
        select jsonb_build_object('shift', shift, 'total', count(*), 'completed', count(*) filter (where status = 'completed'),
                                  'pct', public.report_pct(count(*) filter (where status = 'completed'), count(*))) x
        from valid group by shift) s),
    'byDepartment', (select coalesce(jsonb_agg(x order by (x->>'pct')::numeric nulls first), '[]') from (
        select jsonb_build_object('id', department_id, 'name', coalesce(max(department_name), 'General'), 'total', count(*),
                                  'completed', count(*) filter (where status = 'completed'),
                                  'pct', public.report_pct(count(*) filter (where status = 'completed'), count(*))) x
        from valid group by department_id) s),
    -- heat[depto][día de la semana 0=domingo] = % completados
    'heat', (select coalesce(jsonb_object_agg(dept, days), '{}') from (
        select coalesce(department_id::text, '') as dept, jsonb_object_agg(wd, p) as days from (
          select department_id, extract(dow from scheduled_date)::int::text as wd,
                 public.report_pct(count(*) filter (where status = 'completed'), count(*)) as p
          from valid group by department_id, 2) w
        group by 1) h),
    'topNo', (select coalesce(jsonb_agg(x order by (x->>'count')::int desc), '[]') from (
        select jsonb_build_object('id', q.id, 'text', q.text, 'templateId', q.template_id, 'count', count(*)) x
        from public.checklist_answers a
        join public.checklist_questions q on q.id = a.question_id
        join runs r on r.id = a.run_id
        where a.answer_value = 'no'
        group by q.id, q.text, q.template_id
        order by count(*) desc limit 10) s),
    'lateTemplates', (select coalesce(jsonb_agg(x order by (x->>'pct')::numeric desc, (x->>'late')::int desc), '[]') from (
        select jsonb_build_object('id', template_id, 'title', max(title), 'department', coalesce(max(department_name), 'General'),
                                  'shift', max(shift), 'total', count(*), 'late', count(*) filter (where is_late),
                                  'pct', public.report_pct(count(*) filter (where is_late), count(*))) x
        from late group by template_id
        having count(*) filter (where is_late) >= 2
           and public.report_pct(count(*) filter (where is_late), count(*)) >= 30) s),
    'byHour', (select coalesce(jsonb_agg(x order by x->>'hour'), '[]') from (
        select jsonb_build_object('hour', to_char(scheduled_start, 'HH24'), 'total', count(*),
                                  'completed', count(*) filter (where status = 'completed'),
                                  'pct', public.report_pct(count(*) filter (where status = 'completed'), count(*))) x
        from valid group by to_char(scheduled_start, 'HH24')) s),
    'rounds', jsonb_build_object(
      'times', (select coalesce(jsonb_agg(t order by t), '[]') from (
          select distinct to_char(scheduled_start, 'HH24:MI') t from valid where rounds_total > 1) s),
      'templates', (select coalesce(jsonb_agg(x), '[]') from (
          select jsonb_build_object('id', v.template_id, 'title', max(v.title), 'department', coalesce(max(v.department_name), 'General'),
                   'total', count(*), 'completed', count(*) filter (where v.status = 'completed'),
                   'pct', public.report_pct(count(*) filter (where v.status = 'completed'), count(*)),
                   'byTime', (select jsonb_object_agg(tm, jsonb_build_object('total', n, 'completed', c, 'pct', public.report_pct(c, n)))
                              from (select to_char(v2.scheduled_start, 'HH24:MI') tm, count(*) n, count(*) filter (where v2.status = 'completed') c
                                    from valid v2 where v2.template_id = v.template_id and v2.rounds_total > 1 group by 1) bt)) x
          from valid v where v.rounds_total > 1 group by v.template_id) s))
  ));
end $$;

-- ─── GERENCIA: calificación de apertura y cierre ────────────────────────────
-- Calificación = respuestas «Sí» ÷ preguntas sí/no activas de la plantilla
-- (sin contar las «N/A»). Un checklist sin llenar cuenta todo como no cumplido.
create or replace function public.report_management(p_branches uuid[], p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_ger uuid;
begin
  select d.id into v_ger from public.departments d where d.company_id = public.auth_company_id() and d.code = 'GER' limit 1;
  if v_ger is null then
    return jsonb_build_object('gerDeptId', null, 'branches', '[]'::jsonb, 'days', '[]'::jsonb);
  end if;
  if not exists (select 1 from public.report_runs(p_branches, v_ger, p_from, p_to) r where r.status <> 'cancelled') then
    return jsonb_build_object('gerDeptId', v_ger, 'branches', '[]'::jsonb, 'days', '[]'::jsonb);
  end if;

  return (
  with runs as (select * from public.report_runs(p_branches, v_ger, p_from, p_to) where status <> 'cancelled'),
       answers as (
         select a.run_id, count(*) filter (where a.answer_value = 'yes') as yes, count(*) filter (where a.answer_value = 'na') as na
         from public.checklist_answers a
         join public.checklist_questions q on q.id = a.question_id and q.answer_type = 'yes_no'
         where a.run_id in (select id from runs) and a.answer_value in ('yes', 'no', 'na')
         group by a.run_id),
       scored as (
         select r.branch_id, r.branch_name, r.scheduled_date, r.shift,
                greatest(0, (select count(*) from public.checklist_questions q
                              where q.template_id = r.template_id and q.answer_type = 'yes_no' and q.is_active)
                            - coalesce(a.na, 0)) as total,
                coalesce(a.yes, 0) as yes
         from runs r left join answers a on a.run_id = r.id),
       per_branch as (
         select s.branch_id, max(s.branch_name) as name,
                public.report_pct(sum(s.yes), sum(s.total)) as score,
                public.report_pct(sum(s.yes) filter (where s.shift = 'apertura'), sum(s.total) filter (where s.shift = 'apertura')) as opening,
                public.report_pct(sum(s.yes) filter (where s.shift = 'cierre'), sum(s.total) filter (where s.shift = 'cierre')) as closing,
                (select jsonb_object_agg(dd.scheduled_date::text, jsonb_build_object(
                          'score', public.report_pct(dd.yes, dd.total), 'opening', public.report_pct(dd.yes_o, dd.total_o),
                          'closing', public.report_pct(dd.yes_c, dd.total_c)))
                   from (select s2.scheduled_date, sum(s2.yes) yes, sum(s2.total) total,
                                sum(s2.yes) filter (where s2.shift = 'apertura') yes_o, sum(s2.total) filter (where s2.shift = 'apertura') total_o,
                                sum(s2.yes) filter (where s2.shift = 'cierre') yes_c, sum(s2.total) filter (where s2.shift = 'cierre') total_c
                         from scored s2 where s2.branch_id = s.branch_id group by s2.scheduled_date) dd) as days
         from scored s group by s.branch_id)
  select jsonb_build_object(
    'gerDeptId', v_ger,
    'branches', (select coalesce(jsonb_agg(jsonb_build_object('id', branch_id, 'name', name, 'score', score, 'opening', opening,
                                                              'closing', closing, 'days', days)
                                           order by coalesce(score, -1) desc), '[]') from per_branch),
    'days', (select coalesce(jsonb_agg(d order by d), '[]') from public.report_days(p_from, p_to) d)));
end $$;

-- ─── TAREAS ─────────────────────────────────────────────────────────────────
create or replace function public.report_tasks(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_tz text := public.report_tz();
begin
  return (
  with base as (
         select t.status, t.due_date, t.department_id, t.assigned_to, t.created_at, t.completed_at,
                (t.created_at at time zone v_tz)::date as created_day,
                (t.completed_at at time zone v_tz)::date as done_day
         from public.tasks t
         where (p_branches is null or t.branch_id = any (p_branches))
           and (p_dept is null or t.department_id = p_dept)
           and ((t.created_at at time zone v_tz)::date between p_from and p_to
                or (t.completed_at at time zone v_tz)::date between p_from and p_to)),
       created as (select * from base where created_day between p_from and p_to),
       done as (select *, (due_date is null or done_day <= due_date) as on_time,
                       extract(epoch from completed_at - created_at) / 3600 as hours
                from base where status = 'completed' and done_day between p_from and p_to)
  select jsonb_build_object(
    'createdCount', (select count(*) from created),
    'weekly', (select coalesce(jsonb_agg(jsonb_build_object('week', w,
                 'created', (select count(*) from created c where public.report_week(c.created_day) = w),
                 'closed', (select count(*) from done d where public.report_week(d.done_day) = w)) order by w), '[]')
               from public.report_weeks(p_from, p_to) w),
    'onTime', (select count(*) from done where on_time),
    'lateClosed', (select count(*) from done where not on_time),
    'openLate', (select count(*) from public.tasks t
                  where t.status in ('pending', 'in_progress') and t.due_date < public.company_today(t.company_id)
                    and (p_branches is null or t.branch_id = any (p_branches))
                    and (p_dept is null or t.department_id = p_dept)),
    'byDepartment', (select coalesce(jsonb_agg(x order by coalesce((x->>'hours')::numeric, 0) desc), '[]') from (
        select jsonb_build_object('id', d.department_id, 'name', coalesce(max(dp.name), 'General'), 'count', count(*),
                                  'hours', round(avg(d.hours)::numeric, 1), 'onTime', public.report_pct(count(*) filter (where d.on_time), count(*))) x
        from done d left join public.departments dp on dp.id = d.department_id group by d.department_id) s),
    'byAssignee', (select coalesce(jsonb_agg(x order by coalesce((x->>'hours')::numeric, 0) desc), '[]') from (
        select jsonb_build_object('id', d.assigned_to, 'name', coalesce(max(e.full_name), 'Sin asignar'), 'count', count(*),
                                  'hours', round(avg(d.hours)::numeric, 1), 'onTime', public.report_pct(count(*) filter (where d.on_time), count(*))) x
        from done d left join public.employees e on e.id = d.assigned_to group by d.assigned_to) s)));
end $$;

-- ─── INVENTARIO ─────────────────────────────────────────────────────────────
create or replace function public.report_inventory(
  p_branches uuid[], p_dept uuid, p_from date, p_to date,
  p_prev_from date default null, p_prev_to date default null, p_compare boolean default false)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  v_tz    text := public.report_tz();
  v_cmp   boolean := coalesce(p_compare, false) and p_prev_from is not null and p_prev_to is not null;
  v_start date := case when coalesce(p_compare, false) and p_prev_from is not null then p_prev_from else p_from end;
begin
  return (
  with alerts as (
         select i.status, p.department_id, d.name as dept_name
         from public.inventory i join public.products p on p.id = i.product_id
         left join public.departments d on d.id = p.department_id
         where i.status in ('low', 'critical', 'out_of_stock')
           and (p_branches is null or i.branch_id = any (p_branches))
           and (p_dept is null or p.department_id = p_dept)),
       moves as (
         select m.movement_type, m.quantity, m.unit_cost, m.waste_reason, m.product_id,
                (m.created_at at time zone v_tz)::date as day,
                p.name, p.sku, p.unit, p.cost, p.department_id, d.name as dept_name
         from public.inventory_movements m
         join public.products p on p.id = m.product_id
         left join public.departments d on d.id = p.department_id
         where (m.created_at at time zone v_tz)::date between v_start and p_to
           and (p_branches is null or m.branch_id = any (p_branches))
           and (p_dept is null or p.department_id = p_dept)),
       waste as (select *, quantity * coalesce(unit_cost, cost, 0) as value from moves
                 where movement_type = 'waste' and day between p_from and p_to),
       waste_prev as (select *, quantity * coalesce(unit_cost, cost, 0) as value from moves
                      where v_cmp and movement_type = 'waste' and day between p_prev_from and p_prev_to),
       exps as (
         select x.expiration_date, x.quantity
         from public.product_expirations x join public.products p on p.id = x.product_id
         where x.expiration_date between p_from and p_to
           and (p_branches is null or x.branch_id = any (p_branches))
           and (p_dept is null or p.department_id = p_dept)),
       gaps as (
         select g.has_stock, g.department_id, d.name as dept_name
         from public.shelf_gaps g left join public.departments d on d.id = g.department_id
         where (g.reported_at at time zone v_tz)::date between p_from and p_to
           and (p_branches is null or g.branch_id = any (p_branches))
           and (p_dept is null or g.department_id = p_dept)),
       counts as (
         select ci.difference, ci.difference_value, (ci.counted_at at time zone v_tz)::date as day,
                p.department_id, d.name as dept_name
         from public.cycle_count_items ci
         join public.cycle_count_tasks ct on ct.id = ci.task_id
         join public.products p on p.id = ci.product_id
         left join public.departments d on d.id = p.department_id
         where ci.counted_at is not null
           and (ci.counted_at at time zone v_tz)::date between v_start and p_to
           and (p_branches is null or ct.branch_id = any (p_branches))
           and (p_dept is null or p.department_id = p_dept)),
       counts_cur as (select * from counts where day between p_from and p_to),
       counts_prev as (select * from counts where v_cmp and day between p_prev_from and p_prev_to)
  select jsonb_build_object(
    'lowStock', (select count(*) from alerts),
    'outOfStock', (select count(*) from alerts where status = 'out_of_stock'),
    'alertsByDept', (select coalesce(jsonb_agg(x order by (x->>'total')::int desc), '[]') from (
        select jsonb_build_object('id', department_id, 'name', coalesce(max(dept_name), 'Sin departamento'), 'total', count(*),
                                  'out', count(*) filter (where status = 'out_of_stock')) x
        from alerts group by department_id) s),
    'byType', (select coalesce(jsonb_agg(x order by (x->>'count')::int desc), '[]') from (
        select jsonb_build_object('type', movement_type, 'count', count(*), 'quantity', sum(quantity)) x
        from moves where day between p_from and p_to group by movement_type) s),
    'wasteCount', (select count(*) from waste),
    'wasteQty', public.report_delta((select round(coalesce(sum(quantity), 0), 2) from waste),
                                    case when v_cmp then (select round(coalesce(sum(quantity), 0), 2) from waste_prev) end),
    'wasteCost', public.report_delta((select round(coalesce(sum(value), 0), 2) from waste),
                                     case when v_cmp then (select round(coalesce(sum(value), 0), 2) from waste_prev) end),
    'wasteByReason', (select coalesce(jsonb_agg(x order by (x->>'cost')::numeric desc), '[]') from (
        select jsonb_build_object('reason', w.reason, 'cost', round(sum(w.value), 2), 'count', count(*),
                 'prevCost', case when v_cmp then (select round(coalesce(sum(wp.value), 0), 2) from waste_prev wp
                                                   where coalesce(wp.waste_reason, 'other') = w.reason) end) x
        from (select coalesce(waste_reason, 'other') as reason, value from waste) w group by w.reason) s),
    'wasteByDept', (select coalesce(jsonb_agg(x order by (x->>'cost')::numeric desc), '[]') from (
        select jsonb_build_object('id', department_id, 'name', coalesce(max(dept_name), 'Sin departamento'),
                                  'cost', round(sum(value), 2), 'count', count(*)) x
        from waste group by department_id) s),
    'wasteTopProducts', (select coalesce(jsonb_agg(x order by (x->>'cost')::numeric desc), '[]') from (
        select jsonb_build_object('id', product_id, 'name', max(name), 'sku', max(sku), 'unit', max(unit),
                                  'qty', round(sum(quantity), 2), 'cost', round(sum(value), 2)) x
        from waste group by product_id order by sum(value) desc limit 10) s),
    'expirationsWeekly', (select coalesce(jsonb_agg(jsonb_build_object('week', w,
        'count', (select count(*) from exps e where public.report_week(e.expiration_date) = w),
        'quantity', (select coalesce(sum(e.quantity), 0) from exps e where public.report_week(e.expiration_date) = w)) order by w), '[]')
        from public.report_weeks(p_from, p_to) w),
    'expirationsTotal', (select count(*) from exps),
    'gapsTotal', (select count(*) from gaps),
    'gapsWithStock', (select count(*) from gaps where has_stock),
    'gapsByDept', (select coalesce(jsonb_agg(x order by (x->>'total')::int desc), '[]') from (
        select jsonb_build_object('id', department_id, 'name', coalesce(max(dept_name), 'Sin departamento'), 'total', count(*),
                                  'withStock', count(*) filter (where has_stock)) x
        from gaps group by department_id) s),
    -- Exactitud = % de productos contados (conteo cíclico) sin diferencia.
    'countsTotal', (select count(*) from counts_cur),
    'countAccuracy', public.report_delta(
        (select public.report_pct(count(*) filter (where coalesce(difference, 0) = 0), count(*)) from counts_cur),
        case when v_cmp then (select public.report_pct(count(*) filter (where coalesce(difference, 0) = 0), count(*)) from counts_prev) end),
    'countDiffValue', (select round(coalesce(sum(difference_value), 0), 2) from counts_cur),
    'accuracyByDept', (select coalesce(jsonb_agg(x order by coalesce((x->>'pct')::numeric, 0)), '[]') from (
        select jsonb_build_object('id', department_id, 'name', coalesce(max(dept_name), 'Sin departamento'), 'total', count(*),
                                  'exact', count(*) filter (where coalesce(difference, 0) = 0),
                                  'pct', public.report_pct(count(*) filter (where coalesce(difference, 0) = 0), count(*)),
                                  'value', round(coalesce(sum(difference_value), 0), 2)) x
        from counts_cur group by department_id) s)));
end $$;

-- ─── TEMPERATURAS ───────────────────────────────────────────────────────────
-- Lecturas de preguntas numéricas con equipo. Los eventos fuera de rango
-- salen de las tareas automáticas (se conservan aunque la lectura se corrija)
-- y su cierre da el tiempo de corrección.
create or replace function public.report_temperatures(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_tz text := public.report_tz();
begin
  return (
  with readings as (
         select q.equipment_name as name, q.unit, q.min_value, q.max_value, a.out_of_range, r.scheduled_date as day,
                case when trim(a.answer_value) ~ '^-?[0-9]+(\.[0-9]+)?$' then trim(a.answer_value)::numeric end as value
         from public.checklist_answers a
         join public.checklist_questions q on q.id = a.question_id and q.equipment_name is not null
         join public.checklist_runs r on r.id = a.run_id
         where r.scheduled_date between p_from and p_to
           and (p_branches is null or r.branch_id = any (p_branches))
           and (p_dept is null or r.department_id = p_dept)),
       events as (
         select t.id, t.title, t.status, t.created_at, t.completed_at, t.updated_at, b.name as branch_name, d.name as department_name,
                case t.status when 'completed' then t.completed_at when 'cancelled' then t.updated_at end as fixed_at
         from public.tasks t
         join public.branches b on b.id = t.branch_id
         left join public.departments d on d.id = t.department_id
         where t.source_type = 'checklist_answer' and t.title ilike '%fuera de rango:%'
           and (t.created_at at time zone v_tz)::date between p_from and p_to
           and (p_branches is null or t.branch_id = any (p_branches))
           and (p_dept is null or t.department_id = p_dept)
         order by t.created_at desc limit 200),
       ev as (select *, round((extract(epoch from fixed_at - created_at) / 3600)::numeric, 1) as hours from events),
       daily as (select name, day, round(avg(value), 1) as avg from readings group by name, day)
  select jsonb_build_object(
    'readings', (select count(*) from readings),
    'outOfRange', (select count(*) from ev),
    'outPct', (select public.report_pct(count(*) filter (where out_of_range), count(*)) from readings),
    'openEvents', (select count(*) from ev where fixed_at is null),
    'avgFixHours', (select round(avg(hours), 1) from ev where hours is not null),
    'equipments', (select coalesce(jsonb_agg(x order by (x->>'out')::int desc, x->>'name'), '[]') from (
        select jsonb_build_object('name', r.name, 'unit', coalesce((array_agg(r.unit))[1], ''),
                 'min', (array_agg(r.min_value))[1], 'max', (array_agg(r.max_value))[1],
                 'count', count(*), 'out', count(*) filter (where r.out_of_range),
                 'daily', (select jsonb_agg(jsonb_build_object('day', dy, 'avg', dl.avg) order by dy)
                           from public.report_days(p_from, p_to) dy
                           left join daily dl on dl.name = r.name and dl.day = dy)) x
        from readings r group by r.name) s),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'status', status, 'created_at', created_at,
                 'completed_at', completed_at, 'updated_at', updated_at, 'branch_name', branch_name, 'department_name', department_name,
                 'fixedAt', fixed_at, 'hours', hours) order by created_at desc), '[]') from ev)));
end $$;

-- ─── RECIBO Y PRECIOS ───────────────────────────────────────────────────────
create or replace function public.report_receiving(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare
  v_tz  text := public.report_tz();
  v_out jsonb := '{}';
begin
  if public.has_permission('receive_products') or public.has_permission('view_reports') then
    v_out := v_out || (
      with rec as (
        select r.supplier_id, s.name, r.has_differences
        from public.receiving_orders r join public.suppliers s on s.id = r.supplier_id
        where r.status = 'completed' and (r.completed_at at time zone v_tz)::date between p_from and p_to
          and (p_branches is null or r.branch_id = any (p_branches)))
      select jsonb_build_object(
        'receipts', (select count(*) from rec),
        'receiptsWithDiff', (select count(*) from rec where has_differences),
        'bySupplier', (select coalesce(jsonb_agg(x order by (x->>'count')::int desc), '[]') from (
            select jsonb_build_object('id', supplier_id, 'name', max(name), 'count', count(*),
                                      'withDiff', count(*) filter (where has_differences),
                                      'diffPct', public.report_pct(count(*) filter (where has_differences), count(*))) x
            from rec group by supplier_id) s)));
  end if;

  if public.has_permission('manage_price_changes') or public.has_permission('view_reports') then
    v_out := v_out || jsonb_build_object('priceChanges', (
      select count(*) from public.price_changes pc join public.products p on p.id = pc.product_id
      where pc.status = 'applied' and (pc.applied_at at time zone v_tz)::date between p_from and p_to
        and (p_branches is null or pc.branch_id is null or pc.branch_id = any (p_branches))
        and (p_dept is null or p.department_id = p_dept)));
  end if;

  if public.has_permission('manage_shelf_tags') or public.has_permission('validate_shelf_tags') then
    v_out := v_out || (
      with tags as (
        select st.branch_id, b.name as branch_name, st.status, st.created_at, st.validated_at,
               (st.status = 'validated' and st.validated_at is not null) as validated,
               (st.status = 'validated' and st.validated_at is not null and st.validated_at - st.created_at <= interval '48 hours') as on_time
        from public.shelf_tags st join public.products p on p.id = st.product_id join public.branches b on b.id = st.branch_id
        where (st.created_at at time zone v_tz)::date between p_from and p_to
          and (p_branches is null or st.branch_id = any (p_branches))
          and (p_dept is null or p.department_id = p_dept)),
      pending as (
        select st.branch_id, b.name as branch_name
        from public.shelf_tags st join public.products p on p.id = st.product_id join public.branches b on b.id = st.branch_id
        where st.status in ('pending', 'printed', 'placed')
          and (p_branches is null or st.branch_id = any (p_branches))
          and (p_dept is null or p.department_id = p_dept)),
      stores as (
        select branch_id, max(branch_name) as name, sum(pending)::int as pending, sum(validated)::int as validated, sum(on_time)::int as on_time
        from (select branch_id, branch_name, 1 as pending, 0 as validated, 0 as on_time from pending
              union all
              select branch_id, branch_name, 0, 1, case when on_time then 1 else 0 end from tags where validated) u
        group by branch_id)
      select jsonb_build_object(
        'tagsCreated', (select count(*) from tags),
        'tagsValidated', (select count(*) from tags where validated),
        'tagsOnTime', (select count(*) from tags where on_time),
        'tagsOnTimePct', (select public.report_pct(count(*) filter (where on_time), count(*) filter (where validated)) from tags),
        'tagsPending', (select count(*) from pending),
        -- Por tienda: para que el jefe de zona compare a sus encargados de escáner.
        'tagsByStore', (select coalesce(jsonb_agg(jsonb_build_object('id', branch_id, 'name', name, 'pending', pending,
                           'validated', validated, 'onTime', on_time, 'onTimePct', public.report_pct(on_time, validated))
                         order by coalesce(public.report_pct(on_time, validated), -1) desc, pending), '[]') from stores)));
  end if;
  return v_out;
end $$;

-- ─── SOPORTE ────────────────────────────────────────────────────────────────
create or replace function public.report_support(p_branches uuid[], p_dept uuid, p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = public as $$
declare v_tz text := public.report_tz();
begin
  return (
  with tickets as (
         select t.status, t.category, t.created_at, t.first_response_at, t.due_at,
                coalesce(t.resolved_at, t.closed_at) as ended_at,
                case when t.due_at is null then null
                     when coalesce(t.resolved_at, t.closed_at) is not null then coalesce(t.resolved_at, t.closed_at) <= t.due_at
                     else now() <= t.due_at end as sla_ok
         from public.support_tickets t
         where (t.created_at at time zone v_tz)::date between p_from and p_to
           and (p_branches is null or t.branch_id = any (p_branches))
           and (p_dept is null or t.department_id = p_dept))
  select jsonb_build_object(
    'created', (select count(*) from tickets),
    'open', (select count(*) from public.support_tickets t
              where t.status in ('open', 'in_progress', 'waiting_user')
                and (p_branches is null or t.branch_id = any (p_branches))
                and (p_dept is null or t.department_id = p_dept)),
    'overdueNow', (select count(*) from tickets where due_at is not null and ended_at is null and now() > due_at),
    'firstResponseH', (select round(avg(extract(epoch from first_response_at - created_at) / 3600)::numeric, 1)
                       from tickets where first_response_at is not null),
    'slaPct', (select public.report_pct(count(*) filter (where sla_ok), count(*) filter (where sla_ok is not null)) from tickets),
    'slaMet', (select count(*) from tickets where sla_ok),
    'slaMissed', (select count(*) from tickets where sla_ok = false),
    'byCategory', (select coalesce(jsonb_agg(x order by (x->>'count')::int desc), '[]') from (
        select jsonb_build_object('category', category, 'count', count(*),
                                  'open', count(*) filter (where status in ('open', 'in_progress', 'waiting_user')),
                                  'slaPct', public.report_pct(count(*) filter (where sla_ok), count(*) filter (where sla_ok is not null))) x
        from tickets group by category) s)));
end $$;

-- ─── Permisos: solo usuarios con sesión ─────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'report_pct(numeric, numeric)', 'report_delta(numeric, numeric)', 'report_week(date)', 'report_tz()',
    'report_days(date, date)', 'report_weeks(date, date)', 'report_runs(uuid[], uuid, date, date)',
    'report_summary(uuid[], uuid, date, date, date, date, boolean)', 'report_checklists(uuid[], uuid, date, date)',
    'report_management(uuid[], date, date)', 'report_tasks(uuid[], uuid, date, date)',
    'report_inventory(uuid[], uuid, date, date, date, date, boolean)', 'report_temperatures(uuid[], uuid, date, date)',
    'report_receiving(uuid[], uuid, date, date)', 'report_support(uuid[], uuid, date, date)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
