-- =============================================================================
-- OPERALIA · DEMO 0019 · DOS EMPRESAS CLIENTE DE EJEMPLO CON 30 DÍAS DE HISTORIAL
-- -----------------------------------------------------------------------------
-- SOLO para ambientes de prueba. Requiere demo/0009 (demo_seed_user y
-- seed_company_demo) y la migración 0023 (seed_company_base). Re-ejecutable:
-- el historial se genera una sola vez por empresa.
--
--   Empresa (código)              Propietario   Sucursales
--   ───────────────────────────── ───────────── ─────────────────────────────
--   Súper La Luna (superluna)     luna.admin    Centro, Otay, Playas, Rosarito
--   Mercado Sol (mercadosol)      sol.admin     Centro, Valle, Maneadero, Sauzal
--
-- Usuarios de cada empresa (contraseña prueba123): <x>.admin (propietario),
-- gerente1…gerente4 (uno por sucursal), soporte, jefe.cajas, cajero,
-- abarrotes, almacen, caducidades, escaner, proteccion y recibo (sucursal 001).
--
-- public.demo_company_history(empresa, días): checklists, lecturas de
-- temperatura, tareas, mermas, conteos cíclicos, huecos en anaquel y tickets
-- de los últimos N días. Cada sucursal tiene un nivel de cumplimiento distinto
-- (y un orden distinto en cada empresa) para que las gráficas comparen tiendas.
-- =============================================================================

create or replace function public.demo_company_history(p_company_id uuid, p_days integer default 30)
returns void language plpgsql security definer set search_path = public as $$
declare
  c         uuid := p_company_id;
  v_code    text;
  v_tz      text;
  v_today   date;
  v_started timestamptz := clock_timestamp();
  v_prev    text;
  v_offset  int;
  br        record;
  d         date;
  i         int;
  k         int;
  v_prod    record;
  v_qty     numeric;
  v_task    uuid;
  v_ts      timestamptz;
  v_tk      uuid;
