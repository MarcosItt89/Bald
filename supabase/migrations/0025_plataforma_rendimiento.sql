-- =============================================================================
-- OPERALIA · 0025 · PLATAFORMA: RENDIMIENTO DE LAS TIENDAS Y PROSPECTOS
-- -----------------------------------------------------------------------------
--   A. Indicadores por empresa y sucursal para el superadmin. Solo devuelven
--      AGREGADOS (conteos, sumas y porcentajes), nunca filas de una empresa.
--        platform_company_kpis(desde, hasta)
--        platform_company_trend(empresa, métrica, desde, hasta)
--        platform_checklist_heatmap(desde, hasta, empresa)
--      Las definiciones son las de Estadísticas (src/services/reportService.js):
--        * checklists: corridas del periodo sin canceladas; completados ÷ total
--          (runCompliance). «A tiempo» = completado antes del fin de su
--          horario (isLate del reporte de checklists, al revés). Solo cuentan
--          las corridas cuyo horario ya terminó: las de hoy que siguen en su
--          ventana aún no se pueden calificar (si no, «hoy» saldría en 0 %).
--        * tareas vencidas: abiertas con fecha límite pasada (v_tasks.is_late).
--        * tareas a tiempo: completadas el día de su fecha límite o antes (taskOnTime).
--        * mermas: movimientos 'waste'; valor = cantidad × (unit_cost o costo del producto).
--        * exactitud del conteo cíclico: productos contados sin diferencia ÷ contados.
--        * SLA de soporte: tickets del periodo con vencimiento; cumplido si se
--          resolvió/cerró antes de due_at o si sigue abierto y aún no vence (slaOf).
--      Nuevo (Estadísticas no lo tenía): tiempo de atención de huecos en
--      anaquel = horas de reported_at a resolved_at de los resueltos, con la
--      misma fórmula que las horas de cierre de tareas.
--      Los días se cuentan en la zona horaria de cada empresa.
--   B. platform_company_health(): salud de la cuenta (verde, amarillo, rojo) y
--      avance de arranque por empresa.
--   C. platform_leads: prospectos de la plataforma.
-- Todas las funciones son SECURITY DEFINER y fallan si not is_platform_admin().
-- Re-ejecutable.
-- =============================================================================

