-- =============================================================================
-- OPERALIA · 0024 · PLATAFORMA: ALTA DE EMPRESAS Y SOPORTE ENTRE EMPRESAS
-- -----------------------------------------------------------------------------
--   A. provision_company(...): da de alta una empresa cliente completa en una
--      sola llamada (empresa, semilla base, primera sucursal, propietario con
--      su cuenta y, opcional, datos demo).
--      platform_list_companies() y platform_set_company_status().
--   B. Soporte Operalia: el superadmin atiende los tickets de todas las
--      empresas con RPCs (platform_list_tickets, platform_get_ticket,
--      platform_reply_ticket). Las políticas RLS de support_tickets NO se
--      abren a otras empresas. Sus respuestas se firman "Soporte Operalia".
-- Todas son SECURITY DEFINER y fallan si not is_platform_admin().
-- Re-ejecutable.
-- =============================================================================

-- ─── A. EMPRESAS ────────────────────────────────────────────────────────────
-- Alta de empresa. Todo ocurre en la misma transacción: si algo falla
-- (código repetido, contraseña corta…) no queda nada a medias.
-- La sucursal se crea ANTES de seed_company_base para que reciba sus puntos QR
-- y los checklists del día. La cuenta del propietario la crea
-- admin_set_password en modo sistema (correo usuario@<code>.operalia.local,
-- must_change_password = true).
create or replace function public.provision_company(
  p_name text, p_legal_name text, p_rfc text, p_code text, p_timezone text,
  p_branch_code text, p_branch_name text,
  p_owner_username text, p_owner_full_name text, p_owner_password text,
  p_with_demo boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_code     text := lower(trim(coalesce(p_code, '')));
  v_tz       text := coalesce(nullif(trim(p_timezone), ''), 'America/Tijuana');
  v_username text := lower(trim(coalesce(p_owner_username, '')));
  v_company  uuid;
  v_branch   uuid;
  v_emp      uuid;
  v_prev     text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma da de alta empresas';
  end if;

  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe el nombre de la empresa'; end if;
  if v_code !~ '^[a-z0-9][a-z0-9-]{0,28}[a-z0-9]$' then
    raise exception 'Código de empresa inválido: de 2 a 30 caracteres, solo minúsculas, números y guiones (sin guion al inicio o al final)';
  end if;
  if exists (select 1 from public.companies where code = v_code) then
    raise exception 'Ya existe una empresa con el código %', v_code;
  end if;
  if not exists (select 1 from pg_timezone_names where name = v_tz) then
    raise exception 'Zona horaria desconocida: %', v_tz;
  end if;
  if coalesce(trim(p_branch_code), '') = '' or coalesce(trim(p_branch_name), '') = '' then
    raise exception 'Escribe la clave y el nombre de la primera sucursal';
  end if;
  if v_username !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then
    raise exception 'Usuario del propietario inválido: de 3 a 40 caracteres, minúsculas, números, punto, guion o guion bajo';
  end if;
  if coalesce(trim(p_owner_full_name), '') = '' then raise exception 'Escribe el nombre del propietario'; end if;
  if coalesce(length(p_owner_password), 0) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  if p_with_demo and to_regprocedure('public.seed_company_demo(uuid)') is null then
    raise exception 'Los datos demo no están instalados en esta base (demo/0009)';
  end if;

  v_prev := public.set_bypass('on');

  insert into public.companies (name, legal_name, rfc, timezone, code, status)
  values (trim(p_name), nullif(trim(p_legal_name), ''), nullif(upper(trim(p_rfc)), ''), v_tz, v_code, 'active')
  returning id into v_company;

  insert into public.branches (company_id, code, name)
  values (v_company, trim(p_branch_code), trim(p_branch_name))
  returning id into v_branch;

  perform public.seed_company_base(v_company);

  insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                username, full_name, position, is_owner)
  values (v_company, v_branch,
          (select id from public.departments where company_id = v_company and code = 'ADM'),
          (select id from public.roles where company_id = v_company and code = 'admin'),
          'EMP-0001', v_username, trim(p_owner_full_name), 'Propietario', true)
  returning id into v_emp;

  perform public.admin_set_password(v_emp, p_owner_password);

  if p_with_demo then
    execute 'select public.seed_company_demo($1)' using v_company;
  end if;

  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, new_data)
  values (v_company, 'companies', v_company::text, 'INSERT', public.auth_employee_id(),
          jsonb_build_object('evento', 'empresa_provisionada', 'code', v_code,
                             'sucursal', trim(p_branch_code), 'propietario', v_username,
                             'con_demo', p_with_demo, 'por', auth.uid()));

  perform public.set_bypass(v_prev);
  return jsonb_build_object('id', v_company, 'code', v_code, 'branch_id', v_branch,
                            'owner_employee_id', v_emp, 'owner_username', v_username);
