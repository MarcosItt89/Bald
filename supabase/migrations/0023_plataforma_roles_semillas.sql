-- =============================================================================
-- OPERALIA · 0023 · SUPERADMIN DE PLATAFORMA, ROLES DEL PROPIETARIO Y
--                   SEMILLA BASE POR EMPRESA
-- -----------------------------------------------------------------------------
--   A. platform_admins + is_platform_admin(): el superadmin de la plataforma,
--      distinto del propietario de cada empresa (employees.is_owner).
--   B. Roles y permisos (roles, role_permissions, employee_permissions) solo los
--      edita quien tiene manage_roles Y es propietario o superadmin.
--      Correcciones de RLS que dependían solo de un permiso (ver diario).
--   C. seed_company_base(empresa): todo lo que una empresa necesita para operar
--      (departamentos, zonas, roles y sus permisos, temas de soporte,
--      plantillas de checklist, puntos QR). Re-ejecutable; solo agrega lo que
--      falta. Las semillas de seed/ la llaman para Gato Pelón.
-- Re-ejecutable.
-- =============================================================================

-- ─── A. SUPERADMIN DE PLATAFORMA ────────────────────────────────────────────
create table if not exists public.platform_admins (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;
grant select on public.platform_admins to authenticated;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.platform_admins where user_id = auth.uid())
$$;
revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- Solo un superadmin la lee; nadie la escribe desde la API (se administra en el SQL Editor).
drop policy if exists platform_admins_select on public.platform_admins;
create policy platform_admins_select on public.platform_admins for select to authenticated
  using ((select public.is_platform_admin()));

-- Perfil (0022) + is_owner e is_platform_admin.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name, 'company_code', c.code,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'is_owner', e.is_owner,
    'is_platform_admin', public.is_platform_admin(),
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;

-- ─── B. ROLES Y PERMISOS: SOLO PROPIETARIO O SUPERADMIN ─────────────────────
create or replace function public.can_manage_roles()
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_permission('manage_roles') and (public.auth_is_owner() or public.is_platform_admin())
$$;
revoke all on function public.can_manage_roles() from public, anon;
grant execute on function public.can_manage_roles() to authenticated;

drop policy if exists roles_write on public.roles;
create policy roles_write on public.roles for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.can_manage_roles()))
  with check (company_id = (select public.auth_company_id()) and (select public.can_manage_roles()));

drop policy if exists role_permissions_write on public.role_permissions;
create policy role_permissions_write on public.role_permissions for all to authenticated
  using ((select public.can_manage_roles())
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())))
  with check ((select public.can_manage_roles())
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));

drop policy if exists employee_permissions_write on public.employee_permissions;
create policy employee_permissions_write on public.employee_permissions for all to authenticated
  using ((select public.can_manage_roles())
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.can_manage_roles())
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

-- ─── B. CORRECCIONES DE RLS (permisos que hoy alcanzaban de más) ────────────
-- Datos de la empresa: solo propietario o superadmin (antes bastaba manage_branches).
drop policy if exists companies_update on public.companies;
create policy companies_update on public.companies for update to authenticated
  using (id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and ((select public.auth_is_owner()) or (select public.is_platform_admin())))
  with check (id = (select public.auth_company_id()));

-- Sucursales, departamentos y zonas son de toda la empresa: además del permiso,
-- alcance de empresa (un rol de sucursal con manage_branches no edita las demás).
drop policy if exists branches_write on public.branches;
create policy branches_write on public.branches for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');
drop policy if exists departments_write on public.departments;
create policy departments_write on public.departments for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');
drop policy if exists zones_write on public.zones;
create policy zones_write on public.zones for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');

-- Departamentos extra de un empleado: solo de empleados que el usuario puede gestionar.
drop policy if exists employee_departments_write on public.employee_departments;
create policy employee_departments_write on public.employee_departments for all to authenticated
  using ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())
                     and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(e.branch_id))))
  with check ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())
                     and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(e.branch_id))));