begin
  if exists (select 1 from public.tasks where company_id = c and source_type = 'demo_history') then
    raise notice 'La empresa % ya tiene historial demo; se omite.', c;
    return;
  end if;
  v_prev := public.set_bypass('on');
  select code, timezone into v_code, v_tz from public.companies where id = c;
  v_today := public.company_today(c);
  v_offset := abs(hashtext(v_code)) % 4;

  -- Calidad por sucursal: 0.96 / 0.88 / 0.74 / 0.58, en otro orden en cada empresa,
  -- y escalada por empresa para que también los totales se distingan
  -- (Gato Pelón la mejor, Mercado Sol la más floja).
  create temporary table if not exists _demo_branch (id uuid, code text, q numeric, ger uuid) on commit drop;
  delete from _demo_branch;
  insert into _demo_branch
  select b.id, b.code,
         least(0.99, round((array[0.96, 0.88, 0.74, 0.58])[((row_number() over (order by b.code) - 1 + v_offset) % 4) + 1]
               * case v_code when 'mercadosol' then 0.78 when 'superluna' then 0.93 else 1.08 end, 2)),
         (select e.id from public.employees e join public.roles r on r.id = e.role_id
           where e.branch_id = b.id and r.code = 'gerente' and e.status = 'active' order by e.username limit 1)
  from public.branches b where b.company_id = c and b.status = 'active';

  -- ── Checklists ────────────────────────────────────────────────────────────
  for i in 1..p_days loop
    perform public.generate_checklist_runs(c, v_today - i);
  end loop;

  -- Solo para el historial: tg_checklist_run_rules exige respuestas y fotos y fija
  -- completed_at = now(). Se desactiva mientras se fechan los checklists pasados
  -- (dentro de esta transacción; si algo falla, se revierte).
  alter table public.checklist_runs disable trigger trg_checklist_run_rules;

  -- El sorteo va en la lista del SELECT (un random() por checklist): en el WHERE,
  -- «random() < b.q» solo depende de la sucursal y Postgres puede evaluarlo una
  -- vez por sucursal en lugar de por fila.
  update public.checklist_runs r
     set status = 'completed',
         started_at = ((r.scheduled_date + r.scheduled_start) at time zone v_tz) + interval '5 minutes',
         -- Las tiendas con menor calidad terminan más tarde (algunas fuera de horario).
         completed_at = ((r.scheduled_date + r.scheduled_start) at time zone v_tz)
                        + make_interval(mins => (15 + random() * 40 + (1 - s.q) * 240 * random())::int),
         completed_by = s.ger,
         started_by = s.ger,
         checkpoint_scanned_at = case when r.checkpoint_id is not null or exists (
           select 1 from public.checklist_templates t where t.id = r.template_id and t.checkpoint_required)
           then ((r.scheduled_date + r.scheduled_start) at time zone v_tz) + interval '4 minutes' end
    from (select r2.id, b.q, b.ger, random() as x
            from public.checklist_runs r2 join _demo_branch b on b.id = r2.branch_id
           where r2.company_id = c and r2.scheduled_date between v_today - p_days and v_today - 1
             and r2.status in ('pending', 'overdue')) s
   where r.id = s.id and s.x < s.q;

  update public.checklist_runs r set status = 'overdue'
   where r.company_id = c and r.scheduled_date between v_today - p_days and v_today - 1
     and r.status in ('pending', 'in_progress');
  alter table public.checklist_runs enable trigger trg_checklist_run_rules;

  -- Lecturas de temperatura de los checklists completados (más fuera de rango en las tiendas con menor calidad).
  insert into public.checklist_answers (run_id, question_id, answer_value, answered_by, answered_at)
  select r.id, qn.id,
         round((case when random() < (1 - b.q) * 0.5
                    then qn.max_value + 0.5 + random() * 4
                    else qn.min_value + random() * (qn.max_value - qn.min_value) end)::numeric, 1)::text,
         r.completed_by, r.completed_at
  from public.checklist_runs r
  join _demo_branch b on b.id = r.branch_id
  join public.checklist_questions qn on qn.template_id = r.template_id and qn.is_active
       and qn.equipment_name is not null and qn.min_value is not null and qn.max_value is not null
  where r.company_id = c and r.status = 'completed' and r.scheduled_date between v_today - p_days and v_today - 1
  on conflict (run_id, question_id) do nothing;

  -- Las tareas automáticas por temperatura fuera de rango se fechan con la lectura
  -- y casi todas se corrigen (más rápido en las mejores tiendas).
  update public.tasks t
     set created_at = s.answered_at,
         due_date = (s.answered_at at time zone v_tz)::date,
         status = case when s.x < s.q + 0.03 then 'completed' else 'pending' end,
         completed_at = case when s.x < s.q + 0.03
                             then s.answered_at + make_interval(mins => (20 + random() * 60 + (1 - s.q) * 600)::int) end
    from (select t2.id, a.answered_at, b.q, random() as x
            from public.tasks t2
            join public.checklist_answers a on a.id = t2.source_id
            join _demo_branch b on b.id = t2.branch_id
           where t2.company_id = c and t2.source_type = 'checklist_answer' and t2.created_at >= v_started) s
   where t.id = s.id;

  -- ── Tareas operativas ─────────────────────────────────────────────────────
  for br in select * from _demo_branch loop
    for i in 1..p_days loop
      d := v_today - i;
      for k in 1..(1 + (random() * 2)::int) loop
        v_ts := ((d + time '09:00') at time zone v_tz) + make_interval(mins => (random() * 480)::int);
        insert into public.tasks (company_id, branch_id, department_id, title, priority, due_date, created_by,
                                  status, created_at, completed_at, source_type)
        select c, br.id, (select id from public.departments where company_id = c and code = v.dept), v.title,
               v.prio, d + 1, br.ger,
               x.st, v_ts,
               case when x.st = 'completed'
                    then v_ts + make_interval(mins => (60 + random() * 600 + (1 - br.q) * 2400 * random())::int) end,
               'demo_history'
        from (values
          ('ABA', 'Surtir pasillo de enlatados', 'medium'), ('CAJ', 'Revisar fondo de cajas', 'high'),
          ('ESC', 'Colocar cenefas de oferta', 'medium'),   ('CAD', 'Retirar lácteos próximos a vencer', 'high'),
          ('PRO', 'Revisar cámaras del estacionamiento', 'low'), ('ALM', 'Ordenar bodega de abarrotes', 'low'),
          ('REC', 'Conciliar recibo con factura', 'medium'), ('GER', 'Reunión de arranque con jefes', 'low')
        ) as v(dept, title, prio)
        cross join lateral (select case when random() < br.q then 'completed'
                                        when random() < 0.5 then 'in_progress' else 'pending' end as st) x
        order by random() limit 1;
      end loop;
    end loop;
  end loop;

  -- ── Mermas ────────────────────────────────────────────────────────────────
  for br in select * from _demo_branch loop
    for i in 1..p_days loop
      if random() < 0.35 + (1 - br.q) then
        select p.id, p.cost into v_prod
          from public.inventory inv join public.products p on p.id = inv.product_id
         where inv.branch_id = br.id and inv.stock >= 10 order by random() limit 1;
        if found then
          v_qty := 1 + round((random() * 2 + (1 - br.q) * 6)::numeric);
          insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity, reason,
                                                  waste_reason, created_by, created_at)
          values (c, br.id, v_prod.id, 'waste', v_qty, 'Merma registrada',
                  (array['expired','damaged','theft','mishandling','temperature','other'])[1 + (random() * 5)::int],
                  br.ger, ((v_today - i + time '18:00') at time zone v_tz) + make_interval(mins => (random() * 120)::int));
        end if;
      end if;
    end loop;
  end loop;

  -- ── Conteos cíclicos (planes en las sucursales que no tengan) ─────────────
  insert into public.cycle_count_plans (company_id, branch_id, department_id, name, frequency, items_per_count)
  select c, b.id, null, 'Conteo general', 'daily', 5 from _demo_branch b
  where not exists (select 1 from public.cycle_count_plans x where x.branch_id = b.id);
  update public.cycle_count_plans set frequency = 'daily' where company_id = c;

  for i in reverse p_days..1 loop
    perform public.generate_cycle_counts(c, v_today - i);
  end loop;

  update public.cycle_count_items ci
     set expected_qty = s.stock,
         counted_qty = greatest(s.stock + s.diff, 0),
         difference = greatest(s.stock + s.diff, 0) - s.stock,
         difference_value = round((greatest(s.stock + s.diff, 0) - s.stock) * s.cost, 2),
         counted_by = s.ger,
         counted_at = ((s.scheduled_date + time '10:00') at time zone v_tz) + make_interval(mins => (random() * 180)::int)
    from (select ci2.id, coalesce(inv.stock, 0) as stock, p.cost, b.ger, t.scheduled_date, b.q,
                 random() as x,   -- se cuenta el renglón
                 case when random() < b.q then 0                       -- sin diferencia
                      when random() < 0.8 then -(1 + floor(random() * 3)) -- faltante
                      else 1 end::numeric as diff                      -- sobrante
            from public.cycle_count_items ci2
            join public.cycle_count_tasks t on t.id = ci2.task_id
            join _demo_branch b on b.id = t.branch_id
            join public.products p on p.id = ci2.product_id
            left join public.inventory inv on inv.branch_id = t.branch_id and inv.product_id = ci2.product_id
           where t.company_id = c and t.scheduled_date between v_today - p_days and v_today - 1
             and ci2.counted_at is null) s
   where ci.id = s.id and s.x < s.q + 0.1;

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
   where s.task_id = t.id and t.company_id = c and t.scheduled_date between v_today - p_days and v_today - 1;

  -- ── Huecos en anaquel ─────────────────────────────────────────────────────
  insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock,
                                 status, reported_by, reported_at, last_reported_at, resolved_at, resolved_by)
  select c, b.id, p.department_id, p.id, x.stock, x.stock > 0,
         case when random() < 0.85 then 'resolved' else 'dismissed' end, b.ger, x.ts, x.ts,
         x.ts + make_interval(mins => (30 + random() * 240 + (1 - b.q) * 600)::int), b.ger
  from _demo_branch b
  cross join generate_series(1, p_days) g(day)
  cross join lateral generate_series(1, (random() * (1 + (1 - b.q) * 6))::int) n
  cross join lateral (select p.* from public.products p where p.company_id = c and g.day > 0 order by random() limit 1) p
  cross join lateral (select case when random() < 0.55 then 10 + (random() * 40)::int else 0 end as stock,
                             ((v_today - g.day + time '11:00') at time zone v_tz) + make_interval(mins => (random() * 360)::int) as ts) x;

  -- ── Tickets de mesa de ayuda ──────────────────────────────────────────────
  for i in 1..p_days loop
    if random() < 0.55 then
      select * into br from _demo_branch order by -ln(1 - random()) * q limit 1;   -- carrera exponencial: las tiendas peores reportan más
      v_ts := ((v_today - i + time '08:00') at time zone v_tz) + make_interval(mins => (random() * 600)::int);
      insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by, created_at)
      select c, br.id, v.subj, v.subj || ' en ' || (select name from public.branches where id = br.id) || '.', v.cat, v.module, v.prio, br.ger, v_ts
      from (values
        ('Sin señal en caja 2', 'network', 'Cajas', 'high'), ('Impresora de tickets sin papel atascado', 'printer', 'Cajas', 'medium'),
        ('Lector no lee códigos', 'scanner', 'Cajas', 'medium'), ('No puedo iniciar sesión', 'access', 'Inicio de sesión', 'high'),
        ('Error al guardar checklist', 'bug', 'Checklists', 'medium'), ('Solicitud de reporte nuevo', 'feature', 'Reportes', 'low')
      ) as v(subj, cat, module, prio)
      order by random() limit 1
      returning id into v_tk;
      update public.support_tickets
         set status = case when random() < 0.8 then 'closed' else 'resolved' end,
             first_response_at = v_ts + make_interval(mins => (10 + random() * 90 + (1 - br.q) * 300)::int),
             resolved_at = v_ts + make_interval(mins => (120 + random() * 900 + (1 - br.q) * 2000)::int),
             closed_at = v_ts + make_interval(mins => (1200 + random() * 1200)::int),
             due_at = v_ts + interval '24 hours'
       where id = v_tk;
    end if;
  end loop;

  -- Sin avisos viejos en la campana: el historial no notifica.
  delete from public.notifications where company_id = c and created_at >= v_started;
  perform public.set_bypass(v_prev);
  perform public.run_daily_maintenance(c);
