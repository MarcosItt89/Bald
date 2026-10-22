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
             where r.code='cajas' and rp.permission_code='create_tickets'))
)
select case when ok then '✅ OK' else '❌ FALTA' end as estado, objeto, archivo as ejecutar_si_falta
from checks
order by ok, archivo;
