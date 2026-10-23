-- =============================================================================
-- OPERALIA · SEMILLA 0013 · ZONAS Y JEFE DE ESCÁNER
-- -----------------------------------------------------------------------------
-- Requiere la migración 0015. Re-ejecutable.
--   * Zonas Norte, Sur, Este, Oeste y Centro por empresa.
--   * Sucursales demo: 001 Centro → zona Centro, 002 Norte → Norte, 003 Sur → Sur.
--   * Rol jefe_escaner (alcance 'zone'): permisos de escáner + validar cenefas,
--     reportes y asignar tareas (solo al departamento Escáner de sus tiendas).
--   * Los usuarios demo de zona están en demo/0013_usuarios_zona.sql.
-- =============================================================================

insert into public.zones (company_id, code, name)
select c.id, v.code, v.name
from public.companies c
cross join (values ('NOR', 'Norte'), ('SUR', 'Sur'), ('EST', 'Este'), ('OES', 'Oeste'), ('CEN', 'Centro')) as v(code, name)
on conflict (company_id, code) do nothing;

update public.branches b set zone_id = z.id
  from public.zones z
 where z.company_id = b.company_id and b.zone_id is null
   and z.code = case b.code when '001' then 'CEN' when '002' then 'NOR' when '003' then 'SUR' end;

insert into public.roles (company_id, code, name, scope, is_system, description)
select c.id, 'jefe_escaner', 'Jefe de Escáner', 'zone', true, 'Supervisa ofertas, precios, señalización y cabeceras de las tiendas de sus zonas'
from public.companies c
on conflict (company_id, code) do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join (values
  ('view_dashboard'), ('view_inventory'), ('view_prices'), ('scan_products'), ('report_price_difference'),
  ('manage_price_changes'), ('manage_shelf_tags'), ('validate_shelf_tags'), ('fill_checklists'),
  ('upload_evidence'), ('view_tasks'), ('manage_tasks'), ('view_reports'), ('create_tickets')
) as p(code)
where r.code = 'jefe_escaner'
on conflict do nothing;