end $$;
revoke all on function public.demo_company_history(uuid, integer) from public, anon, authenticated;

-- ─── EMPRESAS, SUCURSALES Y USUARIOS ────────────────────────────────────────
insert into public.companies (id, code, name, legal_name, timezone) values
  ('c0000000-0000-4000-8000-0000000000b1', 'superluna',  'Súper La Luna', 'Súper La Luna S.A. de C.V.', 'America/Tijuana'),
  ('c0000000-0000-4000-8000-0000000000c1', 'mercadosol', 'Mercado Sol',   'Mercado Sol S.A. de C.V.',   'America/Tijuana')
on conflict (id) do nothing;

insert into public.branches (company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status) values
  ('c0000000-0000-4000-8000-0000000000b1', '001', 'La Luna Centro',   'tienda',  'Av. Revolución 800',    'Tijuana',   '664-200-0001', '07:00', '23:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000b1', '002', 'La Luna Otay',     'tienda',  'Blvd. Industrial 1500', 'Tijuana',   '664-200-0002', '07:00', '22:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000b1', '003', 'La Luna Playas',   'express', 'Paseo Ensenada 120',    'Tijuana',   '664-200-0003', '08:00', '22:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000b1', '004', 'La Luna Rosarito', 'tienda',  'Blvd. Juárez 300',      'Rosarito',  '661-200-0004', '07:00', '22:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000c1', '001', 'Sol Centro',       'tienda',  'Av. Juárez 1000',       'Ensenada',  '646-300-0001', '07:00', '22:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000c1', '002', 'Sol Valle',        'tienda',  'Carretera al Valle km 5','Ensenada', '646-300-0002', '07:00', '21:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000c1', '003', 'Sol Maneadero',    'express', 'Calle 3 #45',           'Maneadero', '646-300-0003', '08:00', '21:00', 'active'),
  ('c0000000-0000-4000-8000-0000000000c1', '004', 'Sol Sauzal',       'tienda',  'Blvd. Costero 210',     'El Sauzal', '646-300-0004', '07:00', '22:00', 'active')
