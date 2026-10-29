-- =============================================================================
-- OPERALIA · DEMO 0009 · USUARIOS DE PRUEBA Y DATOS DEMO
-- -----------------------------------------------------------------------------
-- SOLO para ambientes de prueba (nunca en producción). Re-ejecutable.
--
--   * public.demo_seed_user(empresa, usuario, …): empleado + cuenta de Auth
--     (usuario@<código>.operalia.local) ya confirmada.
--   * public.seed_company_demo(empresa): productos, inventario de todas las
--     sucursales, proveedores, plantillas de checklist de departamentos,
--     tareas, pedidos, cambios de precio, caducidades, tickets y planes de
--     conteo cíclico. Requiere seed_company_base y al menos una sucursal.
--   * Gato Pelón: usuarios de prueba, una cuarta sucursal (004 Playas) y sus
--     datos demo.
--
-- Inicio de sesión: Empresa «gatopelon» + usuario + contraseña.
--
--   Usuario            Contraseña   Rol                    Sucursal
--   ─────────────────  ───────────  ─────────────────────  ───────────────
--   gatopelon          prueba123    Admin (superadmin)     Centro
--   soporte            prueba123    Soporte TI             Centro
--   auditor            prueba123    Auditor                Centro
--   gerente.centro     prueba123    Gerente                Centro
--   gerente.norte      prueba123    Gerente                Norte  (prueba aislamiento)
--   supervisor         prueba123    Supervisor (ABA + CAD) Centro
--   jefe.cajas         prueba123    Jefe de cajas          Centro
--   cajero             prueba123    Cajero                 Centro
--   abarrotes          prueba123    Abarrotes              Centro
--   recibo             prueba123    Recibo                 Centro
--   almacen            prueba123    Almacén                Centro
--   proteccion         prueba123    Protección             Centro
--   caducidades        prueba123    Caducidades            Centro
--   escaner            prueba123    Escáner                Centro
--
-- La contraseña solo se usa al CREAR la cuenta: si ya existe, no se cambia.
-- =============================================================================

-- ─── USUARIOS DEMO ──────────────────────────────────────────────────────────
create or replace function public.demo_seed_user(
  p_company_id uuid, p_username text, p_password text, p_full_name text, p_role text,
  p_branch_code text, p_dept_code text, p_position text, p_employee_code text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_email text := public.employee_auth_email(p_company_id, p_username);
  v_emp   uuid;
  v_user  uuid;
begin
  -- 1) Empleado
  select id into v_emp from public.employees where company_id = p_company_id and lower(username) = lower(p_username);
  if v_emp is null then
    insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                  username, full_name, position, email)
    values (
      p_company_id,
      (select id from public.branches where company_id = p_company_id and code = p_branch_code),
      (select id from public.departments where company_id = p_company_id and code = p_dept_code),
      (select id from public.roles where company_id = p_company_id and code = p_role),
      p_employee_code, lower(p_username), p_full_name, p_position, v_email)
    returning id into v_emp;
  end if;

  -- 2) Cuenta de Supabase Auth (el trigger on_auth_user_created la liga al empleado)
  select id into v_user from auth.users where email = v_email;
  if v_user is null then
    v_user := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token)
    values (
      '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email,
      crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', lower(p_username), 'full_name', p_full_name),
      now(), now(), '', '', '', '');

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_user, v_user::text,
            jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
            'email', now(), now(), now());
  end if;

  -- 3) Asegurar el vínculo (por si el empleado se creó después que la cuenta)
  update public.employees set user_id = v_user where id = v_emp and user_id is null;
  return v_emp;
end $$;
revoke all on function public.demo_seed_user(uuid, text, text, text, text, text, text, text, text) from public, anon, authenticated;

