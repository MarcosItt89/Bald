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

-- Los temas de soporte, respuestas rápidas y el permiso create_tickets por rol
-- se siembran por empresa con public.seed_company_base (migración 0023).
