-- =============================================================================
-- OPERALIA · DEMO 0016 · PLANES DE CONTEO CÍCLICO
-- -----------------------------------------------------------------------------
-- Requiere la migración 0019. Re-ejecutable.
--   * Sucursal Centro: «Conteo diario de Abarrotes» (8 productos al día).
--   * Sucursal Norte: «Conteo general» de lunes a viernes (5 productos).
-- =============================================================================

insert into public.cycle_count_plans (company_id, branch_id, department_id, name, frequency, items_per_count)
select b.company_id, b.id, d.id, v.name, v.freq, v.n
from (values
  ('001', 'ABA', 'Conteo diario de Abarrotes', 'daily', 8),
  ('002', null,  'Conteo general',             'weekdays', 5)
) as v(branch, dept, name, freq, n)
join public.branches b on b.code = v.branch
left join public.departments d on d.company_id = b.company_id and d.code = v.dept
where not exists (select 1 from public.cycle_count_plans x where x.branch_id = b.id and x.name = v.name);

select public.generate_cycle_counts(id, public.company_today(id)) from public.companies;
