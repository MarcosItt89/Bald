-- =============================================================================
-- OPERALIA · PRUEBA DE AISLAMIENTO ENTRE EMPRESAS  (SOLO AMBIENTE DE PRUEBAS)
-- -----------------------------------------------------------------------------
-- Requiere los datos demo (pendiente.sql): Gato Pelón y Súper La Luna con sus
-- usuarios. Ejecútalo COMPLETO en el SQL Editor; el resultado es la tabla final.
--
-- Qué hace (como usuarios de Súper La Luna, con request.jwt.claims y
-- `set local role authenticated`, igual que la API):
--   1. En CADA tabla y vista de public y en storage.objects (bucket evidence)
--      intenta leer, insertar, actualizar y borrar datos de Gato Pelón. Todo
--      debe dar 0 filas o error. Personas: un empleado de sucursal, uno de
--      alcance 'self', el propietario y anon (sin sesión).
--   2. RPC platform_* y provision_company: nadie que no sea superadmin.
--      run_daily_maintenance de otra empresa: error.
--   3. Un admin que NO es propietario no cambia role_permissions,
--      employee_permissions ni roles (el propietario sí: control positivo).
--   4. Empresa suspendida: no lee nada (y no puede correr el mantenimiento de otra).
--   5. request_password_reset responde igual exista o no el usuario, y no
--      toca otra empresa.
--   6. pg_cron (run_daily_maintenance y send_checklist_reminders) se salta
--      las empresas suspendidas.
--   7. Lista las funciones SECURITY DEFINER que la API puede llamar y si
--      están revisadas (validan empresa, usuario o superadmin).
--
-- NO DEJA CAMBIOS: todo corre dentro de un bloque que se deshace al final
-- (los intentos que sí escriben se revierten uno por uno).
-- Columnas: ✅ bloqueado por la seguridad (o permitido cuando es control),
-- ❌ falla, ⚠️ no concluyente (lo frenó una regla del negocio o una fila
-- propia antes de llegar a la seguridad; lee el mensaje), — sin datos de
-- Gato Pelón para probar, ℹ️ catálogo global.
-- =============================================================================

create temp table if not exists _aisl_gp (tabla text, id uuid);
create temp table if not exists _aisl_res (
  orden int, grupo text, objeto text, accion text, persona text,
  esperado text, filas int, mensaje text, resultado text);
truncate _aisl_gp;
truncate _aisl_res;
grant select on _aisl_gp to anon, authenticated;

do $aisl$
declare
  v_gp        uuid;
  v_luna      uuid;
  v_personas  jsonb;
  v_res       jsonb := '[]';
  v_probes    jsonb := '[]';
  v_orden     int := 0;
  rel         record;
  pr          jsonb;
  pe          jsonb;
  f           record;
  v_pred      text;
  v_parent    text;
  v_fkcol     text;
  v_sample    jsonb;
  v_cols      text;
  v_col       text;
  v_args      text;
  v_label     text;
  v_esperado  text;
  v_n         int;
  v_msg       text;
  v_ok        text;
  v_uid       uuid;
  -- fixtures
  v_admin_uid uuid := gen_random_uuid();
  v_role_caj  uuid;
  v_perm_new  text;
  v_perm_old  text;
  v_emp_self  uuid;
  v_tz        text;
  v_now       time;
  v_run_luna  uuid;
  v_run_gp    uuid;
  v_old_luna  uuid;
  v_old_gp    uuid;
  v_prev      text;
  v_cnt_gp    int;
  v_cnt_luna  int;
  v_errs      text[];
  v_todos     jsonb;
  -- Errores que vienen de la seguridad (RLS, privilegios, vistas no escribibles, validaciones de las RPC).
  v_seguridad text := 'row-level security|permission denied|cannot (insert into|update|delete from) view|no tienes permiso|no autorizado|superadmin|Soporte Operalia';
  v_user_self text;
  v_user_gp   text;
  v_user_own  text;
