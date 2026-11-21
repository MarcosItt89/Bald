-- =============================================================================
-- OPERALIA · DEMO 0034 · HISTORIAL PARA MINERÍA DE DATOS (TODAS LAS EMPRESAS)
-- -----------------------------------------------------------------------------
-- SOLO para ambientes de prueba. Requiere 0001-0033 y demo/0009 (seed_company_demo).
--
-- Por qué existe: el historial de demo/0019 sale de un solo dado por sucursal
-- («calidad»), así que todo se correlaciona con todo y nada causa nada. Por
-- ejemplo, el motivo de una merma se elige al azar y no tiene que ver con las
-- temperaturas fuera de rango. Un algoritmo como Apriori solo redescubriría
-- ese dado.
--
-- Este script agrega días ANTERIORES al historial que ya existe (no borra ni
-- cambia nada), con causas y efectos de operación real de supermercado:
--
--   Causa oculta (no la ve la app)    Síntomas que sí registra la app
--   ───────────────────────────────── ──────────────────────────────────────────
--   Falta de personal                 apertura tarde, revisión de caducidades y
--                                     rondín sin hacer, tareas atrasadas
--   Falla de refrigeración            lecturas fuera de rango → merma por temperatura
--   Recibo con faltante               hueco en anaquel → diferencias en conteo
--   Recibo con producto dañado        merma por daño
--   Caducidades sin revisar           merma por caducidad
--   Rondín sin hacer + mucha gente    merma por robo → diferencia en conteo
--   Falla de escáner (ticket)         actualización de precios tarde
--   Fin de semana o quincena          más huecos y más faltantes
--
-- Uso:
--   select public.demo_mining_history(id) from public.companies;         -- todas
--   select public.demo_mining_history(id, 120) from public.companies where code = 'nueva';
--
-- Funciona con cualquier empresa: a una empresa nueva sin historial le genera
-- los últimos N días; a una que ya tiene, los N días anteriores al primero.
-- Re-ejecutable: si la empresa ya tiene este historial, se omite.
--
-- El dataset para minería se obtiene con public.mineria_dataset() (migración 0034).
-- =============================================================================

create or replace function public.demo_mining_history(p_company_id uuid, p_days integer default 120)
returns text language plpgsql security definer set search_path = public as $$
declare
  c        uuid := p_company_id;
  v_code   text;
  v_tz     text;
  v_prev   text;
  v_first  date;
  v_end    date;     -- último día a generar (inclusive)
  v_start  date;
  d        date;
  v_rows   int;
