-- =============================================================================
-- OPERALIA · DEMO 0017 · HISTORIAL DE HUECOS EN ANAQUEL
-- -----------------------------------------------------------------------------
-- Requiere la migración 0020 y el inventario demo. Re-ejecutable.
--   * 6 huecos ya resueltos en Sucursal Centro (últimos días) para que
--     Estadísticas → Inventario muestre datos.
-- =============================================================================

insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock,
                               status, reported_at, last_reported_at, resolved_at)
select i.company_id, i.branch_id, p.department_id, p.id,
       case when x.n % 3 = 0 then 0 else i.stock end, x.n % 3 <> 0, 'resolved',
       now() - make_interval(days => (x.n + 1)::int), now() - make_interval(days => (x.n + 1)::int),
       now() - make_interval(days => (x.n + 1)::int) + interval '3 hours'
from (select i.*, row_number() over (order by md5(p.sku)) as n
        from public.inventory i
        join public.branches b on b.id = i.branch_id and b.code = '001' and b.company_id = 'c0000000-0000-4000-8000-000000000001'
        join public.products p on p.id = i.product_id
       where i.stock > 0) x
join public.inventory i on i.id = x.id
join public.products p on p.id = i.product_id
where x.n <= 6
  and not exists (select 1 from public.shelf_gaps g where g.branch_id = i.branch_id);