-- ─── DATOS DEMO POR EMPRESA ─────────────────────────────────────────────────
create or replace function public.seed_company_demo(p_company_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  c   uuid := p_company_id;
  cen uuid; nor uuid;
  e_admin uuid; e_ger uuid; e_jcaj uuid; e_esc uuid; e_aba uuid; e_cad uuid; e_prot uuid; e_sop uuid;
  o_id uuid; tk uuid; v_prev text;
begin
  v_prev := public.set_bypass('on');
  select id into cen from public.branches where company_id = c and status = 'active' order by code limit 1;
  select id into nor from public.branches where company_id = c and status = 'active' and id <> cen order by code limit 1;
  if cen is null then raise exception 'La empresa % no tiene sucursales activas', c; end if;

  -- Primer empleado activo de cada rol (las sucursales en orden de código).
  select e.id into e_admin from public.employees e join public.roles r on r.id = e.role_id
   where e.company_id = c and r.code = 'admin' and e.status = 'active' order by e.is_owner desc, e.username limit 1;
  select e.id into e_ger  from public.employees e join public.roles r on r.id = e.role_id left join public.branches b on b.id = e.branch_id
   where e.company_id = c and r.code = 'gerente' and e.status = 'active' order by b.code nulls last, e.username limit 1;
  select e.id into e_jcaj from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'jefe_cajas' order by e.username limit 1;
  select e.id into e_esc  from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'escaner' order by e.username limit 1;
  select e.id into e_aba  from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'abarrotes' order by e.username limit 1;
  select e.id into e_cad  from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'caducidades' order by e.username limit 1;
  select e.id into e_prot from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'proteccion' order by e.username limit 1;
  select e.id into e_sop  from public.employees e join public.roles r on r.id = e.role_id where e.company_id = c and r.code = 'soporte' order by e.username limit 1;
  e_ger := coalesce(e_ger, e_admin);

  if not exists (select 1 from public.products where company_id = c) then
    -- ── Productos + códigos de barras ───────────────────────────────────────
    insert into public.products (company_id, department_id, sku, name, category, unit, cost, price, controls_expiration, is_weighable)
    select c, (select id from public.departments where company_id = c and code = v.dept), v.sku, v.name, v.cat, v.unit, v.cost, v.price, v.exp, v.weigh
    from (values
      ('ABA','ABR-001','Arroz 1 kg',              'Granos',     'pz', 19.00,  28.50, false, false),
      ('ABA','ABR-002','Frijol negro 1 kg',       'Granos',     'pz', 23.00,  32.00, false, false),
      ('ABA','ABR-003','Aceite vegetal 1 L',      'Aceites',    'pz', 33.00,  45.00, false, false),
      ('ABA','ABR-004','Azúcar estándar 1 kg',    'Endulzantes','pz', 15.00,  22.00, false, false),
      ('ABA','ABR-006','Atún en agua 140 g',      'Enlatados',  'pz', 13.00,  19.90, true,  false),
      ('ABA','ABR-007','Café soluble 200 g',      'Bebidas',    'pz', 61.00,  89.00, false, false),
      ('ABA','BEB-001','Agua natural 1.5 L',      'Bebidas',    'pz',  8.00,  14.00, false, false),
      ('ABA','LIM-001','Detergente en polvo 1 kg','Limpieza',   'pz', 29.00,  42.00, false, false),
      ('CAD','LAC-001','Leche entera 1 L',        'Lácteos',    'pz', 18.00,  24.00, true,  false),
      ('CAD','LAC-002','Yogur fresa 200 g',       'Lácteos',    'pz', 11.00,  18.50, true,  false),
      ('CAD','EMB-001','Jamón de pavo 250 g',     'Embutidos',  'pz', 33.00,  48.00, true,  false),
      ('CAR','CAR-001','Bistec de res',           'Res',        'kg',140.00, 189.00, true,  true),
      ('PES','PES-001','Filete de tilapia',       'Pescado',    'kg', 92.00, 129.00, true,  true),
      ('JUG','JUG-001','Pelota de vinil',         'Juguetes',   'pz', 21.00,  35.00, false, false)
    ) as v(dept, sku, name, cat, unit, cost, price, exp, weigh);

    insert into public.product_barcodes (company_id, product_id, barcode)
    select c, p.id, '75010553' || lpad(row_number() over (order by p.sku)::text, 5, '0')
    from public.products p where p.company_id = c;

    -- ── Inventario de la primera sucursal (el trigger calcula el estado) ────
    insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock, location)
    select c, cen, p.id, v.stock, v.min, v.max, v.loc
    from (values
      ('ABR-001', 45, 20, 120, 'Pasillo 3'), ('ABR-002', 12, 15, 80, 'Pasillo 3'),
      ('ABR-003', 60, 25, 100, 'Pasillo 4'), ('ABR-004',  3, 20, 90, 'Pasillo 4'),
      ('ABR-006', 80, 30, 150, 'Pasillo 5'), ('ABR-007', 25, 10, 50, 'Pasillo 6'),
      ('BEB-001',  0, 40, 200, 'Pasillo 8'), ('LIM-001', 34, 15, 60, 'Pasillo 10'),
      ('LAC-001', 18, 30, 120, 'Refrigerador 1'), ('LAC-002', 22, 10, 60, 'Refrigerador 1'),
      ('EMB-001', 14, 8, 40, 'Salchichonería'),   ('CAR-001', 36.5, 20, 80, 'Vitrina carnes'),
      ('PES-001', 9.2, 10, 40, 'Vitrina pescados'), ('JUG-001', 50, 10, 100, 'Juguetería')
    ) as v(sku, stock, min, max, loc)
    join public.products p on p.sku = v.sku and p.company_id = c;

    -- ── Proveedores y una visita abierta ────────────────────────────────────
    insert into public.suppliers (company_id, code, name, legal_name, merchandise_type, contact_name, phone, email, status) values
      (c, 'PROV-001', 'Distribuidora Nacional',  'Distribuidora Nacional S.A.',  'Abarrotes',  'Jorge Martínez', '664-123-4567', 'ventas@disnacional.mx', 'active'),
      (c, 'PROV-002', 'Lácteos del Noroeste',    'Lácteos del Noroeste S.A.',    'Lácteos',    'Rosa Sánchez',   '664-234-5678', 'pedidos@lacteosno.mx',  'active'),
      (c, 'PROV-003', 'Congelados y Frescos',    'Congelados y Frescos S.A.',    'Cárnicos',   'Manuel Cruz',    '664-345-6789', 'contacto@cyf.mx',       'active'),
      (c, 'PROV-004', 'Bebidas y Refrescos MX',  'Bebidas y Refrescos MX S.A.',  'Bebidas',    'Patricia León',  '664-456-7890', null,                    'inactive');

    insert into public.supplier_visits (company_id, branch_id, supplier_id, check_in_at, driver_name, vehicle_plate, purpose, registered_by)
    select c, cen, s.id, now() - interval '40 minutes', 'Raúl Pérez', 'BC-12-345', 'entrega', e_prot
    from public.suppliers s where s.code = 'PROV-002' and s.company_id = c;

    -- ── Plantillas de checklist por departamento + preguntas ────────────────
    insert into public.checklist_templates (company_id, department_id, title, shift, start_time, end_time, requires_evidence, description)
    select c, (select id from public.departments where company_id = c and code = v.dept), v.title, v.shift, v.st::time, v.et::time, v.ev, v.descr
    from (values
      ('CAJ','Apertura de cajas',            'apertura','07:00','08:30', true,  'Validar que la línea de cajas abre en orden'),
      ('ABA','Apertura de abarrotes',        'apertura','07:00','08:30', false, 'Surtido y limpieza antes de abrir'),
      ('PRO','Rondín de seguridad mañana',   'manana',  '08:00','09:00', true,  'Recorrido de seguridad del inmueble'),
      ('CAD','Revisión de caducidades',      'manana',  '08:00','10:00', true,  'Revisión de fechas en exhibición'),
      ('REC','Preparación de andén de recibo','manana', '09:00','11:00', false, 'Andén listo para proveedores'),
      ('ESC','Actualización de precios',     'manana',  '07:30','09:00', true,  'Cambios de precio y cenefas del día'),
      ('CAD','Control de temperaturas',      'especial','06:00','23:59', false, 'Registro de temperatura de refrigeradores'),
      ('ABA','Cierre de abarrotes',          'cierre',  '21:00','22:00', false, 'Acomodo y reporte de faltantes'),
      ('CAJ','Cierre de cajas',              'cierre',  '21:30','22:30', true,  'Corte y resguardo de la línea de cajas')
    ) as v(dept, title, shift, st, et, ev, descr)
    where not exists (select 1 from public.checklist_templates t where t.company_id = c and t.title = v.title);

    insert into public.checklist_questions (template_id, position, text, answer_type, requires_photo, is_required, min_value, max_value, unit, equipment_name)
    select t.id, q.pos, q.txt, q.typ, q.photo, true, q.mn, q.mx, q.unit, q.equipment
    from public.checklist_templates t
    join (values
      ('Apertura de cajas', 1, '¿Las cajas están limpias y operativas?', 'yes_no', false, null::numeric, null::numeric, null, null),
      ('Apertura de cajas', 2, '¿El punto de venta inicia correctamente?', 'yes_no', false, null, null, null, null),
      ('Apertura de cajas', 3, '¿El fondo de caja está completo?', 'yes_no', false, null, null, null, null),
      ('Apertura de cajas', 4, '¿El área está despejada y señalizada?', 'yes_no', false, null, null, null, null),
      ('Apertura de cajas', 5, 'Fotografía de la línea de cajas abierta', 'photo', true, null, null, null, null),
      ('Apertura de abarrotes', 1, '¿Los anaqueles están surtidos?', 'yes_no', false, null, null, null, null),
      ('Apertura de abarrotes', 2, '¿Los precios están actualizados en anaquel?', 'yes_no', false, null, null, null, null),
      ('Apertura de abarrotes', 3, '¿No hay productos caducados en exhibición?', 'yes_no', false, null, null, null, null),
      ('Apertura de abarrotes', 4, '¿El área está limpia y ordenada?', 'yes_no', false, null, null, null, null),
      ('Rondín de seguridad mañana', 1, '¿Todas las salidas de emergencia están libres?', 'yes_no', false, null, null, null, null),
      ('Rondín de seguridad mañana', 2, '¿Las cámaras de seguridad funcionan?', 'yes_no', false, null, null, null, null),
      ('Rondín de seguridad mañana', 3, '¿Sin incidencias en estacionamiento?', 'yes_no', false, null, null, null, null),
      ('Rondín de seguridad mañana', 4, 'Evidencia fotográfica del rondín', 'photo', true, null, null, null, null),
      ('Revisión de caducidades', 1, '¿Se revisaron lácteos?', 'yes_no', false, null, null, null, null),
      ('Revisión de caducidades', 2, '¿Se revisaron embutidos?', 'yes_no', false, null, null, null, null),
      ('Revisión de caducidades', 3, '¿Se revisaron enlatados?', 'yes_no', false, null, null, null, null),
      ('Revisión de caducidades', 4, 'Cantidad de productos próximos a vencer (≤ 3 días)', 'number', false, null, null, null, null),
      ('Revisión de caducidades', 5, 'Foto de productos detectados', 'photo', true, null, null, null, null),
      ('Preparación de andén de recibo', 1, '¿El andén está limpio y despejado?', 'yes_no', false, null, null, null, null),
      ('Preparación de andén de recibo', 2, '¿La báscula está calibrada?', 'yes_no', false, null, null, null, null),
      ('Preparación de andén de recibo', 3, '¿Se tienen las órdenes de compra del día?', 'yes_no', false, null, null, null, null),
      ('Preparación de andén de recibo', 4, 'Observaciones', 'text', false, null, null, null, null),
      ('Actualización de precios', 1, '¿Se aplicaron todos los cambios de precio del día?', 'yes_no', false, null, null, null, null),
      ('Actualización de precios', 2, '¿Las cenefas pendientes fueron colocadas?', 'yes_no', false, null, null, null, null),
      ('Actualización de precios', 3, 'Foto de anaquel con cenefas actualizadas', 'photo', true, null, null, null, null),
      ('Control de temperaturas', 1, 'Temperatura refrigerador lácteos (°C)', 'number', false, 0, 4, '°C', 'Vitrina de lácteos'),
      ('Control de temperaturas', 2, 'Temperatura vitrina carnes (°C)', 'number', false, 0, 4, '°C', 'Vitrina de carnes'),
      ('Cierre de abarrotes', 1, '¿Se acomodó y surtió el anaquel?', 'yes_no', false, null, null, null, null),
      ('Cierre de abarrotes', 2, '¿Se reportaron faltantes del día?', 'yes_no', false, null, null, null, null),
      ('Cierre de abarrotes', 3, '¿El área quedó limpia?', 'yes_no', false, null, null, null, null),
      ('Cierre de abarrotes', 4, 'Estado general del área', 'option', false, null, null, null, null),
      ('Cierre de cajas', 1, '¿Se realizó el corte de todas las cajas?', 'yes_no', false, null, null, null, null),
      ('Cierre de cajas', 2, '¿El efectivo se resguardó en bóveda?', 'yes_no', false, null, null, null, null),
      ('Cierre de cajas', 3, '¿Las terminales quedaron apagadas?', 'yes_no', false, null, null, null, null),
      ('Cierre de cajas', 4, 'Foto del corte firmado', 'photo', true, null, null, null, null)
    ) as q(title, pos, txt, typ, photo, mn, mx, unit, equipment) on q.title = t.title and t.company_id = c
    where not exists (select 1 from public.checklist_questions x where x.template_id = t.id and x.text = q.txt);

    update public.checklist_questions q set options = '["Excelente","Bueno","Regular","Malo"]'::jsonb
      from public.checklist_templates t
     where t.id = q.template_id and t.company_id = c and q.answer_type = 'option' and q.options is null;

    -- ── Tareas ──────────────────────────────────────────────────────────────
    insert into public.tasks (company_id, branch_id, department_id, title, description, assigned_to, created_by, due_date, priority, status, requires_evidence)
    select c, cen, (select id from public.departments where company_id = c and code = v.dept),
           v.title, v.descr, v.assignee, e_ger, public.company_today(c) + v.days, v.prio, v.status, v.ev
    from (values
      ('ESC','Actualizar cenefas de lácteos',        'Colocar cenefas del nuevo precio de leche', e_esc, 1, 'high',     'pending',     true),
      ('CAD','Revisar temperatura de cámaras de frío','Registrar lecturas cada 4 horas',          e_cad, 0, 'critical', 'in_progress', false),
      ('ABA','Conteo de abarrotes en pasillos 3 y 4', 'Contar pasillos 3 y 4',                     e_aba, 2, 'medium',   'pending',     false),
      ('CAJ','Capacitar a cajero nuevo en devoluciones','Proceso de devolución con ticket',        e_jcaj,3, 'low',      'pending',     false),
      ('PRO','Verificar sellos de seguridad del almacén','',                                       e_prot,-1,'medium',   'pending',     true)
    ) as v(dept, title, descr, assignee, days, prio, status, ev);

    -- ── Pedidos internos ────────────────────────────────────────────────────
    insert into public.orders (company_id, branch_id, department_id, title, status, priority, requested_by, notes)
    values (c, cen, (select id from public.departments where company_id = c and code = 'ABA'),
            'Resurtido abarrotes semana', 'requested', 'high', e_aba, 'Faltante en pasillo 3 y 4')
    returning id into o_id;
    insert into public.order_items (order_id, product_id, quantity)
    select o_id, p.id, v.q from (values ('ABR-002', 40), ('ABR-004', 60), ('BEB-001', 120)) as v(sku, q)
    join public.products p on p.sku = v.sku and p.company_id = c;

    insert into public.orders (company_id, branch_id, department_id, title, status, priority, requested_by, approved_by, approved_at)
    values (c, cen, (select id from public.departments where company_id = c and code = 'CAD'),
            'Reposición lácteos', 'approved', 'medium', e_cad, e_ger, now() - interval '3 hours')
    returning id into o_id;
    insert into public.order_items (order_id, product_id, quantity)
    select o_id, p.id, 48 from public.products p where p.sku = 'LAC-001' and p.company_id = c;

    -- ── Cambios de precio (hoy → se aplican y generan cenefas; mañana → programado)
    insert into public.price_changes (company_id, branch_id, product_id, old_price, new_price, effective_date, reason, requires_tag, created_by)
    select c, null, p.id, p.price, v.np, public.company_today(c) + v.days, v.reason, true, e_esc
    from (values ('LAC-001', 25.50, 0, 'Ajuste de proveedor'),
                 ('ABR-001', 27.00, 0, 'Promoción semanal'),
                 ('ABR-007', 92.00, 1, 'Incremento de lista')) as v(sku, np, days, reason)
    join public.products p on p.sku = v.sku and p.company_id = c;

    -- ── Caducidades ─────────────────────────────────────────────────────────
    insert into public.product_expirations (company_id, branch_id, product_id, lot, quantity, expiration_date, registered_by)
    select c, cen, p.id, v.lot, v.q, public.company_today(c) + v.days, e_cad
    from (values ('LAC-002','L2401', 12, 2), ('LAC-001','L2402', 18, 5), ('EMB-001','E9001', 6, -1),
                 ('ABR-006','A7788', 40, 120), ('CAR-001','C0101', 8.5, 1)) as v(sku, lot, q, days)
    join public.products p on p.sku = v.sku and p.company_id = c;

    -- ── Tickets de mesa de ayuda ────────────────────────────────────────────
    insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
    values (c, cen, 'No me deja cerrar el checklist de apertura',
            'Al presionar "Completar" aparece un error de evidencia aunque ya tomé la foto.',
            'bug', 'Checklists', 'high', coalesce(e_jcaj, e_ger))
    returning id into tk;
    insert into public.support_ticket_messages (ticket_id, author_id, body) values
      (tk, coalesce(e_jcaj, e_ger), 'Adjunto captura del error. Sucede en la caja 3.'),
      (tk, coalesce(e_sop, e_admin), 'Gracias, ¿la foto se subió desde la pregunta 5 o desde Evidencias?');
    update public.support_tickets set assigned_to = coalesce(e_sop, e_admin), status = 'waiting_user' where id = tk;

    insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
    values (c, cen, 'Solicitud: reporte de mermas por semana',
            'Nos serviría un reporte semanal de mermas por departamento para la junta de los lunes.',
            'feature', 'Reportes', 'low', e_ger);
  end if;

  -- Inventario en cada sucursal activa que aún no lo tenga (incluye sucursales nuevas).
  insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock)
  select c, b.id, p.id, 20 + (random() * 80)::int, 15, 100
  from public.branches b cross join public.products p
  where b.company_id = c and b.status = 'active' and p.company_id = c
  on conflict (branch_id, product_id) do nothing;

  -- Planes de conteo cíclico: diario de Abarrotes en la 1.ª sucursal, general en la 2.ª.
  insert into public.cycle_count_plans (company_id, branch_id, department_id, name, frequency, items_per_count)
  select c, v.branch, d.id, v.name, v.freq, v.n
  from (values (cen, 'ABA', 'Conteo diario de Abarrotes', 'daily', 8),
               (nor, null,  'Conteo general',             'weekdays', 5)) as v(branch, dept, name, freq, n)
  left join public.departments d on d.company_id = c and d.code = v.dept
  where v.branch is not null
    and not exists (select 1 from public.cycle_count_plans x where x.branch_id = v.branch and x.name = v.name);

  perform public.generate_checklist_runs(c, public.company_today(c));
  perform public.generate_cycle_counts(c, public.company_today(c));
  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.seed_company_demo(uuid) from public, anon, authenticated;