begin
  select code, timezone into v_code, v_tz from public.companies where id = c;
  if v_code is null then raise exception 'No existe la empresa %', c; end if;
  if exists (select 1 from public.tasks where company_id = c and source_type = 'demo_mineria') then
    return v_code || ': ya tiene historial de minería; se omite.';
  end if;

  v_prev := public.set_bypass('on');
  -- Mismo resultado en cada instalación limpia (reproducible para la clase).
  perform setseed(((abs(hashtext(v_code)) % 1000) / 1000.0) * 0.9);

  -- Catálogo y datos base si la empresa es nueva.
  if not exists (select 1 from public.products where company_id = c) then
    perform public.seed_company_demo(c);
  end if;

  -- ── Catálogo ampliado (más productos que mermar, recibir y contar) ────────
  insert into public.products (company_id, department_id, sku, name, category, unit, cost, price, controls_expiration, is_weighable)
  select c, (select id from public.departments where company_id = c and code = v.dept), v.sku, v.name, v.cat, v.unit, v.cost, v.price, v.exp, v.weigh
  from (values
    ('ABA','ABR-010','Pasta para sopa 200 g',     'Pastas',     'pz',  6.50, 11.00, false, false),
    ('ABA','ABR-011','Harina de trigo 1 kg',      'Harinas',    'pz', 18.00, 27.50, false, false),
    ('ABA','ABR-012','Galletas María 170 g',      'Galletas',   'pz', 11.00, 17.90, true,  false),
    ('ABA','ABR-013','Chiles en vinagre 220 g',   'Enlatados',  'pz', 12.50, 19.50, true,  false),
    ('ABA','BEB-002','Refresco de cola 2 L',      'Bebidas',    'pz', 22.00, 34.00, false, false),
    ('ABA','BEB-003','Jugo de naranja 1 L',       'Bebidas',    'pz', 19.00, 29.90, true,  false),
    ('ABA','LIM-002','Papel higiénico 4 rollos',  'Limpieza',   'pz', 24.00, 36.00, false, false),
    ('ABA','LIM-003','Cloro 1 L',                 'Limpieza',   'pz', 11.00, 18.50, false, false),
    ('CAD','LAC-003','Queso panela 400 g',        'Lácteos',    'pz', 52.00, 76.00, true,  false),
    ('CAD','LAC-004','Crema ácida 450 ml',        'Lácteos',    'pz', 26.00, 38.50, true,  false),
    ('CAD','LAC-005','Mantequilla 90 g',          'Lácteos',    'pz', 17.00, 26.00, true,  false),
    ('CAD','EMB-002','Salchicha de pavo 500 g',   'Embutidos',  'pz', 31.00, 46.00, true,  false),
    ('CAD','PAN-001','Pan de caja blanco 680 g',  'Panadería',  'pz', 34.00, 52.00, true,  false),
    ('CAD','PAN-002','Tortilla de harina 10 pz',  'Panadería',  'pz', 16.00, 25.00, true,  false),
    ('CAR','CAR-002','Pechuga de pollo',          'Pollo',      'kg', 98.00,139.00, true,  true),
    ('CAR','CAR-003','Carne molida de res',       'Res',        'kg',118.00,165.00, true,  true),
    ('PES','PES-002','Camarón mediano',           'Mariscos',   'kg',210.00,289.00, true,  true),
    ('JUG','JUG-002','Carrito de fricción',       'Juguetes',   'pz', 38.00, 65.00, false, false)
  ) as v(dept, sku, name, cat, unit, cost, price, exp, weigh)
  where exists (select 1 from public.departments where company_id = c and code = v.dept)
  on conflict do nothing;

  insert into public.product_barcodes (company_id, product_id, barcode)
  select c, p.id, '7501' || lpad((abs(hashtext(c::text || p.sku)) % 100000000)::text, 8, '0') || '9'
  from public.products p
  where p.company_id = c and not exists (select 1 from public.product_barcodes x where x.product_id = p.id)
  on conflict do nothing;

  -- Inventario en todas las sucursales activas (sin tocar lo que ya existe).
  insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock, location)
  select c, b.id, p.id, 400, 20, 600, 'Piso de venta'
  from public.branches b cross join public.products p
  where b.company_id = c and b.status = 'active' and p.company_id = c
    and not exists (select 1 from public.inventory i where i.branch_id = b.id and i.product_id = p.id);
  -- Las mermas del historial no deben dejar el stock en cero.
  update public.inventory set stock = greatest(stock, 400) where company_id = c;

  -- ── Ventana de días ───────────────────────────────────────────────────────
  select min(scheduled_date) into v_first from public.checklist_runs where company_id = c;
  v_end := coalesce(v_first, public.company_today(c)) - 1;
  v_start := v_end - p_days + 1;

  -- ── Estado oculto de cada sucursal-día (las causas) ───────────────────────
  create temporary table if not exists _mx (
    branch_id uuid, d date, q numeric, ger uuid,
    alta boolean, personal boolean, frio boolean, recibo boolean, rec_falt boolean, rec_dan boolean,
    tk_esc boolean, apertura_tarde boolean, cad_inc boolean, rondin_inc boolean, temp_fuera boolean,
    precios_tarde boolean, tareas_atr boolean,
    m_temp boolean, m_cad boolean, m_dan boolean, m_robo boolean, hueco boolean, conteo_dif boolean
  ) on commit drop;
  delete from _mx;

  insert into _mx (branch_id, d, q, ger, alta, personal, frio, recibo, tk_esc)
  select b.id, g.d::date, b.q, b.ger,
         extract(isodow from g.d) in (5, 6, 7) or extract(day from g.d) in (1, 14, 15, 16, 29, 30, 31),
         false, false, false, false
  from (select b.id,
               (array[0.95, 0.87, 0.76, 0.62])[((row_number() over (order by b.code) - 1 + abs(hashtext(v_code)) % 4) % 4) + 1] as q,
               (select e.id from public.employees e join public.roles r on r.id = e.role_id
                 where e.branch_id = b.id and r.code = 'gerente' and e.status = 'active' order by e.username limit 1) as ger
          from public.branches b where b.company_id = c and b.status = 'active') b
  cross join generate_series(v_start, v_end, interval '1 day') g(d);

  update _mx set ger = coalesce(ger, (select e.id from public.employees e where e.company_id = c and e.is_owner limit 1));

  -- Causas
  update _mx set personal = random() < 0.08 + (1 - q) * 0.35 + case when alta then 0.08 else 0 end,
                 frio     = random() < 0.04 + (1 - q) * 0.10,
                 recibo   = random() < 0.75,
                 tk_esc   = random() < 0.05 + (1 - q) * 0.12;
  update _mx set rec_falt = recibo and random() < 0.10 + (1 - q) * 0.30 + case when alta then 0.10 else 0 end,
                 rec_dan  = recibo and random() < 0.06 + (1 - q) * 0.10;
  -- Síntomas que sí ve la app
  update _mx set apertura_tarde = random() < 0.05 + case when personal then 0.55 else 0 end + (1 - q) * 0.10,
                 cad_inc        = random() < 0.06 + case when personal then 0.60 else 0 end + (1 - q) * 0.20,
                 rondin_inc     = random() < 0.05 + case when personal then 0.50 else 0 end,
                 temp_fuera     = random() < case when frio then 0.90 else 0.03 end,
                 precios_tarde  = random() < 0.08 + case when tk_esc then 0.60 else 0 end + case when personal then 0.25 else 0 end,
                 tareas_atr     = random() < 0.10 + case when personal then 0.50 else 0 end + (1 - q) * 0.20;
  -- Efectos
  update _mx set m_temp = random() < case when temp_fuera then 0.75 else 0.02 end,
                 m_cad  = random() < case when cad_inc then 0.70 else 0.12 end,
                 m_dan  = random() < case when rec_dan then 0.65 else 0.05 end,
                 m_robo = random() < case when rondin_inc and alta then 0.45 when rondin_inc then 0.15 else 0.04 end,
                 hueco  = random() < least(0.95, case when rec_falt then 0.75 else 0.15 end
                                               + case when alta then 0.15 else 0 end
                                               + case when personal then 0.10 else 0 end);
  update _mx set conteo_dif = random() < least(0.95, 0.12 + case when m_robo then 0.45 else 0 end
                                                         + case when rec_falt then 0.25 else 0 end);

  -- ── Checklists ────────────────────────────────────────────────────────────
  d := v_start;
  while d <= v_end loop
    perform public.generate_checklist_runs(c, d);
    d := d + 1;
  end loop;

  alter table public.checklist_runs disable trigger trg_checklist_run_rules;

  -- Cada checklist se completa o no según la calidad de la tienda, la falta de
  -- personal y la regla de su plantilla (caducidades, rondín, precios, apertura).
  update public.checklist_runs r
     set status = 'completed',
         started_at = ((r.scheduled_date + r.scheduled_start) at time zone v_tz) + interval '5 minutes',
         completed_at = ((r.scheduled_date + r.scheduled_start) at time zone v_tz)
                        + case when s.tarde
                               then (r.scheduled_end - r.scheduled_start) + make_interval(mins => (20 + random() * 90)::int)
                               else make_interval(mins => (5 + random() * greatest(10, extract(epoch from (r.scheduled_end - r.scheduled_start)) / 60 * 0.7))::int) end,
         completed_by = s.ger, started_by = s.ger,
         checkpoint_scanned_at = case when r.checkpoint_id is not null or s.cp
           then ((r.scheduled_date + r.scheduled_start) at time zone v_tz) + interval '4 minutes' end
    from (select r2.id, m.ger, t.checkpoint_required as cp,
                 case
                   when t.title = 'Revisión de caducidades' then not m.cad_inc
                   when t.title like 'Rondín%'               then not m.rondin_inc
                   -- Apertura y precios casi siempre se hacen; lo que varía es si a tiempo.
                   when t.shift = 'apertura' or t.title = 'Actualización de precios' then random() < 0.98
                   else random() < m.q - case when m.personal then 0.20 else 0 end + 0.04
                 end as hecho,
                 case
                   when t.title = 'Actualización de precios' then m.precios_tarde
                   when t.shift = 'apertura'                 then m.apertura_tarde
                   else random() < (1 - m.q) * 0.15
                 end as tarde
            from public.checklist_runs r2
            join public.checklist_templates t on t.id = r2.template_id
            join _mx m on m.branch_id = r2.branch_id and m.d = r2.scheduled_date
           where r2.company_id = c and r2.status in ('pending', 'overdue')) s
   where r.id = s.id and s.hecho;

  update public.checklist_runs r set status = 'overdue'
   where r.company_id = c and r.scheduled_date between v_start and v_end and r.status in ('pending', 'in_progress');
  alter table public.checklist_runs enable trigger trg_checklist_run_rules;

  -- Lecturas de temperatura: fuera de rango solo los días con falla de frío.
  insert into public.checklist_answers (run_id, question_id, answer_value, answered_by, answered_at)
  select r.id, qn.id,
         round((case when m.temp_fuera and random() < 0.6
                     then qn.max_value + 1 + random() * 5
                     else qn.min_value + random() * (qn.max_value - qn.min_value) end)::numeric, 1)::text,
         r.completed_by, r.completed_at
  from public.checklist_runs r
  join _mx m on m.branch_id = r.branch_id and m.d = r.scheduled_date
  join public.checklist_questions qn on qn.template_id = r.template_id and qn.is_active
       and qn.equipment_name is not null and qn.min_value is not null and qn.max_value is not null
  where r.company_id = c and r.status = 'completed' and r.scheduled_date between v_start and v_end
  on conflict (run_id, question_id) do nothing;

  -- Tareas automáticas por temperatura: se fechan con la lectura.
  update public.tasks t
     set created_at = a.answered_at,
         due_date = (a.answered_at at time zone v_tz)::date,
         status = 'completed',
         completed_at = a.answered_at + make_interval(mins => (30 + random() * 240)::int)
    from public.checklist_answers a
   where a.id = t.source_id and t.company_id = c and t.source_type = 'checklist_answer'
     and (a.answered_at at time zone v_tz)::date between v_start and v_end;

  -- ── Tareas operativas (atrasadas los días con falta de personal) ──────────
  insert into public.tasks (company_id, branch_id, department_id, title, priority, due_date, created_by,
                            status, created_at, completed_at, source_type)
  select c, m.branch_id, (select id from public.departments where company_id = c and code = v.dept), v.title, v.prio,
         m.d, m.ger, 'completed',
         ((m.d + time '08:00') at time zone v_tz) + make_interval(mins => (random() * 240)::int),
         case when m.tareas_atr
              then ((m.d + 1 + time '10:00') at time zone v_tz) + make_interval(mins => (random() * 600)::int)
              else ((m.d + time '13:00') at time zone v_tz) + make_interval(mins => (random() * 420)::int) end,
         'demo_mineria'
  from _mx m
  cross join lateral (
    select * from (values
      ('ABA', 'Surtir pasillo de enlatados', 'medium'), ('CAJ', 'Revisar fondo de cajas', 'high'),
      ('ESC', 'Colocar cenefas de oferta', 'medium'),   ('CAD', 'Retirar lácteos próximos a vencer', 'high'),
      ('PRO', 'Revisar cámaras del estacionamiento', 'low'), ('ALM', 'Ordenar bodega de abarrotes', 'low'),
      ('REC', 'Conciliar recibo con factura', 'medium'), ('GER', 'Reunión de arranque con jefes', 'low')
    ) as x(dept, title, prio)
    where m.d is not null
    order by random() limit (1 + (random() * 2)::int)
  ) v;

  -- ── Recibos de mercancía ──────────────────────────────────────────────────
  alter table public.receiving_items disable trigger trg_receiving_items_guard;

  create temporary table if not exists _mx_rec (id uuid, branch_id uuid, d date, falt boolean, dan boolean, sup uuid, ger uuid) on commit drop;
  delete from _mx_rec;
  insert into _mx_rec
  select gen_random_uuid(), m.branch_id, m.d, m.rec_falt, m.rec_dan,
         (select s.id from public.suppliers s where s.company_id = c and s.status = 'active' order by random() + (m.d - v_start) * 0 limit 1),
         m.ger
  from _mx m where m.recibo;

  insert into public.receiving_orders (id, company_id, branch_id, supplier_id, invoice_number, status, received_by,
                                       completed_by, completed_at, created_at, notes)
  select r.id, c, r.branch_id, r.sup, 'F-' || to_char(r.d, 'YYMMDD') || '-' || left(r.id::text, 4), 'completed', r.ger,
         r.ger, ((r.d + time '10:30') at time zone v_tz) + make_interval(mins => (random() * 90)::int),
         ((r.d + time '09:30') at time zone v_tz) + make_interval(mins => (random() * 60)::int),
         'Historial de minería'
  from _mx_rec r where r.sup is not null;

  insert into public.receiving_items (receiving_order_id, product_id, expected_qty, received_qty, damaged_qty, created_at)
  select r.id, p.id, x.esp,
         greatest(0, x.esp - case when r.falt and p.rn = 1 then ceil(x.esp * (0.3 + random() * 0.5)) else 0 end),
         case when r.dan and p.rn = 2 then least(x.esp, 1 + floor(random() * 4)) else 0 end,
         ((r.d + time '10:30') at time zone v_tz)
  from _mx_rec r
  cross join lateral (select pp.id, row_number() over () as rn
                        from (select id from public.products where company_id = c order by random() + (r.d - v_start) * 0 limit 4) pp) p
  cross join lateral (select (12 + floor(random() * 36))::numeric as esp) x
  where r.sup is not null;

  update public.receiving_orders o
     set total_items = s.n, total_expected = s.e, total_received = s.r, total_damaged = s.dm,
         has_differences = (s.e <> s.r or s.dm > 0)
    from (select receiving_order_id, count(*) n, sum(expected_qty) e, sum(received_qty) r, sum(damaged_qty) dm
            from public.receiving_items group by receiving_order_id) s
   where s.receiving_order_id = o.id and o.company_id = c and o.notes = 'Historial de minería';
  alter table public.receiving_items enable trigger trg_receiving_items_guard;

  -- ── Mermas (el motivo sale de la causa del día) ───────────────────────────
  insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity, reason,
                                          waste_reason, created_by, created_at)
  select c, m.branch_id, p.id, 'waste', 1 + floor(random() * case w.motivo when 'temperature' then 8 when 'expired' then 6 else 3 end),
         'Merma registrada', w.motivo, m.ger,
         ((m.d + time '17:00') at time zone v_tz) + make_interval(mins => (random() * 240)::int)
  from _mx m
  cross join lateral (values ('temperature', m.m_temp, array['CAD','CAR','PES']),
                             ('expired',     m.m_cad,  array['CAD','ABA']),
                             ('damaged',     m.m_dan,  array['ABA','CAD','JUG']),
                             ('theft',       m.m_robo, array['ABA','CAR','JUG'])) as w(motivo, pasa, deptos)
  cross join lateral (select p.id from public.products p join public.departments dd on dd.id = p.department_id
                       where p.company_id = c and dd.code = any (w.deptos)
                         and (w.motivo <> 'expired' or p.controls_expiration)
                       order by random() + (m.d - v_start) * 0 limit 1) p
  where w.pasa;

  -- ── Huecos en anaquel ─────────────────────────────────────────────────────
  insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock,
                                 status, reported_by, reported_at, last_reported_at, resolved_at, resolved_by)
  select c, m.branch_id, p.department_id, p.id, x.stock, x.stock > 0, 'resolved', m.ger, x.ts, x.ts,
         x.ts + make_interval(mins => (30 + random() * 300)::int), m.ger
  from _mx m
  cross join lateral generate_series(1, 1 + (random() * case when m.rec_falt then 3 else 1 end)::int) n
  cross join lateral (select p.* from public.products p where p.company_id = c and n > 0
                       order by random() + (m.d - v_start) * 0 limit 1) p
  cross join lateral (select case when m.rec_falt then 0 else (random() * 30)::int end as stock,
                             ((m.d + time '11:00') at time zone v_tz) + make_interval(mins => (random() * 360)::int) as ts) x
  where m.hueco;

  -- ── Conteos cíclicos ──────────────────────────────────────────────────────
  insert into public.cycle_count_plans (company_id, branch_id, department_id, name, frequency, items_per_count)
  select c, b.id, null, 'Conteo general', 'daily', 5 from public.branches b
  where b.company_id = c and b.status = 'active'
    and not exists (select 1 from public.cycle_count_plans x where x.branch_id = b.id);

  d := v_start;
  while d <= v_end loop
    perform public.generate_cycle_counts(c, d);
    d := d + 1;
  end loop;

  update public.cycle_count_items ci
     set expected_qty = s.stock,
         counted_qty = greatest(s.stock + s.diff, 0),
         difference = greatest(s.stock + s.diff, 0) - s.stock,
         difference_value = round((greatest(s.stock + s.diff, 0) - s.stock) * s.cost, 2),
         counted_by = s.ger,
         counted_at = ((s.scheduled_date + time '10:00') at time zone v_tz) + make_interval(mins => (random() * 180)::int)
    from (select ci2.id, coalesce(inv.stock, 0) as stock, p.cost, m.ger, t.scheduled_date,
                 case when m.conteo_dif and random() < 0.45 then -(1 + floor(random() * 4))
                      when random() < 0.03 then 1 else 0 end::numeric as diff
            from public.cycle_count_items ci2
            join public.cycle_count_tasks t on t.id = ci2.task_id
            join _mx m on m.branch_id = t.branch_id and m.d = t.scheduled_date
            join public.products p on p.id = ci2.product_id
            left join public.inventory inv on inv.branch_id = t.branch_id and inv.product_id = ci2.product_id
           where t.company_id = c and ci2.counted_at is null) s
   where ci.id = s.id;

  update public.cycle_count_tasks t
     set items_counted = s.counted, items_with_diff = s.with_diff, diff_value = s.value,
         status = case when s.counted >= t.items_total then 'completed' when s.counted > 0 then 'in_progress' else 'pending' end,
         started_at = s.first_at, completed_at = case when s.counted >= t.items_total then s.last_at end,
         completed_by = case when s.counted >= t.items_total then s.by end
    from (select ci.task_id, count(ci.counted_at)::int as counted,
                 count(*) filter (where ci.difference <> 0)::int as with_diff,
                 coalesce(sum(ci.difference_value), 0) as value,
                 min(ci.counted_at) as first_at, max(ci.counted_at) as last_at, max(ci.counted_by::text)::uuid as by
            from public.cycle_count_items ci group by ci.task_id) s
   where s.task_id = t.id and t.company_id = c and t.scheduled_date between v_start and v_end;

  -- ── Tickets de soporte (falla de escáner o de red) ────────────────────────
  insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority,
                                      status, created_by, created_at, first_response_at, resolved_at, closed_at, due_at)
  select c, m.branch_id, v.subj, v.subj || ' (historial).', v.cat, v.module, v.prio, 'closed', m.ger, x.ts,
         x.ts + make_interval(mins => (10 + random() * 120)::int),
         x.ts + make_interval(mins => (120 + random() * 900)::int),
         x.ts + make_interval(mins => (1200 + random() * 1200)::int),
         x.ts + interval '24 hours'
  from _mx m
  cross join lateral (select ((m.d + time '07:30') at time zone v_tz) + make_interval(mins => (random() * 90)::int) as ts) x
  cross join lateral (select * from (values
      ('Lector no lee códigos', 'scanner', 'Cajas', 'medium'),
      ('Escáner de precios sin conexión', 'network', 'Inventario', 'high')) as y(subj, cat, module, prio)
    where m.d is not null order by random() limit 1) v
  where m.tk_esc;

  -- Marca de que la empresa ya tiene este historial (la revisa el guard de arriba).
  insert into public.tasks (company_id, branch_id, title, priority, due_date, status, completed_at, source_type)
  select c, (select id from public.branches where company_id = c and status = 'active' order by code limit 1),
         'Historial de minería generado', 'low', v_end, 'completed', now(), 'demo_mineria'
  where not exists (select 1 from public.tasks where company_id = c and source_type = 'demo_mineria');

  delete from public.notifications where company_id = c and created_at >= now() - interval '10 minutes';
  perform public.set_bypass(v_prev);

  select count(*) into v_rows from _mx;
  return format('%s: %s sucursal-días del %s al %s', v_code, v_rows, v_start, v_end);
end $$;
revoke all on function public.demo_mining_history(uuid, integer) from public, anon, authenticated;

select public.demo_mining_history(id, 120) from public.companies order by code;
