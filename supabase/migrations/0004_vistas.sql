-- =============================================================================
-- OPERALIA · 0004 · VISTAS DE LECTURA
-- -----------------------------------------------------------------------------
-- Objetivo: entregar al frontend filas "planas" con los nombres ya resueltos
-- (producto, sucursal, empleado...) para no repetir joins en cada pantalla.
--
-- IMPORTANTE: todas usan security_invoker = on. Eso hace que la vista se
-- evalúe con los permisos del usuario que consulta, por lo que las políticas
-- RLS de las tablas base siguen aplicando (nadie ve más de lo que le toca).
--
-- Las escrituras siempre se hacen sobre las tablas base, nunca sobre vistas.
-- =============================================================================

-- Empleados con rol, sucursal y departamento.
create or replace view public.v_employees with (security_invoker = on) as
select e.id, e.user_id, e.company_id, e.branch_id, e.department_id, e.role_id,
       e.employee_code, e.username, e.full_name, e.position, e.email, e.phone,
       e.status, e.hired_at, e.created_at, e.updated_at,
       (e.user_id is not null) as has_account,
       r.code as role_code, r.name as role_name, r.scope as role_scope,
       b.name as branch_name, d.name as department_name, d.color as department_color
from public.employees e
join public.roles r on r.id = e.role_id
left join public.branches b on b.id = e.branch_id
left join public.departments d on d.id = e.department_id;

-- Catálogo de productos con códigos de barras concatenados (para búsqueda).
create or replace view public.v_products with (security_invoker = on) as
select p.*, d.name as department_name,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes
from public.products p
left join public.departments d on d.id = p.department_id;

-- Inventario por sucursal con datos del producto y si tiene cenefa pendiente.
create or replace view public.v_inventory with (security_invoker = on) as
select i.id, i.company_id, i.branch_id, i.product_id, i.stock, i.min_stock, i.max_stock,
       i.location, i.status, i.last_movement_at, i.last_counted_at, i.updated_at,
       p.sku, p.name as product_name, p.category, p.unit, p.price, p.previous_price,
       p.price_updated_at, p.department_id, p.controls_expiration, p.status as product_status,
       d.name as department_name, b.name as branch_name,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       exists (select 1 from public.shelf_tags st
               where st.product_id = p.id and st.branch_id = i.branch_id
                 and st.status in ('pending','printed','placed')) as has_pending_tag
from public.inventory i
join public.products p on p.id = i.product_id
join public.branches b on b.id = i.branch_id
left join public.departments d on d.id = p.department_id;

create or replace view public.v_inventory_movements with (security_invoker = on) as
select m.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       e.full_name as created_by_name
from public.inventory_movements m
join public.products p on p.id = m.product_id
join public.branches b on b.id = m.branch_id
left join public.employees e on e.id = m.created_by;

create or replace view public.v_supplier_visits with (security_invoker = on) as
select v.*, s.code as supplier_code, s.name as supplier_name, b.name as branch_name,
       er.full_name as registered_by_name, ec.full_name as closed_by_name,
       extract(epoch from (coalesce(v.check_out_at, now()) - v.check_in_at)) / 60 as minutes_inside
from public.supplier_visits v
join public.suppliers s on s.id = v.supplier_id
join public.branches b on b.id = v.branch_id
left join public.employees er on er.id = v.registered_by
left join public.employees ec on ec.id = v.closed_by;

create or replace view public.v_receiving_orders with (security_invoker = on) as
select r.*, s.code as supplier_code, s.name as supplier_name, b.name as branch_name,
       er.full_name as received_by_name, ec.full_name as completed_by_name,
       (select count(*) from public.receiving_items ri where ri.receiving_order_id = r.id) as items_count
from public.receiving_orders r
join public.suppliers s on s.id = r.supplier_id
join public.branches b on b.id = r.branch_id
left join public.employees er on er.id = r.received_by
left join public.employees ec on ec.id = r.completed_by;

create or replace view public.v_receiving_items with (security_invoker = on) as
select ri.*, p.sku, p.name as product_name, p.unit
from public.receiving_items ri
join public.products p on p.id = ri.product_id;

create or replace view public.v_price_changes with (security_invoker = on) as
select pc.*, p.sku, p.name as product_name, b.name as branch_name,
       e.full_name as created_by_name,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id) as tags_total,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id and st.status = 'validated') as tags_validated