-- ─── GATO PELÓN ─────────────────────────────────────────────────────────────
-- Cuarta sucursal (solo demo).
insert into public.branches (id, company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status, zone_id)
select 'b0000000-0000-4000-8000-000000000004', c.id, '004', 'Sucursal Playas', 'tienda', 'Paseo Playas 300', 'Tijuana', '664-100-0004',
       '07:00', '22:00', 'active', (select z.id from public.zones z where z.company_id = c.id and z.code = 'OES')
from public.companies c where c.id = 'c0000000-0000-4000-8000-000000000001'
on conflict (id) do nothing;
-- Puntos QR y checklists de la sucursal nueva.
select public.seed_company_base('c0000000-0000-4000-8000-000000000001');

select public.demo_seed_user(c, v.u, 'prueba123', v.n, v.r, v.b, v.d, v.p, v.code)
from (values
  ('gatopelon',      'Gato Pelón',             'admin',       '001', 'ADM', 'Administrador general',  'EMP-0001'),
  ('soporte',        'Equipo de Soporte',      'soporte',     '001', 'TI',  'Soporte de plataforma',  'EMP-0002'),
  ('auditor',        'Elena Auditora',         'auditor',     '001', 'ADM', 'Auditora interna',       'EMP-0003'),
  ('gerente.centro', 'Laura Gerente',          'gerente',     '001', 'GER', 'Gerente de sucursal',    'EMP-0004'),
  ('gerente.norte',  'Pedro López',            'gerente',     '002', 'GER', 'Gerente de sucursal',    'EMP-0005'),
  ('supervisor',     'Sofía Supervisora',      'supervisor',  '001', 'ABA', 'Supervisora de piso',    'EMP-0006'),
  ('jefe.cajas',     'Ana Jefa de Cajas',      'jefe_cajas',  '001', 'CAJ', 'Jefa de cajas',          'EMP-0007'),
  ('cajero',         'Luis Cajero',            'cajas',       '001', 'CAJ', 'Cajero',                 'EMP-0008'),
  ('abarrotes',      'Pedro Abarrotes',        'abarrotes',   '001', 'ABA', 'Auxiliar de abarrotes',  'EMP-0009'),
  ('recibo',         'Mario Recibo',           'recibo',      '001', 'REC', 'Jefe de recibo',         'EMP-0010'),
  ('almacen',        'Jorge Almacén',          'almacen',     '001', 'ALM', 'Almacenista',            'EMP-0011'),
  ('proteccion',     'Juan Soria',             'proteccion',  '001', 'PRO', 'Oficial de protección',  'EMP-0012'),
  ('caducidades',    'María Torres',           'caducidades', '001', 'CAD', 'Auxiliar de caducidades','EMP-0013'),
  ('escaner',        'Rosa Escáner',           'escaner',     '001', 'ESC', 'Auxiliar de escáner',    'EMP-0014')
) as v(u, n, r, b, d, p, code)
cross join (select 'c0000000-0000-4000-8000-000000000001'::uuid as c) x;

-- La supervisora cubre Abarrotes y además Caducidades.
insert into public.employee_departments (employee_id, department_id)
select e.id, d.id from public.employees e, public.departments d
where e.username = 'supervisor' and d.code = 'CAD' and d.company_id = e.company_id
  and e.company_id = 'c0000000-0000-4000-8000-000000000001'
on conflict do nothing;

-- Gerentes asignados a sus sucursales.
update public.branches b set manager_id = e.id
from public.employees e
where (b.code, e.username) in (('001','gerente.centro'), ('002','gerente.norte'))
  and b.company_id = e.company_id and b.company_id = 'c0000000-0000-4000-8000-000000000001';

select public.seed_company_demo('c0000000-0000-4000-8000-000000000001');

-- Mantenimiento inicial (marca vencidos según la hora actual, aplica precios del día).
select public.run_daily_maintenance('c0000000-0000-4000-8000-000000000001');
