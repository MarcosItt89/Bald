-- =============================================================================
-- OPERALIA · 0001 · ESQUEMA DE TABLAS
-- -----------------------------------------------------------------------------
-- Objetivo: crear todas las tablas del modelo relacional de Operalia.
--
-- Convenciones:
--   * Todas las llaves primarias son UUID (gen_random_uuid()).
--   * Los estados se guardan como TEXT + CHECK (más fácil de evolucionar que ENUM).
--   * Los códigos de estado van en inglés (se traducen en el frontend) para que
--     el código sea consistente; los nombres visibles van en español.
--   * Casi todas las tablas llevan company_id: es la base del aislamiento
--     multiempresa que aplican las políticas RLS (ver 0005).
--   * created_at / updated_at se mantienen con triggers (ver 0003).
--
-- Este archivo es idempotente (CREATE ... IF NOT EXISTS): se puede re-ejecutar.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ORGANIZACIÓN: empresas, sucursales, departamentos
-- ─────────────────────────────────────────────────────────────────────────────

-- Empresa que usa Operalia (multiempresa desde el diseño).
create table if not exists public.companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  legal_name  text,
  rfc         text,
  timezone    text not null default 'America/Tijuana', -- define el "hoy" operativo
  logo_url    text,
  settings    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Sucursal / tienda / CEDIS de una empresa.
create table if not exists public.branches (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id) on delete cascade,
  code          text not null,                 -- número o clave de tienda
  name          text not null,
  branch_type   text not null default 'tienda', -- tienda, express, almacen, cedis...
  address       text,
  city          text,
  phone         text,
  opening_time  time,
  closing_time  time,
  manager_id    uuid,                          -- FK a employees (se agrega abajo)
  status        text not null default 'active' check (status in ('active','inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (company_id, code)
);

-- Catálogo de departamentos de la empresa (Cajas, Abarrotes, Recibo...).
-- Es por empresa; el empleado se liga a sucursal + departamento.
create table if not exists public.departments (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id) on delete cascade,
  code         text not null,
  name         text not null,
  description  text,
  color        text not null default '#64748b',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (company_id, code)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. SEGURIDAD: permisos, roles, empleados
-- ─────────────────────────────────────────────────────────────────────────────

-- Catálogo global de permisos (acciones que el sistema sabe validar).
create table if not exists public.permissions (
  code         text primary key,               -- ej. 'view_inventory'
  module       text not null,                  -- agrupador visual
  name         text not null,
  description  text
);

-- Rol = paquete de permisos + alcance de datos.
--   scope 'company'    → ve toda la empresa (admin, auditor, soporte)
--   scope 'branch'     → ve toda su sucursal (gerente)
--   scope 'department' → ve su(s) departamento(s) en su sucursal (supervisor, jefes)
--   scope 'self'       → ve lo de su departamento pero las tareas solo propias
create table if not exists public.roles (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id) on delete cascade,
  code         text not null,
  name         text not null,
  description  text,
  scope        text not null default 'department'
               check (scope in ('company','branch','department','self')),
  is_system    boolean not null default false, -- los roles de sistema no se borran
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (company_id, code)
);

create table if not exists public.role_permissions (
  role_id          uuid not null references public.roles(id) on delete cascade,
  permission_code  text not null references public.permissions(code) on delete cascade,
  primary key (role_id, permission_code)
);

-- Empleado. Puede existir sin cuenta (user_id null) y ligarse después.
-- user_id apunta a auth.users (Supabase Auth).
create table if not exists public.employees (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid unique references auth.users(id) on delete set null,
  company_id     uuid not null references public.companies(id) on delete cascade,
  branch_id      uuid references public.branches(id) on delete set null,
  department_id  uuid references public.departments(id) on delete set null,
  role_id        uuid not null references public.roles(id),
  employee_code  text,
  username       text not null,                -- con esto se inicia sesión
  full_name      text not null,
  position       text,                         -- puesto visible (ej. "Jefe de cajas")
  email          text,
  phone          text,
  status         text not null default 'active' check (status in ('active','inactive','suspended')),
  hired_at       date default current_date,
  avatar_url     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (company_id, employee_code)
);
-- Usuario único por empresa: índice employees_company_username_key en 0022
-- (antes era global: employees_username_lower_key).

