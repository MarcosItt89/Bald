-- =============================================================================
-- OPERALIA · 0008 · CATÁLOGOS INICIALES
-- -----------------------------------------------------------------------------
-- Objetivo: dejar la empresa lista para operar: permisos, roles con sus
-- permisos, empresa demo, sucursales y departamentos.
--
-- IDs fijos para la empresa y sucursales → los demás scripts pueden
-- referenciarlos sin búsquedas. Idempotente (ON CONFLICT).
--
-- Si se agrega un permiso nuevo en el frontend (src/config/permissions.js)
-- también debe agregarse aquí.
-- =============================================================================

-- ─── PERMISOS ────────────────────────────────────────────────────────────────
insert into public.permissions (code, module, name, description) values
  ('view_dashboard',             'General',       'Ver dashboard',                  'Acceso al panel principal'),
  ('view_inventory',             'Inventario',    'Ver inventario',                 'Consultar existencias y movimientos'),
  ('manage_inventory',           'Inventario',    'Gestionar inventario',           'Altas de producto, ajustes, conteos y mínimos'),
  ('view_prices',                'Inventario',    'Consultar precios',              'Buscar productos y ver su precio'),
  ('scan_products',              'Inventario',    'Escanear productos',             'Usar lector / cámara para buscar'),
  ('report_price_difference',    'Inventario',    'Reportar diferencia de precio',  'Levantar tarea por precio incorrecto'),
  ('create_orders',              'Pedidos',       'Crear pedidos internos',         'Solicitar mercancía o insumos'),
  ('approve_orders',             'Pedidos',       'Aprobar pedidos',                'Revisar, aprobar, rechazar y enviar pedidos'),
  ('view_suppliers',             'Proveedores',   'Ver proveedores',                'Consultar catálogo de proveedores'),
  ('manage_suppliers',           'Proveedores',   'Gestionar proveedores',          'Alta y edición de proveedores'),
  ('register_supplier_visit',    'Proveedores',   'Registrar accesos',              'Entrada y salida de proveedores'),
  ('receive_products',           'Recibo',        'Recibir mercancía',              'Capturar recibos y productos recibidos'),
  ('close_receiving',            'Recibo',        'Cerrar recibos',                 'Cerrar recibo y afectar inventario'),
  ('fill_checklists',            'Checklists',    'Llenar checklists',              'Responder checklists y bitácoras'),
  ('review_checklists',          'Checklists',    'Revisar checklists',             'Aprobar, rechazar y reabrir checklists'),
  ('manage_checklist_templates', 'Checklists',    'Diseñar checklists',             'Crear y editar plantillas'),
  ('upload_evidence',            'Evidencias',    'Subir evidencias',               'Adjuntar fotos y archivos'),
  ('review_evidence',            'Evidencias',    'Revisar evidencias',             'Aprobar o rechazar evidencias'),
  ('manage_expirations',         'Caducidades',   'Gestionar caducidades',          'Registrar lotes, rebajas y retiros'),
  ('manage_price_changes',       'Precios',       'Gestionar cambios de precio',    'Registrar cambios de precio'),
  ('manage_shelf_tags',          'Precios',       'Gestionar cenefas',              'Imprimir y colocar cenefas'),
  ('validate_shelf_tags',        'Precios',       'Validar cenefas',                'Validar que la cenefa está correcta'),
  ('view_tasks',                 'Tareas',        'Ver tareas',                     'Ver y avanzar tareas asignadas'),
  ('manage_tasks',               'Tareas',        'Gestionar tareas',               'Crear, asignar y cancelar tareas'),
  ('view_reports',               'Reportes',      'Ver reportes',                   'Indicadores y exportación'),
  ('view_audit_logs',            'Reportes',      'Ver bitácora de auditoría',      'Historial de cambios del sistema'),
  ('manage_employees',           'Configuración', 'Gestionar empleados',            'Alta, baja y edición de empleados'),
  ('manage_branches',            'Configuración', 'Gestionar sucursales',           'Sucursales, departamentos y empresa'),
  ('manage_roles',               'Configuración', 'Gestionar roles y permisos',     'Editar roles y permisos especiales'),
  ('create_tickets',             'Soporte',       'Solicitar ayuda',                'Levantar tickets en la mesa de ayuda'),
  ('manage_tickets',             'Soporte',       'Atender tickets',                'Responder, asignar y resolver tickets')