-- Renglones de pedido: quien aprueba solo toca pedidos de sus sucursales/departamentos.
drop policy if exists order_items_write on public.order_items;
create policy order_items_write on public.order_items for all to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id())
              or ((select public.has_permission('approve_orders')) and public.can_access_department(o.branch_id, o.department_id)))))
  with check (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id())
              or ((select public.has_permission('approve_orders')) and public.can_access_department(o.branch_id, o.department_id)))));

-- Cambios de precio programados: editar con el mismo alcance que para crearlos (0015).
drop policy if exists price_changes_update on public.price_changes;
create policy price_changes_update on public.price_changes for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
         and status = 'scheduled'
         and (   (branch_id is null and zone_id is null and (select public.auth_role_scope()) = 'company')
              or (zone_id is not null and ((select public.auth_role_scope()) = 'company' or zone_id in (select public.auth_zone_ids())))
              or (branch_id is not null and public.can_access_branch(branch_id))))
  with check (company_id = (select public.auth_company_id()));

-- Avisos a un departamento (0008): solo de una sucursal a la que se tiene acceso
-- (antes, con manage_tasks se podía avisar a cualquier sucursal o a toda la empresa).
drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and department_id is not null and employee_id is null
              and (select public.has_permission('manage_tasks'))
              and branch_id is not null and public.can_access_branch(branch_id));

