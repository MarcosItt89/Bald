-- =============================================================================
-- OPERALIA · SEMILLA 0008 · CATÁLOGO DE PERMISOS Y EMPRESA GATO PELÓN
-- -----------------------------------------------------------------------------
--   * Catálogo global de permisos (los posteriores los agrega cada migración).
--   * Empresa Gato Pelón (code gatopelon) y sus sucursales; zona de cada una.
--   * public.seed_company_base (migración 0023) le siembra departamentos,
--     zonas, roles y sus permisos, temas de soporte, plantillas de checklist y
--     puntos QR. Antes eso estaba repartido en seed/0008…0018.
-- IDs fijos para la empresa y sucursales. Re-ejecutable.
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
insert into public.companies (id, code, name, legal_name, timezone)
values ('c0000000-0000-4000-8000-000000000001', 'gatopelon', 'Gato Pelón', 'Gato Pelón S.A. de C.V.', 'America/Tijuana')
on conflict (id) do nothing;

-- ─── SUCURSALES ──────────────────────────────────────────────────────────────
insert into public.branches (id, company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status) values
  ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', '001', 'Sucursal Centro', 'tienda',  'Av. Principal 100',  'Tijuana', '664-100-0001', '07:00', '23:00', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', '002', 'Sucursal Norte',  'tienda',  'Blvd. Norte 250',    'Tijuana', '664-100-0002', '07:00', '22:00', 'active'),
  ('b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', '003', 'Sucursal Sur',    'express', 'Calle Sur 45',       'Tijuana', '664-100-0003', '08:00', '21:00', 'active')
on conflict (id) do nothing;

-- ─── SEMILLA BASE ────────────────────────────────────────────────────────────
select public.seed_company_base('c0000000-0000-4000-8000-000000000001');

-- Zona de cada sucursal (001 Centro, 002 Norte, 003 Sur).
update public.branches b set zone_id = z.id
  from public.zones z
 where z.company_id = b.company_id and b.zone_id is null and b.company_id = 'c0000000-0000-4000-8000-000000000001'
   and z.code = case b.code when '001' then 'CEN' when '002' then 'NOR' when '003' then 'SUR' end;