-- FK diferida: gerente de sucursal.
do $$ begin
  alter table public.branches
    add constraint branches_manager_id_fkey
    foreign key (manager_id) references public.employees(id) on delete set null;
exception when duplicate_object then null; end $$;

-- Permisos especiales por empleado (conceder o revocar sobre su rol).
create table if not exists public.employee_permissions (
  employee_id      uuid not null references public.employees(id) on delete cascade,
  permission_code  text not null references public.permissions(code) on delete cascade,
  is_granted       boolean not null default true, -- false = revocado aunque el rol lo tenga
  primary key (employee_id, permission_code)
);

-- Departamentos extra asignados (supervisores que cubren varias áreas).
create table if not exists public.employee_departments (
  employee_id    uuid not null references public.employees(id) on delete cascade,
  department_id  uuid not null references public.departments(id) on delete cascade,
  primary key (employee_id, department_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. PRODUCTOS E INVENTARIO
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.products (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id) on delete cascade,
  department_id        uuid references public.departments(id) on delete set null,
  sku                  text not null,
  name                 text not null,
  description          text,
  category             text,
  brand                text,
  unit                 text not null default 'pz'
                       check (unit in ('pz','kg','g','l','ml','caja','paquete')),
  cost                 numeric(12,2) not null default 0 check (cost >= 0),
  price                numeric(12,2) not null default 0 check (price >= 0),
  previous_price       numeric(12,2),
  price_updated_at     timestamptz,
  controls_expiration  boolean not null default false, -- entra a control de caducidades
  is_weighable         boolean not null default false, -- se vende por peso
  status               text not null default 'active' check (status in ('active','inactive')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (company_id, sku)
);

create table if not exists public.product_barcodes (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  barcode     text not null,
  is_primary  boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (company_id, barcode)
);

-- Existencia de un producto en una sucursal. El status lo calcula un trigger.
create table if not exists public.inventory (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  branch_id         uuid not null references public.branches(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  stock             numeric(12,3) not null default 0,
  min_stock         numeric(12,3) not null default 0 check (min_stock >= 0),
  max_stock         numeric(12,3) check (max_stock is null or max_stock >= 0),
  location          text,                      -- pasillo / anaquel
  status            text not null default 'normal'
                    check (status in ('normal','low','critical','out_of_stock','review')),
  last_movement_at  timestamptz,
  last_counted_at   timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (branch_id, product_id)
);

-- Bitácora inmutable de movimientos. Un trigger aplica cada movimiento al stock.
--   quantity siempre es positiva; el tipo define si suma o resta.
--   'count' (conteo físico) fija el stock al valor capturado.
create table if not exists public.inventory_movements (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  branch_id       uuid not null references public.branches(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  movement_type   text not null check (movement_type in (
                    'in','out','adjustment_in','adjustment_out','receiving',
                    'waste','return','transfer_in','transfer_out','count')),
  quantity        numeric(12,3) not null check (quantity >= 0),
  stock_before    numeric(12,3),
  stock_after     numeric(12,3),
  reference_type  text,                        -- 'receiving_order', 'order', ...
  reference_id    uuid,
  reason          text,
  created_by      uuid references public.employees(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists inventory_movements_branch_idx on public.inventory_movements (branch_id, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. PROVEEDORES Y RECIBO DE MERCANCÍA
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.suppliers (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  code              text not null,             -- código de proveedor
  name              text not null,
  legal_name        text,
  rfc               text,
  merchandise_type  text,
  contact_name      text,
  phone             text,
  email             text,
  status            text not null default 'active' check (status in ('active','inactive','blocked')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (company_id, code)
);

-- Entrada / salida física del proveedor a la sucursal (caseta / protección).
create table if not exists public.supplier_visits (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  branch_id      uuid not null references public.branches(id) on delete cascade,
  supplier_id    uuid not null references public.suppliers(id) on delete cascade,
  check_in_at    timestamptz not null default now(),
  check_out_at   timestamptz,
  driver_name    text,
  vehicle_plate  text,
  purpose        text default 'entrega',
  notes          text,
  registered_by  uuid references public.employees(id) on delete set null,
  closed_by      uuid references public.employees(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (check_out_at is null or check_out_at >= check_in_at)
);

create sequence if not exists public.receiving_folio_seq;

-- Recibo de mercancía (encabezado). Al pasar a 'completed' un trigger
-- calcula totales, genera movimientos de inventario y caducidades.
create table if not exists public.receiving_orders (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  branch_id         uuid not null references public.branches(id) on delete cascade,
  supplier_id       uuid not null references public.suppliers(id),
  visit_id          uuid references public.supplier_visits(id) on delete set null,
  folio             text not null default ('REC-' || lpad(nextval('public.receiving_folio_seq')::text, 6, '0')),
  invoice_number    text,                      -- factura o remisión
  status            text not null default 'in_progress'
                    check (status in ('in_progress','completed','cancelled')),
  received_by       uuid references public.employees(id) on delete set null,
  completed_by      uuid references public.employees(id) on delete set null,
  completed_at      timestamptz,
  total_items       integer not null default 0,
  total_expected    numeric(12,3) not null default 0,
  total_received    numeric(12,3) not null default 0,
  total_damaged     numeric(12,3) not null default 0,
  has_differences   boolean not null default false,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (company_id, folio)
);

create table if not exists public.receiving_items (
  id                  uuid primary key default gen_random_uuid(),
  receiving_order_id  uuid not null references public.receiving_orders(id) on delete cascade,
  product_id          uuid not null references public.products(id),
  expected_qty        numeric(12,3) not null default 0 check (expected_qty >= 0),
  received_qty        numeric(12,3) not null default 0 check (received_qty >= 0),
  damaged_qty         numeric(12,3) not null default 0 check (damaged_qty >= 0),
  weight_kg           numeric(12,3) check (weight_kg is null or weight_kg >= 0),
  difference          numeric(12,3) generated always as (received_qty - expected_qty) stored,
  lot                 text,
  expiration_date     date,
  notes               text,
  created_at          timestamptz not null default now(),
  check (damaged_qty <= received_qty)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. PRECIOS, CENEFAS Y CADUCIDADES
-- ─────────────────────────────────────────────────────────────────────────────

-- branch_id null = el cambio aplica en todas las sucursales de la empresa.
create table if not exists public.price_changes (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  old_price       numeric(12,2) not null,
  new_price       numeric(12,2) not null check (new_price > 0),
  effective_date  date not null default current_date,
  reason          text,
  requires_tag    boolean not null default true,
  status          text not null default 'scheduled' check (status in ('scheduled','applied','cancelled')),
  created_by      uuid references public.employees(id) on delete set null,
  applied_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Cenefa (etiqueta de anaquel). Flujo: pending → printed → placed → validated
-- (o rejected en cualquier punto antes de validar; rejected → pending reimprime).
create table if not exists public.shelf_tags (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  branch_id         uuid not null references public.branches(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  price_change_id   uuid references public.price_changes(id) on delete cascade,
  status            text not null default 'pending'
                    check (status in ('pending','printed','placed','validated','rejected')),
  printed_at        timestamptz,
  printed_by        uuid references public.employees(id) on delete set null,
  placed_at         timestamptz,
  placed_by         uuid references public.employees(id) on delete set null,
  validated_at      timestamptz,
  validated_by      uuid references public.employees(id) on delete set null,
  rejection_reason  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Lotes con fecha de caducidad (módulo Caducidades).
create table if not exists public.product_expirations (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  product_id       uuid not null references public.products(id) on delete cascade,
  lot              text,
  quantity         numeric(12,3) not null default 0 check (quantity >= 0),
  expiration_date  date not null,
  status           text not null default 'active'
                   check (status in ('active','markdown','withdrawn','expired','sold_out')),
  action_notes     text,
  source_type      text,                       -- 'receiving_item' si vino de un recibo
  source_id        uuid,
  registered_by    uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CHECKLISTS / BITÁCORAS
--   templates → questions        (qué se pregunta)
--   runs      → answers          (la ejecución de un día y sus respuestas)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.checklist_templates (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references public.companies(id) on delete cascade,
  department_id      uuid references public.departments(id) on delete set null,
  title              text not null,
  description        text,
  shift              text not null default 'apertura'
                     check (shift in ('apertura','manana','tarde','cierre','nocturno','especial')),
  start_time         time not null default '07:00',
  end_time           time not null default '09:00',
  frequency          text not null default 'daily' check (frequency in ('daily','weekdays','weekly')),
  weekday            smallint check (weekday between 0 and 6), -- para 'weekly' (0 = domingo)
  requires_evidence  boolean not null default false,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (end_time > start_time)
);

create table if not exists public.checklist_questions (
  id              uuid primary key default gen_random_uuid(),
  template_id     uuid not null references public.checklist_templates(id) on delete cascade,
  position        integer not null default 1,
  text            text not null,
  answer_type     text not null default 'yes_no'
                  check (answer_type in ('yes_no','text','number','option','photo','signature')),
  options         jsonb,                       -- para 'option': ["A","B","C"]
  is_required     boolean not null default true,
  requires_photo  boolean not null default false,
  is_active       boolean not null default true, -- se desactiva en vez de borrar (conserva historial)
  created_at      timestamptz not null default now()
);

create table if not exists public.checklist_runs (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  template_id      uuid not null references public.checklist_templates(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete set null,
  scheduled_date   date not null,
  scheduled_start  time not null,
  scheduled_end    time not null,
  status           text not null default 'pending'
                   check (status in ('pending','in_progress','completed','overdue','reopened','cancelled')),
  started_at       timestamptz,
  started_by       uuid references public.employees(id) on delete set null,
  completed_at     timestamptz,
  completed_by     uuid references public.employees(id) on delete set null,
  review_status    text check (review_status in ('pending_review','approved','rejected','correction_required')),
  reviewed_by      uuid references public.employees(id) on delete set null,
  reviewed_at      timestamptz,
  review_comment   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (template_id, branch_id, scheduled_date)
);

create table if not exists public.checklist_answers (
  id             uuid primary key default gen_random_uuid(),
  run_id         uuid not null references public.checklist_runs(id) on delete cascade,
  question_id    uuid not null references public.checklist_questions(id) on delete cascade,
  answer_value   text,                         -- 'yes' | 'no' | 'na' | texto | número | opción
  comment        text,
  answered_by    uuid references public.employees(id) on delete set null,
  answered_at    timestamptz not null default now(),
  unique (run_id, question_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. EVIDENCIAS (archivo en Storage + metadatos aquí)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.evidence_files (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  branch_id       uuid references public.branches(id) on delete set null,
  entity_type     text not null check (entity_type in (
                    'checklist_answer','task','receiving_order','price_change','shelf_tag',
                    'order','expiration','support_ticket','product','supplier_visit','other')),
  entity_id       uuid,
  storage_path    text not null,               -- ruta dentro del bucket 'evidence'
  file_name       text,
  mime_type       text,
  size_bytes      bigint,
  description     text,
  status          text not null default 'pending'
                  check (status in ('pending','approved','rejected','correction_required')),
  uploaded_by     uuid references public.employees(id) on delete set null,
  reviewed_by     uuid references public.employees(id) on delete set null,
  reviewed_at     timestamptz,
  review_comment  text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists evidence_entity_idx on public.evidence_files (entity_type, entity_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. PEDIDOS INTERNOS
-- Flujo: requested → in_review → approved | rejected
--        approved → sent → received → closed ;  requested → cancelled
-- ─────────────────────────────────────────────────────────────────────────────

create sequence if not exists public.order_folio_seq;

create table if not exists public.orders (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  branch_id      uuid not null references public.branches(id) on delete cascade,
  department_id  uuid references public.departments(id) on delete set null,
  folio          text not null default ('PED-' || lpad(nextval('public.order_folio_seq')::text, 6, '0')),
  title          text not null,
  status         text not null default 'requested'
                 check (status in ('requested','in_review','approved','rejected','sent','received','closed','cancelled')),
  priority       text not null default 'medium' check (priority in ('low','medium','high','critical')),
  requested_by   uuid references public.employees(id) on delete set null,
  approved_by    uuid references public.employees(id) on delete set null,
  approved_at    timestamptz,
  status_comment text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (company_id, folio)
);

create table if not exists public.order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  product_id    uuid not null references public.products(id),
  quantity      numeric(12,3) not null check (quantity > 0),
  received_qty  numeric(12,3) check (received_qty is null or received_qty >= 0),
  notes         text
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. TAREAS OPERATIVAS
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.tasks (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references public.companies(id) on delete cascade,
  branch_id          uuid not null references public.branches(id) on delete cascade,
  department_id      uuid references public.departments(id) on delete set null,
  title              text not null,
  description        text,
  assigned_to        uuid references public.employees(id) on delete set null,
  created_by         uuid references public.employees(id) on delete set null,
  due_date           date,
  priority           text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status             text not null default 'pending' check (status in ('pending','in_progress','completed','cancelled')),
  requires_evidence  boolean not null default false,
  completed_at       timestamptz,
  completion_notes   text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. MESA DE AYUDA (tipo osTicket) — soporte interno de la plataforma
-- Flujo: open → in_progress ⇄ waiting_user → resolved → closed (reabrir → open)
-- ─────────────────────────────────────────────────────────────────────────────

create sequence if not exists public.ticket_folio_seq;

create table if not exists public.support_tickets (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references public.companies(id) on delete cascade,
  branch_id          uuid references public.branches(id) on delete set null,
  folio              text not null default ('TCK-' || lpad(nextval('public.ticket_folio_seq')::text, 6, '0')),
  subject            text not null,
  description        text not null,
  category           text not null default 'bug'
                     check (category in ('bug','access','data','feature','training','hardware','other')),
  module             text,                     -- módulo de la app afectado
  priority           text not null default 'medium' check (priority in ('low','medium','high','critical')),
  status             text not null default 'open'
                     check (status in ('open','in_progress','waiting_user','resolved','closed')),
  created_by         uuid references public.employees(id) on delete set null,
  assigned_to        uuid references public.employees(id) on delete set null,
  first_response_at  timestamptz,
  resolved_at        timestamptz,
  closed_at          timestamptz,
  satisfaction       smallint check (satisfaction between 1 and 5), -- calificación del usuario
  page_url           text,                     -- dónde estaba el usuario al reportar
  user_agent         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (company_id, folio)
);

create table if not exists public.support_ticket_messages (
  id           uuid primary key default gen_random_uuid(),
  ticket_id    uuid not null references public.support_tickets(id) on delete cascade,
  author_id    uuid references public.employees(id) on delete set null,
  body         text not null,
  is_internal  boolean not null default false, -- nota interna: solo la ve soporte
  created_at   timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. NOTIFICACIONES Y AUDITORÍA
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.notifications (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id) on delete cascade,
  employee_id  uuid not null references public.employees(id) on delete cascade,
  type         text not null default 'info',   -- task, order, ticket, checklist, evidence...
  title        text not null,
  body         text,
  link         text,                           -- ruta del frontend, ej. '/tasks'
  is_read      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists notifications_employee_idx on public.notifications (employee_id, is_read, created_at desc);

-- Historial de acciones (lo llena un trigger genérico, ver 0003).
create table if not exists public.audit_logs (
  id            bigint generated always as identity primary key,
  company_id    uuid,
  table_name    text not null,
  record_id     text,
  action        text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data      jsonb,
  new_data      jsonb,
  performed_by  uuid,                          -- employees.id
  performed_at  timestamptz not null default now()
);
create index if not exists audit_logs_company_idx on public.audit_logs (company_id, performed_at desc);

-- Índices de apoyo para filtros frecuentes.
create index if not exists employees_company_idx     on public.employees (company_id, branch_id);
create index if not exists inventory_branch_idx      on public.inventory (branch_id, status);
create index if not exists checklist_runs_date_idx   on public.checklist_runs (branch_id, scheduled_date);
create index if not exists tasks_assignee_idx        on public.tasks (assigned_to, status);
create index if not exists orders_branch_idx         on public.orders (branch_id, status);
create index if not exists shelf_tags_branch_idx     on public.shelf_tags (branch_id, status);
create index if not exists tickets_company_idx       on public.support_tickets (company_id, status);
create index if not exists expirations_branch_idx    on public.product_expirations (branch_id, expiration_date);
