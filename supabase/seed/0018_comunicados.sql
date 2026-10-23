-- =============================================================================
-- OPERALIA · SEMILLA 0018 · PERMISOS DE COMUNICADOS
-- -----------------------------------------------------------------------------
-- Requiere la migración 0021. Re-ejecutable.
--   * publish_announcements: admin, gerente, supervisor y jefe de escáner.
--     manage_announcements: admin.
--   * Los comunicados de ejemplo están en demo/0018_comunicados_ejemplo.sql.
-- =============================================================================

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
join (values
  ('publish_announcements', array['admin','gerente','supervisor','jefe_escaner']),
  ('manage_announcements',  array['admin'])
) as p(code, roles) on r.code = any(p.roles)
on conflict do nothing;

