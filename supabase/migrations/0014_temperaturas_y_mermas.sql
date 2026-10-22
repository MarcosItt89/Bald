-- =============================================================================
-- OPERALIA · 0014 · TEMPERATURAS (PREGUNTAS CON RANGO) Y MERMAS CON MOTIVO
-- -----------------------------------------------------------------------------
-- A) Temperaturas: no es un módulo aparte, es una pregunta numérica con rango.
--    * checklist_questions: min_value, max_value, unit, equipment_name.
--    * checklist_answers.out_of_range: lo calcula un trigger. Fuera de rango
--      cuenta como «No» en la calificación y crea la tarea automática de 0013
--      con prioridad high, avisando al jefe del departamento y al gerente.
--    * Una lectura fuera de rango exige comentario y foto para completar.
-- B) Mermas:
--    * inventory_movements: waste_reason (obligatorio en 'waste') y unit_cost
--      (copia products.cost al insertar si viene vacío).
--    * Permiso register_waste (los roles se asignan en seed/0012).
--    * Retirar o marcar vencido un lote de caducidades genera su merma
--      ('expired') automáticamente.
-- La conversión de las preguntas de temperatura existentes está en
-- seed/0012_temperaturas_y_mermas.sql (corre después de las semillas).
-- Re-ejecutable.
-- =============================================================================

-- ═══ A. TEMPERATURAS ═════════════════════════════════════════════════════════
alter table public.checklist_questions add column if not exists min_value numeric;
alter table public.checklist_questions add column if not exists max_value numeric;
alter table public.checklist_questions add column if not exists unit text;
alter table public.checklist_questions add column if not exists equipment_name text;
do $$ begin
  alter table public.checklist_questions add constraint checklist_questions_range_chk
    check (min_value is null or max_value is null or min_value <= max_value);
exception when duplicate_object then null; end $$;

alter table public.checklist_answers add column if not exists out_of_range boolean;

-- Calcula out_of_range y valida que la lectura sea un número.
create or replace function public.tg_checklist_answer_range()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  q public.checklist_questions%rowtype;
  v numeric;
begin
  select * into q from public.checklist_questions where id = new.question_id;
  new.out_of_range := null;
  if q.answer_type <> 'number' or (q.min_value is null and q.max_value is null)
     or coalesce(trim(new.answer_value), '') = '' then
    return new;
  end if;
  begin
    v := replace(trim(new.answer_value), ',', '.')::numeric;
  exception when others then
    raise exception 'La lectura de «%» debe ser un número', q.text;
  end;
  new.answer_value := v::text;
  new.out_of_range := (q.min_value is not null and v < q.min_value) or (q.max_value is not null and v > q.max_value);
  return new;
end $$;
drop trigger if exists trg_checklist_answer_range on public.checklist_answers;
create trigger trg_checklist_answer_range before insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_range();

-- Tarea automática (reemplaza la de 0013): «No» en sí/no o lectura fuera de rango.
create or replace function public.tg_checklist_answer_task()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_run    public.checklist_runs%rowtype;
  v_q      public.checklist_questions%rowtype;
  v_tmpl   text;
  v_actor  uuid := public.auth_employee_id();
  v_prev   text;
  v_fail   boolean;
  v_was    boolean;
  v_range  boolean;
  v_urgent boolean;
  v_title  text;
  v_desc   text;
  r        record;
