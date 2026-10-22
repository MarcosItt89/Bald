-- =============================================================================
-- OPERALIA · 0003 · TRIGGERS Y LÓGICA DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Objetivo: que las reglas críticas vivan en la base de datos y no dependan
-- del frontend (si alguien llama la API directo, las reglas se siguen
-- cumpliendo). Contenido:
--
--   A. Utilidades genéricas  (updated_at, actor, contexto de sistema, notificar)
--   B. Inventario            (status automático, aplicar movimientos)
--   C. Recibo de mercancía   (cierre → totales + inventario + caducidades)
--   D. Precios y cenefas     (cambio de precio → actualiza producto → cenefa)
--   E. Caducidades           (marcar vencidos)
--   F. Checklists            (inicio, cierre con validación, revisión, reapertura)
--   G. Evidencias            (revisión)
--   H. Pedidos internos      (flujo de estados)
--   I. Tareas                (evidencia obligatoria, solo-estado para asignados)
--   J. Mesa de ayuda         (estados, primera respuesta, notas internas)
--   K. Empleados             (anti escalamiento de privilegios, ligar cuenta Auth)
--   L. Auditoría             (audit_logs)
--   M. Mantenimiento diario  (RPC run_daily_maintenance)
-- =============================================================================

-- ═════════════════════════════════════════════════════════════════════════════
-- A. UTILIDADES GENÉRICAS
-- ═════════════════════════════════════════════════════════════════════════════

-- "Modo sistema": SQL Editor / service role (sin usuario) o una función interna
-- que activó la bandera operalia.bypass para actualizar filas en cascada.
create or replace function public.is_system_context()
returns boolean language sql stable as $$
  select auth.uid() is null or coalesce(current_setting('operalia.bypass', true), '') = 'on'
$$;

-- Activa/restaura la bandera. Devuelve el valor anterior para poder
-- restaurarlo (las funciones pueden anidarse).
create or replace function public.set_bypass(p_value text)
returns text language plpgsql as $$
declare v_prev text := coalesce(current_setting('operalia.bypass', true), '');
begin
  perform set_config('operalia.bypass', coalesce(p_value, ''), true);
  return v_prev;
end $$;
revoke all on function public.set_bypass(text) from public, anon, authenticated;

-- updated_at = now() en cada UPDATE.
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Rellena la columna indicada (TG_ARGV[0]) con el empleado que hace la
-- petición. Evita que el cliente "firme" a nombre de otro.
create or replace function public.tg_set_actor()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], public.auth_employee_id()));
  end if;
  return new;
end $$;

