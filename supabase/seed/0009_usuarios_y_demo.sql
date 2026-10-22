-- =============================================================================
-- OPERALIA · 0009 · USUARIOS DE PRUEBA Y DATOS DEMO
-- -----------------------------------------------------------------------------
-- Objetivo: dejar el sistema listo para probar cada rol.
--
-- Inicio de sesión: se usa el USUARIO (no el correo). Internamente Supabase
-- Auth necesita un correo, así que se genera  usuario@operalia.local
-- (el dominio debe coincidir con VITE_AUTH_EMAIL_DOMAIN del .env).
--
--   Usuario            Contraseña   Rol                    Sucursal
--   ─────────────────  ───────────  ─────────────────────  ───────────────
--   gatopelon          tulipan23    Administrador general  Centro
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
-- ⚠ Cambia las contraseñas de prueba antes de usar el sistema en producción.
-- Idempotente: si el usuario ya existe no lo duplica.
-- =============================================================================

-- Función temporal para crear empleado + cuenta de Auth ligada.
create or replace function public._seed_user(
  p_username text, p_password text, p_full_name text, p_role text,
  p_branch_code text, p_dept_code text, p_position text, p_employee_code text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_company uuid := 'c0000000-0000-4000-8000-000000000001';
  v_email   text := lower(p_username) || '@operalia.local';
  v_emp     uuid;
  v_user    uuid;
begin
  -- 1) Empleado
  select id into v_emp from public.employees where lower(username) = lower(p_username);
  if v_emp is null then
    insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                  username, full_name, position, email)
    values (
      v_company,
      (select id from public.branches where company_id = v_company and code = p_branch_code),
      (select id from public.departments where company_id = v_company and code = p_dept_code),
      (select id from public.roles where company_id = v_company and code = p_role),
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

select public._seed_user('gatopelon',      'tulipan23', 'Gato Pelón',             'admin',       '001', 'ADM', 'Administrador general', 'EMP-0001');
select public._seed_user('soporte',        'prueba123', 'Equipo de Soporte',      'soporte',     '001', 'TI',  'Soporte de plataforma', 'EMP-0002');
select public._seed_user('auditor',        'prueba123', 'Elena Auditora',         'auditor',     '001', 'ADM', 'Auditora interna',      'EMP-0003');
select public._seed_user('gerente.centro', 'prueba123', 'Laura Gerente',          'gerente',     '001', 'GER', 'Gerente de sucursal',   'EMP-0004');
select public._seed_user('gerente.norte',  'prueba123', 'Pedro López',            'gerente',     '002', 'GER', 'Gerente de sucursal',   'EMP-0005');
select public._seed_user('supervisor',     'prueba123', 'Sofía Supervisora',      'supervisor',  '001', 'ABA', 'Supervisora de piso',   'EMP-0006');
select public._seed_user('jefe.cajas',     'prueba123', 'Ana Jefa de Cajas',      'jefe_cajas',  '001', 'CAJ', 'Jefa de cajas',         'EMP-0007');
select public._seed_user('cajero',         'prueba123', 'Luis Cajero',            'cajas',       '001', 'CAJ', 'Cajero',                'EMP-0008');
select public._seed_user('abarrotes',      'prueba123', 'Pedro Abarrotes',        'abarrotes',   '001', 'ABA', 'Auxiliar de abarrotes', 'EMP-0009');
select public._seed_user('recibo',         'prueba123', 'Mario Recibo',           'recibo',      '001', 'REC', 'Jefe de recibo',        'EMP-0010');
select public._seed_user('almacen',        'prueba123', 'Jorge Almacén',          'almacen',     '001', 'ALM', 'Almacenista',           'EMP-0011');
select public._seed_user('proteccion',     'prueba123', 'Juan Soria',             'proteccion',  '001', 'PRO', 'Oficial de protección', 'EMP-0012');
select public._seed_user('caducidades',    'prueba123', 'María Torres',           'caducidades', '001', 'CAD', 'Auxiliar de caducidades','EMP-0013');
select public._seed_user('escaner',        'prueba123', 'Rosa Escáner',           'escaner',     '001', 'ESC', 'Auxiliar de escáner',   'EMP-0014');

drop function public._seed_user(text, text, text, text, text, text, text, text);

-- La supervisora cubre Abarrotes y además Caducidades.
insert into public.employee_departments (employee_id, department_id)
select e.id, d.id from public.employees e, public.departments d
where e.username = 'supervisor' and d.code = 'CAD' and d.company_id = e.company_id
on conflict do nothing;

-- Gerentes asignados a sus sucursales.
update public.branches b set manager_id = e.id
from public.employees e
where (b.code, e.username) in (('001','gerente.centro'), ('002','gerente.norte'))
  and b.company_id = e.company_id;

-- =============================================================================
-- DATOS DEMO (productos, inventario, proveedores, checklists, tareas...)
-- Se envuelve en un bloque que solo corre si aún no hay productos.
-- =============================================================================
do $$
declare
  c   uuid := 'c0000000-0000-4000-8000-000000000001';
  cen uuid := 'b0000000-0000-4000-8000-000000000001';
  nor uuid := 'b0000000-0000-4000-8000-000000000002';
  e_admin uuid; e_ger uuid; e_jcaj uuid; e_esc uuid; e_aba uuid; e_cad uuid; e_rec uuid; e_sup uuid; e_prot uuid; e_sop uuid;
  t_id uuid; o_id uuid; tk uuid;
begin
  if exists (select 1 from public.products where company_id = c) then
    raise notice 'Datos demo ya existen; se omiten.';
    return;
  end if;

  select id into e_admin from public.employees where username = 'gatopelon';
  select id into e_ger   from public.employees where username = 'gerente.centro';
  select id into e_jcaj  from public.employees where username = 'jefe.cajas';
  select id into e_esc   from public.employees where username = 'escaner';
  select id into e_aba   from public.employees where username = 'abarrotes';
  select id into e_cad   from public.employees where username = 'caducidades';
  select id into e_rec   from public.employees where username = 'recibo';
  select id into e_sup   from public.employees where username = 'supervisor';
  select id into e_prot  from public.employees where username = 'proteccion';
  select id into e_sop   from public.employees where username = 'soporte';

  -- ── Productos + códigos de barras ─────────────────────────────────────────
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

  -- ── Inventario (el trigger calcula el estado: normal / bajo / crítico / sin existencia)
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

  insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock)
  select c, nor, p.id, (random() * 80)::int, 15, 100 from public.products p where p.company_id = c;

  -- ── Proveedores y una visita abierta ──────────────────────────────────────
  insert into public.suppliers (company_id, code, name, legal_name, merchandise_type, contact_name, phone, email, status) values
    (c, 'PROV-001', 'Distribuidora Nacional',  'Distribuidora Nacional S.A.',  'Abarrotes',  'Jorge Martínez', '664-123-4567', 'ventas@disnacional.mx', 'active'),
    (c, 'PROV-002', 'Lácteos del Noroeste',    'Lácteos del Noroeste S.A.',    'Lácteos',    'Rosa Sánchez',   '664-234-5678', 'pedidos@lacteosno.mx',  'active'),
    (c, 'PROV-003', 'Congelados y Frescos',    'Congelados y Frescos S.A.',    'Cárnicos',   'Manuel Cruz',    '664-345-6789', 'contacto@cyf.mx',       'active'),
    (c, 'PROV-004', 'Bebidas y Refrescos MX',  'Bebidas y Refrescos MX S.A.',  'Bebidas',    'Patricia León',  '664-456-7890', null,                    'inactive');

  insert into public.supplier_visits (company_id, branch_id, supplier_id, check_in_at, driver_name, vehicle_plate, purpose, registered_by)
  select c, cen, s.id, now() - interval '40 minutes', 'Raúl Pérez', 'BC-12-345', 'entrega', e_prot
  from public.suppliers s where s.code = 'PROV-002' and s.company_id = c;

  -- ── Plantillas de checklist + preguntas ───────────────────────────────────
  -- (dept, título, turno, inicio, fin, requiere evidencia, preguntas[texto|tipo|foto])
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
  ) as v(dept, title, shift, st, et, ev, descr);

  insert into public.checklist_questions (template_id, position, text, answer_type, requires_photo, is_required)
  select t.id, q.pos, q.txt, q.typ, q.photo, true
  from public.checklist_templates t
  join (values
    ('Apertura de cajas', 1, '¿Las cajas están limpias y operativas?', 'yes_no', false),
    ('Apertura de cajas', 2, '¿El punto de venta inicia correctamente?', 'yes_no', false),
    ('Apertura de cajas', 3, '¿El fondo de caja está completo?', 'yes_no', false),
    ('Apertura de cajas', 4, '¿El área está despejada y señalizada?', 'yes_no', false),
    ('Apertura de cajas', 5, 'Fotografía de la línea de cajas abierta', 'photo', true),
    ('Apertura de abarrotes', 1, '¿Los anaqueles están surtidos?', 'yes_no', false),
    ('Apertura de abarrotes', 2, '¿Los precios están actualizados en anaquel?', 'yes_no', false),
    ('Apertura de abarrotes', 3, '¿No hay productos caducados en exhibición?', 'yes_no', false),
    ('Apertura de abarrotes', 4, '¿El área está limpia y ordenada?', 'yes_no', false),
    ('Rondín de seguridad mañana', 1, '¿Todas las salidas de emergencia están libres?', 'yes_no', false),
    ('Rondín de seguridad mañana', 2, '¿Las cámaras de seguridad funcionan?', 'yes_no', false),
    ('Rondín de seguridad mañana', 3, '¿Sin incidencias en estacionamiento?', 'yes_no', false),
    ('Rondín de seguridad mañana', 4, 'Evidencia fotográfica del rondín', 'photo', true),
    ('Revisión de caducidades', 1, '¿Se revisaron lácteos?', 'yes_no', false),
    ('Revisión de caducidades', 2, '¿Se revisaron embutidos?', 'yes_no', false),
    ('Revisión de caducidades', 3, '¿Se revisaron enlatados?', 'yes_no', false),
    ('Revisión de caducidades', 4, 'Cantidad de productos próximos a vencer (≤ 3 días)', 'number', false),
    ('Revisión de caducidades', 5, 'Foto de productos detectados', 'photo', true),
    ('Preparación de andén de recibo', 1, '¿El andén está limpio y despejado?', 'yes_no', false),
    ('Preparación de andén de recibo', 2, '¿La báscula está calibrada?', 'yes_no', false),
    ('Preparación de andén de recibo', 3, '¿Se tienen las órdenes de compra del día?', 'yes_no', false),
    ('Preparación de andén de recibo', 4, 'Observaciones', 'text', false),
    ('Actualización de precios', 1, '¿Se aplicaron todos los cambios de precio del día?', 'yes_no', false),
    ('Actualización de precios', 2, '¿Las cenefas pendientes fueron colocadas?', 'yes_no', false),
    ('Actualización de precios', 3, 'Foto de anaquel con cenefas actualizadas', 'photo', true),
    ('Control de temperaturas', 1, 'Temperatura refrigerador lácteos (°C)', 'number', false),
    ('Control de temperaturas', 2, 'Temperatura vitrina carnes (°C)', 'number', false),
    ('Control de temperaturas', 3, '¿Alguna temperatura fuera de rango?', 'yes_no', false),
    ('Cierre de abarrotes', 1, '¿Se acomodó y surtió el anaquel?', 'yes_no', false),
    ('Cierre de abarrotes', 2, '¿Se reportaron faltantes del día?', 'yes_no', false),
    ('Cierre de abarrotes', 3, '¿El área quedó limpia?', 'yes_no', false),
    ('Cierre de abarrotes', 4, 'Estado general del área', 'option', false),
    ('Cierre de cajas', 1, '¿Se realizó el corte de todas las cajas?', 'yes_no', false),
    ('Cierre de cajas', 2, '¿El efectivo se resguardó en bóveda?', 'yes_no', false),
    ('Cierre de cajas', 3, '¿Las terminales quedaron apagadas?', 'yes_no', false),
    ('Cierre de cajas', 4, 'Foto del corte firmado', 'photo', true)
  ) as q(title, pos, txt, typ, photo) on q.title = t.title and t.company_id = c;

  update public.checklist_questions set options = '["Excelente","Bueno","Regular","Malo"]'::jsonb
  where answer_type = 'option' and options is null;

  -- Ejecuciones de hoy para todas las sucursales activas.
  perform public.generate_checklist_runs(c, public.company_today(c));

  -- ── Tareas ────────────────────────────────────────────────────────────────
  insert into public.tasks (company_id, branch_id, department_id, title, description, assigned_to, created_by, due_date, priority, status, requires_evidence)
  select c, cen, (select id from public.departments where company_id = c and code = v.dept),
         v.title, v.descr, v.assignee, e_ger, public.company_today(c) + v.days, v.prio, v.status, v.ev
  from (values
    ('ESC','Actualizar cenefas de lácteos',        'Colocar cenefas del nuevo precio de leche', e_esc, 1, 'high',     'pending',     true),
    ('CAD','Revisar temperatura de cámaras de frío','Registrar lecturas cada 4 horas',          e_cad, 0, 'critical', 'in_progress', false),
    ('ABA','Conteo cíclico de abarrotes',          'Contar pasillos 3 y 4',                     e_aba, 2, 'medium',   'pending',     false),
    ('CAJ','Capacitar a cajero nuevo en devoluciones','Proceso de devolución con ticket',        e_jcaj,3, 'low',      'pending',     false),
    ('PRO','Verificar sellos de seguridad del almacén','',                                       e_prot,-1,'medium',   'pending',     true)
  ) as v(dept, title, descr, assignee, days, prio, status, ev);

  -- ── Pedidos internos ──────────────────────────────────────────────────────
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

  -- ── Caducidades ───────────────────────────────────────────────────────────
  insert into public.product_expirations (company_id, branch_id, product_id, lot, quantity, expiration_date, registered_by)
  select c, cen, p.id, v.lot, v.q, public.company_today(c) + v.days, e_cad
  from (values ('LAC-002','L2401', 12, 2), ('LAC-001','L2402', 18, 5), ('EMB-001','E9001', 6, -1),
               ('ABR-006','A7788', 40, 120), ('CAR-001','C0101', 8.5, 1)) as v(sku, lot, q, days)
  join public.products p on p.sku = v.sku and p.company_id = c;

  -- ── Tickets de mesa de ayuda ──────────────────────────────────────────────
  insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
  values (c, cen, 'No me deja cerrar el checklist de apertura',
          'Al presionar "Completar" aparece un error de evidencia aunque ya tomé la foto.',
          'bug', 'Checklists', 'high', e_jcaj)
  returning id into tk;
  insert into public.support_ticket_messages (ticket_id, author_id, body) values
    (tk, e_jcaj, 'Adjunto captura del error. Sucede en la caja 3.'),
    (tk, e_sop,  'Gracias, ¿la foto se subió desde la pregunta 5 o desde Evidencias?');
  update public.support_tickets set assigned_to = e_sop, status = 'waiting_user' where id = tk;

  insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
  values (c, cen, 'Solicitud: reporte de mermas por semana',
          'Nos serviría un reporte semanal de mermas por departamento para la junta de los lunes.',
          'feature', 'Reportes', 'low', e_ger);
end $$;

-- Mantenimiento inicial (marca vencidos según la hora actual, aplica precios del día).
select public.run_daily_maintenance('c0000000-0000-4000-8000-000000000001');
