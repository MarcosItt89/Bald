-- =============================================================================
-- OPERALIA · 0034 · DATASET PARA MINERÍA DE DATOS (SUCURSAL-DÍA)
-- -----------------------------------------------------------------------------
-- Convierte la operación registrada en la app en una tabla plana: un renglón por
-- sucursal y día, con lo que pasó ese día. Sirve para IBM SPSS Modeler,
-- Watson Studio, Excel o Python sin tocar las tablas de la app.
--
--   public.mineria_dataset(desde, hasta)        conteos y montos (para clústeres,
--                                               árboles de decisión, regresión)
--   public.mineria_dataset_flags(desde, hasta)  los mismos días en 0/1 (para Apriori)
--
-- Solo los superadmins de la plataforma (o el SQL Editor) pueden llamarlas:
-- juntan datos de todas las empresas. Funcionan con datos reales y de demo, y
-- con cualquier empresa nueva sin cambiar nada.
--
-- Exportar a CSV: SQL Editor → `select * from public.mineria_dataset_flags();`
-- → Download CSV. Las fechas son del día local de cada empresa.
--
-- Cómo se reconoce cada checklist (las empresas pueden renombrar plantillas):
--   apertura       turno 'apertura'
--   caducidades    título con «caducidad»
--   rondín         título con «rondín»
--   precios        título con «precio»
-- «Tarde» = terminado después de la hora fin de su plantilla, o vencido.
-- =============================================================================

create or replace function public.mineria_dataset(p_desde date default null, p_hasta date default null)
returns table (
  empresa text, sucursal_codigo text, sucursal text, tipo_sucursal text, ciudad text,
  fecha date, dia_semana int, fin_de_semana int, quincena int,
  checklists_programados int, checklists_completados int, cumplimiento_pct numeric,
  aperturas_tarde int, caducidades_sin_revisar int, rondines_sin_hacer int, precios_tarde int,
  lecturas_temperatura int, lecturas_fuera_rango int,
  tareas int, tareas_atrasadas int,
  recibos int, piezas_faltantes_recibo numeric, piezas_danadas_recibo numeric,
  mermas int, merma_valor numeric, mermas_caducidad int, mermas_temperatura int, mermas_danio int, mermas_robo int,
  huecos_anaquel int, conteo_renglones int, conteo_diferencias int, conteo_valor_diferencia numeric,
  tickets_soporte int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_platform_admin() or public.is_system_context() or auth.uid() is null) then
    raise exception 'Solo los superadmins de la plataforma pueden exportar el dataset de minería';
  end if;

  return query
  with dias as (
    select b.id as branch_id, b.company_id, co.code as empresa, b.code, b.name, b.branch_type, b.city, co.timezone as tz,
           r.scheduled_date as fecha,
           count(*)::int as prog,
           count(*) filter (where r.status = 'completed')::int as comp,
           count(*) filter (where t.shift = 'apertura' and (r.status = 'overdue'
                            or r.completed_at > (r.scheduled_date + r.scheduled_end) at time zone co.timezone))::int as ap_tarde,
           count(*) filter (where t.title ilike '%caducidad%' and r.status <> 'completed')::int as cad,
           count(*) filter (where (t.title ilike '%rondín%' or t.title ilike '%rondin%') and r.status <> 'completed')::int as ron,
           count(*) filter (where t.title ilike '%precio%' and (r.status <> 'completed'
                            or r.completed_at > (r.scheduled_date + r.scheduled_end) at time zone co.timezone))::int as pre
    from public.checklist_runs r
    join public.checklist_templates t on t.id = r.template_id
    join public.branches b on b.id = r.branch_id
    join public.companies co on co.id = b.company_id
    where r.status <> 'cancelled'
      and (p_desde is null or r.scheduled_date >= p_desde)
      and (p_hasta is null or r.scheduled_date <= p_hasta)
      and r.scheduled_date < public.company_today(co.id)
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
  ),
  temp as (
    select r.branch_id, r.scheduled_date as fecha, count(*)::int as n,
           count(*) filter (where a.answer_value ~ '^-?[0-9]+(\.[0-9]+)?$'
                            and (a.answer_value::numeric > q.max_value or a.answer_value::numeric < q.min_value))::int as fuera
    from public.checklist_answers a
    join public.checklist_questions q on q.id = a.question_id and q.min_value is not null and q.max_value is not null
    join public.checklist_runs r on r.id = a.run_id
    group by 1, 2
  ),
  tar as (
    select t.branch_id, (t.created_at at time zone co.timezone)::date as fecha, count(*)::int as n,
           count(*) filter (where (t.completed_at at time zone co.timezone)::date > t.due_date
                            or (t.status <> 'completed' and t.due_date < public.company_today(co.id)))::int as atr
    from public.tasks t join public.companies co on co.id = t.company_id
    where t.branch_id is not null and t.status <> 'cancelled' and t.title <> 'Historial de minería generado'
    group by 1, 2
  ),
  rec as (
    select o.branch_id, (o.completed_at at time zone co.timezone)::date as fecha, count(distinct o.id)::int as n,
           coalesce(sum(greatest(i.expected_qty - i.received_qty, 0)), 0) as falt,
           coalesce(sum(i.damaged_qty), 0) as dan
    from public.receiving_orders o
    join public.companies co on co.id = o.company_id
    left join public.receiving_items i on i.receiving_order_id = o.id
    where o.status = 'completed'
    group by 1, 2
  ),
  mer as (
    select m.branch_id, (m.created_at at time zone co.timezone)::date as fecha, count(*)::int as n,
           round(sum(m.quantity * coalesce(m.unit_cost, p.cost)), 2) as valor,
           count(*) filter (where m.waste_reason = 'expired')::int as cad,
           count(*) filter (where m.waste_reason = 'temperature')::int as tmp,
           count(*) filter (where m.waste_reason in ('damaged', 'mishandling'))::int as dan,
           count(*) filter (where m.waste_reason = 'theft')::int as rob
    from public.inventory_movements m
    join public.companies co on co.id = m.company_id
    join public.products p on p.id = m.product_id
    where m.movement_type = 'waste'
    group by 1, 2
  ),
  hue as (
    select g.branch_id, (g.reported_at at time zone co.timezone)::date as fecha, count(*)::int as n
    from public.shelf_gaps g join public.companies co on co.id = g.company_id
    group by 1, 2
  ),
  con as (
    select t.branch_id, t.scheduled_date as fecha, count(i.counted_at)::int as n,
           count(*) filter (where i.difference <> 0)::int as dif,
           coalesce(sum(i.difference_value), 0) as valor
    from public.cycle_count_tasks t join public.cycle_count_items i on i.task_id = t.id
    group by 1, 2
  ),
  tic as (
    select s.branch_id, (s.created_at at time zone co.timezone)::date as fecha, count(*)::int as n
    from public.support_tickets s join public.companies co on co.id = s.company_id
    where s.branch_id is not null
    group by 1, 2
  )
  select d.empresa, d.code, d.name, d.branch_type, d.city,
         d.fecha, extract(isodow from d.fecha)::int,
         (extract(isodow from d.fecha) in (5, 6, 7))::int,
         (extract(day from d.fecha) in (1, 14, 15, 16, 29, 30, 31))::int,
         d.prog, d.comp, round(100.0 * d.comp / nullif(d.prog, 0), 1),
         d.ap_tarde, d.cad, d.ron, d.pre,
         coalesce(temp.n, 0), coalesce(temp.fuera, 0),
         coalesce(tar.n, 0), coalesce(tar.atr, 0),
         coalesce(rec.n, 0), coalesce(rec.falt, 0), coalesce(rec.dan, 0),
         coalesce(mer.n, 0), coalesce(mer.valor, 0), coalesce(mer.cad, 0), coalesce(mer.tmp, 0), coalesce(mer.dan, 0), coalesce(mer.rob, 0),
         coalesce(hue.n, 0), coalesce(con.n, 0), coalesce(con.dif, 0), coalesce(con.valor, 0),
         coalesce(tic.n, 0)
  from dias d
  left join temp on temp.branch_id = d.branch_id and temp.fecha = d.fecha
  left join tar  on tar.branch_id  = d.branch_id and tar.fecha  = d.fecha
  left join rec  on rec.branch_id  = d.branch_id and rec.fecha  = d.fecha
  left join mer  on mer.branch_id  = d.branch_id and mer.fecha  = d.fecha
  left join hue  on hue.branch_id  = d.branch_id and hue.fecha  = d.fecha
  left join con  on con.branch_id  = d.branch_id and con.fecha  = d.fecha
  left join tic  on tic.branch_id  = d.branch_id and tic.fecha  = d.fecha
  order by d.empresa, d.code, d.fecha;