begin
  select * into v_q from public.checklist_questions where id = new.question_id;
  v_range := v_q.answer_type = 'number' and (v_q.min_value is not null or v_q.max_value is not null);
  if v_q.answer_type <> 'yes_no' and not v_range then return null; end if;

  v_fail := case when v_range then coalesce(new.out_of_range, false) else new.answer_value = 'no' end;
  v_was  := tg_op = 'UPDATE' and case when v_range then coalesce(old.out_of_range, false) else old.answer_value = 'no' end;

  -- Corrección: ya no hay falla → cancelar la tarea si nadie la ha tomado.
  if v_was and not v_fail then
    v_prev := public.set_bypass('on');
    update public.tasks set status = 'cancelled', completion_notes = 'Se corrigió la respuesta del checklist'
     where source_type = 'checklist_answer' and source_id = new.id and status = 'pending';
    perform public.set_bypass(v_prev);
    return null;
  end if;
  if not v_fail or (v_was and not v_range) then return null; end if;

  select * into v_run from public.checklist_runs where id = new.run_id;
  select title into v_tmpl from public.checklist_templates where id = v_run.template_id;
  v_urgent := v_q.is_critical or v_range;

  if v_range then
    v_title := (case when v_q.unit ilike '%°%' then 'Temperatura fuera de rango: ' else 'Lectura fuera de rango: ' end)
               || coalesce(v_q.equipment_name, v_q.text) || ' ' || new.answer_value || coalesce(v_q.unit, '');
    v_desc  := 'Lectura en «' || v_tmpl || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || '). Rango permitido: '
               || coalesce(v_q.min_value::text, '−∞') || ' a ' || coalesce(v_q.max_value::text, '∞') || coalesce(' ' || v_q.unit, '') || '.';
  else
    v_title := (case when v_q.is_critical then 'CRÍTICO: ' else '' end) || v_q.text;
    v_desc  := 'Respuesta «No» en «' || v_tmpl || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || ').';
  end if;
  v_desc := v_desc || coalesce(E'\nComentario: ' || nullif(trim(new.comment), ''), '');

  v_prev := public.set_bypass('on');
  insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, created_by, source_type, source_id)
  values (v_run.company_id, v_run.branch_id, v_run.department_id, left(v_title, 200), v_desc,
          case when v_urgent then 'high' else 'medium' end, v_run.scheduled_date, v_actor, 'checklist_answer', new.id)
  on conflict (source_type, source_id) where source_id is not null
  do update set status = 'pending', title = excluded.title, description = excluded.description,
                completion_notes = null, completed_at = null;
  perform public.set_bypass(v_prev);

  for r in
    select distinct e.id
    from public.employees e
    join public.roles ro on ro.id = e.role_id
    where e.company_id = v_run.company_id and e.status = 'active'
      and e.id is distinct from v_actor
      and (e.branch_id = v_run.branch_id or ro.scope = 'company')
      and (
        (ro.code <> 'admin'
         and exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'review_checklists')
         and (e.department_id = v_run.department_id
              or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = v_run.department_id)))
        or (v_urgent and ro.code = 'gerente' and e.branch_id = v_run.branch_id)
      )
  loop
    perform public.notify_employee(r.id, 'task',
      case when v_range then left(v_title, 120) when v_q.is_critical then 'Falla crítica en checklist' else 'Falla en checklist' end,
      v_tmpl || ': ' || v_q.text, '/tasks');
  end loop;
  return null;
end $$;

-- Completar exige comentario y foto en cada lectura fuera de rango.
create or replace function public.tg_checklist_range_completion()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_missing int;
begin
  if new.status = 'completed' and old.status <> 'completed' then
    select count(*) into v_missing
    from public.checklist_answers a
    where a.run_id = new.id and a.out_of_range
      and (coalesce(trim(a.comment), '') = ''
           or not exists (select 1 from public.evidence_files ev where ev.entity_type = 'checklist_answer' and ev.entity_id = a.id));
    if v_missing > 0 then
      raise exception 'Hay % lectura(s) fuera de rango sin comentario o sin foto', v_missing;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_range_completion on public.checklist_runs;
create trigger trg_checklist_range_completion before update on public.checklist_runs
  for each row execute function public.tg_checklist_range_completion();

-- ═══ B. MERMAS ══════════════════════════════════════════════════════════════
alter table public.inventory_movements add column if not exists waste_reason text;
alter table public.inventory_movements add column if not exists unit_cost numeric(12,2);
do $$ begin
  alter table public.inventory_movements add constraint inventory_movements_waste_reason_chk
    check (waste_reason is null or waste_reason in ('expired','damaged','theft','mishandling','temperature','other'));
exception when duplicate_object then null; end $$;
create index if not exists movements_waste_idx on public.inventory_movements (branch_id, created_at) where movement_type = 'waste';

-- Históricos: costo actual del producto y motivo deducido del texto.
update public.inventory_movements m set unit_cost = p.cost
  from public.products p where p.id = m.product_id and m.unit_cost is null;
