-- =============================================================================
-- OPERALIA · SEMILLA 0016 · PERMISOS DE CONTEO CÍCLICO
-- -----------------------------------------------------------------------------
-- Requiere la migración 0019. Re-ejecutable.
--   * perform_cycle_counts: admin, gerente, supervisor, almacén, abarrotes y
--     caducidades. manage_cycle_counts: admin y gerente.
--   * Los planes de ejemplo están en demo/0016_planes_conteo.sql.
-- =============================================================================

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
join (values
  ('perform_cycle_counts', array['admin','gerente','supervisor','almacen','abarrotes','caducidades']),
  ('manage_cycle_counts',  array['admin','gerente'])
) as p(code, roles) on r.code = any(p.roles)
on conflict do nothing;

