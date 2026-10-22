-- =============================================================================
-- OPERALIA · SEMILLA 0011 · CHECKLISTS DE GERENCIA (APERTURA Y CIERRE)
-- -----------------------------------------------------------------------------
-- El gerente de cada sucursal revisa la tienda completa antes de abrir y al
-- cerrar. Departamento Gerencia (GER), diarios.
--
-- Horarios relativos a la sucursal (0013): apertura respecto a
-- branches.opening_time y cierre respecto a branches.closing_time. Los
-- start_time/end_time son el respaldo si la sucursal no tiene horario
-- (y corresponden a una tienda que abre 07:00 y cierra 22:00).
--
-- Temperaturas como sí/no por ahora (la fase de temperaturas las vuelve
-- numéricas con rango). is_critical: seguridad y valores.
-- Re-ejecutable: no duplica plantillas (por título) ni preguntas.
-- Requiere la migración 0013.
-- =============================================================================

insert into public.checklist_templates
  (company_id, department_id, title, description, shift, start_time, end_time, frequency, requires_evidence,
   schedule_anchor, start_offset_minutes, end_offset_minutes)
select c.id, d.id, v.title, v.descr, v.shift, v.st::time, v.et::time, 'daily', v.ev, v.anchor, v.so, v.eo
from public.companies c
join public.departments d on d.company_id = c.id and d.code = 'GER'
cross join (values
  ('Apertura · Exterior y seguridad', 'Revisión exterior y de seguridad antes de abrir', 'apertura', '06:00', '07:00', true,  'opening', -60,  0),
  ('Apertura · Piso de venta',        'Piso de venta listo para recibir clientes',        'apertura', '06:30', '07:30', true,  'opening', -30, 30),
  ('Apertura · Perecederos y frío',   'Perecederos exhibidos y equipos de frío en rango', 'apertura', '06:30', '07:30', true,  'opening', -30, 30),
  ('Apertura · Cajas y personal',     'Personal, cajas y servicios listos',               'apertura', '06:45', '07:30', false, 'opening', -15, 30),
  ('Cierre · Piso y perecederos',     'Resguardo de perecederos y piso en orden',         'cierre',   '21:00', '22:00', false, 'closing', -60,  0),
  ('Cierre · Cajas y valores',        'Cortes de caja y resguardo de efectivo',           'cierre',   '21:30', '22:30', true,  'closing', -30, 30),
  ('Cierre · Seguridad',              'Tienda cerrada y asegurada',                       'cierre',   '22:00', '23:00', true,  'closing',   0, 60)
) as v(title, descr, shift, st, et, ev, anchor, so, eo)
where not exists (select 1 from public.checklist_templates t where t.company_id = c.id and t.title = v.title);

