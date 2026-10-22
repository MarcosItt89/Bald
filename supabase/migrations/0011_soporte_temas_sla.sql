-- =============================================================================
-- OPERALIA · 0011 · SOPORTE: TEMAS, SLA, RESPUESTAS PREDEFINIDAS Y VISIBILIDAD
-- -----------------------------------------------------------------------------
-- Extiende support_tickets (sin tablas paralelas):
--   * Categorías nuevas: network, pos, printer, scanner.
--   * support_topics: catálogo de temas con prioridad, SLA y autoayuda.
--   * Columnas: topic_id, location, blocks_operation, due_at, department_id.
--     due_at = created_at + sla_hours (la mitad si blocks_operation).
--   * support_canned_responses: respuestas rápidas para soporte.
--   * RLS: empleado → propios; jefes/supervisores → su departamento;
--     gerente → su sucursal; soporte/admin → todos. Notas internas solo soporte.
-- Re-ejecutable.
-- =============================================================================

alter table public.support_tickets drop constraint if exists support_tickets_category_check;
alter table public.support_tickets add constraint support_tickets_category_check
  check (category in ('bug','access','data','feature','training','hardware',
                      'network','pos','printer','scanner','other'));

create table if not exists public.support_topics (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  code              text not null,
  name              text not null,
  category          text not null default 'other'
                    check (category in ('bug','access','data','feature','training','hardware',
                                        'network','pos','printer','scanner','other')),
  default_priority  text not null default 'medium' check (default_priority in ('low','medium','high','critical')),
  sla_hours         numeric(6,2) not null default 24 check (sla_hours > 0),
  self_help         text,
  sort_order        int not null default 0,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (company_id, code)
);

alter table public.support_tickets
  add column if not exists topic_id         uuid references public.support_topics(id) on delete set null,
  add column if not exists location         text,
  add column if not exists blocks_operation boolean not null default false,
  add column if not exists due_at           timestamptz,
  add column if not exists department_id    uuid references public.departments(id) on delete set null;

create index if not exists tickets_branch_dept_idx on public.support_tickets (branch_id, department_id);
create index if not exists tickets_due_idx         on public.support_tickets (company_id, due_at) where status not in ('resolved','closed');
create index if not exists tickets_created_by_idx  on public.support_tickets (created_by);

create table if not exists public.support_canned_responses (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  title       text not null,
  body        text not null,
  is_active   boolean not null default true,
  created_by  uuid references public.employees(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, title)
);

drop trigger if exists trg_updated_at on public.support_topics;
create trigger trg_updated_at before update on public.support_topics
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_updated_at on public.support_canned_responses;
create trigger trg_updated_at before update on public.support_canned_responses
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_actor on public.support_canned_responses;
create trigger trg_actor before insert on public.support_canned_responses
  for each row execute function public.tg_set_actor('created_by');

-- ─── SLA Y DATOS DERIVADOS DEL TEMA ─────────────────────────────────────────
create or replace function public.tg_ticket_sla()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_topic public.support_topics%rowtype;
  v_hours numeric;
begin
  if new.topic_id is not null then
    select * into v_topic from public.support_topics
     where id = new.topic_id and company_id = new.company_id;
    if not found then raise exception 'El tema de soporte no existe'; end if;
  end if;

  if tg_op = 'INSERT' then
    new.department_id := coalesce(new.department_id,
      (select e.department_id from public.employees e where e.id = new.created_by),
      public.auth_department_id());
    if v_topic.id is not null then
      new.category := v_topic.category;
      if new.priority = 'medium' then new.priority := v_topic.default_priority; end if;
    end if;
    if new.blocks_operation and new.priority in ('low','medium') then
      new.priority := 'high';
    end if;
  end if;

  if tg_op = 'INSERT'
     or new.topic_id is distinct from old.topic_id
     or new.blocks_operation is distinct from old.blocks_operation
     or new.priority is distinct from old.priority then
    v_hours := coalesce(v_topic.sla_hours,
      case new.priority when 'critical' then 4 when 'high' then 8 when 'medium' then 24 else 72 end);
    if new.blocks_operation then v_hours := v_hours / 2; end if;
    new.due_at := coalesce(new.created_at, now()) + make_interval(secs => (v_hours * 3600)::double precision);
  end if;
  return new;
end $$;

drop trigger if exists trg_ticket_sla on public.support_tickets;
create trigger trg_ticket_sla before insert or update on public.support_tickets
  for each row execute function public.tg_ticket_sla();

