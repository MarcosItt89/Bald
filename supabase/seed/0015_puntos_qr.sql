-- =============================================================================
-- OPERALIA · SEMILLA 0015 · PUNTOS QR DE EJEMPLO
-- -----------------------------------------------------------------------------
-- Requiere la migración 0018. Re-ejecutable.
--   * manage_checkpoints para admin y gerente.
--   * En cada sucursal: «Área de carritos» (Cajas) y «Cámara de carnes».
--   * «Ronda de carritos y canastillas» exige escanear el QR del Área de
--     carritos de su sucursal. Los QR se imprimen en Checklists → Puntos QR.
-- =============================================================================

insert into public.role_permissions (role_id, permission_code)
select r.id, 'manage_checkpoints' from public.roles r where r.code in ('admin', 'gerente')
on conflict do nothing;

insert into public.checkpoints (company_id, branch_id, department_id, name)
select b.company_id, b.id, d.id, v.name
from public.branches b
cross join (values ('Área de carritos', 'CAJ'), ('Cámara de carnes', null)) as v(name, dept)
left join public.departments d on d.company_id = b.company_id and d.code = v.dept
on conflict (branch_id, name) do nothing;

update public.checklist_templates t
   set checkpoint_required = true,
       checkpoint_id = (select c.id from public.checkpoints c join public.branches b on b.id = c.branch_id
                        where c.company_id = t.company_id and c.name = 'Área de carritos' order by b.code limit 1)
 where t.title = 'Ronda de carritos y canastillas' and t.checkpoint_id is null;