end $$;
revoke all on function public.provision_company(text, text, text, text, text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.provision_company(text, text, text, text, text, text, text, text, text, text, boolean) to authenticated;

-- Resumen por empresa para la pantalla Plataforma → Empresas.
create or replace function public.platform_list_companies()
returns table (
  id uuid, name text, legal_name text, rfc text, code text, status text, plan text, timezone text,
  branches integer, active_employees integer, owner_name text, owner_username text,
  last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve las empresas';
  end if;
  return query
  select c.id, c.name, c.legal_name, c.rfc, c.code, c.status, c.plan, c.timezone,
         (select count(*)::int from public.branches b where b.company_id = c.id and b.status = 'active'),
         (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active'),
         o.full_name, o.username,
         (select max(u.last_sign_in_at) from public.employees e join auth.users u on u.id = e.user_id
           where e.company_id = c.id),
         c.created_at
  from public.companies c
  left join public.employees o on o.company_id = c.id and o.is_owner
  order by c.created_at;
end $$;
revoke all on function public.platform_list_companies() from public, anon;
grant execute on function public.platform_list_companies() to authenticated;

-- Suspender / reactivar. Suspendida: sus empleados pierden el acceso (0022)
-- sin borrar datos. No se suspende la empresa de un superadmin (se quedaría
-- fuera de la plataforma).
create or replace function public.platform_set_company_status(p_company_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c      public.companies%rowtype;
  v_prev text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma cambia el estado de una empresa';
  end if;
  if p_status not in ('active', 'suspended') then raise exception 'Estado inválido: %', p_status; end if;
  select * into c from public.companies where id = p_company_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
  if p_status = 'suspended' and exists (
       select 1 from public.employees e join public.platform_admins pa on pa.user_id = e.user_id
        where e.company_id = c.id) then
    raise exception 'No se puede suspender la empresa de un superadmin de la plataforma';
  end if;
  if c.status = p_status then
    return jsonb_build_object('id', c.id, 'code', c.code, 'status', c.status);
  end if;

  v_prev := public.set_bypass('on');
  update public.companies set status = p_status where id = c.id;
  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, old_data, new_data)
  values (c.id, 'companies', c.id::text, 'UPDATE', public.auth_employee_id(),
          jsonb_build_object('status', c.status),
          jsonb_build_object('evento', case when p_status = 'suspended' then 'empresa_suspendida' else 'empresa_reactivada' end,
                             'status', p_status, 'por', auth.uid()));
  perform public.set_bypass(v_prev);
  return jsonb_build_object('id', c.id, 'code', c.code, 'status', p_status);
end $$;
revoke all on function public.platform_set_company_status(uuid, text) from public, anon;
grant execute on function public.platform_set_company_status(uuid, text) to authenticated;

-- ─── B. SOPORTE OPERALIA ────────────────────────────────────────────────────
-- Mensaje de la plataforma: sin autor (author_id null) y firmado
-- "Soporte Operalia" en la vista. Solo se escribe en modo sistema
-- (platform_reply_ticket); desde la API nadie puede marcarlo.
alter table public.support_ticket_messages add column if not exists is_platform boolean not null default false;

-- 0003 + is_platform. Corre después de trg_actor (orden alfabético), así que
-- anula el autor que trg_actor puso.
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
  if new.is_platform then
    if not public.is_system_context() then
      raise exception 'Solo Soporte Operalia responde como plataforma';
    end if;
    new.author_id := null;
    new.is_internal := false;
  end if;
  return new;
end $$;

drop view if exists public.v_support_ticket_messages;
create view public.v_support_ticket_messages with (security_invoker = on) as
select m.*,
       case when m.is_platform then 'Soporte Operalia' else e.full_name end as author_name,
       case when m.is_platform then 'Plataforma' else e.position end as author_position
from public.support_ticket_messages m
left join public.employees e on e.id = m.author_id;
grant select on public.v_support_ticket_messages to authenticated;

-- Empleados (en su propia empresa) que son superadmin: a ellos llegan los avisos.
create or replace function public.platform_admin_employees()
returns setof uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e
  join public.platform_admins pa on pa.user_id = e.user_id
  where e.status = 'active'
$$;
revoke all on function public.platform_admin_employees() from public, anon, authenticated;

-- Ticket nuevo de otra empresa → aviso al superadmin (los de su propia
-- empresa ya le llegan por tg_ticket_notify).
create or replace function public.tg_ticket_platform_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid;
  v_co  text;
begin
  select name into v_co from public.companies where id = new.company_id;
  for v_emp in
    select x from public.platform_admin_employees() x
    where (select company_id from public.employees where id = x) <> new.company_id
  loop
    perform public.notify_employee(v_emp, 'ticket', 'Nuevo ticket ' || new.folio || ' · ' || v_co,
                                   new.subject, '/plataforma/soporte/' || new.id);
  end loop;
  return null;
end $$;
drop trigger if exists trg_ticket_platform_notify on public.support_tickets;
create trigger trg_ticket_platform_notify after insert on public.support_tickets
  for each row execute function public.tg_ticket_platform_notify();

-- El solicitante respondió en un ticket que atiende Soporte Operalia → aviso.
create or replace function public.tg_ticket_message_platform_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t     public.support_tickets%rowtype;
  v_emp uuid;
begin
  if new.is_platform or new.is_internal then return null; end if;
  select * into t from public.support_tickets where id = new.ticket_id;
  if new.author_id is distinct from t.created_by
     or not exists (select 1 from public.support_ticket_messages m where m.ticket_id = t.id and m.is_platform) then
    return null;
  end if;
  for v_emp in select x from public.platform_admin_employees() x loop
    perform public.notify_employee(v_emp, 'ticket', 'El usuario respondió ' || t.folio,
                                   left(new.body, 140), '/plataforma/soporte/' || t.id);
  end loop;
  return null;
end $$;
drop trigger if exists trg_ticket_message_platform_notify on public.support_ticket_messages;
create trigger trg_ticket_message_platform_notify after insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_platform_notify();

-- Bandeja de todas las empresas. p_status: un estado, 'active' (abiertos),
-- 'done' (resueltos y cerrados) u 'overdue' (vencidos).
create or replace function public.platform_list_tickets(
  p_company_id uuid default null, p_status text default null,
  p_search text default null, p_limit integer default 200)
returns table (
  id uuid, folio text, company_id uuid, company_name text, company_code text,
  branch_name text, department_name text, subject text, category text, topic_name text,
  priority text, status text, blocks_operation boolean, created_by_name text, assigned_to_name text,
  due_at timestamptz, is_overdue boolean, first_response_at timestamptz,
  messages_count bigint, last_message_at timestamptz, platform_replied boolean,
  created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_term text := '%' || nullif(trim(coalesce(p_search, '')), '') || '%';
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia ve los tickets de todas las empresas';
  end if;
  return query
  select v.id, v.folio, v.company_id, c.name, c.code,
         v.branch_name, v.department_name, v.subject, v.category, v.topic_name,
         v.priority, v.status, v.blocks_operation, v.created_by_name, v.assigned_to_name,
         v.due_at, v.is_overdue, v.first_response_at,
         v.messages_count, v.last_message_at,
         exists (select 1 from public.support_ticket_messages m where m.ticket_id = v.id and m.is_platform),
         v.created_at, v.updated_at
  from public.v_support_tickets v
  join public.companies c on c.id = v.company_id
  where (p_company_id is null or v.company_id = p_company_id)
    and (p_status is null
      or (p_status = 'active'  and v.status in ('open', 'in_progress', 'waiting_user'))
      or (p_status = 'done'    and v.status in ('resolved', 'closed'))
      or (p_status = 'overdue' and v.is_overdue)
      or v.status = p_status)
    and (v_term is null or v.folio ilike v_term or v.subject ilike v_term or v.description ilike v_term)
  order by v.updated_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 500));
end $$;
revoke all on function public.platform_list_tickets(uuid, text, text, integer) from public, anon;
grant execute on function public.platform_list_tickets(uuid, text, text, integer) to authenticated;

-- Ticket con su empresa y la conversación completa (incluye notas internas
-- del equipo de soporte de la tienda, marcadas).
create or replace function public.platform_get_ticket(p_ticket_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ticket jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia ve los tickets de todas las empresas';
  end if;
  select to_jsonb(v) || jsonb_build_object('company_name', c.name, 'company_code', c.code, 'company_status', c.status)
    into v_ticket
  from public.v_support_tickets v join public.companies c on c.id = v.company_id
  where v.id = p_ticket_id;
  if v_ticket is null then raise exception 'Ticket no encontrado'; end if;

  return jsonb_build_object(
    'ticket', v_ticket,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'body', m.body, 'created_at', m.created_at,
               'is_internal', m.is_internal, 'is_platform', m.is_platform,
               'author_name', m.author_name, 'author_position', m.author_position)
             order by m.created_at)
      from public.v_support_ticket_messages m where m.ticket_id = p_ticket_id), '[]'::jsonb));