-- ─── VISIBILIDAD ────────────────────────────────────────────────────────────
create or replace function public.can_view_ticket(p_created_by uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.auth_employee_id()
      or public.has_permission('manage_tickets')
      or (public.auth_role_scope() in ('company','branch','department')
          and public.can_access_department(p_branch_id, p_department_id))
$$;

drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets for select to authenticated
  using (company_id = (select public.auth_company_id())
         and public.can_view_ticket(created_by, branch_id, department_id));

drop policy if exists ticket_messages_select on public.support_ticket_messages;
create policy ticket_messages_select on public.support_ticket_messages for select to authenticated
  using (exists (select 1 from public.support_tickets t
                 where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                   and public.can_view_ticket(t.created_by, t.branch_id, t.department_id))
         and (not is_internal or (select public.has_permission('manage_tickets'))));

alter table public.support_topics enable row level security;
drop policy if exists support_topics_select on public.support_topics;
create policy support_topics_select on public.support_topics for select to authenticated
  using (company_id = (select public.auth_company_id())
         and (is_active or (select public.has_permission('manage_tickets'))));
drop policy if exists support_topics_write on public.support_topics;
create policy support_topics_write on public.support_topics for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')));

alter table public.support_canned_responses enable row level security;
drop policy if exists canned_responses_all on public.support_canned_responses;
create policy canned_responses_all on public.support_canned_responses for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')));

-- ─── VISTA ──────────────────────────────────────────────────────────────────
drop view if exists public.v_support_tickets;
create view public.v_support_tickets with (security_invoker = on) as
select t.*, b.name as branch_name, d.name as department_name,
       tp.name as topic_name, tp.code as topic_code,
       ec.full_name as created_by_name, ec.position as created_by_position,
       ea.full_name as assigned_to_name,
       (t.due_at is not null and t.due_at < now() and t.status not in ('resolved','closed')) as is_overdue,
       (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id and not m.is_internal) as messages_count,
       (select max(m.created_at) from public.support_ticket_messages m where m.ticket_id = t.id) as last_message_at
from public.support_tickets t
left join public.branches b      on b.id = t.branch_id
left join public.departments d   on d.id = t.department_id
left join public.support_topics tp on tp.id = t.topic_id
left join public.employees ec    on ec.id = t.created_by
left join public.employees ea    on ea.id = t.assigned_to;

grant select, insert, update, delete on public.support_topics, public.support_canned_responses to authenticated;
grant select on public.v_support_tickets to authenticated;
grant execute on function public.can_view_ticket(uuid, uuid, uuid) to authenticated;

-- ─── SEMILLA (por cada empresa existente) ───────────────────────────────────
insert into public.role_permissions (role_id, permission_code)
select r.id, 'create_tickets' from public.roles r
where exists (select 1 from public.permissions p where p.code = 'create_tickets')
on conflict do nothing;

insert into public.support_topics (company_id, code, name, category, default_priority, sla_hours, self_help, sort_order)
select c.id, v.code, v.name, v.category, v.priority, v.sla, v.help, v.ord
from public.companies c
cross join (values
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
   E'1. Revisa que tu usuario esté bien escrito (sin espacios).\n2. Revisa mayúsculas en la contraseña.\n3. Prueba en otro dispositivo.\n4. Pide a tu jefe que confirme que tu cuenta está activa.', 8),
  ('app_error', 'Error en la app', 'bug', 'medium', 24,
   E'1. Recarga la página.\n2. Cierra sesión y vuelve a entrar.\n3. Toma una foto o captura del mensaje de error.', 9),
  ('feature_request', 'Solicitud de mejora', 'feature', 'low', 120,
   E'Describe qué te gustaría mejorar y cómo te ayudaría en tu trabajo diario.', 10)
) as v(code, name, category, priority, sla, help, ord)
on conflict (company_id, code) do nothing;

insert into public.support_canned_responses (company_id, title, body)
select c.id, v.title, v.body
from public.companies c
cross join (values
  ('Recibido, en revisión', 'Hola, recibimos tu reporte y ya lo estamos revisando. Te avisamos en cuanto tengamos novedades.'),
  ('Necesitamos más información', 'Para ayudarte mejor, ¿nos puedes enviar una foto del problema y decirnos desde cuándo ocurre?'),
  ('Técnico en camino', 'Un técnico va en camino a tu sucursal. Por favor mantén el equipo como está para poder revisarlo.'),
  ('Prueba reiniciar', 'Por favor apaga el equipo, espera 30 segundos y vuelve a encenderlo. Cuéntanos si el problema continúa.'),
  ('Resuelto', 'El problema quedó resuelto. Si vuelve a ocurrir, reabre este ticket y lo atendemos de inmediato.')
) as v(title, body)
on conflict (company_id, title) do nothing;
