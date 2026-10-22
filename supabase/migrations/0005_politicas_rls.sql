-- =============================================================================
-- OPERALIA · 0005 · ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
-- Objetivo: que cada usuario solo lea/escriba lo que le corresponde, aunque
-- llame a la API directamente con la llave pública.
--
-- Reglas base (definidas en Objetivos.md §15):
--   Admin / Auditor / Soporte (scope company) → toda la empresa
--   Gerente (scope branch)                    → su sucursal
--   Supervisor / Jefes (scope department)     → sus departamentos
--   Empleado (scope self)                     → su departamento; tareas propias
--
-- Patrón:
--   * SELECT  → filtra por empresa + can_access_branch / can_access_department
--   * INSERT/UPDATE/DELETE → además exige el permiso del módulo (has_permission)
--   * Las reglas de flujo (transiciones de estado) las validan los triggers 0003.
--
-- Las funciones se envuelven en (select ...) para que Postgres las evalúe una
-- sola vez por consulta (recomendación de rendimiento de Supabase).
-- El rol "anon" no tiene ninguna política: sin sesión no se ve nada.
-- =============================================================================

-- Activar RLS en todas las tablas del esquema public.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Limpia políticas previas para poder re-ejecutar este archivo.
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- ─── ORGANIZACIÓN ────────────────────────────────────────────────────────────

create policy companies_select on public.companies for select to authenticated
  using (id = (select public.auth_company_id()));
create policy companies_update on public.companies for update to authenticated
  using (id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

create policy branches_select on public.branches for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy branches_write on public.branches for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

create policy departments_select on public.departments for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy departments_write on public.departments for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

-- ─── SEGURIDAD ───────────────────────────────────────────────────────────────

create policy permissions_select on public.permissions for select to authenticated using (true);

create policy roles_select on public.roles for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy roles_write on public.roles for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_roles')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_roles')));

create policy role_permissions_select on public.role_permissions for select to authenticated
  using (exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));
create policy role_permissions_write on public.role_permissions for all to authenticated
  using ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));

-- Empleados: alcance company ve a todos; los demás a su sucursal (y a sí mismos).
create policy employees_select on public.employees for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (select public.auth_role_scope()) = 'company'
      or branch_id = (select public.auth_branch_id())
      or user_id = (select auth.uid())));
create policy employees_insert on public.employees for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees')));
create policy employees_update on public.employees for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees'))
         and ((select public.auth_role_scope()) = 'company' or branch_id = (select public.auth_branch_id())))
  with check (company_id = (select public.auth_company_id()));
-- No hay DELETE: los empleados se dan de baja con status = 'inactive' (trazabilidad).

create policy employee_permissions_select on public.employee_permissions for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
create policy employee_permissions_write on public.employee_permissions for all to authenticated
  using ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

create policy employee_departments_select on public.employee_departments for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
create policy employee_departments_write on public.employee_departments for all to authenticated
  using ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

-- ─── PRODUCTOS E INVENTARIO ──────────────────────────────────────────────────

create policy products_select on public.products for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy products_write on public.products for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')));

create policy barcodes_select on public.product_barcodes for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy barcodes_write on public.product_barcodes for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')));

create policy inventory_select on public.inventory for select to authenticated
  using (public.can_access_branch(branch_id));
-- El stock NO se edita directo: se registra un movimiento (trigger). Aquí solo
-- se permite dar de alta el renglón y ajustar mínimo/máximo/ubicación.
create policy inventory_insert on public.inventory for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_inventory')) and stock = 0);
create policy inventory_update on public.inventory for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_inventory')))
  with check (public.can_access_branch(branch_id));

create policy movements_select on public.inventory_movements for select to authenticated
  using (public.can_access_branch(branch_id));
create policy movements_insert on public.inventory_movements for insert to authenticated
  with check (public.can_access_branch(branch_id) and (
                 (select public.has_permission('manage_inventory'))
              -- Caducidades puede dar de baja (merma) lotes vencidos o retirados.
              or (movement_type = 'waste' and (select public.has_permission('manage_expirations')))));
-- Sin UPDATE/DELETE: la bitácora de movimientos es inmutable.

-- ─── PROVEEDORES Y RECIBO ────────────────────────────────────────────────────

create policy suppliers_select on public.suppliers for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy suppliers_write on public.suppliers for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_suppliers')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_suppliers')));

create policy visits_select on public.supplier_visits for select to authenticated
  using (public.can_access_branch(branch_id));
create policy visits_insert on public.supplier_visits for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('register_supplier_visit')));
create policy visits_update on public.supplier_visits for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('register_supplier_visit')))
  with check (public.can_access_branch(branch_id));

create policy receiving_select on public.receiving_orders for select to authenticated
  using (public.can_access_branch(branch_id));
create policy receiving_insert on public.receiving_orders for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('receive_products')));
create policy receiving_update on public.receiving_orders for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('receive_products')))
  with check (public.can_access_branch(branch_id));

create policy receiving_items_select on public.receiving_items for select to authenticated
  using (exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)));
create policy receiving_items_write on public.receiving_items for all to authenticated
  using ((select public.has_permission('receive_products'))
         and exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)))
  with check ((select public.has_permission('receive_products'))
         and exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)));

-- ─── PRECIOS, CENEFAS, CADUCIDADES ───────────────────────────────────────────

create policy price_changes_select on public.price_changes for select to authenticated
  using (company_id = (select public.auth_company_id()) and (branch_id is null or public.can_access_branch(branch_id)));
create policy price_changes_insert on public.price_changes for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
              and (branch_id is null and (select public.auth_role_scope()) = 'company' or public.can_access_branch(branch_id)));
