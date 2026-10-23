-- =============================================================================
-- OPERALIA · VERIFICAR INSTALACIÓN (solo lectura, no modifica nada)
-- Pégalo en el SQL Editor. Cada fila dice si el objeto existe y, si falta,
-- qué archivo ejecutar.
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
  ('0012_propietario_contrasenas_checklists', 'gatopelon es propietario',
     exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
     and (xpath('/row/c/text()', query_to_xml(
       'select count(*) as c from public.employees where username = ''gatopelon'' and ' ||
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='employees' and column_name='is_owner')
            then 'is_owner' else 'false' end, false, true, '')))[1]::text::int = 1),
  ('0012_propietario_contrasenas_checklists', 'función admin_set_password',      exists (select 1 from pg_proc where proname='admin_set_password')),
  ('0012_propietario_contrasenas_checklists', 'función request_password_reset',  exists (select 1 from pg_proc where proname='request_password_reset')),
  ('0012_propietario_contrasenas_checklists', 'checklist Limpieza de cajas',     exists (select 1 from public.checklist_templates where title='Limpieza de cajas')),
  ('0012_propietario_contrasenas_checklists', 'checklist Revisión de tarimas',   exists (select 1 from public.checklist_templates where title='Revisión de tarimas y retornables')),
  ('0012 (activa pg_cron en Database → Extensions)', 'tarea automática diaria (pg_cron)',
     to_regclass('cron.job') is not null
     and (xpath('/row/c/text()', query_to_xml(
       case when to_regclass('cron.job') is null then 'select 0 as c'
            else 'select count(*) as c from cron.job where jobname = ''operalia-mantenimiento''' end, false, true, '')))[1]::text::int = 1),
  ('seed/0008_catalogos', 'empresa Gato Pelón',
     exists (select 1 from public.companies where id='c0000000-0000-4000-8000-000000000001')),
  ('seed/0009_usuarios_y_demo', 'usuario gatopelon en Auth',
     exists (select 1 from auth.users where email='gatopelon@operalia.local')),
  ('seed/0009_usuarios_y_demo', 'usuario cajero en Auth',
     exists (select 1 from auth.users where email='cajero@operalia.local')),
  ('0011_soporte_temas_sla', '10 temas de soporte sembrados',
     case when to_regclass('public.support_topics') is null then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.support_topics', false, true, '')))[1]::text::int >= 10 end),
  ('0011_soporte_temas_sla', 'rol cajas con create_tickets',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='cajas' and rp.permission_code='create_tickets')),
  ('0013_checklists_criticos_y_horarios', 'columna checklist_questions.is_critical', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='is_critical')),
  ('0013_checklists_criticos_y_horarios', 'columna checklist_templates.schedule_anchor', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_templates' and column_name='schedule_anchor')),
  ('0013_checklists_criticos_y_horarios', 'trigger trg_checklist_answer_task', exists (select 1 from pg_trigger where tgname='trg_checklist_answer_task')),
  ('0013_checklists_criticos_y_horarios', 'función checklist_window',          exists (select 1 from pg_proc where proname='checklist_window')),
  ('seed/0011_checklists_gerencia', '7 checklists de Gerencia',
     (select count(*) from public.checklist_templates t join public.departments d on d.id=t.department_id
       where d.code='GER' and (t.title like 'Apertura · %' or t.title like 'Cierre · %')) >= 7),
  ('0014_temperaturas_y_mermas', 'columna checklist_questions.equipment_name', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='equipment_name')),
  ('0014_temperaturas_y_mermas', 'columna checklist_answers.out_of_range',     exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_answers' and column_name='out_of_range')),
  ('0014_temperaturas_y_mermas', 'columna inventory_movements.waste_reason',   exists (select 1 from information_schema.columns where table_schema='public' and table_name='inventory_movements' and column_name='waste_reason')),
  ('0014_temperaturas_y_mermas', 'vista v_inventory_movements con total_cost', exists (select 1 from information_schema.columns where table_schema='public' and table_name='v_inventory_movements' and column_name='total_cost')),
  ('0014_temperaturas_y_mermas', 'trigger trg_expiration_waste', exists (select 1 from pg_trigger where tgname='trg_expiration_waste')),
  ('0014_temperaturas_y_mermas', 'permiso register_waste',       exists (select 1 from public.permissions where code='register_waste')),
  ('seed/0012_temperaturas_y_mermas', 'gerente con register_waste',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='gerente' and rp.permission_code='register_waste')),
  ('seed/0012_temperaturas_y_mermas', 'lecturas de temperatura con rango',
     case when not exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_questions' and column_name='equipment_name') then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.checklist_questions where equipment_name is not null and is_active', false, true, '')))[1]::text::int >= 7 end),
  ('0015_zonas_jefe_escaner', 'tabla zones',                     to_regclass('public.zones') is not null),
  ('0015_zonas_jefe_escaner', 'tabla employee_zones',            to_regclass('public.employee_zones') is not null),
  ('0015_zonas_jefe_escaner', 'tabla branch_prices',             to_regclass('public.branch_prices') is not null),
  ('0015_zonas_jefe_escaner', 'columna price_changes.zone_id',   exists (select 1 from information_schema.columns where table_schema='public' and table_name='price_changes' and column_name='zone_id')),
  ('0015_zonas_jefe_escaner', 'función auth_zone_ids',           exists (select 1 from pg_proc where proname='auth_zone_ids')),
  ('seed/0013_zonas_jefe_escaner', 'rol jefe_escaner (alcance zone)', exists (select 1 from public.roles where code='jefe_escaner' and scope='zone')),
  ('seed/0013_zonas_jefe_escaner', 'usuario jefe.escaner con zonas',
     case when to_regclass('public.employee_zones') is null then false
          else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.employee_zones ez join public.employees e on e.id = ez.employee_id where e.username = ''jefe.escaner''', false, true, '')))[1]::text::int >= 1 end),
  ('0016_checklists_repetidos', 'columna checklist_templates.repeat_every_minutes', exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_templates' and column_name='repeat_every_minutes')),
  ('0016_checklists_repetidos', 'columna checklist_runs.round_no',  exists (select 1 from information_schema.columns where table_schema='public' and table_name='checklist_runs' and column_name='round_no')),
  ('0016_checklists_repetidos', 'restricción única por hora de inicio',
     exists (select 1 from pg_constraint where conname = 'checklist_runs_template_branch_date_start_key')),
  ('0016_checklists_repetidos', 'sin la restricción única vieja (una corrida por día)',
     not exists (select 1 from pg_constraint con where con.conrelid = 'public.checklist_runs'::regclass and con.contype = 'u'
                 and array_length(con.conkey, 1) = 3)),
  ('seed/0014_checklists_repetidos', 'checklist Ronda de carritos y canastillas',
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
  ('seed/0015_puntos_qr', 'gerente con manage_checkpoints',
     exists (select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id
             where r.code='gerente' and rp.permission_code='manage_checkpoints'))
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
  (select id::text from auth.users where email = 'jefe.escaner@operalia.local'), false);
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