begin
  select id into v_gp from public.companies where code = 'gatopelon';
  select id into v_luna from public.companies where code = 'superluna';
  if v_gp is null or v_luna is null then
    raise exception 'Faltan las empresas demo gatopelon y superluna: instala pendiente.sql (con demo/)';
  end if;

  v_personas := jsonb_build_array(
    jsonb_build_object('key', 'sucursal', 'uid', (
      select e.user_id from public.employees e join public.roles r on r.id = e.role_id
      where e.company_id = v_luna and r.scope = 'branch' and e.user_id is not null and e.status = 'active' and not e.is_owner
      order by e.username limit 1)),
    jsonb_build_object('key', 'self', 'uid', (
      select e.user_id from public.employees e join public.roles r on r.id = e.role_id
      where e.company_id = v_luna and r.scope = 'self' and e.user_id is not null and e.status = 'active'
      order by e.username limit 1)),
    jsonb_build_object('key', 'propietario', 'uid', (
      select e.user_id from public.employees e
      where e.company_id = v_luna and e.is_owner and e.user_id is not null and e.status = 'active')),
    jsonb_build_object('key', 'anon', 'uid', null),
    jsonb_build_object('key', 'admin', 'uid', v_admin_uid));
  if exists (select 1 from jsonb_array_elements(v_personas) x where x->>'key' in ('sucursal', 'self', 'propietario') and x->>'uid' is null) then
    raise exception 'Súper La Luna necesita un empleado de sucursal, uno de alcance self y su propietario, todos con cuenta';
  end if;

  begin  -- ═══ todo lo de este bloque se deshace al final ═══════════════════

  -- ─── Fixtures (como postgres) ──────────────────────────────────────────────
  -- Admin de Súper La Luna que NO es propietario.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, email_change, email_change_token_new, recovery_token)
  values ('00000000-0000-0000-0000-000000000000', v_admin_uid, 'authenticated', 'authenticated',
          'aislamiento.admin@superluna.operalia.local', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.employees (company_id, branch_id, department_id, role_id, employee_code, username, full_name, user_id)
  select v_luna,
         (select id from public.branches where company_id = v_luna order by code limit 1),
         (select id from public.departments where company_id = v_luna and code = 'ADM'),
         (select id from public.roles where company_id = v_luna and code = 'admin'),
         'EMP-AISL', 'aislamiento.admin', 'Admin de prueba (no propietario)', v_admin_uid;

  -- Un archivo de evidencia de Gato Pelón en Storage.
  insert into storage.objects (bucket_id, name, owner_id)
  values ('evidence', v_gp || '/aislamiento/muestra.jpg',
          (select user_id::text from public.employees where company_id = v_gp and user_id is not null limit 1));

  -- ─── 1. Pruebas por tabla y vista ──────────────────────────────────────────
  for rel in
    select c.oid, c.relname, c.relkind,
           exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'company_id' and not a.attisdropped) as has_company
    from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')
    order by c.relkind, c.relname
  loop
    v_label := rel.relname || case when rel.relkind = 'v' then ' (vista)' else '' end;

    -- ¿Cuáles son las filas de Gato Pelón?
    v_pred := null;
    if rel.relname = 'companies' then
      v_pred := format('id = %L', v_gp);
    elsif rel.relname in ('permissions', 'platform_admins', 'platform_leads') then
      v_pred := 'true';                       -- catálogo global o tablas solo de plataforma
    elsif rel.has_company then
      v_pred := format('company_id = %L', v_gp);
    else
      -- Tabla hija: su primera llave foránea hacia una tabla con company_id
      -- (en una vista, la de su tabla base: v_x → x).
      select a.attname, cf.relname into v_fkcol, v_parent
      from pg_constraint k
      join pg_class ct on ct.oid = k.conrelid
      join pg_class cf on cf.oid = k.confrelid and cf.relnamespace = 'public'::regnamespace
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
      where ct.relnamespace = 'public'::regnamespace
        and ct.relname = case when rel.relkind = 'v' then substr(rel.relname, 3) else rel.relname end
        and k.contype = 'f' and array_length(k.conkey, 1) = 1
        and exists (select 1 from pg_attribute x where x.attrelid = cf.oid and x.attname = 'company_id')
        and exists (select 1 from pg_attribute y where y.attrelid = rel.oid and y.attname = a.attname and not y.attisdropped)
      order by a.attnum limit 1;
      if v_parent is not null then
        if not exists (select 1 from _aisl_gp where tabla = v_parent) then
          execute format('insert into _aisl_gp select %L, id from public.%I where company_id = %L', v_parent, v_parent, v_gp);
        end if;
        v_pred := format('%I in (select id from _aisl_gp where tabla = %L)', v_fkcol, v_parent);
      end if;
    end if;

    if v_pred is null then
      v_orden := v_orden + 1;
      v_res := v_res || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', 'leer',
        'persona', 'sucursal', 'resultado', '❌', 'mensaje', 'No se pudo saber qué filas son de Gato Pelón: revisa esta tabla');
      continue;
    end if;

    execute format('select to_jsonb(t) from public.%I t where %s limit 1', rel.relname, v_pred) into v_sample;

    select string_agg(quote_ident(a.attname), ', ' order by a.attnum),
           (array_agg(quote_ident(a.attname) order by (a.attname = 'id'), a.attnum))[1]
      into v_cols, v_col
    from pg_attribute a
    where a.attrelid = rel.oid and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '';

    v_esperado := case when rel.relname = 'permissions' then 'info' when v_sample is null then 'vacio' else 'deny' end;

    v_todos := '["sucursal","self","propietario","anon"]'::jsonb;

    -- Leer (como PostgREST: SELECT con filtro).
    v_orden := v_orden + 1;
    v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '1 leer',
      'esperado', v_esperado, 'personas', v_todos, 'tipo', 'query',
      'sql', format('select count(*)::int from (select 1 from public.%I where %s limit 1000) s', rel.relname, v_pred));

    -- Insertar una copia de una fila de Gato Pelón (id nuevo), SIN RETURNING:
    -- con RETURNING fallaría por la política de lectura aunque la inserción pasara.
    -- Las cuentas (columnas hacia auth.users) se ligan solas: van vacías.
    select coalesce(v_sample - array_agg(a.attname::text), v_sample) into v_sample
    from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
    where k.conrelid = rel.oid and k.contype = 'f' and k.confrelid = 'auth.users'::regclass;
    if v_sample is not null and v_sample ? 'id' and jsonb_typeof(v_sample->'id') = 'string'
       and (v_sample->>'id') ~ '^[0-9a-f-]{36}$' then
      v_sample := jsonb_set(v_sample, '{id}', to_jsonb(gen_random_uuid()::text));
    end if;
    v_orden := v_orden + 1;
    v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '2 insertar',
      'esperado', case when v_sample is null then 'vacio' else 'deny' end, 'personas', v_todos, 'tipo', 'dml',
      'sql', case when v_sample is not null then format(
        'insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, %L::jsonb)',
        rel.relname, v_cols, v_cols, rel.relname, v_sample) end);

    -- Actualizar y borrar con filtro (lo que manda la API).
    v_orden := v_orden + 1;
    v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '3 actualizar',
      'esperado', case when v_esperado = 'info' then 'deny' else v_esperado end, 'personas', v_todos, 'tipo', 'dml',
      'sql', format('update public.%I set %s = %s where %s', rel.relname, v_col, v_col, v_pred));
    v_orden := v_orden + 1;
    v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '4 borrar',
      'esperado', case when v_esperado = 'info' then 'deny' else v_esperado end, 'personas', v_todos, 'tipo', 'dml',
      'sql', format('delete from public.%I where %s', rel.relname, v_pred));

    -- A ciegas (sin WHERE): así no aplica la política de lectura, solo la de
    -- escritura. Después se cuenta, como postgres, cuántas filas de Gato Pelón
    -- se tocaron. Solo tablas (en una vista se prueba su tabla base).
    if rel.relkind = 'r' and v_sample is not null then
      execute format('select count(*)::int from public.%I where %s', rel.relname, v_pred) into v_n;
      v_orden := v_orden + 1;
      v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '6 borrar sin filtro',
        'esperado', 'deny', 'personas', v_todos, 'tipo', 'ciego',
        'sql', format('delete from public.%I', rel.relname),
        'check', format('select %s - count(*)::int from public.%I where %s', v_n, rel.relname, v_pred));
      if exists (select 1 from pg_attribute a where a.attrelid = rel.oid and a.attname = 'updated_at' and not a.attisdropped) then
        -- trg_updated_at pone updated_at = now() en cada fila actualizada.
        execute format('select count(*)::int from public.%I where %s and updated_at = now()', rel.relname, v_pred) into v_n;
        v_orden := v_orden + 1;
        v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '1 tablas', 'objeto', v_label, 'accion', '5 actualizar sin filtro',
          'esperado', 'deny', 'personas', v_todos, 'tipo', 'ciego',
          'sql', format('update public.%I set updated_at = now()', rel.relname),
          'check', format('select count(*)::int - %s from public.%I where %s and updated_at = now()', v_n, rel.relname, v_pred));
      end if;
    end if;
  end loop;

  -- storage.objects, bucket evidence (la carpeta de primer nivel es la empresa)
  v_pred := format('bucket_id = %L and (storage.foldername(name))[1] = %L', 'evidence', v_gp::text);
  v_probes := v_probes
    || jsonb_build_object('orden', v_orden + 1, 'grupo', '1 tablas', 'objeto', 'storage.objects (evidence)', 'accion', '1 leer', 'esperado', 'deny',
         'personas', '["sucursal","self","propietario","anon"]'::jsonb,
         'sql', format('select count(*)::int from storage.objects where %s', v_pred))
    || jsonb_build_object('orden', v_orden + 2, 'grupo', '1 tablas', 'objeto', 'storage.objects (evidence)', 'accion', '2 insertar', 'esperado', 'deny',
         'personas', '["sucursal","self","propietario","anon"]'::jsonb, 'tipo', 'dml',
         'sql', format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, coalesce(auth.uid()::text, %L))',
                       'evidence', v_gp || '/aislamiento/intruso.jpg', 'anon'))
    || jsonb_build_object('orden', v_orden + 3, 'grupo', '1 tablas', 'objeto', 'storage.objects (evidence)', 'accion', '3 actualizar', 'esperado', 'deny',
         'personas', '["sucursal","self","propietario","anon"]'::jsonb, 'tipo', 'dml',
         'sql', format('update storage.objects set name = name where %s', v_pred))
    || jsonb_build_object('orden', v_orden + 4, 'grupo', '1 tablas', 'objeto', 'storage.objects (evidence)', 'accion', '4 borrar', 'esperado', 'deny',
         'personas', '["sucursal","self","propietario","anon"]'::jsonb, 'tipo', 'dml',
         'sql', format('delete from storage.objects where %s', v_pred))
    || jsonb_build_object('orden', v_orden + 5, 'grupo', '1 tablas', 'objeto', 'storage.objects (evidence)', 'accion', '6 borrar sin filtro', 'esperado', 'deny',
         'personas', '["sucursal","self","propietario","anon"]'::jsonb, 'tipo', 'ciego',
         'sql', 'delete from storage.objects',
         'check', format('select %s - count(*)::int from storage.objects where %s',
                         (select count(*) from storage.objects where bucket_id = 'evidence' and (storage.foldername(name))[1] = v_gp::text), v_pred));
  v_orden := v_orden + 5;

  -- Controles: la sesión es la esperada y ve su propia empresa (si no, todo
  -- saldría en 0 y la prueba no valdría).
  v_probes := v_probes
    || jsonb_build_object('orden', 0, 'grupo', '0 control', 'objeto', 'sesión de prueba', 'accion', 'rol authenticated',
         'esperado', 'allow', 'personas', '["sucursal","self","propietario","admin"]'::jsonb,
         'sql', 'select (current_user = ''authenticated'' and auth.uid() is not null)::int')
    || jsonb_build_object('orden', 0, 'grupo', '0 control', 'objeto', 'sesión de prueba', 'accion', 'rol anon',
         'esperado', 'allow', 'personas', '["anon"]'::jsonb, 'sql', 'select (current_user = ''anon'' and auth.uid() is null)::int')
    || jsonb_build_object('orden', 0, 'grupo', '0 control', 'objeto', 'employees de su empresa', 'accion', 'leer',
         'esperado', 'allow', 'personas', '["sucursal","self","propietario","admin"]'::jsonb,
         'sql', format('select count(*)::int from public.employees where company_id = %L', v_luna));

  -- ─── 2. RPC de plataforma y mantenimiento de otra empresa ─────────────────
  for f in
    select p.oid, p.proname,
           coalesce((select string_agg('null::' || format_type(t, null), ', ' order by o)
                     from unnest(p.proargtypes) with ordinality u(t, o)), '') as args,
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and (p.proname like 'platform\_%' or p.proname = 'provision_company')
    order by p.proname
  loop
    v_orden := v_orden + 1;
    v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '2 rpc', 'objeto', f.sig, 'accion', 'ejecutar',
      'esperado', 'error', 'personas', '["sucursal","self","propietario","anon","admin"]'::jsonb,
      'sql', format('select count(*)::int from (select * from public.%I(%s)) s', f.proname, f.args));
  end loop;
  v_orden := v_orden + 1;
  v_probes := v_probes || jsonb_build_object('orden', v_orden, 'grupo', '2 rpc', 'objeto', 'run_daily_maintenance(Gato Pelón)', 'accion', 'ejecutar',
    'esperado', 'error', 'personas', '["sucursal","self","propietario","anon","admin"]'::jsonb,
    'sql', format('select count(*)::int from (select public.run_daily_maintenance(%L::uuid)) s', v_gp));
  -- Funciones auxiliares que reciben un id: con ids de Gato Pelón no deben responder nada.
  v_probes := v_probes
    || jsonb_build_object('orden', v_orden + 1, 'grupo', '2 rpc', 'objeto', 'effective_price(producto de Gato Pelón)', 'accion', 'ejecutar',
         'esperado', 'deny', 'personas', '["sucursal","self","propietario","anon","admin"]'::jsonb,
         'sql', format('select count(*)::int from (select public.effective_price(%L::uuid, %L::uuid) v) s where v is not null',
                       (select id from public.products where company_id = v_gp limit 1),
                       (select id from public.branches where company_id = v_gp order by code limit 1)))
    || jsonb_build_object('orden', v_orden + 2, 'grupo', '2 rpc', 'objeto', 'checkpoint_for_run(checklist de Gato Pelón)', 'accion', 'ejecutar',
         'esperado', 'deny', 'personas', '["sucursal","self","propietario","anon","admin"]'::jsonb,
         'sql', format('select count(*)::int from (select public.checkpoint_for_run(%L::uuid) v) s where v is not null',
                       (select r.id from public.checklist_runs r join public.checklist_templates t on t.id = r.template_id
                         where r.company_id = v_gp and t.checkpoint_id is not null limit 1)))
    || jsonb_build_object('orden', v_orden + 3, 'grupo', '2 rpc', 'objeto', 'announcement_matches(empleado de Gato Pelón)', 'accion', 'ejecutar',
         'esperado', 'deny', 'personas', '["sucursal","self","propietario","anon","admin"]'::jsonb,
         'sql', format('select count(*)::int from (select public.announcement_matches(%L::uuid, %L, null, null, null) v) s where v',
                       (select id from public.employees where company_id = v_gp limit 1), 'company'));
  v_orden := v_orden + 3;

  -- ─── 3. Roles y permisos: admin no propietario (el propietario es el control) ─
  select id into v_role_caj from public.roles where company_id = v_luna and code = 'cajas';
  select code into v_perm_new from public.permissions
   where code not in (select permission_code from public.role_permissions where role_id = v_role_caj) order by code limit 1;
  select permission_code into v_perm_old from public.role_permissions where role_id = v_role_caj order by permission_code limit 1;
  select e.id into v_emp_self from public.employees e join public.roles r on r.id = e.role_id
   where e.company_id = v_luna and r.scope = 'self' order by e.username limit 1;
  v_probes := v_probes
    || jsonb_build_object('orden', v_orden + 1, 'grupo', '3 roles', 'objeto', 'role_permissions (su empresa)', 'accion', 'insertar',
         'esperado', '{"admin":"deny","propietario":"allow"}'::jsonb, 'personas', '["admin","propietario"]'::jsonb,
         'tipo', 'dml', 'sql', format('insert into public.role_permissions (role_id, permission_code) values (%L, %L)', v_role_caj, v_perm_new))
    || jsonb_build_object('orden', v_orden + 2, 'grupo', '3 roles', 'objeto', 'role_permissions (su empresa)', 'accion', 'borrar',
         'esperado', '{"admin":"deny","propietario":"allow"}'::jsonb, 'personas', '["admin","propietario"]'::jsonb,
         'tipo', 'dml', 'sql', format('delete from public.role_permissions where role_id = %L and permission_code = %L', v_role_caj, v_perm_old))
    || jsonb_build_object('orden', v_orden + 3, 'grupo', '3 roles', 'objeto', 'employee_permissions (su empresa)', 'accion', 'insertar',
         'esperado', '{"admin":"deny","propietario":"allow"}'::jsonb, 'personas', '["admin","propietario"]'::jsonb,
         'tipo', 'dml', 'sql', format('insert into public.employee_permissions (employee_id, permission_code, is_granted) values (%L, %L, true)', v_emp_self, v_perm_new))
    || jsonb_build_object('orden', v_orden + 4, 'grupo', '3 roles', 'objeto', 'roles (su empresa)', 'accion', 'actualizar',
         'esperado', '{"admin":"deny","propietario":"allow"}'::jsonb, 'personas', '["admin","propietario"]'::jsonb,
         'tipo', 'dml', 'sql', format('update public.roles set name = name where id = %L', v_role_caj));
  v_orden := v_orden + 4;

  -- ─── Ejecuta las pruebas 0 a 3, persona por persona ───────────────────────
  for pe in select * from jsonb_array_elements(v_personas) loop
    v_uid := (pe->>'uid')::uuid;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims',
      case when v_uid is null then '{"role":"anon"}' else json_build_object('sub', v_uid, 'role', 'authenticated')::text end, true);
    if v_uid is null then set local role anon; else set local role authenticated; end if;

    for pr in select * from jsonb_array_elements(v_probes) loop
      continue when not (pr->'personas') ? (pe->>'key');
      v_esperado := coalesce(pr->'esperado'->>(pe->>'key'), pr->>'esperado');
      v_n := null; v_msg := null;
      if pr->>'sql' is not null then
        begin
          if pr->>'tipo' = 'dml' then
            execute pr->>'sql';
            get diagnostics v_n = row_count;
          elsif pr->>'tipo' = 'ciego' then
            execute pr->>'sql';
            reset role;                              -- cuenta como postgres lo que se tocó
            execute pr->>'check' into v_n;
          else
            execute pr->>'sql' into v_n;
          end if;
          raise exception using message = '__aisl__' || coalesce(v_n, 0);   -- deshace lo que haya escrito (y el reset role)
        exception when others then
          if left(sqlerrm, 8) = '__aisl__' then v_n := substr(sqlerrm, 9)::int; v_msg := null;
          else v_n := null; v_msg := sqlerrm; end if;
        end;
      end if;
      v_ok := case v_esperado
        when 'vacio' then '—'
        when 'info'  then 'ℹ️'
        when 'deny'  then case when v_n = 0 then '✅'
                               when v_msg ~* v_seguridad then '✅'
                               when v_msg is not null then '⚠️'
                               else '❌' end
        when 'error' then case when v_msg is not null then '✅' else '❌' end
        when 'allow' then case when v_msg is null and v_n > 0 then '✅' else '❌' end
      end;
      v_res := v_res || jsonb_build_object('orden', (pr->>'orden')::int, 'grupo', pr->>'grupo', 'objeto', pr->>'objeto',
        'accion', pr->>'accion', 'persona', pe->>'key', 'esperado', v_esperado, 'filas', v_n, 'mensaje', v_msg, 'resultado', v_ok);
    end loop;

    reset role;
    perform set_config('request.jwt.claims', '', true);
  end loop;

  -- ─── 4. Empresa suspendida: no lee nada ───────────────────────────────────
  update public.companies set status = 'suspended' where id = v_luna;
  for pe in select * from jsonb_array_elements(v_personas) where value->>'key' in ('sucursal', 'propietario') loop
    v_uid := (pe->>'uid')::uuid;
    perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
    set local role authenticated;
    v_errs := '{}';
    for rel in
      select c.relname from pg_class c
      where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v') and c.relname <> 'permissions'
      order by c.relname
    loop
      begin
        execute format('select count(*)::int from (select 1 from public.%I limit 1) s', rel.relname) into v_n;
        if v_n > 0 then v_errs := v_errs || rel.relname; end if;
      exception when others then null;   -- error = no lee
      end;
    end loop;
    begin
      select count(*)::int into v_n from storage.objects where bucket_id = 'evidence';
      if v_n > 0 then v_errs := v_errs || 'storage.objects'::text; end if;
    exception when others then null;
    end;
    if public.get_my_profile() is not null then v_errs := v_errs || 'get_my_profile()'::text; end if;
    v_res := v_res || jsonb_build_object('orden', v_orden + 1, 'grupo', '4 suspendida', 'objeto', 'Súper La Luna suspendida',
      'accion', 'leer todas las tablas y vistas', 'persona', pe->>'key', 'esperado', 'deny',
      'resultado', case when cardinality(v_errs) = 0 then '✅' else '❌' end,
      'mensaje', case when cardinality(v_errs) > 0 then 'Ve filas en: ' || array_to_string(v_errs, ', ') end);

    -- Tampoco corre el mantenimiento de otra empresa.
    v_msg := null;
    begin
      perform public.run_daily_maintenance(v_gp);
    exception when others then v_msg := sqlerrm;
    end;
    v_res := v_res || jsonb_build_object('orden', v_orden + 2, 'grupo', '4 suspendida', 'objeto', 'Súper La Luna suspendida',
      'accion', 'run_daily_maintenance(Gato Pelón)', 'persona', pe->>'key', 'esperado', 'error',
      'resultado', case when v_msg is not null then '✅' else '❌' end,
      'mensaje', case when v_msg is null then 'Corrió el mantenimiento de Gato Pelón' end);
    reset role;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  v_orden := v_orden + 2;

  -- ─── 6. pg_cron se salta las empresas suspendidas (Súper La Luna sigue suspendida) ─
  v_prev := public.set_bypass('on');
  select timezone into v_tz from public.companies where id = v_luna;
  v_now := (now() at time zone v_tz)::time;
  if v_now between time '00:20' and time '23:40' then
    -- Un checklist de hoy por vencer en cada empresa (Gato Pelón es el control).
    select id into v_run_luna from public.checklist_runs where company_id = v_luna and scheduled_date = public.company_today(v_luna) limit 1;
    select id into v_run_gp from public.checklist_runs where company_id = v_gp and scheduled_date = public.company_today(v_gp) limit 1;
    update public.checklist_runs
       set status = 'pending', reminded_at = null,
           scheduled_start = ((now() at time zone (select timezone from public.companies c where c.id = company_id)) - interval '10 minutes')::time,
           scheduled_end   = ((now() at time zone (select timezone from public.companies c where c.id = company_id)) + interval '10 minutes')::time
     where id in (v_run_luna, v_run_gp);
    -- Un checklist de ayer pendiente en cada empresa: el mantenimiento lo marcaría vencido.
    select id into v_old_luna from public.checklist_runs where company_id = v_luna and scheduled_date < public.company_today(v_luna) limit 1;
    select id into v_old_gp from public.checklist_runs where company_id = v_gp and scheduled_date < public.company_today(v_gp) limit 1;
    update public.checklist_runs set status = 'pending' where id in (v_old_luna, v_old_gp);
    perform public.set_bypass(v_prev);

    -- Exactamente lo que ejecuta pg_cron, pero SIN filtrar: la función misma debe saltarse la suspendida.
    perform public.send_checklist_reminders(c.id) from public.companies c;
    perform public.run_daily_maintenance(c.id) from public.companies c;

    v_res := v_res
      || jsonb_build_object('orden', v_orden + 1, 'grupo', '6 pg_cron', 'objeto', 'send_checklist_reminders', 'accion', 'empresa suspendida',
           'persona', 'pg_cron', 'esperado', 'deny',
           'resultado', case when (select reminded_at from public.checklist_runs where id = v_run_luna) is null then '✅' else '❌' end,
           'mensaje', case when (select reminded_at from public.checklist_runs where id = v_run_luna) is not null then 'Mandó recordatorio a Súper La Luna' end)
      || jsonb_build_object('orden', v_orden + 2, 'grupo', '6 pg_cron', 'objeto', 'send_checklist_reminders', 'accion', 'control: empresa activa',
           'persona', 'pg_cron', 'esperado', 'allow',
           'resultado', case when (select reminded_at from public.checklist_runs where id = v_run_gp) is not null then '✅' else '❌' end)
      || jsonb_build_object('orden', v_orden + 3, 'grupo', '6 pg_cron', 'objeto', 'run_daily_maintenance', 'accion', 'empresa suspendida',
           'persona', 'pg_cron', 'esperado', 'deny',
           'resultado', case when (select status from public.checklist_runs where id = v_old_luna) = 'pending' then '✅' else '❌' end,
           'mensaje', case when (select status from public.checklist_runs where id = v_old_luna) <> 'pending' then 'Procesó a Súper La Luna' end)
      || jsonb_build_object('orden', v_orden + 4, 'grupo', '6 pg_cron', 'objeto', 'run_daily_maintenance', 'accion', 'control: empresa activa',
           'persona', 'pg_cron', 'esperado', 'allow',
           'resultado', case when (select status from public.checklist_runs where id = v_old_gp) = 'overdue' then '✅' else '❌' end);
  else
    perform public.set_bypass(v_prev);
    v_res := v_res || jsonb_build_object('orden', v_orden + 1, 'grupo', '6 pg_cron', 'objeto', 'send_checklist_reminders y run_daily_maintenance',
      'accion', 'empresa suspendida', 'persona', 'pg_cron', 'resultado', '—', 'mensaje', 'Cerca de medianoche no se puede armar la prueba; vuelve a correrla');
  end if;
  v_orden := v_orden + 4;
  update public.companies set status = 'active' where id = v_luna;

  -- ─── 5. «Olvidé mi contraseña» no revela si el usuario existe ─────────────
  select username into v_user_self from public.employees where id = v_emp_self;
  select e.username into v_user_gp from public.employees e
   where e.company_id = v_gp and not exists (select 1 from public.employees x where x.company_id = v_luna and lower(x.username) = lower(e.username))
   order by e.username limit 1;
  select username into v_user_own from public.employees where company_id = v_luna and is_owner;
  select count(*)::int into v_cnt_gp from public.notifications where company_id = v_gp;

  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  v_errs := '{}';
  for v_label, v_args in
    select * from (values ('superluna', v_user_self), ('superluna', 'no.existe.aislamiento'),
                          ('superluna', v_user_gp), ('gatopelon', v_user_own)) as t(code, u)
  loop
    begin
      perform public.request_password_reset(v_label, v_args);
      v_errs := v_errs || 'ok'::text;
    exception when others then
      v_errs := v_errs || sqlerrm;
    end;
  end loop;
  reset role;
  perform set_config('request.jwt.claims', '', true);

  v_res := v_res
    || jsonb_build_object('orden', v_orden + 1, 'grupo', '5 contraseña', 'objeto', 'request_password_reset',
         'accion', 'misma respuesta exista o no (y en otra empresa)', 'persona', 'anon', 'esperado', 'allow',
         'resultado', case when array_to_string(v_errs, '|') = 'ok|ok|ok|ok' then '✅' else '❌' end,
         'mensaje', case when array_to_string(v_errs, '|') <> 'ok|ok|ok|ok' then array_to_string(v_errs, ' | ') end)
    || jsonb_build_object('orden', v_orden + 2, 'grupo', '5 contraseña', 'objeto', 'request_password_reset',
         'accion', 'no avisa a otra empresa', 'persona', 'anon', 'esperado', 'deny',
         'resultado', case when (select count(*) from public.notifications where company_id = v_gp) = v_cnt_gp then '✅' else '❌' end,
         'mensaje', case when (select count(*) from public.notifications where company_id = v_gp) <> v_cnt_gp then 'Creó avisos en Gato Pelón' end);
  v_orden := v_orden + 2;

  raise exception using message = '__fin_aislamiento__';
  exception when others then
    if sqlerrm <> '__fin_aislamiento__' then raise; end if;
  end;  -- ═══ aquí se deshacen los fixtures y cualquier escritura ═════════════

  insert into _aisl_res (orden, grupo, objeto, accion, persona, esperado, filas, mensaje, resultado)
  select orden, grupo, objeto, accion, persona, esperado, filas, mensaje, resultado
  from jsonb_to_recordset(v_res) as x(orden int, grupo text, objeto text, accion text, persona text,
                                      esperado text, filas int, mensaje text, resultado text);