-- Inserta una notificación para un empleado.
create or replace function public.notify_employee(
  p_employee_id uuid, p_type text, p_title text, p_body text default null, p_link text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_employee_id is null then return; end if;
  insert into public.notifications (company_id, employee_id, type, title, body, link)
  select e.company_id, e.id, p_type, p_title, p_body, p_link
  from public.employees e where e.id = p_employee_id and e.status = 'active';
end $$;
revoke all on function public.notify_employee(uuid, text, text, text, text) from public, anon, authenticated;

-- Trigger updated_at en todas las tablas que tengan esa columna.
do $$
declare t text;
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_name = c.table_name and tb.table_schema = c.table_schema
    where c.table_schema = 'public' and c.column_name = 'updated_at' and tb.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists trg_updated_at on public.%I', t);
    execute format('create trigger trg_updated_at before update on public.%I
                    for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;

-- Columnas "firmadas" automáticamente al insertar.
do $$
declare r record;
begin
  for r in select * from (values
    ('inventory_movements','created_by'), ('supplier_visits','registered_by'),
    ('receiving_orders','received_by'),   ('price_changes','created_by'),
    ('product_expirations','registered_by'), ('evidence_files','uploaded_by'),
    ('orders','requested_by'),            ('tasks','created_by'),
    ('support_tickets','created_by'),     ('support_ticket_messages','author_id'),
    ('checklist_answers','answered_by')
  ) as v(tbl, col)
  loop
    execute format('drop trigger if exists trg_actor on public.%I', r.tbl);
    execute format('create trigger trg_actor before insert on public.%I
                    for each row execute function public.tg_set_actor(%L)', r.tbl, r.col);
  end loop;
end $$;

-- product_barcodes hereda la empresa del producto (útil al sembrar datos).
create or replace function public.tg_barcode_company()
returns trigger language plpgsql as $$
begin
  if new.company_id is null then
    select company_id into new.company_id from public.products where id = new.product_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_barcode_company on public.product_barcodes;
create trigger trg_barcode_company before insert on public.product_barcodes
  for each row execute function public.tg_barcode_company();

-- ═════════════════════════════════════════════════════════════════════════════
-- B. INVENTARIO
-- ═════════════════════════════════════════════════════════════════════════════

-- Estado del inventario según existencia vs mínimo:
--   stock <= 0           → out_of_stock (sin existencia)
--   stock <= 50% mínimo  → critical
--   stock <= mínimo      → low
--   si no                → normal   ('review' solo se asigna manualmente)
create or replace function public.tg_inventory_status()
returns trigger language plpgsql as $$
begin
  -- Respeta "pendiente de revisión" (asignado a mano) mientras no cambie el stock.
  if new.status = 'review' then
    if tg_op = 'INSERT' then return new; end if;
    if new.stock = old.stock then return new; end if;
  end if;
  new.status := case
    when new.stock <= 0                       then 'out_of_stock'
    when new.stock <= new.min_stock * 0.5     then 'critical'
    when new.stock <= new.min_stock           then 'low'
    else 'normal'
  end;
  return new;
end $$;
drop trigger if exists trg_inventory_status on public.inventory;
create trigger trg_inventory_status before insert or update on public.inventory
  for each row execute function public.tg_inventory_status();

-- Aplica un movimiento al stock. Bloquea la fila (FOR UPDATE) para evitar
-- carreras si dos personas registran al mismo tiempo. Guarda stock antes/después.
-- No permite dejar stock negativo.
create or replace function public.tg_apply_inventory_movement()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_inv public.inventory%rowtype;
  v_new numeric;
begin
  if new.company_id is null then
    select company_id into new.company_id from public.branches where id = new.branch_id;
  end if;

  select * into v_inv from public.inventory
  where branch_id = new.branch_id and product_id = new.product_id
  for update;

  if not found then
    insert into public.inventory (company_id, branch_id, product_id, stock)
    values (new.company_id, new.branch_id, new.product_id, 0)
    returning * into v_inv;
  end if;

  v_new := case new.movement_type
    when 'count' then new.quantity
    when 'in' then v_inv.stock + new.quantity
    when 'adjustment_in' then v_inv.stock + new.quantity
    when 'receiving' then v_inv.stock + new.quantity
    when 'return' then v_inv.stock + new.quantity
    when 'transfer_in' then v_inv.stock + new.quantity
    else v_inv.stock - new.quantity   -- out, adjustment_out, waste, transfer_out
  end;

  if v_new < 0 then
    raise exception 'Stock insuficiente: existencia actual %, se intentó retirar %', v_inv.stock, new.quantity
      using errcode = 'P0001';
  end if;

  new.stock_before := v_inv.stock;
  new.stock_after  := v_new;

  update public.inventory
     set stock = v_new,
         last_movement_at = now(),
         last_counted_at = case when new.movement_type = 'count' then now() else last_counted_at end
   where id = v_inv.id;

  return new;
end $$;
drop trigger if exists trg_apply_movement on public.inventory_movements;
create trigger trg_apply_movement before insert on public.inventory_movements
  for each row execute function public.tg_apply_inventory_movement();

-- ═════════════════════════════════════════════════════════════════════════════
-- C. RECIBO DE MERCANCÍA
-- ═════════════════════════════════════════════════════════════════════════════

-- Antes de actualizar el encabezado: un recibo cerrado ya no se modifica; al
-- cerrarlo se valida permiso, que tenga productos y se calculan totales.
create or replace function public.tg_receiving_before_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if old.status <> 'in_progress' and not public.is_system_context() then
    raise exception 'El recibo % ya está %, no se puede modificar', old.folio,
      case old.status when 'completed' then 'cerrado' else 'cancelado' end;
  end if;

  if new.status = 'completed' and old.status <> 'completed' then
    if not public.is_system_context() and not public.has_permission('close_receiving') then
      raise exception 'No tienes permiso para cerrar recibos';
    end if;

    select count(*),
           coalesce(sum(expected_qty),0), coalesce(sum(received_qty),0), coalesce(sum(damaged_qty),0),
           bool_or(received_qty <> expected_qty or damaged_qty > 0)
      into v_count, new.total_expected, new.total_received, new.total_damaged, new.has_differences
      from public.receiving_items where receiving_order_id = new.id;

    if v_count = 0 then
      raise exception 'No se puede cerrar un recibo sin productos';
    end if;

    new.total_items     := v_count;
    new.has_differences := coalesce(new.has_differences, false);
    new.completed_at    := now();
    new.completed_by    := coalesce(public.auth_employee_id(), new.completed_by);
  end if;
  return new;
end $$;
drop trigger if exists trg_receiving_before_update on public.receiving_orders;
create trigger trg_receiving_before_update before update on public.receiving_orders
  for each row execute function public.tg_receiving_before_update();

-- Después de cerrar: cada producto recibido (menos dañado) entra al inventario
-- y, si trae caducidad, se registra el lote en Caducidades.
create or replace function public.tg_receiving_after_complete()
returns trigger language plpgsql security definer set search_path = public as $$
declare it record;
begin
  if new.status = 'completed' and old.status <> 'completed' then
    for it in select * from public.receiving_items where receiving_order_id = new.id loop
      if it.received_qty - it.damaged_qty > 0 then
        insert into public.inventory_movements
          (company_id, branch_id, product_id, movement_type, quantity, reference_type, reference_id, reason, created_by)
        values
          (new.company_id, new.branch_id, it.product_id, 'receiving', it.received_qty - it.damaged_qty,
           'receiving_order', new.id, 'Recibo ' || new.folio, new.completed_by);
      end if;
      if it.damaged_qty > 0 then
        -- Registro informativo: lo dañado no entra a stock (cantidad 0, razón explica).
        null;
      end if;
      if it.expiration_date is not null then
        insert into public.product_expirations
          (company_id, branch_id, product_id, lot, quantity, expiration_date, source_type, source_id, registered_by)
        values
          (new.company_id, new.branch_id, it.product_id, it.lot, it.received_qty - it.damaged_qty,
           it.expiration_date, 'receiving_item', it.id, new.completed_by);
      end if;
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists trg_receiving_after_complete on public.receiving_orders;
create trigger trg_receiving_after_complete after update on public.receiving_orders
  for each row execute function public.tg_receiving_after_complete();

-- Los renglones solo se editan mientras el recibo esté abierto.
create or replace function public.tg_receiving_items_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.receiving_orders
  where id = coalesce(new.receiving_order_id, old.receiving_order_id);
  if v_status <> 'in_progress' and not public.is_system_context() then
    raise exception 'El recibo ya no está abierto; no se pueden modificar sus productos';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists trg_receiving_items_guard on public.receiving_items;
create trigger trg_receiving_items_guard before insert or update or delete on public.receiving_items
  for each row execute function public.tg_receiving_items_guard();

-- ═════════════════════════════════════════════════════════════════════════════
-- D. CAMBIOS DE PRECIO Y CENEFAS
-- ═════════════════════════════════════════════════════════════════════════════

-- Aplica un cambio: actualiza el producto, marca el cambio como aplicado y
-- genera cenefas pendientes (sustituye las que seguían pendientes).
create or replace function public.apply_price_change(p_price_change_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  pc     public.price_changes%rowtype;
  v_prev text;
begin
  select * into pc from public.price_changes where id = p_price_change_id for update;
  if not found or pc.status <> 'scheduled' then return; end if;

  v_prev := public.set_bypass('on');

  update public.products
     set previous_price = price, price = pc.new_price, price_updated_at = now()
   where id = pc.product_id;

  update public.price_changes set status = 'applied', applied_at = now() where id = pc.id;

  if pc.requires_tag then
    -- Cenefas anteriores sin colocar quedan obsoletas.
    update public.shelf_tags
       set status = 'rejected', rejection_reason = 'Reemplazada por un cambio de precio más reciente'
     where product_id = pc.product_id and status in ('pending','printed')
       and (pc.branch_id is null or branch_id = pc.branch_id);

    insert into public.shelf_tags (company_id, branch_id, product_id, price_change_id)
    select pc.company_id, b.id, pc.product_id, pc.id
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and (pc.branch_id is null or b.id = pc.branch_id);
  end if;

  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.apply_price_change(uuid) from public, anon, authenticated;

create or replace function public.tg_price_change_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select price into new.old_price from public.products where id = new.product_id;
  if new.old_price is null then raise exception 'Producto no encontrado'; end if;
  if new.new_price = new.old_price then
    raise exception 'El precio nuevo es igual al actual (%)', new.old_price;
  end if;
  new.status := 'scheduled';
  new.applied_at := null;
  return new;
end $$;
drop trigger if exists trg_price_change_before_insert on public.price_changes;
create trigger trg_price_change_before_insert before insert on public.price_changes
  for each row execute function public.tg_price_change_before_insert();

create or replace function public.tg_price_change_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.effective_date <= public.company_today(new.company_id) then
    perform public.apply_price_change(new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_price_change_after_insert on public.price_changes;
create trigger trg_price_change_after_insert after insert on public.price_changes
  for each row execute function public.tg_price_change_after_insert();

-- Flujo de la cenefa. Validar requiere permiso validate_shelf_tags.
create or replace function public.tg_shelf_tag_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.auth_employee_id();
begin
  if new.status = old.status or public.is_system_context() then return new; end if;

  if not (
       (old.status = 'pending'  and new.status in ('printed','rejected'))
    or (old.status = 'printed'  and new.status in ('placed','rejected'))
    or (old.status = 'placed'   and new.status in ('validated','rejected'))
    or (old.status = 'rejected' and new.status = 'pending')
  ) then
    raise exception 'Transición de cenefa no permitida: % → %', old.status, new.status;
  end if;

  if new.status = 'validated' and not public.has_permission('validate_shelf_tags') then
    raise exception 'No tienes permiso para validar cenefas';
  end if;

  case new.status
    when 'printed'   then new.printed_at := now();   new.printed_by := v_actor;
    when 'placed'    then new.placed_at := now();    new.placed_by := v_actor;
    when 'validated' then new.validated_at := now(); new.validated_by := v_actor;
    when 'pending'   then new.printed_at := null; new.placed_at := null; new.rejection_reason := null;
    else null;
  end case;
  return new;
end $$;
drop trigger if exists trg_shelf_tag_flow on public.shelf_tags;
create trigger trg_shelf_tag_flow before update on public.shelf_tags
  for each row execute function public.tg_shelf_tag_flow();

-- ═════════════════════════════════════════════════════════════════════════════
-- E. CADUCIDADES
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_expiration_status()
returns trigger language plpgsql as $$
begin
  if new.status = 'active' and new.expiration_date < public.company_today(new.company_id) then
    new.status := 'expired';
  end if;
  return new;
end $$;
drop trigger if exists trg_expiration_status on public.product_expirations;
create trigger trg_expiration_status before insert or update on public.product_expirations
  for each row execute function public.tg_expiration_status();

-- ═════════════════════════════════════════════════════════════════════════════
-- F. CHECKLISTS
-- ═════════════════════════════════════════════════════════════════════════════

-- Solo se responde si la ejecución está abierta.
create or replace function public.tg_checklist_answer_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.checklist_runs where id = new.run_id;
  if v_status not in ('pending','in_progress','reopened') and not public.is_system_context() then
    raise exception 'Este checklist está % y ya no acepta respuestas',
      case v_status when 'completed' then 'completado' when 'overdue' then 'vencido' else v_status end;
  end if;
  new.answered_at := now();
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.answered_by := public.auth_employee_id();
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_answer_guard on public.checklist_answers;
create trigger trg_checklist_answer_guard before insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_guard();

-- Primera respuesta → la ejecución pasa a "en progreso".
create or replace function public.tg_checklist_answer_after()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.checklist_runs
     set status = 'in_progress'
   where id = new.run_id and status in ('pending','reopened');
  return null;
end $$;
drop trigger if exists trg_checklist_answer_after on public.checklist_answers;
create trigger trg_checklist_answer_after after insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_after();

-- Reglas de la ejecución:
--   * vencido → solo se puede reabrir (con review_checklists) o cancelar
--   * completar exige todas las obligatorias respondidas y las fotos requeridas
--   * revisar exige review_checklists; "corrección requerida" reabre el checklist
create or replace function public.tg_checklist_run_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor   uuid := public.auth_employee_id();
  v_system  boolean := public.is_system_context();
  v_missing int;
begin
  -- Reapertura de vencidos
  if old.status = 'overdue' and new.status <> 'overdue' then
    if new.status not in ('reopened','cancelled') then
      raise exception 'Un checklist vencido primero debe reabrirse';
    end if;
    if not v_system and not public.has_permission('review_checklists') then
      raise exception 'No tienes permiso para reabrir checklists vencidos';
    end if;
  end if;

  -- Revisión del supervisor / gerente
  if new.review_status is distinct from old.review_status
     and new.review_status in ('approved','rejected','correction_required') then
    if old.status <> 'completed' then
      raise exception 'Solo se pueden revisar checklists completados';
    end if;
    if not v_system and not public.has_permission('review_checklists') then
      raise exception 'No tienes permiso para revisar checklists';
    end if;
    if not v_system and v_actor = old.completed_by then
      raise exception 'No puedes revisar un checklist que tú mismo completaste';
    end if;
    new.reviewed_by := coalesce(v_actor, new.reviewed_by);
    new.reviewed_at := now();
    if new.review_status = 'correction_required' then
      new.status := 'reopened';
    end if;
  elsif old.status = 'completed' and new.status <> 'completed' and not v_system then
    raise exception 'Un checklist completado solo cambia mediante revisión';
  end if;

  -- Inicio
  if new.status = 'in_progress' and old.status in ('pending','reopened') then
    new.started_at := coalesce(old.started_at, now());
    new.started_by := coalesce(old.started_by, v_actor);
  end if;

  -- Cierre con validaciones
  if new.status = 'completed' and old.status <> 'completed' then
    if old.status not in ('pending','in_progress','reopened') then
      raise exception 'No se puede completar un checklist %', old.status;
    end if;

    select count(*) into v_missing
    from public.checklist_questions q
    where q.template_id = new.template_id and q.is_required and q.is_active
      and not exists (
        select 1 from public.checklist_answers a
        where a.run_id = new.id and a.question_id = q.id and coalesce(trim(a.answer_value), '') <> '');
    if v_missing > 0 then
      raise exception 'Faltan % pregunta(s) obligatoria(s) por responder', v_missing;
    end if;

    select count(*) into v_missing
    from public.checklist_questions q
    where q.template_id = new.template_id and q.requires_photo and q.is_active
      and not exists (
        select 1 from public.checklist_answers a
        join public.evidence_files ev on ev.entity_type = 'checklist_answer' and ev.entity_id = a.id
        where a.run_id = new.id and a.question_id = q.id);
    if v_missing > 0 then
      raise exception 'Falta evidencia fotográfica en % pregunta(s)', v_missing;
    end if;

    new.completed_at   := now();
    new.completed_by   := coalesce(v_actor, new.completed_by);
    new.review_status  := 'pending_review';
    new.reviewed_by    := null;
    new.reviewed_at    := null;
  end if;

  return new;
end $$;
drop trigger if exists trg_checklist_run_rules on public.checklist_runs;
create trigger trg_checklist_run_rules before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_rules();

-- Avisar a quien completó si su checklist fue rechazado o requiere corrección.
create or replace function public.tg_checklist_run_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_title text;
begin
  if new.review_status is distinct from old.review_status
     and new.review_status in ('rejected','correction_required') then
    select title into v_title from public.checklist_templates where id = new.template_id;
    perform public.notify_employee(new.completed_by, 'checklist',
      case new.review_status when 'rejected' then 'Checklist rechazado' else 'Checklist requiere corrección' end,
      v_title || coalesce(': ' || new.review_comment, ''), '/checklists');
  end if;
  return null;
end $$;
drop trigger if exists trg_checklist_run_notify on public.checklist_runs;
create trigger trg_checklist_run_notify after update on public.checklist_runs
  for each row execute function public.tg_checklist_run_notify();

-- Genera las ejecuciones del día para cada plantilla activa × sucursal activa.
-- Idempotente (unique template+branch+date).
create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end)
  select t.company_id, t.id, b.id, t.department_id, p_date, t.start_time, t.end_time
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  where t.company_id = p_company_id and t.is_active
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict (template_id, branch_id, scheduled_date) do nothing;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;
revoke all on function public.generate_checklist_runs(uuid, date) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- G. EVIDENCIAS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_evidence_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.branch_id := coalesce(new.branch_id, public.auth_branch_id());
    new.status := 'pending';
    return new;
  end if;

  if new.status is distinct from old.status and not public.is_system_context() then
    if not public.has_permission('review_evidence') then
      raise exception 'No tienes permiso para revisar evidencias';
    end if;
    if public.auth_employee_id() = old.uploaded_by then
      raise exception 'No puedes revisar tu propia evidencia';
    end if;
    new.reviewed_by := public.auth_employee_id();
    new.reviewed_at := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_evidence_rules on public.evidence_files;
create trigger trg_evidence_rules before insert or update on public.evidence_files
  for each row execute function public.tg_evidence_rules();

create or replace function public.tg_evidence_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('rejected','correction_required') then
    perform public.notify_employee(new.uploaded_by, 'evidence',
      case new.status when 'rejected' then 'Evidencia rechazada' else 'Evidencia requiere corrección' end,
      coalesce(new.review_comment, new.file_name), '/evidence');
  end if;
  return null;
end $$;
drop trigger if exists trg_evidence_notify on public.evidence_files;
create trigger trg_evidence_notify after update on public.evidence_files
  for each row execute function public.tg_evidence_notify();

-- ═════════════════════════════════════════════════════════════════════════════
-- H. PEDIDOS INTERNOS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_order_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor     uuid := public.auth_employee_id();
  v_approver  boolean;
  v_requester boolean;
begin
  if public.is_system_context() then return new; end if;
  v_approver  := public.has_permission('approve_orders');
  v_requester := v_actor = old.requested_by;

  if new.status is distinct from old.status then
    if not (
         (old.status = 'requested' and new.status in ('in_review','approved','rejected','cancelled'))
      or (old.status = 'in_review' and new.status in ('approved','rejected'))
      or (old.status = 'approved'  and new.status in ('sent','cancelled'))
      or (old.status = 'sent'      and new.status = 'received')
      or (old.status = 'received'  and new.status = 'closed')
    ) then
      raise exception 'Transición de pedido no permitida: % → %', old.status, new.status;
    end if;

    if new.status in ('in_review','approved','rejected','sent') and not v_approver then
      raise exception 'Solo quien aprueba pedidos puede cambiarlo a %', new.status;
    end if;
    if new.status = 'cancelled' and not (v_approver or v_requester) then
      raise exception 'Solo el solicitante o un aprobador puede cancelar el pedido';
    end if;
    if new.status in ('received','closed') and not (v_approver or v_requester) then
      raise exception 'Solo el solicitante o un aprobador puede marcarlo como %', new.status;
    end if;
    if new.status in ('approved','rejected') then
      new.approved_by := v_actor;
      new.approved_at := now();
    end if;
  elsif old.status <> 'requested' and not v_approver then
    raise exception 'El pedido ya está en proceso; no se puede editar';
  end if;
  return new;
end $$;
drop trigger if exists trg_order_flow on public.orders;
create trigger trg_order_flow before update on public.orders
  for each row execute function public.tg_order_flow();

create or replace function public.tg_order_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_label text;
begin
  if new.status is distinct from old.status and new.requested_by is distinct from public.auth_employee_id() then
    v_label := case new.status
      when 'in_review' then 'en revisión' when 'approved' then 'aprobado' when 'rejected' then 'rechazado'
      when 'sent' then 'enviado' when 'received' then 'recibido' when 'closed' then 'cerrado'
      when 'cancelled' then 'cancelado' else new.status end;
    perform public.notify_employee(new.requested_by, 'order',
      'Pedido ' || new.folio || ' ' || v_label, new.title || coalesce(' — ' || new.status_comment, ''), '/orders');
  end if;
  return null;
end $$;
drop trigger if exists trg_order_notify on public.orders;
create trigger trg_order_notify after update on public.orders
  for each row execute function public.tg_order_notify();

-- Renglones editables solo mientras el pedido está "solicitado".
create or replace function public.tg_order_items_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.orders where id = coalesce(new.order_id, old.order_id);
  if not public.is_system_context() and v_status <> 'requested'
     and not (tg_op = 'UPDATE' and v_status = 'sent') then  -- en 'sent' se captura received_qty
    raise exception 'El pedido ya no admite cambios en sus productos';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists trg_order_items_guard on public.order_items;
create trigger trg_order_items_guard before insert or update or delete on public.order_items
  for each row execute function public.tg_order_items_guard();

-- ═════════════════════════════════════════════════════════════════════════════
-- I. TAREAS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_task_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_system_context() and not public.has_permission('manage_tasks') then
    -- El asignado solo puede mover el estado y dejar notas de cierre.
    if (to_jsonb(new) - array['status','completed_at','completion_notes','updated_at'])
       <> (to_jsonb(old) - array['status','completed_at','completion_notes','updated_at']) then
      raise exception 'Solo puedes cambiar el estado de tus tareas';
    end if;
    if new.status = 'cancelled' then
      raise exception 'Solo un supervisor puede cancelar tareas';
    end if;
  end if;

  if new.status = 'completed' and old.status <> 'completed' then
    if new.requires_evidence and not exists (
      select 1 from public.evidence_files where entity_type = 'task' and entity_id = new.id) then
      raise exception 'Esta tarea requiere evidencia antes de completarse';
    end if;
    new.completed_at := now();
  elsif new.status <> 'completed' then
    new.completed_at := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_task_rules on public.tasks;
create trigger trg_task_rules before update on public.tasks
  for each row execute function public.tg_task_rules();

create or replace function public.tg_task_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_to is not null
     and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to)
     and new.assigned_to is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.assigned_to, 'task', 'Nueva tarea asignada', new.title, '/tasks');
  end if;
  return null;
end $$;
drop trigger if exists trg_task_notify on public.tasks;
create trigger trg_task_notify after insert or update on public.tasks
  for each row execute function public.tg_task_notify();

-- ═════════════════════════════════════════════════════════════════════════════
-- J. MESA DE AYUDA (SOPORTE)
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_ticket_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_agent boolean;
begin
  if tg_op = 'INSERT' then
    new.branch_id := coalesce(new.branch_id, public.auth_branch_id());
    new.status := 'open';
    if not public.is_system_context() and not public.has_permission('manage_tickets') then
      new.assigned_to := null; -- solo soporte asigna
    end if;
    return new;
  end if;

  if not public.is_system_context() then
    v_agent := public.has_permission('manage_tickets');
    if not v_agent then
      -- El solicitante solo puede cerrar, reabrir o calificar su ticket.
      if (to_jsonb(new) - array['status','satisfaction','updated_at','resolved_at','closed_at'])
         <> (to_jsonb(old) - array['status','satisfaction','updated_at','resolved_at','closed_at']) then
        raise exception 'Solo el equipo de soporte puede editar el ticket';
      end if;
      if new.status is distinct from old.status and not (
           new.status = 'closed'
        or (old.status in ('resolved','closed') and new.status = 'open')) then
        raise exception 'Solo puedes cerrar o reabrir tu ticket';
      end if;
    end if;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'resolved' then new.resolved_at := now(); end if;
    if new.status = 'closed'   then new.closed_at := now(); new.resolved_at := coalesce(new.resolved_at, now()); end if;
    if new.status = 'open' and old.status in ('resolved','closed') then
      new.resolved_at := null; new.closed_at := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_ticket_before on public.support_tickets;
create trigger trg_ticket_before before insert or update on public.support_tickets
  for each row execute function public.tg_ticket_before();

create or replace function public.tg_ticket_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare agent record;
begin
  if tg_op = 'INSERT' then
    -- Avisar a todo el equipo de soporte de la empresa.
    for agent in
      select e.id from public.employees e
      join public.role_permissions rp on rp.role_id = e.role_id and rp.permission_code = 'manage_tickets'
      where e.company_id = new.company_id and e.status = 'active' and e.id is distinct from new.created_by
    loop
      perform public.notify_employee(agent.id, 'ticket', 'Nuevo ticket ' || new.folio, new.subject, '/support/' || new.id);
    end loop;
    return null;
  end if;

  if new.assigned_to is distinct from old.assigned_to and new.assigned_to is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.assigned_to, 'ticket', 'Ticket asignado ' || new.folio, new.subject, '/support/' || new.id);
  end if;
  if new.status is distinct from old.status and new.created_by is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.created_by, 'ticket',
      'Ticket ' || new.folio || ': ' || case new.status
        when 'in_progress' then 'en atención' when 'waiting_user' then 'esperando tu respuesta'
        when 'resolved' then 'resuelto' when 'closed' then 'cerrado' else 'reabierto' end,
      new.subject, '/support/' || new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_ticket_notify on public.support_tickets;
create trigger trg_ticket_notify after insert or update on public.support_tickets
  for each row execute function public.tg_ticket_notify();

-- Mensajes: nota interna solo para soporte; no se escribe en tickets cerrados.
create or replace function public.tg_ticket_message_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.support_tickets where id = new.ticket_id;
  if v_status = 'closed' and not public.is_system_context() then
    raise exception 'El ticket está cerrado; reábrelo para responder';
  end if;
  if new.is_internal and not public.is_system_context() and not public.has_permission('manage_tickets') then
    new.is_internal := false;
  end if;
  return new;
end $$;
drop trigger if exists trg_ticket_message_before on public.support_ticket_messages;
create trigger trg_ticket_message_before before insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_before();

-- Tras un mensaje: primera respuesta, cambio de estado automático y avisos.
create or replace function public.tg_ticket_message_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t      public.support_tickets%rowtype;
  v_prev text;
begin
  select * into t from public.support_tickets where id = new.ticket_id;
  if new.is_internal then return null; end if;

  v_prev := public.set_bypass('on');
  if new.author_id is distinct from t.created_by then
    -- Respondió soporte
    update public.support_tickets
       set first_response_at = coalesce(first_response_at, now()),
           status = case when status = 'open' then 'in_progress' else status end
     where id = t.id;
    perform public.notify_employee(t.created_by, 'ticket', 'Respuesta en ' || t.folio, left(new.body, 140), '/support/' || t.id);
  else
    -- Respondió el solicitante
    update public.support_tickets
       set status = case when status in ('waiting_user','resolved') then 'in_progress' else status end
     where id = t.id;
    perform public.notify_employee(t.assigned_to, 'ticket', 'El usuario respondió ' || t.folio, left(new.body, 140), '/support/' || t.id);
  end if;
  perform public.set_bypass(v_prev);
  return null;
end $$;
drop trigger if exists trg_ticket_message_after on public.support_ticket_messages;
create trigger trg_ticket_message_after after insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_after();

-- ═════════════════════════════════════════════════════════════════════════════
-- K. EMPLEADOS Y CUENTAS
-- ═════════════════════════════════════════════════════════════════════════════

-- Evita escalamiento de privilegios:
--   * nadie cambia su propio rol, estado o sucursal
--   * solo alcance 'company' asigna roles de alcance 'company'
--   * un gerente solo gestiona empleados de su sucursal
--   * la cuenta de Auth (user_id) solo la liga el sistema
create or replace function public.tg_employee_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_target_scope text;
begin
  if public.is_system_context() then return new; end if;

  if (tg_op = 'INSERT' and new.user_id is not null)
     or (tg_op = 'UPDATE' and new.user_id is distinct from old.user_id) then
    raise exception 'La cuenta de acceso se liga automáticamente; no se puede asignar manualmente';
  end if;

  select scope into v_target_scope from public.roles where id = new.role_id and company_id = new.company_id;
  if v_target_scope is null then
    raise exception 'Rol inválido para esta empresa';
  end if;
  if v_target_scope = 'company' and public.auth_role_scope() <> 'company' then
    raise exception 'Solo un administrador puede asignar roles con alcance de empresa';
  end if;

  if tg_op = 'UPDATE' and old.user_id = auth.uid() and (
       new.role_id <> old.role_id or new.status <> old.status
    or new.branch_id is distinct from old.branch_id or new.company_id <> old.company_id) then
    raise exception 'No puedes modificar tu propio rol, estado o sucursal';
  end if;

  if public.auth_role_scope() <> 'company' and new.branch_id is distinct from public.auth_branch_id() then
    raise exception 'Solo puedes gestionar empleados de tu sucursal';
  end if;
  return new;
end $$;
drop trigger if exists trg_employee_guard on public.employees;
create trigger trg_employee_guard before insert or update on public.employees
  for each row execute function public.tg_employee_guard();

-- Cuando se crea un usuario en Supabase Auth, se liga al empleado
-- pre-registrado cuyo username coincide con la parte antes de la @.
-- Si no existe un empleado pre-registrado, la cuenta queda sin acceso.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.employees
     set user_id = new.id,
         email = coalesce(email, new.email)
   where lower(username) = lower(split_part(new.email, '@', 1))
     and user_id is null
     and status = 'active';
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ═════════════════════════════════════════════════════════════════════════════
-- L. AUDITORÍA
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then
    return null; -- no registrar updates sin cambios reales
  end if;
  insert into public.audit_logs (company_id, table_name, record_id, action, old_data, new_data, performed_by)
  values (
    coalesce((v_new ->> 'company_id')::uuid, (v_old ->> 'company_id')::uuid, public.auth_company_id()),
    tg_table_name,
    coalesce(v_new ->> 'id', v_old ->> 'id'),
    tg_op, v_old, v_new, public.auth_employee_id());
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'companies','branches','departments','roles','role_permissions','employees','employee_permissions',
    'products','price_changes','shelf_tags','suppliers','receiving_orders','orders',
    'tasks','checklist_templates','checklist_runs','evidence_files','product_expirations','support_tickets']
  loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I
                    for each row execute function public.tg_audit()', t);
  end loop;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- M. MANTENIMIENTO DIARIO (lo llama el frontend al iniciar sesión)