on conflict do nothing;

select public.seed_company_base(id) from public.companies where code in ('superluna', 'mercadosol');

-- Zona de cada sucursal (001 Centro, 002 Norte, 003 Sur, 004 Oeste).
update public.branches b set zone_id = z.id
  from public.zones z, public.companies c
 where c.id = b.company_id and c.code in ('superluna', 'mercadosol') and z.company_id = b.company_id and b.zone_id is null
   and z.code = case b.code when '001' then 'CEN' when '002' then 'NOR' when '003' then 'SUR' when '004' then 'OES' end;

select public.demo_seed_user(c.id, replace(v.u, '<x>', c.prefix), 'prueba123', v.n || ' ' || c.short, v.r, v.b, v.d, v.p, v.code)
from (values ('c0000000-0000-4000-8000-0000000000b1'::uuid, 'luna', 'La Luna'),
             ('c0000000-0000-4000-8000-0000000000c1'::uuid, 'sol',  'Sol')) as c(id, prefix, short)
cross join (values
  ('<x>.admin',   'Propietario',       'admin',       '001', 'ADM', 'Propietario',            'EMP-0001'),
  ('gerente1',    'Gerente 001',       'gerente',     '001', 'GER', 'Gerente de sucursal',    'EMP-0002'),
  ('gerente2',    'Gerente 002',       'gerente',     '002', 'GER', 'Gerente de sucursal',    'EMP-0003'),
  ('gerente3',    'Gerente 003',       'gerente',     '003', 'GER', 'Gerente de sucursal',    'EMP-0004'),
  ('gerente4',    'Gerente 004',       'gerente',     '004', 'GER', 'Gerente de sucursal',    'EMP-0005'),
  ('soporte',     'Soporte',           'soporte',     '001', 'TI',  'Soporte de plataforma',  'EMP-0006'),
  ('jefe.cajas',  'Jefa de Cajas',     'jefe_cajas',  '001', 'CAJ', 'Jefa de cajas',          'EMP-0007'),
  ('cajero',      'Cajero',            'cajas',       '001', 'CAJ', 'Cajero',                 'EMP-0008'),
  ('abarrotes',   'Abarrotes',         'abarrotes',   '001', 'ABA', 'Auxiliar de abarrotes',  'EMP-0009'),
  ('almacen',     'Almacén',           'almacen',     '001', 'ALM', 'Almacenista',            'EMP-0010'),
  ('caducidades', 'Caducidades',       'caducidades', '001', 'CAD', 'Auxiliar de caducidades','EMP-0011'),
  ('escaner',     'Escáner',           'escaner',     '001', 'ESC', 'Auxiliar de escáner',    'EMP-0012'),
  ('proteccion',  'Protección',        'proteccion',  '001', 'PRO', 'Oficial de protección',  'EMP-0013'),
  ('recibo',      'Recibo',            'recibo',      '001', 'REC', 'Jefe de recibo',         'EMP-0014')
) as v(u, n, r, b, d, p, code);

-- Propietarios (uno por empresa; en modo sistema por tg_employee_owner_guard).
do $$
declare v_prev text;
begin
  v_prev := public.set_bypass('on');
  update public.employees e set is_owner = true
   where (e.company_id, e.username) in (('c0000000-0000-4000-8000-0000000000b1'::uuid, 'luna.admin'),
                                        ('c0000000-0000-4000-8000-0000000000c1'::uuid, 'sol.admin'))
     and not e.is_owner
     and not exists (select 1 from public.employees o where o.company_id = e.company_id and o.is_owner);
  perform public.set_bypass(v_prev);
end $$;

-- Gerente de cada sucursal.
update public.branches b set manager_id = e.id
  from public.employees e
 where e.company_id = b.company_id and e.username = 'gerente' || right(b.code, 1)
   and b.company_id in ('c0000000-0000-4000-8000-0000000000b1', 'c0000000-0000-4000-8000-0000000000c1')
   and b.manager_id is null;

select public.seed_company_demo(id) from public.companies where code in ('superluna', 'mercadosol');
select public.demo_company_history(id, 30) from public.companies where code in ('superluna', 'mercadosol');