update public.inventory_movements set waste_reason = case when reason ilike '%caduc%' then 'expired' else 'other' end
 where movement_type = 'waste' and waste_reason is null;

create or replace function public.tg_movement_cost()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.unit_cost is null then
    select cost into new.unit_cost from public.products where id = new.product_id;
  end if;
  if new.movement_type = 'waste' and new.waste_reason is null then
    raise exception 'Indica el motivo de la merma';
  end if;
  if new.movement_type <> 'waste' then new.waste_reason := null; end if;
  return new;
end $$;
drop trigger if exists trg_movement_cost on public.inventory_movements;
create trigger trg_movement_cost before insert on public.inventory_movements
  for each row execute function public.tg_movement_cost();

insert into public.permissions (code, module, name, description) values
  ('register_waste', 'Inventario', 'Registrar mermas', 'Capturar merma con motivo, cantidad y foto')
on conflict (code) do nothing;

drop policy if exists movements_insert on public.inventory_movements;
create policy movements_insert on public.inventory_movements for insert to authenticated
  with check (public.can_access_branch(branch_id) and (
                 (select public.has_permission('manage_inventory'))
              or (movement_type = 'waste' and (select public.has_permission('register_waste')))
              or (movement_type = 'waste' and (select public.has_permission('manage_expirations')))));

-- Foto de la merma.
alter table public.evidence_files drop constraint if exists evidence_files_entity_type_check;
alter table public.evidence_files add constraint evidence_files_entity_type_check check (entity_type in (
  'checklist_run','checklist_answer','task','receiving_order','price_change','shelf_tag',
  'order','expiration','support_ticket','product','supplier_visit','inventory_movement','other'));

-- Caducidades: retirar (o marcar vencido a mano) genera la merma una sola vez.
-- El vencimiento automático del mantenimiento (contexto de sistema) no la genera:
-- el producto aún está en anaquel hasta que alguien lo retira.
create or replace function public.tg_expiration_waste()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_stock numeric; v_qty numeric;
begin
  if new.status in ('withdrawn','expired') and old.status is distinct from new.status
     and not public.is_system_context() and new.quantity > 0
     and not exists (select 1 from public.inventory_movements
                     where reference_type = 'product_expiration' and reference_id = new.id) then
    select stock into v_stock from public.inventory where branch_id = new.branch_id and product_id = new.product_id;
    v_qty := least(new.quantity, coalesce(v_stock, 0));
    if v_qty > 0 then
      insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity,
                                              waste_reason, reason, reference_type, reference_id)
      values (new.company_id, new.branch_id, new.product_id, 'waste', v_qty, 'expired',
              'Merma por caducidad · lote ' || coalesce(new.lot, 's/n'), 'product_expiration', new.id);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_expiration_waste on public.product_expirations;
create trigger trg_expiration_waste after update on public.product_expirations
  for each row execute function public.tg_expiration_waste();

-- La vista expone las columnas nuevas (m.* se fija al crear la vista).
drop view if exists public.v_inventory_movements;
create view public.v_inventory_movements with (security_invoker = on) as
select m.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       e.full_name as created_by_name,
       round(m.quantity * coalesce(m.unit_cost, 0), 2) as total_cost
from public.inventory_movements m
join public.products p on p.id = m.product_id
join public.branches b on b.id = m.branch_id
left join public.employees e on e.id = m.created_by;
grant select on public.v_inventory_movements to authenticated;

-- v_tasks también fija t.*: se recrea para incluir source_type/source_id (0013).
drop view if exists public.v_tasks;
create view public.v_tasks with (security_invoker = on) as
select t.*, d.name as department_name, b.name as branch_name,
       ea.full_name as assigned_to_name, ec.full_name as created_by_name,
       (select count(*) from public.evidence_files ev where ev.entity_type = 'task' and ev.entity_id = t.id) as evidence_count,
       (t.status in ('pending','in_progress') and t.due_date < public.company_today(t.company_id)) as is_late
from public.tasks t
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees ea on ea.id = t.assigned_to
left join public.employees ec on ec.id = t.created_by;
grant select on public.v_tasks to authenticated;
