-- =============================================================================
-- OPERALIA · SEMILLA 0012 · TEMPERATURAS CON RANGO Y PERMISO DE MERMAS
-- -----------------------------------------------------------------------------
-- Requiere la migración 0014. Re-ejecutable.
--   * Las preguntas sí/no de temperatura se retiran (is_active = false, el
--     historial se conserva) y se agregan lecturas numéricas por equipo:
--       refrigeración 0 a 4 °C · congelación −25 a −18 °C
--   * Las lecturas numéricas que ya existían (Control de temperaturas) reciben
--     su rango y equipo.
--   * register_waste para gerente, almacén, abarrotes, caducidades y admin.
-- =============================================================================

-- ─── Retirar preguntas sí/no de temperatura ─────────────────────────────────
update public.checklist_questions q set is_active = false
  from public.checklist_templates t
 where t.id = q.template_id and q.is_active
   and (t.title, q.text) in (
     ('Apertura · Perecederos y frío', 'Temperaturas de cámaras y vitrinas en rango'),
     ('Cierre · Piso y perecederos', 'Cámaras cerradas y en rango'),
     ('Control de temperaturas', '¿Alguna temperatura fuera de rango?'));

-- ─── Lecturas numéricas nuevas ──────────────────────────────────────────────
insert into public.checklist_questions (template_id, position, text, answer_type, is_required, min_value, max_value, unit, equipment_name)
select t.id, v.pos, v.txt, v.typ, true, v.mn, v.mx, v.unit, v.equipment
from public.checklist_templates t
join (values
  ('Apertura · Perecederos y frío', 6, 'Temperatura cámara de refrigeración', 'number', 0::numeric, 4::numeric, '°C', 'Cámara de refrigeración'),
  ('Apertura · Perecederos y frío', 7, 'Temperatura cámara de congelación',   'number', -25, -18, '°C', 'Cámara de congelación'),
  ('Apertura · Perecederos y frío', 8, 'Temperatura vitrina de lácteos',      'number', 0, 4, '°C', 'Vitrina de lácteos'),
  ('Apertura · Perecederos y frío', 9, 'Temperatura vitrina de carnes',       'number', 0, 4, '°C', 'Vitrina de carnes'),
  ('Cierre · Piso y perecederos', 6, 'Cámaras cerradas',                                'yes_no', null, null, null, null),
  ('Cierre · Piso y perecederos', 7, 'Temperatura cámara de refrigeración al cierre', 'number', 0, 4, '°C', 'Cámara de refrigeración'),
  ('Cierre · Piso y perecederos', 8, 'Temperatura cámara de congelación al cierre',   'number', -25, -18, '°C', 'Cámara de congelación')
) as v(title, pos, txt, typ, mn, mx, unit, equipment) on v.title = t.title
where not exists (select 1 from public.checklist_questions x where x.template_id = t.id and x.text = v.txt);

-- ─── Rango a las lecturas que ya eran numéricas ─────────────────────────────
update public.checklist_questions q
   set min_value = v.mn, max_value = v.mx, unit = '°C', equipment_name = v.equipment
  from public.checklist_templates t,
       (values ('Temperatura refrigerador lácteos (°C)', 0::numeric, 4::numeric, 'Vitrina de lácteos'),
               ('Temperatura vitrina carnes (°C)', 0, 4, 'Vitrina de carnes')) as v(txt, mn, mx, equipment)
 where t.id = q.template_id and t.title = 'Control de temperaturas' and q.text = v.txt
   and q.equipment_name is null;

-- ─── Permiso de mermas ──────────────────────────────────────────────────────
insert into public.role_permissions (role_id, permission_code)
select r.id, 'register_waste' from public.roles r
where r.code in ('admin', 'gerente', 'almacen', 'abarrotes', 'caducidades')
on conflict do nothing;
