-- =============================================================================
-- OPERALIA · 0027 · RENDIMIENTO EN CASCADA
-- -----------------------------------------------------------------------------
-- El mismo tablero de rendimiento (0025) en cada nivel, con las mismas
-- métricas y sin duplicar su cálculo:
--   * Superadmin (Operalia)  → todas las empresas y sus sucursales
--                              (platform_company_kpis / _trend / platform_checklist_heatmap).
--   * Cada empresa           → sus sucursales, según el alcance de quien
--                              consulta: propietario y administradores, todas;
--                              jefe de zona, las de sus zonas; gerente, la suya
--                              (branch_kpis / branch_trend / branch_checklist_heatmap,
--                              permiso view_reports, filtro can_access_branch).
-- El cálculo vive en perf_kpis / perf_trend / perf_heatmap (internas, la API
-- no las puede llamar), copiadas de 0025 con dos parámetros de alcance:
-- p_company_id (null = todas) y p_branch_ids (null = todas las de la empresa).
-- Re-ejecutable.
-- =============================================================================

-- ─── Cálculo (interno) ──────────────────────────────────────────────────────
create or replace function public.perf_kpis(p_from date, p_to date, p_company_id uuid, p_branch_ids uuid[])
returns table (
  company_id uuid, company_name text, company_code text, company_status text,
  branch_id uuid, branch_name text, branch_code text, branch_status text,
  runs_total integer, runs_completed integer, runs_on_time integer,
  checklist_pct integer, checklist_on_time_pct integer,
  tasks_late integer,
  waste_count integer, waste_qty numeric, waste_value numeric,
  counts_total integer, counts_exact integer, count_accuracy_pct integer,
  gaps_open integer, gaps_resolved integer, gap_hours numeric,
  tickets_open integer, tickets_overdue integer, sla_total integer, sla_met integer, sla_pct integer,
  employees_active integer, users_7d integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 366 then raise exception 'El periodo máximo es de un año'; end if;

  return query
  with keys as (
    select b.company_id as cid, b.id as bid from public.branches b
     where (p_company_id is null or b.company_id = p_company_id)
       and (p_branch_ids is null or b.id = any (p_branch_ids))
    union all
    -- Fila «sin sucursal» de la empresa (tickets o empleados sin sucursal):
    -- solo cuando se ve la empresa completa.
    select c.id, null::uuid from public.companies c
     where p_branch_ids is null and (p_company_id is null or c.id = p_company_id)
  ),
  runs as (
    select r.company_id as cid, r.branch_id as bid,
           count(*) as total,
           count(*) filter (where r.status = 'completed') as done,
           count(*) filter (where r.status = 'completed'
                              and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone c.timezone)) as on_time
    from public.checklist_runs r join public.companies c on c.id = r.company_id
    where r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
      and ((r.scheduled_date + r.scheduled_end) at time zone c.timezone) <= now()
    group by 1, 2
  ),
  late as (
    select t.company_id as cid, t.branch_id as bid, count(*) as n
    from public.tasks t
    where t.status in ('pending', 'in_progress') and t.due_date < public.company_today(t.company_id)
    group by 1, 2
  ),
  waste as (
    select m.company_id as cid, m.branch_id as bid, count(*) as n, sum(m.quantity) as qty,
           sum(m.quantity * coalesce(m.unit_cost, p.cost, 0)) as val
    from public.inventory_movements m
    join public.companies c on c.id = m.company_id
    join public.products p on p.id = m.product_id
    where m.movement_type = 'waste' and (m.created_at at time zone c.timezone)::date between p_from and p_to
    group by 1, 2
  ),
  counts as (
    select k.company_id as cid, k.branch_id as bid, count(*) as total, count(*) filter (where i.difference = 0) as exact
    from public.cycle_count_items i
    join public.cycle_count_tasks k on k.id = i.task_id
    join public.companies c on c.id = k.company_id
    where i.counted_at is not null and (i.counted_at at time zone c.timezone)::date between p_from and p_to
    group by 1, 2
  ),
  gaps as (
    select g.company_id as cid, g.branch_id as bid,
           count(*) filter (where g.status = 'open') as open_n,
           count(*) filter (where g.status = 'resolved' and (g.resolved_at at time zone c.timezone)::date between p_from and p_to) as resolved_n,
           coalesce(sum(extract(epoch from g.resolved_at - g.reported_at) / 3600)
             filter (where g.status = 'resolved' and (g.resolved_at at time zone c.timezone)::date between p_from and p_to), 0) as hours_sum
    from public.shelf_gaps g join public.companies c on c.id = g.company_id
    group by 1, 2
  ),
  tickets as (
    select s.company_id as cid, s.branch_id as bid,
           count(*) filter (where s.status in ('open', 'in_progress', 'waiting_user')) as open_n,
           count(*) filter (where s.status in ('open', 'in_progress', 'waiting_user') and s.due_at < now()) as overdue_n,
           count(*) filter (where s.due_at is not null and (s.created_at at time zone c.timezone)::date between p_from and p_to) as sla_total,
           count(*) filter (where s.due_at is not null and (s.created_at at time zone c.timezone)::date between p_from and p_to
                              and case when coalesce(s.resolved_at, s.closed_at) is not null
                                       then coalesce(s.resolved_at, s.closed_at) <= s.due_at
                                       else now() <= s.due_at end) as sla_met
    from public.support_tickets s join public.companies c on c.id = s.company_id
    group by 1, 2
  ),
  people as (
    select e.company_id as cid, e.branch_id as bid, count(*) as active_n,
           count(*) filter (where u.last_sign_in_at >= now() - interval '7 days') as recent_n
    from public.employees e left join auth.users u on u.id = e.user_id
    where e.status = 'active'
    group by 1, 2
  ),
  agg as (
    select k.cid, k.bid,
           grouping(k.bid) as is_total,
           sum(coalesce(ru.total, 0))::int as runs_total,
           sum(coalesce(ru.done, 0))::int as runs_completed,
           sum(coalesce(ru.on_time, 0))::int as runs_on_time,
           sum(coalesce(la.n, 0))::int as tasks_late,
           sum(coalesce(wa.n, 0))::int as waste_count,
           round(sum(coalesce(wa.qty, 0)), 3) as waste_qty,
           round(sum(coalesce(wa.val, 0)), 2) as waste_value,
           sum(coalesce(co.total, 0))::int as counts_total,
           sum(coalesce(co.exact, 0))::int as counts_exact,
           sum(coalesce(ga.open_n, 0))::int as gaps_open,
           sum(coalesce(ga.resolved_n, 0))::int as gaps_resolved,
           sum(coalesce(ga.hours_sum, 0)) as gap_hours_sum,
           sum(coalesce(ti.open_n, 0))::int as tickets_open,
           sum(coalesce(ti.overdue_n, 0))::int as tickets_overdue,
           sum(coalesce(ti.sla_total, 0))::int as sla_total,
           sum(coalesce(ti.sla_met, 0))::int as sla_met,
           sum(coalesce(pe.active_n, 0))::int as employees_active,
           sum(coalesce(pe.recent_n, 0))::int as users_7d
    from keys k
    left join runs ru    on ru.cid = k.cid and ru.bid is not distinct from k.bid
    left join late la    on la.cid = k.cid and la.bid is not distinct from k.bid
    left join waste wa   on wa.cid = k.cid and wa.bid is not distinct from k.bid
    left join counts co  on co.cid = k.cid and co.bid is not distinct from k.bid
    left join gaps ga    on ga.cid = k.cid and ga.bid is not distinct from k.bid
    left join tickets ti on ti.cid = k.cid and ti.bid is not distinct from k.bid
    left join people pe  on pe.cid = k.cid and pe.bid is not distinct from k.bid
    group by grouping sets ((k.cid), (k.cid, k.bid))
    having grouping(k.bid) = 1 or k.bid is not null
  )
  select a.cid, c.name, c.code, c.status,
         case when a.is_total = 1 then null else a.bid end, b.name, b.code, b.status,
         a.runs_total, a.runs_completed, a.runs_on_time,
         round(100.0 * a.runs_completed / nullif(a.runs_total, 0))::int,
         round(100.0 * a.runs_on_time / nullif(a.runs_total, 0))::int,
         a.tasks_late,
         a.waste_count, a.waste_qty, a.waste_value,
         a.counts_total, a.counts_exact,
         round(100.0 * a.counts_exact / nullif(a.counts_total, 0))::int,
         a.gaps_open, a.gaps_resolved,
         round((a.gap_hours_sum / nullif(a.gaps_resolved, 0))::numeric, 1),
         a.tickets_open, a.tickets_overdue, a.sla_total, a.sla_met,
         round(100.0 * a.sla_met / nullif(a.sla_total, 0))::int,
         a.employees_active, a.users_7d
  from agg a
  join public.companies c on c.id = a.cid
  left join public.branches b on b.id = a.bid and a.is_total = 0
  order by c.name, a.is_total desc, b.code;
