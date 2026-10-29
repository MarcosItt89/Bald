-- =============================================================================
-- OPERALIA · DEMO 0013 · USUARIOS DE ZONA
-- -----------------------------------------------------------------------------
-- Requiere demo/0009 (demo_seed_user). Re-ejecutable.
--   * jefe.escaner (zonas Centro y Norte) y escaner.norte, contraseña prueba123.
--     jefe.escaner NO ve la Sucursal Sur (zona Sur): ver pruebas en verificar.sql.
-- =============================================================================

select public.demo_seed_user('c0000000-0000-4000-8000-000000000001', 'jefe.escaner',  'prueba123', 'Raúl Jefe de Escáner', 'jefe_escaner', '001', 'ESC', 'Jefe de escáner (zonas Centro y Norte)', 'EMP-0015');
select public.demo_seed_user('c0000000-0000-4000-8000-000000000001', 'escaner.norte', 'prueba123', 'Diana Escáner Norte',  'escaner',      '002', 'ESC', 'Encargada de escáner',                   'EMP-0016');

insert into public.employee_zones (employee_id, zone_id)
select e.id, z.id
from public.employees e
join public.zones z on z.company_id = e.company_id and z.code in ('CEN', 'NOR')
where e.company_id = 'c0000000-0000-4000-8000-000000000001' and e.username = 'jefe.escaner'
on conflict do nothing;