end $aisl$;

-- ─── 7. Funciones SECURITY DEFINER que la API puede llamar ──────────────────
-- Cada una está revisada a mano (ver el diario 2026-10-30). Una nueva que no
-- esté en esta lista sale ❌ «sin revisar» hasta que alguien la revise.
insert into _aisl_res (orden, grupo, objeto, accion, persona, resultado, mensaje)
select 10000 + row_number() over (order by p.proname), '7 security definer',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       case when has_function_privilege('anon', p.oid, 'execute') then 'anon y authenticated' else 'authenticated' end,
       'revisión',
       case when r.nota is null then '❌'
            when has_function_privilege('anon', p.oid, 'execute') and not r.anon then '❌'
            else '✅' end,
       case when r.nota is null then 'Sin revisar: confirma que valida empresa, usuario o superadmin y agrégala aquí'
            when has_function_privilege('anon', p.oid, 'execute') and not r.anon then 'No debería poder llamarla anon. ' || r.nota
            else r.nota end
from pg_proc p
left join (values
  -- Solo sobre el usuario que llama (auth.uid): no reciben empresa.
  ('auth_company_id', 'Sobre el usuario que llama', false), ('auth_employee_id', 'Sobre el usuario que llama', false),
  ('auth_branch_id', 'Sobre el usuario que llama', false), ('auth_department_id', 'Sobre el usuario que llama', false),
  ('auth_role_code', 'Sobre el usuario que llama', false), ('auth_role_scope', 'Sobre el usuario que llama', false),
  ('auth_is_owner', 'Sobre el usuario que llama', false), ('auth_zone_ids', 'Sobre el usuario que llama', false),
  ('has_permission', 'Sobre el usuario que llama', false), ('my_permissions', 'Sobre el usuario que llama', false),
  ('get_my_profile', 'Sobre el usuario que llama; empresa activa', false), ('is_platform_admin', 'Sobre el usuario que llama', false),
  ('can_manage_roles', 'Sobre el usuario que llama', false), ('clear_must_change_password', 'Solo la cuenta propia', false),
  ('can_access_branch', 'Compara contra la empresa y alcance de quien llama', false),
  ('can_access_department', 'Compara contra la empresa y alcance de quien llama', false),
  ('can_publish_announcement', 'Compara contra la empresa y alcance de quien llama', false),
  ('can_view_ticket', 'Compara contra el empleado y alcance de quien llama', false),
  ('is_my_notification', 'Compara contra el empleado de quien llama', false),
  ('company_today', 'Solo devuelve la fecha de hoy en la zona horaria de la empresa; no lee datos', false),
  -- Validan empresa (company_id = auth_company_id()) y permiso.
  ('announcement_matches', 'Valida empresa (0026)', false), ('announcement_counts', 'Valida empresa (can_track_announcement)', false),
  ('announcement_progress', 'Valida empresa (can_track_announcement)', false), ('can_track_announcement', 'Valida empresa', false),
  ('mark_announcement_read', 'Valida empresa', false), ('mark_notification_read', 'Solo avisos propios', false),
  ('mark_all_notifications_read', 'Solo avisos propios', false), ('admin_set_password', 'Valida empresa y alcance (o superadmin para un propietario sin cuenta)', false),
  ('close_shelf_gap', 'Valida empresa, permiso y sucursal', false), ('create_order_from_shelf_gap', 'Valida empresa, permiso y sucursal', false),
  ('record_cycle_count', 'Valida empresa, permiso y departamento', false), ('report_price_difference', 'Valida empresa, permiso y sucursal', false),
  ('report_shelf_gap', 'Valida empresa, permiso y sucursal', false), ('start_checklist_with_checkpoint', 'Valida empresa, permiso y departamento', false),
  ('run_daily_maintenance', 'Solo su empresa; se salta suspendidas (0026)', false),
  ('effective_price', 'Valida empresa (0026)', false), ('checkpoint_for_run', 'Valida empresa (0026)', false),
  -- Superadmin.
  ('provision_company', 'Valida superadmin', false), ('platform_list_companies', 'Valida superadmin', false),
  ('platform_set_company_status', 'Valida superadmin', false), ('platform_list_tickets', 'Valida superadmin', false),
  ('platform_get_ticket', 'Valida superadmin', false), ('platform_reply_ticket', 'Valida superadmin', false),
  ('platform_company_kpis', 'Valida superadmin', false), ('platform_company_trend', 'Valida superadmin', false),
  ('platform_checklist_heatmap', 'Valida superadmin', false), ('platform_company_health', 'Valida superadmin', false),
  -- Pública por diseño (pantalla de login).
  ('request_password_reset', 'Pública por diseño: responde igual exista o no el usuario', true)
) as r(fn, nota, anon) on r.fn = p.proname
where p.pronamespace = 'public'::regnamespace and p.prosecdef
  and p.prorettype <> 'trigger'::regtype
  and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));

