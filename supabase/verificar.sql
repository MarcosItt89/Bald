-- =============================================================================
-- OPERALIA · VERIFICAR INSTALACIÓN (solo lectura, no modifica nada)
-- Pégalo en el SQL Editor. Cada fila dice si el objeto existe y, si falta,
-- qué archivo ejecutar. Con instalacion-limpia.sql (sin demo) las filas
-- «demo/…» salen ❌ y es lo esperado.
-- =============================================================================
with checks(archivo, objeto, ok) as (values
  ('0001-0007 (pendiente.sql)', 'tabla employees con username',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='username')),
  ('0001-0007 (pendiente.sql)', 'función has_permission',        to_regprocedure('public.has_permission(text)') is not null),
  ('0001-0007 (pendiente.sql)', 'vista v_support_tickets',       to_regclass('public.v_support_tickets') is not null),
  ('0001-0007 (pendiente.sql)', 'bucket evidence',               exists (select 1 from storage.buckets where id='evidence')),
  ('0008_notificaciones_departamento', 'tabla notification_reads',   to_regclass('public.notification_reads') is not null),
  ('0008_notificaciones_departamento', 'vista v_my_notifications',   to_regclass('public.v_my_notifications') is not null),
  ('0008_notificaciones_departamento', 'función mark_all_notifications_read',
     exists (select 1 from pg_proc where proname='mark_all_notifications_read')),
  ('0009_checklists_evidencia', 'función tg_checklist_run_evidence',
     exists (select 1 from pg_proc where proname='tg_checklist_run_evidence')),
  ('0010_cancelar_checklist', 'trigger trg_checklist_run_cancel',
     exists (select 1 from pg_trigger where tgname='trg_checklist_run_cancel')),
  ('0011_soporte_temas_sla', 'tabla support_topics',             to_regclass('public.support_topics') is not null),
  ('0011_soporte_temas_sla', 'tabla support_canned_responses',   to_regclass('public.support_canned_responses') is not null),
  ('0011_soporte_temas_sla', 'columna support_tickets.due_at',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='support_tickets' and column_name='due_at')),
  ('0011_soporte_temas_sla', 'trigger trg_ticket_sla',           exists (select 1 from pg_trigger where tgname='trg_ticket_sla')),
  ('0011_soporte_temas_sla', 'función can_view_ticket',          exists (select 1 from pg_proc where proname='can_view_ticket')),
  ('0012 + seed/0010_propietario', 'cada empresa tiene exactamente un propietario',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
     and (xpath('/row/c/text()', query_to_xml(
       'select count(*) as c from public.companies c where (select count(*) from public.employees e where e.company_id = c.id and ' ||
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
            then 'e.is_owner' else 'false' end || ') <> 1', false, true, '')))[1]::text::int = 0),
  ('seed/0010_propietario', 'chee es el propietario de Gato Pelón',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
     and (xpath('/row/c/text()', query_to_xml(
       'select count(*) as c from public.employees where company_id = ''c0000000-0000-4000-8000-000000000001'' and username = ''chee'' and ' ||
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
            then 'is_owner' else 'false' end, false, true, '')))[1]::text::int = 1),
  ('0012_propietario_contrasenas_checklists', 'función admin_set_password',      exists (select 1 from pg_proc where proname='admin_set_password')),
  ('0012_propietario_contrasenas_checklists', 'función request_password_reset',  exists (select 1 from pg_proc where proname='request_password_reset')),
  ('seed/0008 (seed_company_base, 0023)', 'checklist Limpieza de cajas',     exists (select 1 from public.checklist_templates where title='Limpieza de cajas')),
  ('seed/0008 (seed_company_base, 0023)', 'checklist Revisión de tarimas',   exists (select 1 from public.checklist_templates where title='Revisión de tarimas y retornables')),
  ('0012 (activa pg_cron en Database → Extensions)', 'tarea automática diaria (pg_cron)',
     to_regclass('cron.job') is not null
     and (xpath('/row/c/text()', query_to_xml(
       case when to_regclass('cron.job') is null then 'select 0 as c'
            else 'select count(*) as c from cron.job where jobname = ''operalia-mantenimiento''' end, false, true, '')))[1]::text::int = 1),
  ('seed/0008_catalogos', 'empresa Gato Pelón',
     exists (select 1 from public.companies where id='c0000000-0000-4000-8000-000000000001')),
  ('demo/0009_usuarios_y_demo', 'usuario gatopelon en Auth',
     exists (select 1 from auth.users where email='gatopelon@gatopelon.operalia.local')),
  ('demo/0009_usuarios_y_demo', 'usuario cajero en Auth',
     exists (select 1 from auth.users where email='cajero@gatopelon.operalia.local')),
  ('seed/0008 (seed_company_base, 0023)', '10 temas de soporte sembrados',
     case when to_regclass('public.support_topics') is null then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.support_topics', false, true, '')))[1]::text::int >= 10 end),
  ('seed/0008 (seed_company_base, 0023)', 'rol cajas con create_tickets',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='cajas' and rp.permission_code='create_tickets')),
  ('0013_checklists_criticos_y_horarios', 'columna checklist_questions.is_critical', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='is_critical')),
  ('0013_checklists_criticos_y_horarios', 'columna checklist_templates.schedule_anchor', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_templates' and column_name='schedule_anchor')),
  ('0013_checklists_criticos_y_horarios', 'trigger trg_checklist_answer_task', exists (select 1 from pg_trigger where tgname='trg_checklist_answer_task')),
  ('0013_checklists_criticos_y_horarios', 'función checklist_window',          exists (select 1 from pg_proc where proname='checklist_window')),
  ('seed/0008 (seed_company_base, 0023)', '7 checklists de Gerencia',
     (select count(*) from public.checklist_templates t join public.departments d on d.id=t.department_id
       where d.code='GER' and (t.title like 'Apertura · %' or t.title like 'Cierre · %')) >= 7),
  ('0014_temperaturas_y_mermas', 'columna checklist_questions.equipment_name', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='equipment_name')),
  ('0014_temperaturas_y_mermas', 'columna checklist_answers.out_of_range',     exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_answers' and column_name='out_of_range')),
  ('0014_temperaturas_y_mermas', 'columna inventory_movements.waste_reason',   exists (select 1 from information_schema.columns where table_schema='public' and table_name='inventory_movements' and column_name='waste_reason')),
  ('0014_temperaturas_y_mermas', 'vista v_inventory_movements con total_cost', exists (select 1 from information_schema.columns where table_schema='public' and table_name='v_inventory_movements' and column_name='total_cost')),
  ('0014_temperaturas_y_mermas', 'trigger trg_expiration_waste', exists (select 1 from pg_trigger where tgname='trg_expiration_waste')),
  ('0014_temperaturas_y_mermas', 'permiso register_waste',       exists (select 1 from public.permissions where code='register_waste')),
  ('seed/0008 (seed_company_base, 0023)', 'gerente con register_waste',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='gerente' and rp.permission_code='register_waste')),
  ('seed/0008 (seed_company_base, 0023) + demo/0009', 'lecturas de temperatura con rango',
     case when not exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='equipment_name') then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.checklist_questions where equipment_name is not null and is_active', false, true, '')))[1]::text::int >= 7 end),
  ('0015_zonas_jefe_escaner', 'tabla zones',                     to_regclass('public.zones') is not null),
  ('0015_zonas_jefe_escaner', 'tabla employee_zones',            to_regclass('public.employee_zones') is not null),
  ('0015_zonas_jefe_escaner', 'tabla branch_prices',             to_regclass('public.branch_prices') is not null),
  ('0015_zonas_jefe_escaner', 'columna price_changes.zone_id',   exists (select 1 from information_schema.columns where table_schema='public' and table_name='price_changes' and column_name='zone_id')),
  ('0015_zonas_jefe_escaner', 'función auth_zone_ids',           exists (select 1 from pg_proc where proname='auth_zone_ids')),
  ('seed/0008 (seed_company_base, 0023)', 'rol jefe_escaner (alcance zone)', exists (select 1 from public.roles where code='jefe_escaner' and scope='zone')),
  ('demo/0013_usuarios_zona', 'usuario jefe.escaner con zonas',
     case when to_regclass('public.employee_zones') is null then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.employee_zones ez join public.employees e on e.id = ez.employee_id where e.username = ''jefe.escaner''', false, true, '')))[1]::text::int >= 1 end),
  ('0016_checklists_repetidos', 'columna checklist_templates.repeat_every_minutes', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_templates' and column_name='repeat_every_minutes')),
  ('0016_checklists_repetidos', 'columna checklist_runs.round_no',  exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_runs' and column_name='round_no')),
  ('0016_checklists_repetidos', 'restricción única por hora de inicio',
     exists (select 1 from pg_constraint where conname = 'checklist_runs_template_branch_date_start_key')),
  ('0016_checklists_repetidos', 'sin la restricción única vieja (una corrida por día)',
     not exists (select 1 from pg_constraint con where con.conrelid = 'public.checklist_runs'::regclass and con.contype = 'u'
                 and array_length(con.conkey, 1) = 3)),
  ('seed/0008 (seed_company_base, 0023)', 'checklist Ronda de carritos y canastillas',
     exists (select 1 from public.checklist_templates where title = 'Ronda de carritos y canastillas')),
  ('0017_recordatorio_checklists', 'columna checklist_runs.reminded_at',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_runs' and column_name='reminded_at')),
  ('0017_recordatorio_checklists', 'función send_checklist_reminders', exists (select 1 from pg_proc where proname='send_checklist_reminders')),
  ('0017_recordatorio_checklists', 'el mantenimiento diario envía recordatorios',
     exists (select 1 from pg_proc where proname='run_daily_maintenance' and prosrc like '%send_checklist_reminders%')),
  ('0017 (activa pg_cron en Database → Extensions)', 'recordatorios cada 5 min (pg_cron)',
     to_regclass('cron.job') is not null
     and (xpath('/row/c/text()', query_to_xml(
       case when to_regclass('cron.job') is null then 'select 0 as c'
            else 'select count(*) as c from cron.job where jobname = ''operalia-recordatorios''' end, false, true, '')))[1]::text::int = 1),
  ('0018_puntos_qr', 'tabla checkpoints',                 to_regclass('public.checkpoints') is not null),
  ('0018_puntos_qr', 'función start_checklist_with_checkpoint', exists (select 1 from pg_proc where proname='start_checklist_with_checkpoint')),
  ('0018_puntos_qr', 'trigger trg_checklist_run_checkpoint',     exists (select 1 from pg_trigger where tgname='trg_checklist_run_checkpoint')),
  ('0018_puntos_qr', 'permiso manage_checkpoints',        exists (select 1 from public.permissions where code='manage_checkpoints')),
  ('seed/0008 (seed_company_base, 0023)', 'gerente con manage_checkpoints',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='gerente' and rp.permission_code='manage_checkpoints')),
  ('0019_conteo_ciclico', 'tablas de conteo cíclico',
     to_regclass('public.cycle_count_plans') is not null and to_regclass('public.cycle_count_tasks') is not null and to_regclass('public.cycle_count_items') is not null),
  ('0019_conteo_ciclico', 'función record_cycle_count',     exists (select 1 from pg_proc where proname='record_cycle_count')),
  ('0019_conteo_ciclico', 'el mantenimiento diario genera conteos',
     exists (select 1 from pg_proc where proname='run_daily_maintenance' and prosrc like '%generate_cycle_counts%')),
  ('0019_conteo_ciclico', 'permisos de conteo cíclico',
     (select count(*) from public.permissions where code in ('perform_cycle_counts','manage_cycle_counts')) = 2),
  ('demo/0009 (seed_company_demo)', 'planes de conteo de ejemplo',
     case when to_regclass('public.cycle_count_plans') is null then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.cycle_count_plans', false, true, '')))[1]::text::int >= 1 end),
  ('0020_huecos_anaquel', 'tabla shelf_gaps y vista v_shelf_gaps',
     to_regclass('public.shelf_gaps') is not null and to_regclass('public.v_shelf_gaps') is not null),
  ('0020_huecos_anaquel', 'funciones report_shelf_gap / create_order_from_shelf_gap / close_shelf_gap',
     (select count(distinct proname) from pg_proc where proname in ('report_shelf_gap','create_order_from_shelf_gap','close_shelf_gap')) = 3),
  ('0020_huecos_anaquel', 'cierre automático por tarea y pedido',
     (select count(*) from pg_trigger where tgname in ('trg_shelf_gap_task_done','trg_shelf_gap_order_done')) = 2),
  ('0020_huecos_anaquel', 'permisos de huecos en anaquel',
     (select count(*) from public.permissions where code in ('report_shelf_gaps','manage_shelf_gaps')) = 2),
  ('seed/0008 (seed_company_base, 0023)', 'almacén con manage_shelf_gaps',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='almacen' and rp.permission_code='manage_shelf_gaps')),
  ('0021_comunicados', 'tablas announcements / announcement_reads y vista',
     to_regclass('public.announcements') is not null and to_regclass('public.announcement_reads') is not null
     and to_regclass('public.v_announcements') is not null),
  ('0021_comunicados', 'funciones de lectura y avance',
     (select count(distinct proname) from pg_proc where proname in ('mark_announcement_read','announcement_progress','announcement_matches','can_publish_announcement')) = 4),
  ('0021_comunicados', 'aviso al publicar (trigger)',   exists (select 1 from pg_trigger where tgname='trg_announcement_notify')),
  ('0021_comunicados', 'bucket privado announcements',  exists (select 1 from storage.buckets where id='announcements' and not public)),
  ('0021_comunicados', 'permisos de comunicados',
     (select count(*) from public.permissions where code in ('publish_announcements','manage_announcements')) = 2),
  ('seed/0008 (seed_company_base, 0023)', 'gerente con publish_announcements',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='gerente' and rp.permission_code='publish_announcements')),
  ('0022_multiempresa_login', 'columna companies.code',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='companies' and column_name='code')),
  ('0022_multiempresa_login', 'usuario único por empresa (employees_company_username_key)',
     to_regclass('public.employees_company_username_key') is not null and to_regclass('public.employees_username_lower_key') is null),
  ('0022_multiempresa_login', 'request_password_reset(código, usuario)',
     to_regprocedure('public.request_password_reset(text, text)') is not null and to_regprocedure('public.request_password_reset(text)') is null),
  ('0022_multiempresa_login', 'ninguna cuenta con @operalia.local sin empresa',
     not exists (select 1 from auth.users where lower(email) like '%@operalia.local')),
  ('0023_plataforma_roles_semillas', 'tabla platform_admins y función is_platform_admin',
     to_regclass('public.platform_admins') is not null and to_regprocedure('public.is_platform_admin()') is not null),
  ('0023_plataforma_roles_semillas', 'función seed_company_base',
     to_regprocedure('public.seed_company_base(uuid)') is not null),
  ('0023_plataforma_roles_semillas', 'roles solo con propietario o superadmin (can_manage_roles)',
     to_regprocedure('public.can_manage_roles()') is not null),
  ('0024_plataforma_empresas_soporte', 'alta de empresas (provision_company, platform_list_companies, platform_set_company_status)',
     to_regprocedure('public.provision_company(text, text, text, text, text, text, text, text, text, text, boolean)') is not null
     and to_regprocedure('public.platform_list_companies()') is not null
     and to_regprocedure('public.platform_set_company_status(uuid, text)') is not null),
  ('0024_plataforma_empresas_soporte', 'Soporte Operalia (platform_list_tickets, platform_get_ticket, platform_reply_ticket)',
     to_regprocedure('public.platform_list_tickets(uuid, text, text, integer)') is not null
     and to_regprocedure('public.platform_get_ticket(uuid)') is not null
     and to_regprocedure('public.platform_reply_ticket(uuid, text, text)') is not null),
  ('0024_plataforma_empresas_soporte', 'mensajes firmados por la plataforma (support_ticket_messages.is_platform)',
     exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'support_ticket_messages' and column_name = 'is_platform')
     and exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'v_support_ticket_messages' and column_name = 'is_platform')),
  ('platform_admins: ver diario 2026-10-29', 'hay al menos un superadmin de la plataforma',
     exists (select 1 from public.platform_admins pa join auth.users u on u.id = pa.user_id)),
  ('0025_plataforma_rendimiento', 'rendimiento de tiendas (platform_company_kpis, platform_company_trend, platform_checklist_heatmap)',
     to_regprocedure('public.platform_company_kpis(date, date)') is not null
     and to_regprocedure('public.platform_company_trend(uuid, text, date, date)') is not null
     and to_regprocedure('public.platform_checklist_heatmap(date, date, uuid)') is not null),
  ('0025_plataforma_rendimiento', 'salud de la cuenta y avance de arranque (platform_company_health)',
     to_regprocedure('public.platform_company_health()') is not null),
  ('0025_plataforma_rendimiento', 'prospectos (platform_leads, solo superadmin)',
     to_regclass('public.platform_leads') is not null
     and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'platform_leads')),
  ('0026_aislamiento_empresas', 'mantenimiento y recordatorios se saltan empresas suspendidas',
     position('empresa suspendida' in pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure)) > 0
     and position('p_company_id and status = ''active''' in pg_get_functiondef('public.send_checklist_reminders(uuid, integer)'::regprocedure)) > 0),
  ('0026_aislamiento_empresas', 'effective_price, checkpoint_for_run y announcement_matches validan empresa',
     position('auth_company_id' in pg_get_functiondef('public.effective_price(uuid, uuid)'::regprocedure)) > 0
     and position('auth_company_id' in pg_get_functiondef('public.checkpoint_for_run(uuid)'::regprocedure)) > 0
     and position('auth_company_id' in pg_get_functiondef('public.announcement_matches(uuid, text, uuid, uuid, uuid)'::regprocedure)) > 0),
  ('0026_aislamiento_empresas', 'anon solo ejecuta request_password_reset',
     not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
                  and p.proname <> 'request_password_reset' and has_function_privilege('anon', p.oid, 'execute'))),
  ('demo/0019_empresas_demo', 'Gato Pelón, Súper La Luna y Mercado Sol con 4 sucursales',
     (select count(*) from public.companies c where c.code in ('gatopelon','superluna','mercadosol')
        and (select count(*) from public.branches b where b.company_id = c.id) = 4) = 3),
  ('demo/0025_rendimiento_demo', '30 días de historial en las 3 tiendas demo y prospectos de ejemplo',
     (select count(distinct t.company_id) from public.tasks t join public.companies c on c.id = t.company_id
       where t.source_type = 'demo_history' and c.code in ('gatopelon','superluna','mercadosol')) = 3
     and exists (select 1 from public.platform_leads))
)
select case when ok then '✅ OK' else '❌ FALTA' end as estado, objeto, archivo as ejecutar_si_falta
from checks
order by ok, archivo;