from public.price_changes pc
join public.products p on p.id = pc.product_id
left join public.branches b on b.id = pc.branch_id
left join public.employees e on e.id = pc.created_by;

create or replace view public.v_shelf_tags with (security_invoker = on) as
select st.*, p.sku, p.name as product_name, p.price as current_price,
       pc.old_price, pc.new_price, pc.effective_date, b.name as branch_name,
       d.name as department_name,
       ep.full_name as printed_by_name, epl.full_name as placed_by_name, ev.full_name as validated_by_name
from public.shelf_tags st
join public.products p on p.id = st.product_id
join public.branches b on b.id = st.branch_id
left join public.departments d on d.id = p.department_id
left join public.price_changes pc on pc.id = st.price_change_id
left join public.employees ep on ep.id = st.printed_by
left join public.employees epl on epl.id = st.placed_by
left join public.employees ev on ev.id = st.validated_by;

create or replace view public.v_expirations with (security_invoker = on) as
select x.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       d.name as department_name, e.full_name as registered_by_name,
       (x.expiration_date - public.company_today(x.company_id)) as days_left
from public.product_expirations x
join public.products p on p.id = x.product_id
join public.branches b on b.id = x.branch_id
left join public.departments d on d.id = p.department_id
left join public.employees e on e.id = x.registered_by;

create or replace view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;

create or replace view public.v_evidence with (security_invoker = on) as
select ev.*, eu.full_name as uploaded_by_name, er.full_name as reviewed_by_name, b.name as branch_name
from public.evidence_files ev
left join public.employees eu on eu.id = ev.uploaded_by
left join public.employees er on er.id = ev.reviewed_by
left join public.branches b on b.id = ev.branch_id;

create or replace view public.v_orders with (security_invoker = on) as
select o.*, d.name as department_name, b.name as branch_name,
       er.full_name as requested_by_name, ea.full_name as approved_by_name,
       (select count(*) from public.order_items oi where oi.order_id = o.id) as items_count,
       (select coalesce(sum(oi.quantity), 0) from public.order_items oi where oi.order_id = o.id) as total_quantity
from public.orders o
join public.branches b on b.id = o.branch_id
left join public.departments d on d.id = o.department_id
left join public.employees er on er.id = o.requested_by
left join public.employees ea on ea.id = o.approved_by;

create or replace view public.v_order_items with (security_invoker = on) as
select oi.*, p.sku, p.name as product_name, p.unit
from public.order_items oi
join public.products p on p.id = oi.product_id;

create or replace view public.v_tasks with (security_invoker = on) as
select t.*, d.name as department_name, b.name as branch_name,
       ea.full_name as assigned_to_name, ec.full_name as created_by_name,
       (select count(*) from public.evidence_files ev where ev.entity_type = 'task' and ev.entity_id = t.id) as evidence_count,
       (t.status in ('pending','in_progress') and t.due_date < public.company_today(t.company_id)) as is_late
from public.tasks t
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees ea on ea.id = t.assigned_to
left join public.employees ec on ec.id = t.created_by;

create or replace view public.v_support_tickets with (security_invoker = on) as
select t.*, b.name as branch_name,
       ec.full_name as created_by_name, ec.position as created_by_position,
       ea.full_name as assigned_to_name,
       (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id and not m.is_internal) as messages_count,
       (select max(m.created_at) from public.support_ticket_messages m where m.ticket_id = t.id) as last_message_at
from public.support_tickets t
left join public.branches b on b.id = t.branch_id
left join public.employees ec on ec.id = t.created_by
left join public.employees ea on ea.id = t.assigned_to;

create or replace view public.v_support_ticket_messages with (security_invoker = on) as
select m.*, e.full_name as author_name, e.position as author_position
from public.support_ticket_messages m
left join public.employees e on e.id = m.author_id;

create or replace view public.v_audit_logs with (security_invoker = on) as
select a.*, e.full_name as performed_by_name
from public.audit_logs a
left join public.employees e on e.id = a.performed_by;

-- Las vistas solo son accesibles para usuarios autenticados.
do $$
declare v text;
begin
  for v in select table_name from information_schema.views where table_schema = 'public' and table_name like 'v\_%'
  loop
    execute format('revoke all on public.%I from anon', v);
    execute format('grant select on public.%I to authenticated', v);
  end loop;
end $$;
