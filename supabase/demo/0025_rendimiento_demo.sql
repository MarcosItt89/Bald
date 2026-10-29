-- =============================================================================
-- OPERALIA · DEMO · 0025 · RENDIMIENTO DE LAS TIENDAS Y PROSPECTOS
-- -----------------------------------------------------------------------------
-- SOLO PARA PRUEBAS. Da a Plataforma → Rendimiento datos que se distingan:
--   * 30 días de historial también para Gato Pelón (demo_company_history, 0019).
--   * Últimos inicios de sesión simulados: no en todas las empresas entra la
--     misma proporción de usuarios (Gato Pelón ~85 %, Súper La Luna ~55 %,
--     Mercado Sol ~20 %). Solo toca cuentas que nunca han entrado.
--   * Huecos en anaquel abiertos (de 0 a 4 por sucursal).
--   * Prospectos de ejemplo en platform_leads; Súper La Luna y Mercado Sol
--     quedan ligadas a su prospecto ganado.
-- Re-ejecutable.
-- =============================================================================

select public.demo_company_history(id, 30) from public.companies where code = 'gatopelon';

update auth.users u
   set last_sign_in_at = now() - make_interval(mins => abs(hashtext(u.email)) % (6 * 24 * 60))
  from public.employees e
  join public.companies c on c.id = e.company_id
 where e.user_id = u.id and u.last_sign_in_at is null
   and abs(hashtext(e.username || c.code)) % 100 < case c.code when 'gatopelon' then 85 when 'superluna' then 55 when 'mercadosol' then 20 end;

insert into public.platform_leads (chain_name, contact_name, contact_email, contact_phone, branch_count, business_type, status, notes, company_id)
select v.chain, v.contact, v.email, v.phone, v.n, v.giro, v.status, v.notes,
       (select c.id from public.companies c where c.code = v.code)
from (values
  ('Súper La Luna', 'Lucía Navarro', 'lucia@superluna.mx', '664-200-1000', 4, 'Supermercado', 'won', 'Arrancó con 4 sucursales.', 'superluna'),
  ('Mercado Sol', 'Raúl Soto', 'raul@mercadosol.mx', '664-300-2000', 6, 'Supermercado', 'won', 'Planea abrir 2 sucursales más en primavera.', 'mercadosol'),
  ('Farmacias Pino', 'Andrea Pino', 'andrea@farmaciaspino.mx', '686-111-2233', 9, 'Farmacia', 'negotiation', 'Pide precio por sucursal y capacitación presencial.', null),
  ('Ferretería El Clavo', 'Jorge Ibarra', null, '664-555-0101', 3, 'Ferretería', 'demo', 'Demo agendada; le interesan recibo y conteo cíclico.', null),
  ('Abarrotes Doña Mary', 'María López', 'mary@donamary.mx', null, 2, 'Abarrotes', 'won', 'Firmó; falta darla de alta.', null),
  ('Minisúper 24/7', 'Pedro Gil', null, '664-777-8899', 12, 'Tienda de conveniencia', 'new', null, null),
  ('Carnicería La Res', 'Tomás Ruiz', null, null, 1, 'Carnicería', 'lost', 'Eligió otro sistema por precio.', null)
) as v(chain, contact, email, phone, n, giro, status, notes, code)
where not exists (select 1 from public.platform_leads l where l.chain_name = v.chain);

-- Huecos que siguen abiertos (el historial los deja todos resueltos o
-- descartados): de 0 a 4 por sucursal, para que el ranking de huecos abiertos
-- tenga diferencias.
insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock,
                               status, reported_by, reported_at, last_reported_at)
select b.company_id, b.id, p.department_id, p.id, 0, false, 'open', null,
       now() - make_interval(hours => (2 + p.rn * 5)::int), now() - make_interval(hours => (2 + p.rn)::int)
from public.branches b
join public.companies c on c.id = b.company_id and c.code in ('gatopelon', 'superluna', 'mercadosol')
cross join lateral (
  select x.id, x.department_id, row_number() over (order by x.sku) as rn
  from public.products x where x.company_id = b.company_id
) p
where b.status = 'active'
  and p.rn <= abs(hashtext(c.code || b.code)) % 5
  and not exists (select 1 from public.shelf_gaps g where g.branch_id = b.id and g.status = 'open');
