-- =============================================================================
-- OPERALIA · 0032 · SEGURIDAD Y BITÁCORA DE PLATAFORMA
-- -----------------------------------------------------------------------------
--   1. request_password_reset (anon, pantalla de login): además del límite por
--      empleado (una solicitud cada 15 min), máximo 20 solicitudes distintas
--      por EMPRESA por hora. Pasado el tope responde igual (no avisa a nadie y
--      no revela nada): evita que alguien llene de notificaciones a los
--      encargados probando usuarios.
--   2. platform_audit_log(): la Bitácora de la Consola. Eventos de plataforma
--      de todas las empresas: alta, suspensión, reactivación, cambios de marca
--      hechos por un superadmin y respuestas de «Soporte Operalia». Valida
--      is_platform_admin().
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. Tope por empresa en la recuperación de contraseña ───────────────────
create index if not exists notifications_password_reset_idx
  on public.notifications (company_id, created_at desc) where link like '/employees?reset=%';

create or replace function public.request_password_reset(p_company_code text, p_username text)
returns void language plpgsql security definer set search_path = public as $$
declare
  c_max_hour constant int := 20;   -- solicitudes distintas por empresa por hora
  t      public.employees%rowtype;
  ag     record;
  v_link text;
begin
  select e.* into t from public.employees e
  join public.companies c on c.id = e.company_id
  where c.code = lower(trim(coalesce(p_company_code, ''))) and c.status = 'active'
    and lower(e.username) = lower(split_part(trim(coalesce(p_username, '')), '@', 1))
    and e.status = 'active'
  limit 1;
  if not found then return; end if;

  v_link := '/employees?reset=' || t.id;
  -- Por empleado: una solicitud cada 15 minutos.
  if exists (select 1 from public.notifications
             where link = v_link and created_at > now() - interval '15 minutes') then
    return;
  end if;
  -- Por empresa: tope de solicitudes en la última hora.
  if (select count(distinct n.link) from public.notifications n
       where n.company_id = t.company_id and n.link like '/employees?reset=%'
         and n.created_at > now() - interval '1 hour') >= c_max_hour then
    return;
  end if;

  for ag in
    select distinct e.id from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = t.company_id and e.status = 'active' and e.id <> t.id
      and (e.is_owner
        or (r.code = 'admin' and not t.is_owner)
        or (exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'manage_employees')
            and r.scope = 'branch' and e.branch_id = t.branch_id
            and (select r2.scope from public.roles r2 where r2.id = t.role_id) not in ('company')))
  loop
    perform public.notify_employee(ag.id, 'password', 'Solicitud de contraseña: ' || t.full_name,
      '@' || t.username || ' olvidó su contraseña. Asígnale una temporal.', v_link);
  end loop;
end $$;
revoke all on function public.request_password_reset(text, text) from public;
grant execute on function public.request_password_reset(text, text) to anon, authenticated;

-- ─── 2. Bitácora de plataforma ──────────────────────────────────────────────
-- event: alta | suspension | reactivacion | marca | soporte
create or replace function public.platform_audit_log(
  p_limit int default 300, p_company_id uuid default null, p_event text default null)
returns table (at timestamptz, event text, company_id uuid, company_name text, company_code text,
               actor_name text, detail text, ref_id text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve la bitácora';
  end if;
  return query
  select x.at, x.event, x.company_id, c.name, c.code, x.actor_name, x.detail, x.ref_id
  from (
    -- Alta, suspensión y reactivación (provision_company y platform_set_company_status, 0024).
    select a.performed_at as at,
           case a.new_data->>'evento' when 'empresa_provisionada' then 'alta'
                                      when 'empresa_suspendida' then 'suspension'
                                      else 'reactivacion' end as event,
           a.company_id,
           e.full_name as actor_name,
           case when a.new_data->>'evento' = 'empresa_provisionada'
                then concat_ws(' · ', 'Código ' || (a.new_data->>'code'), 'sucursal ' || (a.new_data->>'sucursal'),
                               'propietario @' || (a.new_data->>'propietario'),
                               case when (a.new_data->>'con_demo')::boolean then 'con datos demo' end)
                else null end as detail,
           a.id::text as ref_id
    from public.audit_logs a
    left join public.employees e on e.id = a.performed_by
    where a.new_data->>'evento' in ('empresa_provisionada', 'empresa_suspendida', 'empresa_reactivada')
    union all
    -- Cambios de marca que hizo un superadmin (set_company_branding, 0028).
    select a.performed_at, 'marca', a.company_id, e.full_name,
           concat_ws(' · ', 'Color ' || (a.new_data->>'brand_color'), 'nombre «' || (a.new_data->>'display_name') || '»',
                     case when a.new_data->>'logo_url' is not null then 'con logo' else 'sin logo' end),
           a.id::text
    from public.audit_logs a
    left join public.employees e on e.id = a.performed_by
    where a.new_data->>'evento' = 'marca_actualizada'
      and exists (select 1 from public.platform_admins pa where pa.user_id::text = a.new_data->>'por')
    union all
    -- Respuestas de «Soporte Operalia» (platform_reply_ticket, 0024).
    select m.created_at, 'soporte', t.company_id, coalesce(e.full_name, 'Soporte Operalia'),
           t.folio || ' · ' || left(regexp_replace(m.body, '\s+', ' ', 'g'), 160),
           t.id::text
    from public.support_ticket_messages m
    join public.support_tickets t on t.id = m.ticket_id
    left join public.employees e on e.id = m.author_id
    where m.is_platform
  ) x
  left join public.companies c on c.id = x.company_id
  where (p_company_id is null or x.company_id = p_company_id)
    and (p_event is null or x.event = p_event)
  order by x.at desc
  limit least(greatest(coalesce(p_limit, 300), 1), 1000);
end $$;
revoke all on function public.platform_audit_log(int, uuid, text) from public, anon;
grant execute on function public.platform_audit_log(int, uuid, text) to authenticated;