-- ─── C. PROSPECTOS (va primero: la salud de la cuenta lo consulta) ──────────
create table if not exists public.platform_leads (
  id            uuid primary key default gen_random_uuid(),
  chain_name    text not null,                 -- nombre de la cadena
  contact_name  text,
  contact_email text,
  contact_phone text,
  branch_count  integer check (branch_count is null or branch_count >= 0),
  business_type text,                          -- giro: abarrotes, farmacia, ferretería…
  status        text not null default 'new'
                check (status in ('new','demo','negotiation','won','lost')),
  notes         text,
  company_id    uuid references public.companies(id) on delete set null, -- al darla de alta
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists platform_leads_status_idx on public.platform_leads (status, updated_at desc);

drop trigger if exists trg_updated_at on public.platform_leads;
create trigger trg_updated_at before update on public.platform_leads
  for each row execute function public.tg_set_updated_at();

create or replace function public.tg_platform_lead_actor()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end $$;
drop trigger if exists trg_platform_lead_actor on public.platform_leads;
create trigger trg_platform_lead_actor before insert on public.platform_leads
  for each row execute function public.tg_platform_lead_actor();

-- Solo superadmins, desde la app; ninguna empresa los ve.
alter table public.platform_leads enable row level security;
revoke all on public.platform_leads from anon;
grant select, insert, update, delete on public.platform_leads to authenticated;
drop policy if exists platform_leads_all on public.platform_leads;
create policy platform_leads_all on public.platform_leads for all to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

-- ─── A. INDICADORES POR EMPRESA Y SUCURSAL ──────────────────────────────────
-- Una fila por empresa (branch_id null) y una por sucursal. Trae numeradores y
-- denominadores para que el frontend sume la plataforma completa sin promediar
-- porcentajes. Las métricas «actuales» (tareas vencidas, huecos y tickets
-- abiertos, empleados, accesos de 7 días) no dependen del periodo.
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
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 366 then raise exception 'El periodo máximo es de un año'; end if;

  return query
  with keys as (
    select b.company_id as cid, b.id as bid from public.branches b
    union all
    select c.id, null::uuid from public.companies c
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
revoke all on function public.platform_company_kpis(date, date) from public, anon;
grant execute on function public.platform_company_kpis(date, date) to authenticated;

-- Serie diaria de una métrica (p_company_id null = toda la plataforma).
-- value: el valor del día (null si no hubo base para calcularlo); base: cuántos
-- registros lo forman (corridas, tareas, mermas, productos contados…).
--   checklist_pct · checklist_on_time_pct · tasks_on_time_pct · waste_value ·
--   waste_count · count_accuracy_pct · gaps_reported · gap_hours · tickets_created
create or replace function public.platform_company_trend(p_company_id uuid, p_metric text, p_from date, p_to date)
returns table (day date, value numeric, base integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
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
    from public.checklist_runs r join co on co.id = r.company_id
    where p_metric in ('checklist_pct', 'checklist_on_time_pct')
      and r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
      and ((r.scheduled_date + r.scheduled_end) at time zone co.timezone) <= now()
    union all
    -- Tareas completadas ese día: a tiempo si no tenían fecha límite o se cerraron a más tardar ese día
    select (t.completed_at at time zone co.timezone)::date,
           (t.due_date is null or (t.completed_at at time zone co.timezone)::date <= t.due_date)::int::numeric
    from public.tasks t join co on co.id = t.company_id
    where p_metric = 'tasks_on_time_pct' and t.status = 'completed' and t.completed_at is not null
      and (t.completed_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Mermas
    select (m.created_at at time zone co.timezone)::date,
           case when p_metric = 'waste_value' then m.quantity * coalesce(m.unit_cost, p.cost, 0) else 1 end
    from public.inventory_movements m join co on co.id = m.company_id join public.products p on p.id = m.product_id
    where p_metric in ('waste_value', 'waste_count') and m.movement_type = 'waste'
      and (m.created_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Conteo cíclico
    select (i.counted_at at time zone co.timezone)::date, (i.difference = 0)::int::numeric
    from public.cycle_count_items i join public.cycle_count_tasks k on k.id = i.task_id join co on co.id = k.company_id
    where p_metric = 'count_accuracy_pct' and i.counted_at is not null
      and (i.counted_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Huecos reportados ese día / horas de atención de los resueltos ese día
    select case when p_metric = 'gaps_reported' then (g.reported_at at time zone co.timezone)::date
                else (g.resolved_at at time zone co.timezone)::date end,
           case when p_metric = 'gaps_reported' then 1
                else (extract(epoch from g.resolved_at - g.reported_at) / 3600)::numeric end
    from public.shelf_gaps g join co on co.id = g.company_id
    where (p_metric = 'gaps_reported' and (g.reported_at at time zone co.timezone)::date between p_from and p_to)
       or (p_metric = 'gap_hours' and g.status = 'resolved' and (g.resolved_at at time zone co.timezone)::date between p_from and p_to)
    union all
    -- Tickets creados
    select (s.created_at at time zone co.timezone)::date, 1::numeric
    from public.support_tickets s join co on co.id = s.company_id
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
revoke all on function public.platform_company_trend(uuid, text, date, date) from public, anon;
grant execute on function public.platform_company_trend(uuid, text, date, date) to authenticated;

-- Cumplimiento de checklists (runCompliance) por sucursal y día.
create or replace function public.platform_checklist_heatmap(p_from date, p_to date, p_company_id uuid default null)
returns table (company_id uuid, company_name text, branch_id uuid, branch_name text, day date, runs_total integer, pct integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
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
  group by c.id, c.name, b.id, b.name, b.code, r.scheduled_date
  order by c.name, b.code, r.scheduled_date;
end $$;
revoke all on function public.platform_checklist_heatmap(date, date, uuid) from public, anon;
grant execute on function public.platform_checklist_heatmap(date, date, uuid) to authenticated;

-- ─── B. SALUD DE LA CUENTA Y AVANCE DE ARRANQUE ─────────────────────────────
-- Salud (últimos 7 días de cada empresa); gana el peor de los tres criterios:
--   uso:         % de empleados con cuenta que entraron  · verde ≥ 60, amarillo ≥ 30, rojo < 30
--   checklists:  % completados a tiempo, solo de los que  · verde ≥ 60, amarillo ≥ 45, rojo < 45 (sin corridas: amarillo)
--                ya terminaron su horario (los de hoy aún abiertos no cuentan)
--   tickets:     abiertos por sucursal activa            · verde ≤ 1, amarillo ≤ 2, rojo > 2
-- Arranque: 5 pasos (sucursales creadas, empleados con cuenta, productos
-- cargados, primera plantilla usada, primer recibo cerrado).
create or replace function public.platform_company_health()
returns table (
  company_id uuid, health text, reasons text[],
  accounts integer, users_7d integer, usage_pct integer,
  runs_7d integer, checklist_on_time_pct integer, tickets_open integer, branches integer,
  onboarding_pct integer, onboarding jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve la salud de las cuentas';
  end if;

  return query
  with base as (
    select c.id as cid, c.timezone as tz, public.company_today(c.id) as today,
           (select count(*)::int from public.branches b where b.company_id = c.id and b.status = 'active') as branches,
           (select l.branch_count from public.platform_leads l where l.company_id = c.id
             order by l.updated_at desc limit 1) as target_branches,
           (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active' and e.user_id is not null) as accounts,
           (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active'
               and e.user_id is not null and not e.is_owner) as staff_accounts,
           (select count(*)::int from public.employees e join auth.users u on u.id = e.user_id
             where e.company_id = c.id and e.status = 'active' and u.last_sign_in_at >= now() - interval '7 days') as users_7d,
           (select count(*)::int from public.products p where p.company_id = c.id) as products,
           (select min(r.completed_at) from public.checklist_runs r where r.company_id = c.id and r.status = 'completed') as first_run,
           (select min(o.completed_at) from public.receiving_orders o where o.company_id = c.id and o.status = 'completed') as first_receipt,
           (select count(*)::int from public.support_tickets s where s.company_id = c.id
               and s.status in ('open', 'in_progress', 'waiting_user')) as tickets_open
    from public.companies c
  ),
  week as (
    select b.cid,
           count(r.id)::int as runs_7d,
           round(100.0 * count(r.id) filter (where r.status = 'completed'
                   and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone b.tz)) / nullif(count(r.id), 0))::int as on_time
    from base b
    left join public.checklist_runs r on r.company_id = b.cid and r.status <> 'cancelled'
         and r.scheduled_date between b.today - 6 and b.today
         and ((r.scheduled_date + r.scheduled_end) at time zone b.tz) <= now()
    group by b.cid
  ),
  scored as (
    select b.*, w.runs_7d, w.on_time,
           round(100.0 * b.users_7d / nullif(b.accounts, 0))::int as usage_pct,
           case when coalesce(round(100.0 * b.users_7d / nullif(b.accounts, 0)), 0) >= 60 then 0
                when coalesce(round(100.0 * b.users_7d / nullif(b.accounts, 0)), 0) >= 30 then 1 else 2 end as s_usage,
           case when w.on_time is null then 1 when w.on_time >= 60 then 0 when w.on_time >= 45 then 1 else 2 end as s_runs,
           case when b.tickets_open <= greatest(b.branches, 1) then 0
                when b.tickets_open <= 2 * greatest(b.branches, 1) then 1 else 2 end as s_tickets
    from base b join week w on w.cid = b.cid
  )
  select s.cid,
         (array['green', 'yellow', 'red'])[greatest(s.s_usage, s.s_runs, s.s_tickets) + 1],
         array_remove(array[
           case when s.s_usage > 0 then
             case when s.accounts = 0 then 'Nadie tiene cuenta todavía'
                  else coalesce(s.usage_pct, 0) || ' % de los usuarios entró en 7 días' end end,
           case when s.s_runs > 0 then
             case when s.on_time is null then 'Sin checklists en 7 días'
                  else s.on_time || ' % de checklists a tiempo' end end,
           case when s.s_tickets > 0 then s.tickets_open || ' tickets abiertos' end
         ], null),
         s.accounts, s.users_7d, s.usage_pct, s.runs_7d, s.on_time, s.tickets_open, s.branches,
         (100 * ((s.branches >= greatest(coalesce(s.target_branches, 1), 1))::int
               + (s.staff_accounts >= greatest(s.branches, 1))::int
               + (s.products > 0)::int
               + (s.first_run is not null)::int
               + (s.first_receipt is not null)::int) / 5)::int,
         jsonb_build_array(
           jsonb_build_object('key', 'branches', 'label', 'Sucursales creadas',
             'done', s.branches >= greatest(coalesce(s.target_branches, 1), 1),
             'detail', s.branches || coalesce(' de ' || s.target_branches, '')),
           jsonb_build_object('key', 'accounts', 'label', 'Empleados con cuenta',
             'done', s.staff_accounts >= greatest(s.branches, 1),
             'detail', s.staff_accounts || ' además del propietario (mínimo 1 por sucursal)'),
           jsonb_build_object('key', 'products', 'label', 'Productos cargados',
             'done', s.products > 0, 'detail', s.products || ' productos'),
           jsonb_build_object('key', 'first_run', 'label', 'Primera plantilla usada',
             'done', s.first_run is not null,
             'detail', coalesce(to_char(s.first_run at time zone s.tz, 'DD/MM/YYYY'), 'ningún checklist completado')),
           jsonb_build_object('key', 'first_receipt', 'label', 'Primer recibo cerrado',
             'done', s.first_receipt is not null,
             'detail', coalesce(to_char(s.first_receipt at time zone s.tz, 'DD/MM/YYYY'), 'ningún recibo cerrado')))
  from scored s;
end $$;
revoke all on function public.platform_company_health() from public, anon;
grant execute on function public.platform_company_health() to authenticated;