end $$;

-- Versión dicotómica (0/1) para Apriori: cada columna es «pasó o no pasó».
create or replace function public.mineria_dataset_flags(p_desde date default null, p_hasta date default null)
returns table (
  id_dia text, empresa text, sucursal_codigo text, fecha date,
  fin_de_semana int, quincena int, cumplimiento_bajo int,
  apertura_tarde int, caducidades_sin_revisar int, rondin_sin_hacer int, precios_tarde int,
  temp_fuera_rango int, tareas_atrasadas int,
  recibo_con_faltante int, recibo_con_danio int,
  merma_caducidad int, merma_temperatura int, merma_danio int, merma_robo int,
  hueco_anaquel int, conteo_con_diferencia int, ticket_soporte int)
language sql stable security definer set search_path = public as $$
  select d.empresa || '-' || d.sucursal_codigo || '-' || to_char(d.fecha, 'YYYYMMDD'),
         d.empresa, d.sucursal_codigo, d.fecha,
         d.fin_de_semana, d.quincena, (d.cumplimiento_pct < 80)::int,
         (d.aperturas_tarde > 0)::int, (d.caducidades_sin_revisar > 0)::int, (d.rondines_sin_hacer > 0)::int, (d.precios_tarde > 0)::int,
         (d.lecturas_fuera_rango > 0)::int, (d.tareas_atrasadas > 0)::int,
         (d.piezas_faltantes_recibo > 0)::int, (d.piezas_danadas_recibo > 0)::int,
         (d.mermas_caducidad > 0)::int, (d.mermas_temperatura > 0)::int, (d.mermas_danio > 0)::int, (d.mermas_robo > 0)::int,
         (d.huecos_anaquel > 0)::int, (d.conteo_diferencias > 0)::int, (d.tickets_soporte > 0)::int
  from public.mineria_dataset(p_desde, p_hasta) d;
$$;

revoke all on function public.mineria_dataset(date, date) from public, anon;
revoke all on function public.mineria_dataset_flags(date, date) from public, anon;
grant execute on function public.mineria_dataset(date, date) to authenticated;
grant execute on function public.mineria_dataset_flags(date, date) to authenticated;