-- ═════════════════════════════════════════════════════════════════════════════
-- Idempotente y barato. Sin pg_cron: el primer usuario del día "despierta"
-- el proceso. Si se activa pg_cron puede programarse (ver docs/guias).
create or replace function public.run_daily_maintenance(p_company_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_company uuid := coalesce(public.auth_company_id(), p_company_id);
  v_today   date;
  v_now     time;
  v_tz      text;
  v_runs    int := 0;
  v_overdue int := 0;
  v_prices  int := 0;
  v_expired int := 0;
  v_prev    text;
  pc        record;
begin
  if v_company is null then
    raise exception 'Sin empresa asociada';
  end if;
  if auth.uid() is not null and p_company_id is not null and p_company_id <> public.auth_company_id() then
    raise exception 'No autorizado';
  end if;

  select timezone into v_tz from public.companies where id = v_company;
  v_today := (now() at time zone v_tz)::date;
  v_now   := (now() at time zone v_tz)::time;

  v_prev := public.set_bypass('on');

  v_runs := public.generate_checklist_runs(v_company, v_today);

  update public.checklist_runs
     set status = 'overdue'
   where company_id = v_company
     and status in ('pending','in_progress')
     and (scheduled_date < v_today or (scheduled_date = v_today and scheduled_end < v_now));
  get diagnostics v_overdue = row_count;

  for pc in
    select id from public.price_changes
    where company_id = v_company and status = 'scheduled' and effective_date <= v_today
  loop
    perform public.apply_price_change(pc.id);
    v_prices := v_prices + 1;
  end loop;

  update public.product_expirations
     set status = 'expired'
   where company_id = v_company and status = 'active' and expiration_date < v_today;
  get diagnostics v_expired = row_count;

  perform public.set_bypass(v_prev);

  return jsonb_build_object('date', v_today, 'runs_created', v_runs, 'runs_overdue', v_overdue,
                            'prices_applied', v_prices, 'lots_expired', v_expired);
end $$;
revoke all on function public.run_daily_maintenance(uuid) from public, anon;
grant execute on function public.run_daily_maintenance(uuid) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- N. REPORTE DE DIFERENCIA DE PRECIO (RPC)
-- ═════════════════════════════════════════════════════════════════════════════
-- Caja o piso detecta que el precio del anaquel no coincide con el sistema.
-- Crea una tarea de prioridad alta para el departamento de Escáner de la
-- sucursal, firmada por quien reporta. Así el cajero (que no puede crear
-- tareas) dispara el flujo de corrección sin depender de WhatsApp.
create or replace function public.report_price_difference(
  p_product_id uuid, p_branch_id uuid default null, p_observed_price numeric default null, p_comment text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task    uuid;
  v_branch  uuid := coalesce(p_branch_id, public.auth_branch_id());
  v_product public.products%rowtype;
  v_dept    uuid;
begin
  if not public.has_permission('report_price_difference') then
    raise exception 'No tienes permiso para reportar diferencias de precio';
  end if;
  if not public.can_access_branch(v_branch) then
    raise exception 'Sucursal no permitida';
  end if;
  select * into v_product from public.products where id = p_product_id and company_id = public.auth_company_id();
  if not found then raise exception 'Producto no encontrado'; end if;

  select id into v_dept from public.departments
  where company_id = v_product.company_id and code = 'ESC' limit 1;

  insert into public.tasks (company_id, branch_id, department_id, title, description, created_by, due_date, priority)
  values (v_product.company_id, v_branch, coalesce(v_dept, v_product.department_id),
          'Diferencia de precio: ' || v_product.name,
          format('SKU %s. Precio en sistema %s%s.%s', v_product.sku, v_product.price,
                 coalesce(', precio observado ' || p_observed_price, ''), coalesce(' ' || p_comment, '')),
          public.auth_employee_id(), public.company_today(v_product.company_id), 'high')
  returning id into v_task;
  return v_task;
end $$;
revoke all on function public.report_price_difference(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.report_price_difference(uuid, uuid, numeric, text) to authenticated;
