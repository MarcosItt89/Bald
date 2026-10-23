-- =============================================================================
-- OPERALIA · SEMILLA 0017 · PERMISOS DE HUECOS EN ANAQUEL
-- -----------------------------------------------------------------------------
-- Requiere la migración 0020. Re-ejecutable.
--   * report_shelf_gaps: admin, gerente, supervisor, jefe de cajas, cajas,
--     abarrotes, almacén, caducidades y escáner.
--   * manage_shelf_gaps: admin, gerente, supervisor y almacén.
--   * El historial de ejemplo está en demo/0017_huecos_historial.sql.
-- =============================================================================

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
join (values
  ('report_shelf_gaps', array['admin','gerente','supervisor','jefe_cajas','cajas','abarrotes','almacen','caducidades','escaner']),
  ('manage_shelf_gaps', array['admin','gerente','supervisor','almacen'])
) as p(code, roles) on r.code = any(p.roles)
on conflict do nothing;