-- ─── Resultado ──────────────────────────────────────────────────────────────
with cel as (
  select grupo, objeto, accion, min(orden) as orden,
         max(resultado) filter (where persona = 'sucursal')    as sucursal,
         max(resultado) filter (where persona = 'self')        as self,
         max(resultado) filter (where persona = 'propietario') as propietario,
         max(resultado) filter (where persona = 'anon')        as anon,
         max(resultado) filter (where persona = 'admin')       as admin_no_propietario,
         max(resultado) filter (where persona in ('pg_cron', 'revisión')) as resultado,
         bool_or(resultado = '❌') as falla,
         bool_or(resultado = '⚠️') as aviso,
         string_agg(case when resultado in ('❌', '⚠️') then resultado || ' ' || persona || ': ' || coalesce(mensaje, filas || ' fila(s)') end, ' · ') as detalle
  from _aisl_res
  group by grupo, objeto, accion
)
select regexp_replace(grupo, '^[0-9]+ ', '') as grupo, objeto, accion, sucursal, self, propietario, anon, admin_no_propietario, resultado, detalle
from (
  select '🧾 RESUMEN' as grupo,
         (select count(*) filter (where falla) from cel) || ' con ❌ y ' || (select count(*) filter (where aviso and not falla) from cel)
           || ' con ⚠️ de ' || (select count(*) from cel) || ' pruebas' as objeto,
         null::text as accion, null::text as sucursal, null::text as self, null::text as propietario, null::text as anon,
         null::text as admin_no_propietario, null::text as resultado,
         (select string_agg(objeto || ' · ' || coalesce(regexp_replace(accion, '^[0-9] ', ''), ''), ' | ') from cel where falla) as detalle,
         -1 as orden, true as falla
  union all
  select grupo, objeto, regexp_replace(accion, '^[0-9] ', ''), sucursal, self, propietario, anon, admin_no_propietario, resultado, detalle, orden, falla or aviso
  from cel
) s
order by s.orden < 0 desc, s.falla desc, s.grupo, s.orden, s.objeto;