-- =============================================================================
-- PRUEBAS DE SEGURIDAD POR ZONA (0015) — selecciona desde aquí hasta el final y
-- ejecútalo aparte. Se hace pasar por jefe.escaner (zonas Centro y Norte) y
-- comprueba que NO ve nada de sucursales de otras zonas. No modifica datos.
-- La columna "como" debe decir authenticated; si dice postgres, la prueba no aplica.
-- =============================================================================
select set_config('request.jwt.claim.sub',
  (select id::text from auth.users where email = 'jefe.escaner@gatopelon.operalia.local'), false);
set role authenticated;

with fuera as (
  select b.id from public.branches b
  where b.zone_id is null or b.zone_id not in (select public.auth_zone_ids())
), pruebas(prueba, valor, esperado) as (values
  ('mis zonas',                                  (select count(*) from public.auth_zone_ids()), 2),
  ('sucursales accesibles fuera de mis zonas',   (select count(*) from fuera f where public.can_access_branch(f.id)), 0),
  ('inventario de otras zonas',                  (select count(*) from public.v_inventory where branch_id in (select id from fuera)), 0),
  ('checklists de otras zonas',                  (select count(*) from public.checklist_runs where branch_id in (select id from fuera)), 0),
  ('tareas de otras zonas',                      (select count(*) from public.tasks where branch_id in (select id from fuera)), 0),
  ('cenefas de otras zonas',                     (select count(*) from public.shelf_tags where branch_id in (select id from fuera)), 0),
  ('empleados de otras zonas',                   (select count(*) from public.employees where branch_id in (select id from fuera) and user_id <> auth.uid()), 0),
  ('evidencias de otras zonas',                  (select count(*) from public.evidence_files where branch_id in (select id from fuera)), 0)
)
select case when valor = esperado then '✅ OK' else '❌ FALLA' end as estado, prueba, valor, esperado,
       current_user as como, auth.uid() as usuario
from pruebas;