end $$;
revoke all on function public.platform_get_ticket(uuid) from public, anon;
grant execute on function public.platform_get_ticket(uuid) to authenticated;

-- Responde como "Soporte Operalia" y, opcionalmente, cambia el estado. Los
-- triggers de 0003 marcan la primera respuesta, pasan el ticket a "en
-- atención" y avisan a quien lo levantó.
create or replace function public.platform_reply_ticket(p_ticket_id uuid, p_body text, p_status text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t      public.support_tickets%rowtype;
  v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_msg  uuid;
  v_prev text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia responde tickets de otras empresas';
  end if;
  select * into t from public.support_tickets where id = p_ticket_id;
  if not found then raise exception 'Ticket no encontrado'; end if;
  if v_body is null and p_status is null then raise exception 'Escribe una respuesta'; end if;
  if p_status is not null and p_status not in ('open', 'in_progress', 'waiting_user', 'resolved', 'closed') then
    raise exception 'Estado inválido: %', p_status;
  end if;
  if t.status = 'closed' and v_body is not null and coalesce(p_status, 'closed') = 'closed' then
    raise exception 'El ticket está cerrado; reábrelo para responder';
  end if;

  -- Primero el estado (así reabre antes de responder y el aviso de "en
  -- atención" automático no se suma al del estado elegido).
  v_prev := public.set_bypass('on');
  if p_status is not null then
    update public.support_tickets set status = p_status where id = t.id and status is distinct from p_status;
  end if;
  if v_body is not null then
    insert into public.support_ticket_messages (ticket_id, body, is_platform)
    values (t.id, v_body, true)
    returning id into v_msg;
  end if;
  perform public.set_bypass(v_prev);

  return jsonb_build_object('message_id', v_msg,
                            'status', (select status from public.support_tickets where id = t.id));
end $$;
revoke all on function public.platform_reply_ticket(uuid, text, text) from public, anon;
grant execute on function public.platform_reply_ticket(uuid, text, text) to authenticated;