end $$;
revoke all on function public.perf_kpis(date, date, uuid, uuid[]) from public, anon, authenticated;

create or replace function public.perf_trend(p_company_id uuid, p_branch_ids uuid[], p_metric text, p_from date, p_to date)
returns table (day date, value numeric, base integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 366 then raise exception 'El periodo máximo es de un año'; end if;
  if p_metric not in ('checklist_pct', 'checklist_on_time_pct', 'tasks_on_time_pct', 'waste_value', 'waste_count',
                      'count_accuracy_pct', 'gaps_reported', 'gap_hours', 'tickets_created') then
    raise exception 'Métrica desconocida: %', p_metric;
  end if;

  return query
  with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
  co as (select c.id, c.timezone from public.companies c where p_company_id is null or c.id = p_company_id),
  src as (
    -- Checklists (por fecha programada)
    select r.scheduled_date as day,
           case when p_metric = 'checklist_pct' then (r.status = 'completed')
                else (r.status = 'completed' and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone co.timezone)) end::int::numeric as v
    from public.checklist_runs r join co on co.id = r.company_id and (p_branch_ids is null or r.branch_id = any (p_branch_ids))
    where p_metric in ('checklist_pct', 'checklist_on_time_pct')
      and r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
      and ((r.scheduled_date + r.scheduled_end) at time zone co.timezone) <= now()
    union all
    -- Tareas completadas ese día: a tiempo si no tenían fecha límite o se cerraron a más tardar ese día
    select (t.completed_at at time zone co.timezone)::date,
           (t.due_date is null or (t.completed_at at time zone co.timezone)::date <= t.due_date)::int::numeric
    from public.tasks t join co on co.id = t.company_id and (p_branch_ids is null or t.branch_id = any (p_branch_ids))
    where p_metric = 'tasks_on_time_pct' and t.status = 'completed' and t.completed_at is not null
      and (t.completed_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Mermas
    select (m.created_at at time zone co.timezone)::date,
           case when p_metric = 'waste_value' then m.quantity * coalesce(m.unit_cost, p.cost, 0) else 1 end
    from public.inventory_movements m join co on co.id = m.company_id and (p_branch_ids is null or m.branch_id = any (p_branch_ids)) join public.products p on p.id = m.product_id
    where p_metric in ('waste_value', 'waste_count') and m.movement_type = 'waste'
      and (m.created_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Conteo cíclico
    select (i.counted_at at time zone co.timezone)::date, (i.difference = 0)::int::numeric
    from public.cycle_count_items i join public.cycle_count_tasks k on k.id = i.task_id join co on co.id = k.company_id and (p_branch_ids is null or k.branch_id = any (p_branch_ids))
    where p_metric = 'count_accuracy_pct' and i.counted_at is not null
      and (i.counted_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Huecos reportados ese día / horas de atención de los resueltos ese día
    select case when p_metric = 'gaps_reported' then (g.reported_at at time zone co.timezone)::date
                else (g.resolved_at at time zone co.timezone)::date end,
           case when p_metric = 'gaps_reported' then 1
                else (extract(epoch from g.resolved_at - g.reported_at) / 3600)::numeric end
    from public.shelf_gaps g join co on co.id = g.company_id and (p_branch_ids is null or g.branch_id = any (p_branch_ids))
    where (p_metric = 'gaps_reported' and (g.reported_at at time zone co.timezone)::date between p_from and p_to)
       or (p_metric = 'gap_hours' and g.status = 'resolved' and (g.resolved_at at time zone co.timezone)::date between p_from and p_to)
    union all
    -- Tickets creados
    select (s.created_at at time zone co.timezone)::date, 1::numeric
    from public.support_tickets s join co on co.id = s.company_id and (p_branch_ids is null or s.branch_id = any (p_branch_ids))
    where p_metric = 'tickets_created' and (s.created_at at time zone co.timezone)::date between p_from and p_to
  )
  select d.day,
         case
           when p_metric in ('waste_value') then round(coalesce(sum(s.v), 0), 2)
           when p_metric in ('waste_count', 'gaps_reported', 'tickets_created') then coalesce(sum(s.v), 0)
           when p_metric = 'gap_hours' then round(avg(s.v), 1)
           else round(100.0 * sum(s.v) / nullif(count(s.v), 0))
         end,
         count(s.v)::int
  from days d left join src s on s.day = d.day
  group by d.day
  order by d.day;
end $$;
revoke all on function public.perf_trend(uuid, uuid[], text, date, date) from public, anon, authenticated;

create or replace function public.perf_heatmap(p_from date, p_to date, p_company_id uuid, p_branch_ids uuid[])
returns table (company_id uuid, company_name text, branch_id uuid, branch_name text, day date, runs_total integer, pct integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 92 then raise exception 'El mapa de calor abarca hasta 93 días'; end if;
  return query
  select c.id, c.name, b.id, b.name, r.scheduled_date, count(*)::int,
         round(100.0 * count(*) filter (where r.status = 'completed') / count(*))::int
  from public.checklist_runs r
  join public.branches b on b.id = r.branch_id
  join public.companies c on c.id = r.company_id
  where r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
    and ((r.scheduled_date + r.scheduled_end) at time zone c.timezone) <= now()
    and (p_company_id is null or r.company_id = p_company_id)
    and (p_branch_ids is null or r.branch_id = any (p_branch_ids))
  group by c.id, c.name, b.id, b.name, b.code, r.scheduled_date
  order by c.name, b.code, r.scheduled_date;
end $$;
revoke all on function public.perf_heatmap(date, date, uuid, uuid[]) from public, anon, authenticated;

-- ─── Superadmin: toda la plataforma (misma firma que en 0025) ──────────────
create or replace function public.platform_company_kpis(p_from date, p_to date)
returns table (
  company_id uuid, company_name text, company_code text, company_status text,
  branch_id uuid, branch_name text, branch_code text, branch_status text,
  runs_total integer, runs_completed integer, runs_on_time integer,
  checklist_pct integer, checklist_on_time_pct integer,
  tasks_late integer,
  waste_count integer, waste_qty numeric, waste_value numeric,
  counts_total integer, counts_exact integer, count_accuracy_pct integer,
  gaps_open integer, gaps_resolved integer, gap_hours numeric,
  tickets_open integer, tickets_overdue integer, sla_total integer, sla_met integer, sla_pct integer,
  employees_active integer, users_7d integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  return query select * from public.perf_kpis(p_from, p_to, null, null);
end $$;
revoke all on function public.platform_company_kpis(date, date) from public, anon;
grant execute on function public.platform_company_kpis(date, date) to authenticated;

create or replace function public.platform_company_trend(p_company_id uuid, p_metric text, p_from date, p_to date)
returns table (day date, value numeric, base integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  return query select * from public.perf_trend(p_company_id, null, p_metric, p_from, p_to);
end $$;
revoke all on function public.platform_company_trend(uuid, text, date, date) from public, anon;
grant execute on function public.platform_company_trend(uuid, text, date, date) to authenticated;

create or replace function public.platform_checklist_heatmap(p_from date, p_to date, p_company_id uuid default null)
returns table (company_id uuid, company_name text, branch_id uuid, branch_name text, day date, runs_total integer, pct integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  return query select * from public.perf_heatmap(p_from, p_to, p_company_id, null);
end $$;
revoke all on function public.platform_checklist_heatmap(date, date, uuid) from public, anon;
grant execute on function public.platform_checklist_heatmap(date, date, uuid) to authenticated;

-- ─── Cada empresa: sus sucursales, según el alcance de quien consulta ──────
-- Sucursales que quien llama puede ver (company: todas; zone: las de sus
-- zonas; branch y menores: la suya). Exige view_reports.
create or replace function public.my_report_branch_ids()
returns uuid[] language plpgsql stable security definer set search_path = public as $$
begin
  if public.auth_company_id() is null or not public.has_permission('view_reports') then
    raise exception 'No tienes permiso para ver el rendimiento de las sucursales';
  end if;
  return array(select b.id from public.branches b
               where b.company_id = public.auth_company_id() and public.can_access_branch(b.id));
end $$;
revoke all on function public.my_report_branch_ids() from public, anon, authenticated;

create or replace function public.branch_kpis(p_from date, p_to date)
returns table (
  company_id uuid, company_name text, company_code text, company_status text,
  branch_id uuid, branch_name text, branch_code text, branch_status text,
  runs_total integer, runs_completed integer, runs_on_time integer,
  checklist_pct integer, checklist_on_time_pct integer,
  tasks_late integer,
  waste_count integer, waste_qty numeric, waste_value numeric,
  counts_total integer, counts_exact integer, count_accuracy_pct integer,
  gaps_open integer, gaps_resolved integer, gap_hours numeric,
  tickets_open integer, tickets_overdue integer, sla_total integer, sla_met integer, sla_pct integer,
  employees_active integer, users_7d integer)
language plpgsql stable security definer set search_path = public as $$
begin
  return query select * from public.perf_kpis(p_from, p_to, public.auth_company_id(), public.my_report_branch_ids());
end $$;
revoke all on function public.branch_kpis(date, date) from public, anon;
grant execute on function public.branch_kpis(date, date) to authenticated;

-- p_branch_id null = todas las sucursales que puede ver.
create or replace function public.branch_trend(p_branch_id uuid, p_metric text, p_from date, p_to date)
returns table (day date, value numeric, base integer)
language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[] := public.my_report_branch_ids();
begin
  if p_branch_id is not null then
    if not (p_branch_id = any (v_ids)) then raise exception 'Sucursal no permitida'; end if;
    v_ids := array[p_branch_id];
  end if;
  return query select * from public.perf_trend(public.auth_company_id(), v_ids, p_metric, p_from, p_to);
end $$;
revoke all on function public.branch_trend(uuid, text, date, date) from public, anon;
grant execute on function public.branch_trend(uuid, text, date, date) to authenticated;

create or replace function public.branch_checklist_heatmap(p_from date, p_to date)
returns table (company_id uuid, company_name text, branch_id uuid, branch_name text, day date, runs_total integer, pct integer)
language plpgsql stable security definer set search_path = public as $$
begin
  return query select * from public.perf_heatmap(p_from, p_to, public.auth_company_id(), public.my_report_branch_ids());
end $$;
revoke all on function public.branch_checklist_heatmap(date, date) from public, anon;
grant execute on function public.branch_checklist_heatmap(date, date) to authenticated;