-- ─── B. CUENTA DEL PROPIETARIO ──────────────────────────────────────────────
-- admin_set_password (0012/0022) no dejaba crear la cuenta de un propietario
-- pre-registrado (ej. chee). Ahora:
--   * desde el SQL Editor (modo sistema) se crea o restablece cualquier cuenta;
--   * un superadmin crea la cuenta de un propietario que aún no la tiene y
--     gestiona administradores.
-- Una vez que el propietario tiene cuenta, su contraseña solo la cambia él.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.admin_set_password(uuid, text)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');
  if position('is_platform_admin' in v_src) = 0 then
    v_src := replace(v_src,
      'if not public.has_permission(''manage_employees'') then',
      'if not public.is_system_context() and not public.has_permission(''manage_employees'') then');
    v_src := replace(v_src,
      'select * into t from public.employees where id = p_employee_id and company_id = public.auth_company_id();',
      'select * into t from public.employees where id = p_employee_id
     and (public.is_system_context() or company_id = public.auth_company_id());');
    v_src := replace(v_src,
      'if t.is_owner then raise exception',
      'if t.is_owner and not public.is_system_context() and not (t.user_id is null and public.is_platform_admin()) then raise exception');
    v_src := replace(v_src,
      'if v_scope = ''company'' and not public.auth_is_owner() then',
      'if v_scope = ''company'' and not public.auth_is_owner() and not public.is_system_context() and not public.is_platform_admin() then');
    if position('is_platform_admin' in v_src) = 0 or position('is_system_context() and not public.has_permission' in v_src) = 0 then
      raise exception 'No se pudo actualizar admin_set_password: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- ─── C. SEMILLA BASE POR EMPRESA ────────────────────────────────────────────
-- Lo que antes sembraban seed/0008…0018 (y las migraciones 0011 y 0012) para
-- cada empresa. Solo AGREGA lo que falta: no quita permisos que el propietario
-- haya cambiado ni duplica plantillas. No crea sucursales (son de cada empresa);
-- crea los puntos QR de las sucursales que ya existan.
-- Regla: si una migración agrega un permiso, lo asigna a los roles de todas
-- las empresas y lo agrega también a la matriz de aquí.
create or replace function public.seed_company_base(p_company_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_prev text;
begin
  if not exists (select 1 from public.companies where id = p_company_id) then
    raise exception 'Empresa % no existe', p_company_id;
  end if;
  v_prev := public.set_bypass('on');

  -- Departamentos
  insert into public.departments (company_id, code, name, color, description)
  select p_company_id, v.code, v.name, v.color, v.descr
  from (values
    ('ADM', 'Administración', '#0f172a', 'Oficina y administración general'),
    ('GER', 'Gerencia',       '#1e40af', 'Gerencia de sucursal'),
    ('CAJ', 'Cajas',          '#2563eb', 'Línea de cajas y atención'),
    ('ABA', 'Abarrotes',      '#16a34a', 'Piso de venta abarrotes'),
    ('REC', 'Recibo',         '#9333ea', 'Andén y recibo de mercancía'),
    ('ALM', 'Almacén',        '#78350f', 'Bodega y resguardo'),
    ('PRO', 'Protección',     '#dc2626', 'Seguridad y prevención de pérdidas'),
    ('CAD', 'Caducidades',    '#ea580c', 'Control de fechas de caducidad'),
    ('ESC', 'Escáner',        '#0891b2', 'Precios, escaneo y cenefas'),
    ('CAR', 'Carnicería',     '#b91c1c', 'Cárnicos'),
    ('PES', 'Pescadería',     '#0e7490', 'Pescados y mariscos'),
    ('JUG', 'Juguetería',     '#db2777', 'Juguetes y temporada'),
    ('TI',  'Soporte TI',     '#475569', 'Mantenimiento de la plataforma')
  ) as v(code, name, color, descr)
  on conflict (company_id, code) do nothing;

  -- Zonas
  insert into public.zones (company_id, code, name)
  select p_company_id, v.code, v.name
  from (values ('NOR', 'Norte'), ('SUR', 'Sur'), ('EST', 'Este'), ('OES', 'Oeste'), ('CEN', 'Centro')) as v(code, name)
  on conflict (company_id, code) do nothing;

  -- Roles de sistema
  insert into public.roles (company_id, code, name, scope, is_system, description)
  select p_company_id, v.code, v.name, v.scope, true, v.descr
  from (values
    ('admin',        'Administrador general', 'company',    'Control total de la empresa'),
    ('soporte',      'Soporte TI',            'company',    'Atiende la mesa de ayuda'),
    ('auditor',      'Auditor',               'company',    'Solo lectura de reportes y evidencias'),
    ('jefe_escaner', 'Jefe de Escáner',       'zone',       'Supervisa ofertas, precios, señalización y cabeceras de las tiendas de sus zonas'),
    ('gerente',      'Gerente de sucursal',   'branch',     'Supervisa toda su sucursal'),
    ('supervisor',   'Supervisor',            'department', 'Revisa departamentos asignados'),
    ('jefe_cajas',   'Jefe de cajas',         'department', 'Responsable de la línea de cajas'),
    ('cajas',        'Cajero(a)',             'self',       'Consulta de precios y checklists de caja'),
    ('abarrotes',    'Abarrotes',             'department', 'Inventario y pedidos de abarrotes'),
    ('recibo',       'Recibo',                'department', 'Proveedores y recibo de mercancía'),
    ('almacen',      'Almacén',               'department', 'Entradas, salidas y ajustes'),
    ('proteccion',   'Protección',            'department', 'Rondines y control de accesos'),
    ('caducidades',  'Caducidades',           'department', 'Control de lotes y fechas'),
    ('escaner',      'Escáner',               'department', 'Cambios de precio y cenefas')
  ) as v(code, name, scope, descr)
  on conflict (company_id, code) do nothing;

  -- Permisos por rol (matriz completa hasta 0021; el admin recibe todos).
  insert into public.role_permissions (role_id, permission_code)
  select r.id, p.code from public.roles r cross join public.permissions p
  where r.company_id = p_company_id and r.code = 'admin'
  on conflict do nothing;

  insert into public.role_permissions (role_id, permission_code)
  select r.id, perm
  from (values
    ('soporte',      array['view_dashboard','create_tickets','manage_tickets','view_reports','view_audit_logs']),
    ('auditor',      array['view_dashboard','view_inventory','view_prices','view_suppliers','view_tasks',
                           'view_reports','view_audit_logs','create_tickets']),
    ('jefe_escaner', array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                           'manage_price_changes','manage_shelf_tags','validate_shelf_tags','fill_checklists',
                           'upload_evidence','view_tasks','manage_tasks','view_reports','create_tickets',
                           'publish_announcements']),
    ('gerente',      array['view_dashboard','view_inventory','manage_inventory','view_prices','scan_products',
                           'report_price_difference','create_orders','approve_orders','view_suppliers','manage_suppliers',
                           'register_supplier_visit','receive_products','close_receiving','fill_checklists',
                           'review_checklists','manage_checklist_templates','upload_evidence','review_evidence',
                           'manage_expirations','manage_price_changes','manage_shelf_tags','validate_shelf_tags',
                           'view_tasks','manage_tasks','view_reports','view_audit_logs','manage_employees','create_tickets',
                           'register_waste','manage_checkpoints','perform_cycle_counts','manage_cycle_counts',
                           'report_shelf_gaps','manage_shelf_gaps','publish_announcements']),
    ('supervisor',   array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                           'view_suppliers','fill_checklists','review_checklists','upload_evidence','review_evidence',
                           'manage_expirations','validate_shelf_tags','view_tasks','manage_tasks','view_reports','create_tickets',
                           'perform_cycle_counts','report_shelf_gaps','manage_shelf_gaps','publish_announcements']),
    ('jefe_cajas',   array['view_dashboard','view_prices','scan_products','report_price_difference',
                           'fill_checklists','review_checklists','upload_evidence','review_evidence',
                           'view_tasks','manage_tasks','view_reports','create_tickets','report_shelf_gaps']),
    ('cajas',        array['view_dashboard','view_prices','scan_products','report_price_difference',
                           'fill_checklists','upload_evidence','view_tasks','create_tickets','report_shelf_gaps']),
    ('abarrotes',    array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                           'fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps']),
    ('recibo',       array['view_dashboard','view_inventory','view_suppliers','register_supplier_visit',
                           'receive_products','close_receiving','fill_checklists','upload_evidence','view_tasks','create_tickets']),
    ('almacen',      array['view_dashboard','view_inventory','manage_inventory','view_prices','create_orders',
                           'receive_products','fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps','manage_shelf_gaps']),
    ('proteccion',   array['view_dashboard','view_suppliers','register_supplier_visit','fill_checklists',
                           'upload_evidence','view_tasks','create_tickets']),
    ('caducidades',  array['view_dashboard','view_inventory','view_prices','scan_products','manage_expirations',
                           'create_orders','fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps']),
    ('escaner',      array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                           'manage_price_changes','manage_shelf_tags','fill_checklists','upload_evidence','view_tasks',
                           'create_tickets','report_shelf_gaps'])
  ) as m(role_code, perms)
  join public.roles r on r.company_id = p_company_id and r.code = m.role_code
  cross join lateral unnest(m.perms) as perm
  where exists (select 1 from public.permissions p where p.code = perm)
  on conflict do nothing;

  -- Mesa de ayuda: temas con autoayuda y respuestas rápidas (antes en 0011).
  insert into public.support_topics (company_id, code, name, category, default_priority, sla_hours, self_help, sort_order)
  select p_company_id, v.code, v.name, v.category, v.priority, v.sla, v.help, v.ord
  from (values
    ('no_signal_pos', 'Sin señal en caja', 'network', 'high', 4,
     E'1. Revisa que el cable de red esté conectado en la terminal y en la pared.\n2. Verifica si otras cajas tienen señal.\n3. Apaga y enciende el módem o switch del área (espera 1 minuto).\n4. Si usas WiFi, confirma que estés en la red de la tienda.', 1),
    ('slow_wifi', 'WiFi lento en piso de venta', 'network', 'medium', 24,
     E'1. Acércate al repetidor más cercano y vuelve a probar.\n2. Olvida la red y vuelve a conectarte.\n3. Cierra apps que descarguen en segundo plano.\n4. Anota en qué pasillo o zona falla.', 2),
    ('repeater_down', 'Repetidor o antena sin conexión', 'network', 'high', 8,
     E'1. Revisa que el repetidor tenga luz encendida.\n2. Desconéctalo de la corriente 10 segundos y vuelve a conectarlo.\n3. Verifica que nadie lo haya movido o desconectado.', 3),
    ('pos_no_power', 'Terminal de cobro no enciende', 'pos', 'critical', 2,
     E'1. Revisa que el cable de corriente esté bien conectado.\n2. Prueba en otro contacto o regulador.\n3. Mantén presionado el botón de encendido 10 segundos.\n4. Si hay otra caja libre, usa esa mientras tanto.', 4),
    ('ticket_printer', 'Impresora de tickets', 'printer', 'high', 8,
     E'1. Verifica que tenga papel y que el rollo esté bien colocado.\n2. Cierra bien la tapa.\n3. Apágala y enciéndela.\n4. Revisa que el cable USB esté conectado.', 5),
    ('scanner_no_read', 'Lector no lee', 'scanner', 'medium', 8,
     E'1. Limpia la ventana del lector con un paño seco.\n2. Desconecta y vuelve a conectar el cable.\n3. Prueba con otro código de barras.\n4. Mientras tanto captura el código a mano.', 6),
    ('scale_no_connect', 'Báscula no conecta', 'scanner', 'high', 8,
     E'1. Revisa que la báscula esté encendida y en cero.\n2. Revisa el cable entre la báscula y la caja.\n3. Reinicia la báscula y luego la aplicación de caja.', 7),
    ('cant_login', 'No puedo iniciar sesión', 'access', 'high', 4,
     E'1. Revisa que la empresa y tu usuario estén bien escritos (sin espacios).\n2. Revisa mayúsculas en la contraseña.\n3. Prueba en otro dispositivo.\n4. Pide a tu jefe que confirme que tu cuenta está activa.', 8),
    ('app_error', 'Error en la app', 'bug', 'medium', 24,
     E'1. Recarga la página.\n2. Cierra sesión y vuelve a entrar.\n3. Toma una foto o captura del mensaje de error.', 9),
    ('feature_request', 'Solicitud de mejora', 'feature', 'low', 120,
     E'Describe qué te gustaría mejorar y cómo te ayudaría en tu trabajo diario.', 10)
  ) as v(code, name, category, priority, sla, help, ord)
  on conflict (company_id, code) do nothing;

  insert into public.support_canned_responses (company_id, title, body)
  select p_company_id, v.title, v.body
  from (values
    ('Recibido, en revisión', 'Hola, recibimos tu reporte y ya lo estamos revisando. Te avisamos en cuanto tengamos novedades.'),
    ('Necesitamos más información', 'Para ayudarte mejor, ¿nos puedes enviar una foto del problema y decirnos desde cuándo ocurre?'),
    ('Técnico en camino', 'Un técnico va en camino a tu sucursal. Por favor mantén el equipo como está para poder revisarlo.'),
    ('Prueba reiniciar', 'Por favor apaga el equipo, espera 30 segundos y vuelve a encenderlo. Cuéntanos si el problema continúa.'),
    ('Resuelto', 'El problema quedó resuelto. Si vuelve a ocurrir, reabre este ticket y lo atendemos de inmediato.')
  ) as v(title, body)
  on conflict (company_id, title) do nothing;

  -- Plantillas: Gerencia (apertura/cierre), Cajas y Protección (antes 0012) y la ronda de carritos.
  insert into public.checklist_templates
    (company_id, department_id, title, description, shift, start_time, end_time, frequency, requires_evidence,
     schedule_anchor, start_offset_minutes, end_offset_minutes, repeat_every_minutes, repeat_until)
  select p_company_id, d.id, v.title, v.descr, v.shift, v.st::time, v.et::time, 'daily', v.ev,
         coalesce(v.anchor, 'fixed'), v.so, v.eo, v.rep, v.until::time
  from (values
    ('GER', 'Apertura · Exterior y seguridad', 'Revisión exterior y de seguridad antes de abrir', 'apertura', '06:00', '07:00', true,  'opening', -60,  0, null::int, null),
    ('GER', 'Apertura · Piso de venta',        'Piso de venta listo para recibir clientes',        'apertura', '06:30', '07:30', true,  'opening', -30, 30, null, null),
    ('GER', 'Apertura · Perecederos y frío',   'Perecederos exhibidos y equipos de frío en rango', 'apertura', '06:30', '07:30', true,  'opening', -30, 30, null, null),
    ('GER', 'Apertura · Cajas y personal',     'Personal, cajas y servicios listos',               'apertura', '06:45', '07:30', false, 'opening', -15, 30, null, null),
    ('GER', 'Cierre · Piso y perecederos',     'Resguardo de perecederos y piso en orden',         'cierre',   '21:00', '22:00', false, 'closing', -60,  0, null, null),
    ('GER', 'Cierre · Cajas y valores',        'Cortes de caja y resguardo de efectivo',           'cierre',   '21:30', '22:30', true,  'closing', -30, 30, null, null),
    ('GER', 'Cierre · Seguridad',              'Tienda cerrada y asegurada',                       'cierre',   '22:00', '23:00', true,  'closing',   0, 60, null, null),
    ('CAJ', 'Limpieza de cajas', 'Canastillas, inicio y fin de cajas, y carritos de servicio (silla de ruedas, carrito eléctrico)', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Recolección de carritos', 'Foto de la hoja firmada de recolección de carritos de 7:00 a 22:00', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Recolección de devoluciones', 'Foto de la hoja firmada por todas las áreas de 7:00 a 22:00', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('PRO', 'Revisión de tarimas y retornables', 'Existencias en recibo: tarimas azules y cafés, javas de fruta y pacas de cartón', 'cierre', '20:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Ronda de carritos y canastillas', 'Recolectar carritos del estacionamiento y acomodar canastillas en la entrada', 'especial', '08:00', '10:00', false, null, null, null, 120, '20:00')
  ) as v(dept, title, descr, shift, st, et, ev, anchor, so, eo, rep, until)
  join public.departments d on d.company_id = p_company_id and d.code = v.dept
  where not exists (select 1 from public.checklist_templates t where t.company_id = p_company_id and t.title = v.title);

  -- Preguntas (solo a plantillas que aún no tienen ninguna).
  insert into public.checklist_questions (template_id, position, text, answer_type, options, is_required, is_critical, requires_photo)
  select t.id, q.pos, q.txt, q.typ, q.opts::jsonb, q.req, q.crit, q.photo
  from public.checklist_templates t
  join (values
    ('Apertura · Exterior y seguridad', 1, 'Estacionamiento limpio e iluminado', 'yes_no', null, true, false, false),
    ('Apertura · Exterior y seguridad', 2, 'Fachada y anuncios encendidos', 'yes_no', null, true, false, false),
    ('Apertura · Exterior y seguridad', 3, 'Accesos y salidas de emergencia libres', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 4, 'Alarma desactivada correctamente', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 5, 'Cámaras de vigilancia grabando', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 6, 'Carritos y canastillas en su lugar', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 1, 'Pisos limpios y secos', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 2, 'Pasillos sin obstáculos ni tarimas', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 3, 'Anaqueles surtidos sin huecos visibles', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 4, 'Cabeceras armadas según la promoción vigente', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 5, 'Cenefas y precios de oferta colocados', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 6, 'Señalización correcta', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 7, 'Música y aire acondicionado funcionando', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 2, 'Fruta y verdura surtida y sin producto en mal estado', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 3, 'Carnes y salchichonería exhibidas correctamente', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 4, 'Panadería y tortillería listas', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 5, 'Sin producto caducado en exhibición', 'yes_no', null, true, true, false),
    ('Apertura · Cajas y personal', 1, 'Personal completo y uniformado', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 2, 'Cajas con fondo asignado', 'yes_no', null, true, true, false),
    ('Apertura · Cajas y personal', 3, 'Terminales y básculas funcionando', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 4, 'Bolsas e insumos en cajas', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 5, 'Baños limpios y surtidos', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 1, 'Perecederos retirados o resguardados', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 2, 'Merma del día registrada', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 4, 'Piso limpio', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 5, 'Producto devuelto a su lugar', 'yes_no', null, true, false, false),
    ('Cierre · Cajas y valores', 1, 'Cortes de caja realizados', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 2, 'Efectivo resguardado en caja fuerte', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 3, 'Diferencias de caja reportadas', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 4, 'Terminales cerradas', 'yes_no', null, true, false, false),
    ('Cierre · Seguridad', 1, 'Equipos no esenciales apagados', 'yes_no', null, true, false, false),
    ('Cierre · Seguridad', 2, 'Puertas y accesos cerrados', 'yes_no', null, true, true, false),
    ('Cierre · Seguridad', 3, 'Alarma activada', 'yes_no', null, true, true, false),
    ('Cierre · Seguridad', 4, 'Pendientes para el turno de mañana', 'text', null, false, false, false),
    ('Limpieza de cajas', 1, 'Inicio de cajas: banda, escáner, monitor y mostrador limpios', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 2, 'Canastillas limpias, completas y acomodadas', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 3, 'Sillas de ruedas limpias y en buen estado', 'yes_no', null, true, false, false),
    ('Limpieza de cajas', 4, 'Carritos eléctricos limpios y con batería cargada', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 5, 'Fin de cajas: área limpia, sin basura ni producto olvidado', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 6, 'Observaciones (equipo dañado, faltantes)', 'text', null, false, false, false),
    ('Recolección de carritos', 1, 'Foto de la hoja de recolección firmada (7:00 a 22:00)', 'photo', null, true, false, true),
    ('Recolección de carritos', 2, '¿Todas las horas tienen firma?', 'yes_no', null, true, false, false),
    ('Recolección de carritos', 3, 'Número de rondas realizadas', 'number', null, true, false, false),
    ('Recolección de carritos', 4, 'Observaciones', 'text', null, false, false, false),
    ('Recolección de devoluciones', 1, 'Foto de la hoja de devoluciones firmada (7:00 a 22:00)', 'photo', null, true, false, true),
    ('Recolección de devoluciones', 2, '¿Firmaron todas las áreas?', 'yes_no', null, true, false, false),
    ('Recolección de devoluciones', 3, 'Áreas que no firmaron (si aplica)', 'text', null, false, false, false),
    ('Recolección de devoluciones', 4, 'Piezas devueltas recolectadas', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 1, 'Tarimas azules en recibo (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 2, 'Tarimas cafés en recibo (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 3, 'Javas de fruta (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 4, 'Pacas de cartón sobrante (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 5, 'Estado del área de retornables', 'option', '["Ordenada","Con exceso","Obstruye el paso"]', true, false, false),
    ('Revisión de tarimas y retornables', 6, 'Foto del área de tarimas y retornables', 'photo', null, true, false, true),
    ('Revisión de tarimas y retornables', 7, 'Observaciones', 'text', null, false, false, false),
    ('Ronda de carritos y canastillas', 1, 'Carritos recolectados del estacionamiento', 'yes_no', null, true, false, false),
    ('Ronda de carritos y canastillas', 2, 'Canastillas acomodadas en la entrada', 'yes_no', null, true, false, false),
    ('Ronda de carritos y canastillas', 3, 'Carritos dañados encontrados (cantidad)', 'number', null, false, false, false),
    ('Ronda de carritos y canastillas', 4, 'Foto del área de carritos', 'photo', null, true, false, true)
  ) as q(title, pos, txt, typ, opts, req, crit, photo) on q.title = t.title
  where t.company_id = p_company_id
    and not exists (select 1 from public.checklist_questions x where x.template_id = t.id);

  -- Lecturas de temperatura con rango (0014); se agregan por texto, sin duplicar.
  insert into public.checklist_questions (template_id, position, text, answer_type, is_required, min_value, max_value, unit, equipment_name)
  select t.id, v.pos, v.txt, v.typ, true, v.mn, v.mx, v.unit, v.equipment
  from public.checklist_templates t
  join (values
    ('Apertura · Perecederos y frío', 6, 'Temperatura cámara de refrigeración', 'number', 0::numeric, 4::numeric, '°C', 'Cámara de refrigeración'),
    ('Apertura · Perecederos y frío', 7, 'Temperatura cámara de congelación',   'number', -25, -18, '°C', 'Cámara de congelación'),
    ('Apertura · Perecederos y frío', 8, 'Temperatura vitrina de lácteos',      'number', 0, 4, '°C', 'Vitrina de lácteos'),
    ('Apertura · Perecederos y frío', 9, 'Temperatura vitrina de carnes',       'number', 0, 4, '°C', 'Vitrina de carnes'),
    ('Cierre · Piso y perecederos', 6, 'Cámaras cerradas',                                'yes_no', null, null, null, null),
    ('Cierre · Piso y perecederos', 7, 'Temperatura cámara de refrigeración al cierre', 'number', 0, 4, '°C', 'Cámara de refrigeración'),
    ('Cierre · Piso y perecederos', 8, 'Temperatura cámara de congelación al cierre',   'number', -25, -18, '°C', 'Cámara de congelación')
  ) as v(title, pos, txt, typ, mn, mx, unit, equipment) on v.title = t.title
  where t.company_id = p_company_id
    and not exists (select 1 from public.checklist_questions x where x.template_id = t.id and x.text = v.txt);

  -- Preguntas sí/no de temperatura retiradas en 0014 (empresas que ya las tenían).
  update public.checklist_questions q set is_active = false
    from public.checklist_templates t
   where t.id = q.template_id and t.company_id = p_company_id and q.is_active
     and (t.title, q.text) in (('Apertura · Perecederos y frío', 'Temperaturas de cámaras y vitrinas en rango'),
                               ('Cierre · Piso y perecederos', 'Cámaras cerradas y en rango'));

  -- Puntos QR en cada sucursal; la ronda de carritos exige el del Área de carritos (0018).
  insert into public.checkpoints (company_id, branch_id, department_id, name)
  select b.company_id, b.id, d.id, v.name
  from public.branches b
  cross join (values ('Área de carritos', 'CAJ'), ('Cámara de carnes', null)) as v(name, dept)
  left join public.departments d on d.company_id = b.company_id and d.code = v.dept
  where b.company_id = p_company_id
  on conflict (branch_id, name) do nothing;

  update public.checklist_templates t
     set checkpoint_required = true,
         checkpoint_id = (select c.id from public.checkpoints c join public.branches b on b.id = c.branch_id
                          where c.company_id = t.company_id and c.name = 'Área de carritos' order by b.code limit 1)
   where t.company_id = p_company_id and t.title = 'Ronda de carritos y canastillas' and t.checkpoint_id is null
     and exists (select 1 from public.checkpoints c where c.company_id = t.company_id and c.name = 'Área de carritos');

  -- Los gerentes sin departamento pertenecen a Gerencia.
  update public.employees e set department_id = d.id
    from public.departments d, public.roles r
   where e.company_id = p_company_id and r.id = e.role_id and r.code = 'gerente' and e.department_id is null
     and d.company_id = e.company_id and d.code = 'GER';

  perform public.generate_checklist_runs(p_company_id, public.company_today(p_company_id));
  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.seed_company_base(uuid) from public, anon, authenticated;

-- Empresas que ya existen: completa lo que les falte.
select public.seed_company_base(id) from public.companies;
