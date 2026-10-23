-- =============================================================================
-- OPERALIA · SEMILLA 0018 · COMUNICADOS DE EJEMPLO
-- -----------------------------------------------------------------------------
-- Requiere la migración 0021. Re-ejecutable.
--   * publish_announcements: admin, gerente, supervisor y jefe de escáner.
--     manage_announcements: admin.
--   * Dos comunicados: uno a toda la empresa (admin) y uno a la Sucursal
--     Centro (gerente.centro). Al insertarlos se avisa a su alcance.
-- =============================================================================

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
join (values
  ('publish_announcements', array['admin','gerente','supervisor','jefe_escaner']),
  ('manage_announcements',  array['admin'])
) as p(code, roles) on r.code = any(p.roles)
on conflict do nothing;

insert into public.announcements (company_id, title, body, scope, branch_id, valid_until, published_by)
select e.company_id, v.title, v.body, v.scope, b.id, public.company_today(e.company_id) + v.days, e.id
from (values
  ('gatopelon', 'Nuevo canal de comunicados',
   'A partir de hoy los avisos oficiales llegan por Operalia. Abre cada comunicado y confirma con «Leído» para que tu gerente sepa que lo recibiste.',
   'company', null, 30),
  ('gerente.centro', 'Inventario general el domingo',
   'El domingo a las 7:00 hacemos inventario general en la Sucursal Centro. Todos los departamentos se presentan con su lista impresa. No se reciben proveedores ese día.',
   'branch', '001', 7)
) as v(username, title, body, scope, branch, days)
join public.employees e on e.username = v.username
left join public.branches b on b.company_id = e.company_id and b.code = v.branch
where not exists (select 1 from public.announcements a where a.company_id = e.company_id and a.title = v.title);