create policy price_changes_update on public.price_changes for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes')) and status = 'scheduled')
  with check (company_id = (select public.auth_company_id()));

create policy shelf_tags_select on public.shelf_tags for select to authenticated
  using (public.can_access_branch(branch_id));
create policy shelf_tags_update on public.shelf_tags for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_shelf_tags')))
  with check (public.can_access_branch(branch_id));
-- Las cenefas las crea el trigger de cambios de precio (no hay INSERT directo).

create policy expirations_select on public.product_expirations for select to authenticated
  using (public.can_access_branch(branch_id));
create policy expirations_write on public.product_expirations for all to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_expirations')))
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_expirations')));

-- ─── CHECKLISTS ──────────────────────────────────────────────────────────────

create policy templates_select on public.checklist_templates for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy templates_write on public.checklist_templates for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checklist_templates')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checklist_templates')));

create policy questions_select on public.checklist_questions for select to authenticated
  using (exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())));
create policy questions_write on public.checklist_questions for all to authenticated
  using ((select public.has_permission('manage_checklist_templates'))
         and exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_checklist_templates'))
         and exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())));

create policy runs_select on public.checklist_runs for select to authenticated
  using (public.can_access_department(branch_id, department_id));
create policy runs_insert on public.checklist_runs for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_checklist_templates')));
create policy runs_update on public.checklist_runs for update to authenticated
  using (public.can_access_department(branch_id, department_id)
         and ((select public.has_permission('fill_checklists')) or (select public.has_permission('review_checklists'))))
  with check (public.can_access_department(branch_id, department_id));

create policy answers_select on public.checklist_answers for select to authenticated
  using (exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)));
create policy answers_insert on public.checklist_answers for insert to authenticated
  with check ((select public.has_permission('fill_checklists'))
         and exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)));
create policy answers_update on public.checklist_answers for update to authenticated
  using ((select public.has_permission('fill_checklists'))
         and exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)))
  with check (true);

-- ─── EVIDENCIAS ──────────────────────────────────────────────────────────────

create policy evidence_select on public.evidence_files for select to authenticated
  using (company_id = (select public.auth_company_id())
         and (branch_id is null or public.can_access_branch(branch_id) or uploaded_by = (select public.auth_employee_id())));
create policy evidence_insert on public.evidence_files for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (
                 (select public.has_permission('upload_evidence'))
              or (entity_type = 'support_ticket' and (select public.has_permission('create_tickets')))));
create policy evidence_update on public.evidence_files for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('review_evidence'))
         and (branch_id is null or public.can_access_branch(branch_id)))
  with check (company_id = (select public.auth_company_id()));
create policy evidence_delete on public.evidence_files for delete to authenticated
  using (uploaded_by = (select public.auth_employee_id()) and status = 'pending');

-- ─── PEDIDOS ─────────────────────────────────────────────────────────────────

create policy orders_select on public.orders for select to authenticated
  using (public.can_access_department(branch_id, department_id) or requested_by = (select public.auth_employee_id()));
create policy orders_insert on public.orders for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('create_orders')));
create policy orders_update on public.orders for update to authenticated
  using (public.can_access_department(branch_id, department_id)
         and (requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders'))))
  with check (public.can_access_branch(branch_id));

create policy orders_delete on public.orders for delete to authenticated
  using (requested_by = (select public.auth_employee_id()) and status = 'requested');

create policy order_items_select on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (public.can_access_department(o.branch_id, o.department_id) or o.requested_by = (select public.auth_employee_id()))));
create policy order_items_write on public.order_items for all to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders')))))
  with check (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders')))));

-- ─── TAREAS ──────────────────────────────────────────────────────────────────

create policy tasks_select on public.tasks for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         assigned_to = (select public.auth_employee_id())
      or created_by = (select public.auth_employee_id())
      or ((select public.auth_role_scope()) <> 'self' and public.can_access_department(branch_id, department_id))));
create policy tasks_insert on public.tasks for insert to authenticated
  with check (public.can_access_department(branch_id, department_id) and (select public.has_permission('manage_tasks')));
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = (select public.auth_employee_id())
      or ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id)))
  with check (company_id = (select public.auth_company_id()));
create policy tasks_delete on public.tasks for delete to authenticated
  using ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id) and status = 'pending');

-- ─── MESA DE AYUDA ───────────────────────────────────────────────────────────

create policy tickets_select on public.support_tickets for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))));
create policy tickets_insert on public.support_tickets for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('create_tickets')));
create policy tickets_update on public.support_tickets for update to authenticated
  using (company_id = (select public.auth_company_id()) and (
         created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))))
  with check (company_id = (select public.auth_company_id()));

create policy ticket_messages_select on public.support_ticket_messages for select to authenticated
  using (exists (select 1 from public.support_tickets t where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                 and (t.created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))))
         and (not is_internal or (select public.has_permission('manage_tickets'))));
create policy ticket_messages_insert on public.support_ticket_messages for insert to authenticated
  with check (exists (select 1 from public.support_tickets t where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                 and (t.created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets')))));

-- ─── NOTIFICACIONES Y AUDITORÍA ──────────────────────────────────────────────

create policy notifications_select on public.notifications for select to authenticated
  using (employee_id = (select public.auth_employee_id()));
create policy notifications_update on public.notifications for update to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));
create policy notifications_delete on public.notifications for delete to authenticated
  using (employee_id = (select public.auth_employee_id()));

create policy audit_select on public.audit_logs for select to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('view_audit_logs')));
-- audit_logs solo la escribe el trigger (SECURITY DEFINER).

-- ─── PRIVILEGIOS DE TABLA ────────────────────────────────────────────────────
-- anon no puede tocar nada; authenticated pasa por las políticas de arriba.
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
