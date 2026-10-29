-- =============================================================================
-- OPERALIA · 0026 · AISLAMIENTO ENTRE EMPRESAS: CORRECCIONES
-- -----------------------------------------------------------------------------
-- Lo que encontró supabase/pruebas/aislamiento.sql (detalle en el diario
-- 2026-10-30):
--   1. run_daily_maintenance comparaba `p_company_id <> auth_company_id()`.
--      Con la empresa suspendida (o un usuario sin empleado) auth_company_id()
--      es null, la comparación da null y dejaba correr el mantenimiento de
--      OTRA empresa. Ahora `is distinct from`; el mismo cambio, por higiene, en
--      toda función SECURITY DEFINER que compare `<> public.auth_company_id()`.
--   2. pg_cron procesaba empresas suspendidas: run_daily_maintenance y
--      send_checklist_reminders ahora se las saltan, y los jobs solo recorren
--      las activas.
--   3. effective_price, checkpoint_for_run y announcement_matches respondían
--      con ids de otra empresa (las dos primeras, incluso sin sesión). Ahora
--      solo responden sobre la empresa de quien llama (o en modo sistema).
--   4. anon podía ejecutar funciones que no necesita. Se le revoca EXECUTE en
--      todas las de public salvo request_password_reset (pantalla de login).
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. `<> auth_company_id()` → `is distinct from` ─────────────────────────
do $$
declare
  f     record;
  v_src text;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef
      and pg_get_functiondef(p.oid) like '%<> public.auth_company_id()%'
  loop
    v_src := replace(pg_get_functiondef(f.oid), chr(13), '');
    v_src := replace(v_src, '<> public.auth_company_id()', 'is distinct from public.auth_company_id()');
    execute v_src;
  end loop;
end $$;

-- ─── 2. Empresas suspendidas: el mantenimiento y los recordatorios las saltan ─
do $$
declare v_src text;
begin
  select replace(pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure), chr(13), '') into v_src;
  if position('empresa suspendida' in v_src) = 0 then
    v_src := replace(v_src,
      'select timezone into v_tz from public.companies where id = v_company;',
      'select timezone into v_tz from public.companies where id = v_company;
  if v_tz is null or not exists (select 1 from public.companies where id = v_company and status = ''active'') then
    return jsonb_build_object(''company_id'', v_company, ''skipped'', ''empresa suspendida'');
  end if;');
    if position('empresa suspendida' in v_src) = 0 then
      raise exception 'No se pudo actualizar run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;

  select replace(pg_get_functiondef('public.send_checklist_reminders(uuid, integer)'::regprocedure), chr(13), '') into v_src;
  if position('p_company_id and status = ''active''' in v_src) = 0 then
    v_src := replace(v_src,
      'select timezone into v_tz from public.companies where id = p_company_id;',
      'select timezone into v_tz from public.companies where id = p_company_id and status = ''active'';');
    if position('p_company_id and status = ''active''' in v_src) = 0 then
      raise exception 'No se pudo actualizar send_checklist_reminders: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- Los jobs de pg_cron (0012 y 0017) solo recorren las empresas activas.
do $$
begin
  perform cron.schedule('operalia-mantenimiento', '5 * * * *',
    'select public.run_daily_maintenance(id) from public.companies where status = ''active''');
  perform cron.schedule('operalia-recordatorios', '*/5 * * * *',
    'select public.send_checklist_reminders(id) from public.companies where status = ''active''');
exception when others then
  raise notice 'pg_cron no disponible (%). Las funciones ya se saltan las empresas suspendidas.', sqlerrm;
end $$;

-- ─── 3. Funciones auxiliares que recibían ids de otra empresa ──────────────
-- Precio vigente (0015): lo usan triggers de cambios de precio, como el
-- usuario que inserta o en modo sistema (aplicar cambios programados).
create or replace function public.effective_price(p_product_id uuid, p_branch_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(
    (select bp.price from public.branch_prices bp
       join public.products p on p.id = bp.product_id
      where bp.branch_id = p_branch_id and bp.product_id = p_product_id
        and (public.is_system_context() or p.company_id = public.auth_company_id())),
    (select p.price from public.products p
      where p.id = p_product_id
        and (public.is_system_context() or p.company_id = public.auth_company_id())))
$$;

-- Punto QR que corresponde a un checklist (0018).
create or replace function public.checkpoint_for_run(p_run_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select c.id
  from public.checklist_runs r
  join public.checklist_templates t on t.id = r.template_id
  join public.checkpoints model on model.id = t.checkpoint_id
  join public.checkpoints c on c.branch_id = r.branch_id and c.name = model.name and c.is_active
  where r.id = p_run_id
    and (public.is_system_context() or r.company_id = public.auth_company_id())
$$;

-- ¿Un comunicado le llega a este empleado? (0021). Solo empleados de la
-- empresa de quien pregunta.
create or replace function public.announcement_matches(
  p_employee_id uuid, p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    left join public.branches b on b.id = e.branch_id
    where e.id = p_employee_id
      and (public.is_system_context() or e.company_id = public.auth_company_id())
      and case p_scope
            when 'company' then true
            when 'zone' then b.zone_id = p_zone_id
                          or exists (select 1 from public.employee_zones ez where ez.employee_id = e.id and ez.zone_id = p_zone_id)
            when 'branch' then e.branch_id = p_branch_id
            when 'department' then (p_branch_id is null or e.branch_id = p_branch_id)
                               and (e.department_id = p_department_id
                                    or exists (select 1 from public.employee_departments ed
                                               where ed.employee_id = e.id and ed.department_id = p_department_id))
            else false
          end)
$$;

-- ─── 4. anon solo ejecuta request_password_reset ────────────────────────────
-- Supabase da EXECUTE a anon (y a PUBLIC) en cada función nueva. Se conserva
-- el acceso de authenticated donde ya lo tenía y se quita el de PUBLIC y anon.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and p.proname <> 'request_password_reset'
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    if has_function_privilege('authenticated', f.sig::oid, 'execute') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end $$;
-- Funciones futuras de postgres: sin EXECUTE automático para anon.
alter default privileges in schema public revoke execute on functions from anon;