insert into public.checklist_questions (template_id, position, text, answer_type, is_required, is_critical)
select t.id, q.pos, q.txt, q.typ, q.req, q.crit
from public.checklist_templates t
join public.departments d on d.id = t.department_id and d.code = 'GER'
join (values
  ('Apertura · Exterior y seguridad', 1, 'Estacionamiento limpio e iluminado', 'yes_no', true, false),
  ('Apertura · Exterior y seguridad', 2, 'Fachada y anuncios encendidos', 'yes_no', true, false),
  ('Apertura · Exterior y seguridad', 3, 'Accesos y salidas de emergencia libres', 'yes_no', true, true),
  ('Apertura · Exterior y seguridad', 4, 'Alarma desactivada correctamente', 'yes_no', true, true),
  ('Apertura · Exterior y seguridad', 5, 'Cámaras de vigilancia grabando', 'yes_no', true, true),
  ('Apertura · Exterior y seguridad', 6, 'Carritos y canastillas en su lugar', 'yes_no', true, false),

  ('Apertura · Piso de venta', 1, 'Pisos limpios y secos', 'yes_no', true, false),
  ('Apertura · Piso de venta', 2, 'Pasillos sin obstáculos ni tarimas', 'yes_no', true, false),
  ('Apertura · Piso de venta', 3, 'Anaqueles surtidos sin huecos visibles', 'yes_no', true, false),
  ('Apertura · Piso de venta', 4, 'Cabeceras armadas según la promoción vigente', 'yes_no', true, false),
  ('Apertura · Piso de venta', 5, 'Cenefas y precios de oferta colocados', 'yes_no', true, false),
  ('Apertura · Piso de venta', 6, 'Señalización correcta', 'yes_no', true, false),
  ('Apertura · Piso de venta', 7, 'Música y aire acondicionado funcionando', 'yes_no', true, false),

  ('Apertura · Perecederos y frío', 1, 'Temperaturas de cámaras y vitrinas en rango', 'yes_no', true, false),
  ('Apertura · Perecederos y frío', 2, 'Fruta y verdura surtida y sin producto en mal estado', 'yes_no', true, false),
  ('Apertura · Perecederos y frío', 3, 'Carnes y salchichonería exhibidas correctamente', 'yes_no', true, false),
  ('Apertura · Perecederos y frío', 4, 'Panadería y tortillería listas', 'yes_no', true, false),
  ('Apertura · Perecederos y frío', 5, 'Sin producto caducado en exhibición', 'yes_no', true, true),

  ('Apertura · Cajas y personal', 1, 'Personal completo y uniformado', 'yes_no', true, false),
  ('Apertura · Cajas y personal', 2, 'Cajas con fondo asignado', 'yes_no', true, true),
  ('Apertura · Cajas y personal', 3, 'Terminales y básculas funcionando', 'yes_no', true, false),
  ('Apertura · Cajas y personal', 4, 'Bolsas e insumos en cajas', 'yes_no', true, false),
  ('Apertura · Cajas y personal', 5, 'Baños limpios y surtidos', 'yes_no', true, false),

  ('Cierre · Piso y perecederos', 1, 'Perecederos retirados o resguardados', 'yes_no', true, false),
  ('Cierre · Piso y perecederos', 2, 'Merma del día registrada', 'yes_no', true, false),
  ('Cierre · Piso y perecederos', 3, 'Cámaras cerradas y en rango', 'yes_no', true, false),
  ('Cierre · Piso y perecederos', 4, 'Piso limpio', 'yes_no', true, false),
  ('Cierre · Piso y perecederos', 5, 'Producto devuelto a su lugar', 'yes_no', true, false),

  ('Cierre · Cajas y valores', 1, 'Cortes de caja realizados', 'yes_no', true, true),
  ('Cierre · Cajas y valores', 2, 'Efectivo resguardado en caja fuerte', 'yes_no', true, true),
  ('Cierre · Cajas y valores', 3, 'Diferencias de caja reportadas', 'yes_no', true, true),
  ('Cierre · Cajas y valores', 4, 'Terminales cerradas', 'yes_no', true, false),

  ('Cierre · Seguridad', 1, 'Equipos no esenciales apagados', 'yes_no', true, false),
  ('Cierre · Seguridad', 2, 'Puertas y accesos cerrados', 'yes_no', true, true),
  ('Cierre · Seguridad', 3, 'Alarma activada', 'yes_no', true, true),
  ('Cierre · Seguridad', 4, 'Pendientes para el turno de mañana', 'text', false, false)
) as q(title, pos, txt, typ, req, crit) on q.title = t.title
where not exists (select 1 from public.checklist_questions x where x.template_id = t.id);

-- El gerente llena y revisa los checklists de su sucursal.
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join (values ('fill_checklists'), ('review_checklists'), ('upload_evidence')) as p(code)
where r.code = 'gerente'
on conflict do nothing;

-- Los gerentes demo pertenecen a Gerencia (así aparecen en «Míos»).
update public.employees e set department_id = d.id
from public.departments d, public.roles r
where r.id = e.role_id and r.code = 'gerente' and e.department_id is null
  and d.company_id = e.company_id and d.code = 'GER';

select public.generate_checklist_runs(id, public.company_today(id)) from public.companies;