on conflict (code) do update set module = excluded.module, name = excluded.name, description = excluded.description;

-- ─── EMPRESA ─────────────────────────────────────────────────────────────────
insert into public.companies (id, name, legal_name, timezone)
values ('c0000000-0000-4000-8000-000000000001', 'Gato Pelón', 'Gato Pelón S.A. de C.V.', 'America/Tijuana')
on conflict (id) do nothing;

-- ─── SUCURSALES ──────────────────────────────────────────────────────────────
insert into public.branches (id, company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status) values
  ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', '001', 'Sucursal Centro', 'tienda',  'Av. Principal 100',  'Tijuana', '664-100-0001', '07:00', '23:00', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', '002', 'Sucursal Norte',  'tienda',  'Blvd. Norte 250',    'Tijuana', '664-100-0002', '07:00', '22:00', 'active'),
  ('b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', '003', 'Sucursal Sur',    'express', 'Calle Sur 45',       'Tijuana', '664-100-0003', '08:00', '21:00', 'inactive')
on conflict (id) do nothing;

-- ─── DEPARTAMENTOS ───────────────────────────────────────────────────────────
insert into public.departments (company_id, code, name, color, description) values
  ('c0000000-0000-4000-8000-000000000001', 'ADM', 'Administración', '#0f172a', 'Oficina y administración general'),
  ('c0000000-0000-4000-8000-000000000001', 'GER', 'Gerencia',       '#1e40af', 'Gerencia de sucursal'),
  ('c0000000-0000-4000-8000-000000000001', 'CAJ', 'Cajas',          '#2563eb', 'Línea de cajas y atención'),
  ('c0000000-0000-4000-8000-000000000001', 'ABA', 'Abarrotes',      '#16a34a', 'Piso de venta abarrotes'),
  ('c0000000-0000-4000-8000-000000000001', 'REC', 'Recibo',         '#9333ea', 'Andén y recibo de mercancía'),
  ('c0000000-0000-4000-8000-000000000001', 'ALM', 'Almacén',        '#78350f', 'Bodega y resguardo'),
  ('c0000000-0000-4000-8000-000000000001', 'PRO', 'Protección',     '#dc2626', 'Seguridad y prevención de pérdidas'),
  ('c0000000-0000-4000-8000-000000000001', 'CAD', 'Caducidades',    '#ea580c', 'Control de fechas de caducidad'),
  ('c0000000-0000-4000-8000-000000000001', 'ESC', 'Escáner',        '#0891b2', 'Precios, escaneo y cenefas'),
  ('c0000000-0000-4000-8000-000000000001', 'CAR', 'Carnicería',     '#b91c1c', 'Cárnicos'),
  ('c0000000-0000-4000-8000-000000000001', 'PES', 'Pescadería',     '#0e7490', 'Pescados y mariscos'),
  ('c0000000-0000-4000-8000-000000000001', 'JUG', 'Juguetería',     '#db2777', 'Juguetes y temporada'),
  ('c0000000-0000-4000-8000-000000000001', 'TI',  'Soporte TI',     '#475569', 'Mantenimiento de la plataforma')
on conflict (company_id, code) do nothing;

-- ─── ROLES ───────────────────────────────────────────────────────────────────
insert into public.roles (company_id, code, name, scope, is_system, description) values
  ('c0000000-0000-4000-8000-000000000001', 'admin',       'Administrador general', 'company',    true, 'Control total de la empresa'),
  ('c0000000-0000-4000-8000-000000000001', 'soporte',     'Soporte TI',            'company',    true, 'Atiende la mesa de ayuda'),
  ('c0000000-0000-4000-8000-000000000001', 'auditor',     'Auditor',               'company',    true, 'Solo lectura de reportes y evidencias'),
  ('c0000000-0000-4000-8000-000000000001', 'gerente',     'Gerente de sucursal',   'branch',     true, 'Supervisa toda su sucursal'),
  ('c0000000-0000-4000-8000-000000000001', 'supervisor',  'Supervisor',            'department', true, 'Revisa departamentos asignados'),
  ('c0000000-0000-4000-8000-000000000001', 'jefe_cajas',  'Jefe de cajas',         'department', true, 'Responsable de la línea de cajas'),
  ('c0000000-0000-4000-8000-000000000001', 'cajas',       'Cajero(a)',             'self',       true, 'Consulta de precios y checklists de caja'),
  ('c0000000-0000-4000-8000-000000000001', 'abarrotes',   'Abarrotes',             'department', true, 'Inventario y pedidos de abarrotes'),
  ('c0000000-0000-4000-8000-000000000001', 'recibo',      'Recibo',                'department', true, 'Proveedores y recibo de mercancía'),
  ('c0000000-0000-4000-8000-000000000001', 'almacen',     'Almacén',               'department', true, 'Entradas, salidas y ajustes'),
  ('c0000000-0000-4000-8000-000000000001', 'proteccion',  'Protección',            'department', true, 'Rondines y control de accesos'),
  ('c0000000-0000-4000-8000-000000000001', 'caducidades', 'Caducidades',           'department', true, 'Control de lotes y fechas'),
  ('c0000000-0000-4000-8000-000000000001', 'escaner',     'Escáner',               'department', true, 'Cambios de precio y cenefas')
on conflict (company_id, code) do nothing;

-- ─── PERMISOS POR ROL ────────────────────────────────────────────────────────
with matrix(role_code, perms) as (values
  ('admin', (select array_agg(code) from public.permissions)),
  ('soporte', array['view_dashboard','create_tickets','manage_tickets','view_reports','view_audit_logs']),
  ('auditor', array['view_dashboard','view_inventory','view_prices','view_suppliers','view_tasks',
                    'view_reports','view_audit_logs']),
  ('gerente', array['view_dashboard','view_inventory','manage_inventory','view_prices','scan_products',
                    'report_price_difference','create_orders','approve_orders','view_suppliers','manage_suppliers',
                    'register_supplier_visit','receive_products','close_receiving','fill_checklists',
                    'review_checklists','manage_checklist_templates','upload_evidence','review_evidence',
                    'manage_expirations','manage_price_changes','manage_shelf_tags','validate_shelf_tags',
                    'view_tasks','manage_tasks','view_reports','view_audit_logs','manage_employees','create_tickets']),
  ('supervisor', array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                    'view_suppliers','fill_checklists','review_checklists','upload_evidence','review_evidence',
                    'manage_expirations','validate_shelf_tags','view_tasks','manage_tasks','view_reports','create_tickets']),
  ('jefe_cajas', array['view_dashboard','view_prices','scan_products','report_price_difference',
                    'fill_checklists','review_checklists','upload_evidence','review_evidence',
                    'view_tasks','manage_tasks','view_reports','create_tickets']),
  ('cajas', array['view_dashboard','view_prices','scan_products','report_price_difference',
                    'fill_checklists','upload_evidence','view_tasks']),
  ('abarrotes', array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                    'fill_checklists','upload_evidence','view_tasks']),
  ('recibo', array['view_dashboard','view_inventory','view_suppliers','register_supplier_visit',
                    'receive_products','close_receiving','fill_checklists','upload_evidence','view_tasks']),
  ('almacen', array['view_dashboard','view_inventory','manage_inventory','view_prices','create_orders',
                    'receive_products','fill_checklists','upload_evidence','view_tasks']),
  ('proteccion', array['view_dashboard','view_suppliers','register_supplier_visit','fill_checklists',
                    'upload_evidence','view_tasks']),
  ('caducidades', array['view_dashboard','view_inventory','view_prices','scan_products','manage_expirations',
                    'create_orders','fill_checklists','upload_evidence','view_tasks']),
  ('escaner', array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                    'manage_price_changes','manage_shelf_tags','fill_checklists','upload_evidence','view_tasks'])
)
insert into public.role_permissions (role_id, permission_code)
select r.id, unnest(m.perms)
from matrix m
join public.roles r on r.code = m.role_code and r.company_id = 'c0000000-0000-4000-8000-000000000001'
on conflict do nothing;
