-- =============================================================================
-- OPERALIA · instalacion-limpia.sql — INSTALACIÓN PARA PRODUCCIÓN, SIN DATOS DEMO (pegar y ejecutar en SQL Editor)
-- Generado por supabase/build-pendiente.mjs a partir de migrations/*, seed/*.
-- No lo edites a mano: cambia los archivos fuente y vuelve a generarlo.
-- Es re-ejecutable: no duplica datos ni borra lo ya instalado.
-- =============================================================================

-- ─── PASO 0 · LIMPIEZA DEL ESQUEMA DEL PROTOTIPO ANTERIOR ────────────────────
-- El proyecto tenía 13 tablas de un prototipo con columnas incompatibles
-- (p. ej. employees sin username / user_id). Solo se eliminan si se detecta
-- ese esquema viejo; si ya está instalado Operalia, este paso no hace nada.
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'employees')
     and not exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'employees' and column_name = 'username') then
    raise notice 'Esquema anterior detectado: se eliminan las tablas del prototipo';
    drop table if exists
      public.audit_logs, public.notifications, public.evidence_files,
      public.checklist_answers, public.checklist_runs, public.checklist_questions,
      public.checklist_templates, public.employees, public.role_permissions,
      public.roles, public.permissions, public.departments, public.branches,
      public.companies
    cascade;
  end if;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0001_esquema_tablas.sql <<<<<<<<<<<<<<<<
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


-- >>>>>>>>>>>>>>>> migrations/0002_funciones_seguridad.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0002 · FUNCIONES AUXILIARES DE SEGURIDAD
-- -----------------------------------------------------------------------------
-- Objetivo: responder "¿quién es el usuario que hace la petición?" y "¿qué
-- puede ver/hacer?". Las usan las políticas RLS (0005), los triggers (0003) y
-- el frontend (vía supabase.rpc).
--
-- Todas son SECURITY DEFINER: se ejecutan con permisos del dueño para poder
-- leer employees/roles sin caer en recursión de RLS. Solo devuelven datos del
-- propio usuario (auth.uid()), así que no filtran información de otros.
--
-- auth.uid() es NULL cuando el SQL se ejecuta desde el SQL Editor / service
-- role (por ejemplo, al sembrar datos). Los triggers usan eso para saber que
-- están en "modo sistema" y no validar permisos.
-- =============================================================================

-- Empleado activo ligado a la sesión actual.
create or replace function public.auth_employee_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_company_id()
returns uuid language sql stable security definer set search_path = public as $$
  select company_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_branch_id()
returns uuid language sql stable security definer set search_path = public as $$
  select branch_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

create or replace function public.auth_department_id()
returns uuid language sql stable security definer set search_path = public as $$
  select department_id from public.employees where user_id = auth.uid() and status = 'active' limit 1
$$;

-- Alcance del rol: 'company' | 'branch' | 'department' | 'self'.
create or replace function public.auth_role_scope()
returns text language sql stable security definer set search_path = public as $$
  select r.scope
  from public.employees e join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_code()
returns text language sql stable security definer set search_path = public as $$
  select r.code
  from public.employees e join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

-- Permisos efectivos = permisos del rol + concedidos al empleado − revocados.
create or replace function public.my_permissions()
returns setof text language sql stable security definer set search_path = public as $$
  with me as (
    select e.id, e.role_id from public.employees e
    where e.user_id = auth.uid() and e.status = 'active' limit 1
  )
  select rp.permission_code from public.role_permissions rp join me on me.role_id = rp.role_id
  where not exists (
    select 1 from public.employee_permissions ep
    where ep.employee_id = (select id from me)
      and ep.permission_code = rp.permission_code and not ep.is_granted)
  union
  select ep.permission_code from public.employee_permissions ep join me on me.id = ep.employee_id
  where ep.is_granted
$$;

create or replace function public.has_permission(p_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.my_permissions() as perm where perm = p_code)
$$;

-- ¿Puede ver datos de esta sucursal?
--   company → cualquier sucursal de su empresa; demás → solo la suya.
create or replace function public.can_access_branch(p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_branch_id is null then false
    when public.auth_role_scope() = 'company' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id())
    else p_branch_id = public.auth_branch_id()
  end
$$;

-- ¿Puede ver datos de este departamento en esta sucursal?
--   company/branch → basta con la sucursal.
--   department/self → su departamento o los asignados en employee_departments.
--   department_id null (registro general de la sucursal) → visible para la sucursal.
create or replace function public.can_access_department(p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when not public.can_access_branch(p_branch_id) then false
    when public.auth_role_scope() in ('company','branch') then true
    when p_department_id is null then true
    when p_department_id = public.auth_department_id() then true
    else exists (
      select 1 from public.employee_departments ed
      where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id)
  end
$$;

-- "Hoy" según la zona horaria de la empresa (evita desfases UTC en checklists).
create or replace function public.company_today(p_company_id uuid default null)
returns date language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce(
    (select timezone from public.companies where id = coalesce(p_company_id, public.auth_company_id())),
    'America/Tijuana'))::date
$$;

-- Perfil completo para el frontend en una sola llamada (supabase.rpc('get_my_profile')).
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;

-- Solo usuarios autenticados pueden llamar estas funciones vía API.
do $$
declare fn text;
begin
  foreach fn in array array[
    'auth_employee_id()','auth_company_id()','auth_branch_id()','auth_department_id()',
    'auth_role_scope()','auth_role_code()','my_permissions()','has_permission(text)',
    'can_access_branch(uuid)','can_access_department(uuid, uuid)','company_today(uuid)',
    'get_my_profile()']
  loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Valores por defecto: company_id se llena solo con la empresa del usuario.
-- Así el frontend no tiene que enviarla (y RLS verifica que sea la suya).
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_name = c.table_name and tb.table_schema = c.table_schema
    where c.table_schema = 'public' and c.column_name = 'company_id'
      and tb.table_type = 'BASE TABLE' and c.table_name not in ('companies','audit_logs')
  loop
    execute format('alter table public.%I alter column company_id set default public.auth_company_id()', t);
  end loop;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0003_triggers_logica.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0003 · TRIGGERS Y LÓGICA DE NEGOCIO
-- -----------------------------------------------------------------------------
-- Objetivo: que las reglas críticas vivan en la base de datos y no dependan
-- del frontend (si alguien llama la API directo, las reglas se siguen
-- cumpliendo). Contenido:
--
--   A. Utilidades genéricas  (updated_at, actor, contexto de sistema, notificar)
--   B. Inventario            (status automático, aplicar movimientos)
--   C. Recibo de mercancía   (cierre → totales + inventario + caducidades)
--   D. Precios y cenefas     (cambio de precio → actualiza producto → cenefa)
--   E. Caducidades           (marcar vencidos)
--   F. Checklists            (inicio, cierre con validación, revisión, reapertura)
--   G. Evidencias            (revisión)
--   H. Pedidos internos      (flujo de estados)
--   I. Tareas                (evidencia obligatoria, solo-estado para asignados)
--   J. Mesa de ayuda         (estados, primera respuesta, notas internas)
--   K. Empleados             (anti escalamiento de privilegios, ligar cuenta Auth)
--   L. Auditoría             (audit_logs)
--   M. Mantenimiento diario  (RPC run_daily_maintenance)
-- =============================================================================

-- ═════════════════════════════════════════════════════════════════════════════
-- A. UTILIDADES GENÉRICAS
-- ═════════════════════════════════════════════════════════════════════════════

-- "Modo sistema": SQL Editor / service role (sin usuario) o una función interna
-- que activó la bandera operalia.bypass para actualizar filas en cascada.
create or replace function public.is_system_context()
returns boolean language sql stable as $$
  select auth.uid() is null or coalesce(current_setting('operalia.bypass', true), '') = 'on'
$$;

-- Activa/restaura la bandera. Devuelve el valor anterior para poder
-- restaurarlo (las funciones pueden anidarse).
create or replace function public.set_bypass(p_value text)
returns text language plpgsql as $$
declare v_prev text := coalesce(current_setting('operalia.bypass', true), '');
begin
  perform set_config('operalia.bypass', coalesce(p_value, ''), true);
  return v_prev;
end $$;
revoke all on function public.set_bypass(text) from public, anon, authenticated;

-- updated_at = now() en cada UPDATE.
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Rellena la columna indicada (TG_ARGV[0]) con el empleado que hace la
-- petición. Evita que el cliente "firme" a nombre de otro.
create or replace function public.tg_set_actor()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], public.auth_employee_id()));
  end if;
  return new;
end $$;

-- Inserta una notificación para un empleado.
create or replace function public.notify_employee(
  p_employee_id uuid, p_type text, p_title text, p_body text default null, p_link text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_employee_id is null then return; end if;
  insert into public.notifications (company_id, employee_id, type, title, body, link)
  select e.company_id, e.id, p_type, p_title, p_body, p_link
  from public.employees e where e.id = p_employee_id and e.status = 'active';
end $$;
revoke all on function public.notify_employee(uuid, text, text, text, text) from public, anon, authenticated;

-- Trigger updated_at en todas las tablas que tengan esa columna.
do $$
declare t text;
begin
  for t in
    select c.table_name from information_schema.columns c
    join information_schema.tables tb on tb.table_name = c.table_name and tb.table_schema = c.table_schema
    where c.table_schema = 'public' and c.column_name = 'updated_at' and tb.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists trg_updated_at on public.%I', t);
    execute format('create trigger trg_updated_at before update on public.%I
                    for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;

-- Columnas "firmadas" automáticamente al insertar.
do $$
declare r record;
begin
  for r in select * from (values
    ('inventory_movements','created_by'), ('supplier_visits','registered_by'),
    ('receiving_orders','received_by'),   ('price_changes','created_by'),
    ('product_expirations','registered_by'), ('evidence_files','uploaded_by'),
    ('orders','requested_by'),            ('tasks','created_by'),
    ('support_tickets','created_by'),     ('support_ticket_messages','author_id'),
    ('checklist_answers','answered_by')
  ) as v(tbl, col)
  loop
    execute format('drop trigger if exists trg_actor on public.%I', r.tbl);
    execute format('create trigger trg_actor before insert on public.%I
                    for each row execute function public.tg_set_actor(%L)', r.tbl, r.col);
  end loop;
end $$;

-- product_barcodes hereda la empresa del producto (útil al sembrar datos).
create or replace function public.tg_barcode_company()
returns trigger language plpgsql as $$
begin
  if new.company_id is null then
    select company_id into new.company_id from public.products where id = new.product_id;
  end if;
  return new;
end $$;
drop trigger if exists trg_barcode_company on public.product_barcodes;
create trigger trg_barcode_company before insert on public.product_barcodes
  for each row execute function public.tg_barcode_company();

-- ═════════════════════════════════════════════════════════════════════════════
-- B. INVENTARIO
-- ═════════════════════════════════════════════════════════════════════════════

-- Estado del inventario según existencia vs mínimo:
--   stock <= 0           → out_of_stock (sin existencia)
--   stock <= 50% mínimo  → critical
--   stock <= mínimo      → low
--   si no                → normal   ('review' solo se asigna manualmente)
create or replace function public.tg_inventory_status()
returns trigger language plpgsql as $$
begin
  -- Respeta "pendiente de revisión" (asignado a mano) mientras no cambie el stock.
  if new.status = 'review' then
    if tg_op = 'INSERT' then return new; end if;
    if new.stock = old.stock then return new; end if;
  end if;
  new.status := case
    when new.stock <= 0                       then 'out_of_stock'
    when new.stock <= new.min_stock * 0.5     then 'critical'
    when new.stock <= new.min_stock           then 'low'
    else 'normal'
  end;
  return new;
end $$;
drop trigger if exists trg_inventory_status on public.inventory;
create trigger trg_inventory_status before insert or update on public.inventory
  for each row execute function public.tg_inventory_status();

-- Aplica un movimiento al stock. Bloquea la fila (FOR UPDATE) para evitar
-- carreras si dos personas registran al mismo tiempo. Guarda stock antes/después.
-- No permite dejar stock negativo.
create or replace function public.tg_apply_inventory_movement()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_inv public.inventory%rowtype;
  v_new numeric;
begin
  if new.company_id is null then
    select company_id into new.company_id from public.branches where id = new.branch_id;
  end if;

  select * into v_inv from public.inventory
  where branch_id = new.branch_id and product_id = new.product_id
  for update;

  if not found then
    insert into public.inventory (company_id, branch_id, product_id, stock)
    values (new.company_id, new.branch_id, new.product_id, 0)
    returning * into v_inv;
  end if;

  v_new := case new.movement_type
    when 'count' then new.quantity
    when 'in' then v_inv.stock + new.quantity
    when 'adjustment_in' then v_inv.stock + new.quantity
    when 'receiving' then v_inv.stock + new.quantity
    when 'return' then v_inv.stock + new.quantity
    when 'transfer_in' then v_inv.stock + new.quantity
    else v_inv.stock - new.quantity   -- out, adjustment_out, waste, transfer_out
  end;

  if v_new < 0 then
    raise exception 'Stock insuficiente: existencia actual %, se intentó retirar %', v_inv.stock, new.quantity
      using errcode = 'P0001';
  end if;

  new.stock_before := v_inv.stock;
  new.stock_after  := v_new;

  update public.inventory
     set stock = v_new,
         last_movement_at = now(),
         last_counted_at = case when new.movement_type = 'count' then now() else last_counted_at end
   where id = v_inv.id;

  return new;
end $$;
drop trigger if exists trg_apply_movement on public.inventory_movements;
create trigger trg_apply_movement before insert on public.inventory_movements
  for each row execute function public.tg_apply_inventory_movement();

-- ═════════════════════════════════════════════════════════════════════════════
-- C. RECIBO DE MERCANCÍA
-- ═════════════════════════════════════════════════════════════════════════════

-- Antes de actualizar el encabezado: un recibo cerrado ya no se modifica; al
-- cerrarlo se valida permiso, que tenga productos y se calculan totales.
create or replace function public.tg_receiving_before_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if old.status <> 'in_progress' and not public.is_system_context() then
    raise exception 'El recibo % ya está %, no se puede modificar', old.folio,
      case old.status when 'completed' then 'cerrado' else 'cancelado' end;
  end if;

  if new.status = 'completed' and old.status <> 'completed' then
    if not public.is_system_context() and not public.has_permission('close_receiving') then
      raise exception 'No tienes permiso para cerrar recibos';
    end if;

    select count(*),
           coalesce(sum(expected_qty),0), coalesce(sum(received_qty),0), coalesce(sum(damaged_qty),0),
           bool_or(received_qty <> expected_qty or damaged_qty > 0)
      into v_count, new.total_expected, new.total_received, new.total_damaged, new.has_differences
      from public.receiving_items where receiving_order_id = new.id;

    if v_count = 0 then
      raise exception 'No se puede cerrar un recibo sin productos';
    end if;

    new.total_items     := v_count;
    new.has_differences := coalesce(new.has_differences, false);
    new.completed_at    := now();
    new.completed_by    := coalesce(public.auth_employee_id(), new.completed_by);
  end if;
  return new;
end $$;
drop trigger if exists trg_receiving_before_update on public.receiving_orders;
create trigger trg_receiving_before_update before update on public.receiving_orders
  for each row execute function public.tg_receiving_before_update();

-- Después de cerrar: cada producto recibido (menos dañado) entra al inventario
-- y, si trae caducidad, se registra el lote en Caducidades.
create or replace function public.tg_receiving_after_complete()
returns trigger language plpgsql security definer set search_path = public as $$
declare it record;
begin
  if new.status = 'completed' and old.status <> 'completed' then
    for it in select * from public.receiving_items where receiving_order_id = new.id loop
      if it.received_qty - it.damaged_qty > 0 then
        insert into public.inventory_movements
          (company_id, branch_id, product_id, movement_type, quantity, reference_type, reference_id, reason, created_by)
        values
          (new.company_id, new.branch_id, it.product_id, 'receiving', it.received_qty - it.damaged_qty,
           'receiving_order', new.id, 'Recibo ' || new.folio, new.completed_by);
      end if;
      if it.damaged_qty > 0 then
        -- Registro informativo: lo dañado no entra a stock (cantidad 0, razón explica).
        null;
      end if;
      if it.expiration_date is not null then
        insert into public.product_expirations
          (company_id, branch_id, product_id, lot, quantity, expiration_date, source_type, source_id, registered_by)
        values
          (new.company_id, new.branch_id, it.product_id, it.lot, it.received_qty - it.damaged_qty,
           it.expiration_date, 'receiving_item', it.id, new.completed_by);
      end if;
    end loop;
  end if;
  return null;
end $$;
drop trigger if exists trg_receiving_after_complete on public.receiving_orders;
create trigger trg_receiving_after_complete after update on public.receiving_orders
  for each row execute function public.tg_receiving_after_complete();

-- Los renglones solo se editan mientras el recibo esté abierto.
create or replace function public.tg_receiving_items_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.receiving_orders
  where id = coalesce(new.receiving_order_id, old.receiving_order_id);
  if v_status <> 'in_progress' and not public.is_system_context() then
    raise exception 'El recibo ya no está abierto; no se pueden modificar sus productos';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists trg_receiving_items_guard on public.receiving_items;
create trigger trg_receiving_items_guard before insert or update or delete on public.receiving_items
  for each row execute function public.tg_receiving_items_guard();

-- ═════════════════════════════════════════════════════════════════════════════
-- D. CAMBIOS DE PRECIO Y CENEFAS
-- ═════════════════════════════════════════════════════════════════════════════

-- Aplica un cambio: actualiza el producto, marca el cambio como aplicado y
-- genera cenefas pendientes (sustituye las que seguían pendientes).
create or replace function public.apply_price_change(p_price_change_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  pc     public.price_changes%rowtype;
  v_prev text;
begin
  select * into pc from public.price_changes where id = p_price_change_id for update;
  if not found or pc.status <> 'scheduled' then return; end if;

  v_prev := public.set_bypass('on');

  update public.products
     set previous_price = price, price = pc.new_price, price_updated_at = now()
   where id = pc.product_id;

  update public.price_changes set status = 'applied', applied_at = now() where id = pc.id;

  if pc.requires_tag then
    -- Cenefas anteriores sin colocar quedan obsoletas.
    update public.shelf_tags
       set status = 'rejected', rejection_reason = 'Reemplazada por un cambio de precio más reciente'
     where product_id = pc.product_id and status in ('pending','printed')
       and (pc.branch_id is null or branch_id = pc.branch_id);

    insert into public.shelf_tags (company_id, branch_id, product_id, price_change_id)
    select pc.company_id, b.id, pc.product_id, pc.id
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and (pc.branch_id is null or b.id = pc.branch_id);
  end if;

  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.apply_price_change(uuid) from public, anon, authenticated;

create or replace function public.tg_price_change_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select price into new.old_price from public.products where id = new.product_id;
  if new.old_price is null then raise exception 'Producto no encontrado'; end if;
  if new.new_price = new.old_price then
    raise exception 'El precio nuevo es igual al actual (%)', new.old_price;
  end if;
  new.status := 'scheduled';
  new.applied_at := null;
  return new;
end $$;
drop trigger if exists trg_price_change_before_insert on public.price_changes;
create trigger trg_price_change_before_insert before insert on public.price_changes
  for each row execute function public.tg_price_change_before_insert();

create or replace function public.tg_price_change_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.effective_date <= public.company_today(new.company_id) then
    perform public.apply_price_change(new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_price_change_after_insert on public.price_changes;
create trigger trg_price_change_after_insert after insert on public.price_changes
  for each row execute function public.tg_price_change_after_insert();

-- Flujo de la cenefa. Validar requiere permiso validate_shelf_tags.
create or replace function public.tg_shelf_tag_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_actor uuid := public.auth_employee_id();
begin
  if new.status = old.status or public.is_system_context() then return new; end if;

  if not (
       (old.status = 'pending'  and new.status in ('printed','rejected'))
    or (old.status = 'printed'  and new.status in ('placed','rejected'))
    or (old.status = 'placed'   and new.status in ('validated','rejected'))
    or (old.status = 'rejected' and new.status = 'pending')
  ) then
    raise exception 'Transición de cenefa no permitida: % → %', old.status, new.status;
  end if;

  if new.status = 'validated' and not public.has_permission('validate_shelf_tags') then
    raise exception 'No tienes permiso para validar cenefas';
  end if;

  case new.status
    when 'printed'   then new.printed_at := now();   new.printed_by := v_actor;
    when 'placed'    then new.placed_at := now();    new.placed_by := v_actor;
    when 'validated' then new.validated_at := now(); new.validated_by := v_actor;
    when 'pending'   then new.printed_at := null; new.placed_at := null; new.rejection_reason := null;
    else null;
  end case;
  return new;
end $$;
drop trigger if exists trg_shelf_tag_flow on public.shelf_tags;
create trigger trg_shelf_tag_flow before update on public.shelf_tags
  for each row execute function public.tg_shelf_tag_flow();

-- ═════════════════════════════════════════════════════════════════════════════
-- E. CADUCIDADES
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_expiration_status()
returns trigger language plpgsql as $$
begin
  if new.status = 'active' and new.expiration_date < public.company_today(new.company_id) then
    new.status := 'expired';
  end if;
  return new;
end $$;
drop trigger if exists trg_expiration_status on public.product_expirations;
create trigger trg_expiration_status before insert or update on public.product_expirations
  for each row execute function public.tg_expiration_status();

-- ═════════════════════════════════════════════════════════════════════════════
-- F. CHECKLISTS
-- ═════════════════════════════════════════════════════════════════════════════

-- Solo se responde si la ejecución está abierta.
create or replace function public.tg_checklist_answer_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.checklist_runs where id = new.run_id;
  if v_status not in ('pending','in_progress','reopened') and not public.is_system_context() then
    raise exception 'Este checklist está % y ya no acepta respuestas',
      case v_status when 'completed' then 'completado' when 'overdue' then 'vencido' else v_status end;
  end if;
  new.answered_at := now();
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.answered_by := public.auth_employee_id();
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_answer_guard on public.checklist_answers;
create trigger trg_checklist_answer_guard before insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_guard();

-- Primera respuesta → la ejecución pasa a "en progreso".
create or replace function public.tg_checklist_answer_after()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.checklist_runs
     set status = 'in_progress'
   where id = new.run_id and status in ('pending','reopened');
  return null;
end $$;
drop trigger if exists trg_checklist_answer_after on public.checklist_answers;
create trigger trg_checklist_answer_after after insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_after();

-- Reglas de la ejecución:
--   * vencido → solo se puede reabrir (con review_checklists) o cancelar
--   * completar exige todas las obligatorias respondidas y las fotos requeridas
--   * revisar exige review_checklists; "corrección requerida" reabre el checklist
create or replace function public.tg_checklist_run_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor   uuid := public.auth_employee_id();
  v_system  boolean := public.is_system_context();
  v_missing int;
begin
  -- Reapertura de vencidos
  if old.status = 'overdue' and new.status <> 'overdue' then
    if new.status not in ('reopened','cancelled') then
      raise exception 'Un checklist vencido primero debe reabrirse';
    end if;
    if not v_system and not public.has_permission('review_checklists') then
      raise exception 'No tienes permiso para reabrir checklists vencidos';
    end if;
  end if;

  -- Revisión del supervisor / gerente
  if new.review_status is distinct from old.review_status
     and new.review_status in ('approved','rejected','correction_required') then
    if old.status <> 'completed' then
      raise exception 'Solo se pueden revisar checklists completados';
    end if;
    if not v_system and not public.has_permission('review_checklists') then
      raise exception 'No tienes permiso para revisar checklists';
    end if;
    if not v_system and v_actor = old.completed_by then
      raise exception 'No puedes revisar un checklist que tú mismo completaste';
    end if;
    new.reviewed_by := coalesce(v_actor, new.reviewed_by);
    new.reviewed_at := now();
    if new.review_status = 'correction_required' then
      new.status := 'reopened';
    end if;
  elsif old.status = 'completed' and new.status <> 'completed' and not v_system then
    raise exception 'Un checklist completado solo cambia mediante revisión';
  end if;

  -- Inicio
  if new.status = 'in_progress' and old.status in ('pending','reopened') then
    new.started_at := coalesce(old.started_at, now());
    new.started_by := coalesce(old.started_by, v_actor);
  end if;

  -- Cierre con validaciones
  if new.status = 'completed' and old.status <> 'completed' then
    if old.status not in ('pending','in_progress','reopened') then
      raise exception 'No se puede completar un checklist %', old.status;
    end if;

    select count(*) into v_missing
    from public.checklist_questions q
    where q.template_id = new.template_id and q.is_required and q.is_active
      and not exists (
        select 1 from public.checklist_answers a
        where a.run_id = new.id and a.question_id = q.id and coalesce(trim(a.answer_value), '') <> '');
    if v_missing > 0 then
      raise exception 'Faltan % pregunta(s) obligatoria(s) por responder', v_missing;
    end if;

    select count(*) into v_missing
    from public.checklist_questions q
    where q.template_id = new.template_id and q.requires_photo and q.is_active
      and not exists (
        select 1 from public.checklist_answers a
        join public.evidence_files ev on ev.entity_type = 'checklist_answer' and ev.entity_id = a.id
        where a.run_id = new.id and a.question_id = q.id);
    if v_missing > 0 then
      raise exception 'Falta evidencia fotográfica en % pregunta(s)', v_missing;
    end if;

    new.completed_at   := now();
    new.completed_by   := coalesce(v_actor, new.completed_by);
    new.review_status  := 'pending_review';
    new.reviewed_by    := null;
    new.reviewed_at    := null;
  end if;

  return new;
end $$;
drop trigger if exists trg_checklist_run_rules on public.checklist_runs;
create trigger trg_checklist_run_rules before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_rules();

-- Avisar a quien completó si su checklist fue rechazado o requiere corrección.
create or replace function public.tg_checklist_run_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_title text;
begin
  if new.review_status is distinct from old.review_status
     and new.review_status in ('rejected','correction_required') then
    select title into v_title from public.checklist_templates where id = new.template_id;
    perform public.notify_employee(new.completed_by, 'checklist',
      case new.review_status when 'rejected' then 'Checklist rechazado' else 'Checklist requiere corrección' end,
      v_title || coalesce(': ' || new.review_comment, ''), '/checklists');
  end if;
  return null;
end $$;
drop trigger if exists trg_checklist_run_notify on public.checklist_runs;
create trigger trg_checklist_run_notify after update on public.checklist_runs
  for each row execute function public.tg_checklist_run_notify();

-- Genera las ejecuciones del día para cada plantilla activa × sucursal activa.
-- Idempotente (unique template+branch+date).
create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end)
  select t.company_id, t.id, b.id, t.department_id, p_date, t.start_time, t.end_time
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  where t.company_id = p_company_id and t.is_active
    -- Las rondas de un día se generan juntas; si ya hay corridas de ese día no se agregan más
    -- (así cambiar la hora o la repetición de una plantilla aplica desde el día siguiente).
    and not exists (select 1 from public.checklist_runs x
                    where x.template_id = t.id and x.branch_id = b.id and x.scheduled_date = p_date)
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;
revoke all on function public.generate_checklist_runs(uuid, date) from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- G. EVIDENCIAS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_evidence_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.branch_id := coalesce(new.branch_id, public.auth_branch_id());
    new.status := 'pending';
    return new;
  end if;

  if new.status is distinct from old.status and not public.is_system_context() then
    if not public.has_permission('review_evidence') then
      raise exception 'No tienes permiso para revisar evidencias';
    end if;
    if public.auth_employee_id() = old.uploaded_by then
      raise exception 'No puedes revisar tu propia evidencia';
    end if;
    new.reviewed_by := public.auth_employee_id();
    new.reviewed_at := now();
  end if;
  return new;
end $$;
drop trigger if exists trg_evidence_rules on public.evidence_files;
create trigger trg_evidence_rules before insert or update on public.evidence_files
  for each row execute function public.tg_evidence_rules();

create or replace function public.tg_evidence_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('rejected','correction_required') then
    perform public.notify_employee(new.uploaded_by, 'evidence',
      case new.status when 'rejected' then 'Evidencia rechazada' else 'Evidencia requiere corrección' end,
      coalesce(new.review_comment, new.file_name), '/evidence');
  end if;
  return null;
end $$;
drop trigger if exists trg_evidence_notify on public.evidence_files;
create trigger trg_evidence_notify after update on public.evidence_files
  for each row execute function public.tg_evidence_notify();

-- ═════════════════════════════════════════════════════════════════════════════
-- H. PEDIDOS INTERNOS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_order_flow()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_actor     uuid := public.auth_employee_id();
  v_approver  boolean;
  v_requester boolean;
begin
  if public.is_system_context() then return new; end if;
  v_approver  := public.has_permission('approve_orders');
  v_requester := v_actor = old.requested_by;

  if new.status is distinct from old.status then
    if not (
         (old.status = 'requested' and new.status in ('in_review','approved','rejected','cancelled'))
      or (old.status = 'in_review' and new.status in ('approved','rejected'))
      or (old.status = 'approved'  and new.status in ('sent','cancelled'))
      or (old.status = 'sent'      and new.status = 'received')
      or (old.status = 'received'  and new.status = 'closed')
    ) then
      raise exception 'Transición de pedido no permitida: % → %', old.status, new.status;
    end if;

    if new.status in ('in_review','approved','rejected','sent') and not v_approver then
      raise exception 'Solo quien aprueba pedidos puede cambiarlo a %', new.status;
    end if;
    if new.status = 'cancelled' and not (v_approver or v_requester) then
      raise exception 'Solo el solicitante o un aprobador puede cancelar el pedido';
    end if;
    if new.status in ('received','closed') and not (v_approver or v_requester) then
      raise exception 'Solo el solicitante o un aprobador puede marcarlo como %', new.status;
    end if;
    if new.status in ('approved','rejected') then
      new.approved_by := v_actor;
      new.approved_at := now();
    end if;
  elsif old.status <> 'requested' and not v_approver then
    raise exception 'El pedido ya está en proceso; no se puede editar';
  end if;
  return new;
end $$;
drop trigger if exists trg_order_flow on public.orders;
create trigger trg_order_flow before update on public.orders
  for each row execute function public.tg_order_flow();

create or replace function public.tg_order_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_label text;
begin
  if new.status is distinct from old.status and new.requested_by is distinct from public.auth_employee_id() then
    v_label := case new.status
      when 'in_review' then 'en revisión' when 'approved' then 'aprobado' when 'rejected' then 'rechazado'
      when 'sent' then 'enviado' when 'received' then 'recibido' when 'closed' then 'cerrado'
      when 'cancelled' then 'cancelado' else new.status end;
    perform public.notify_employee(new.requested_by, 'order',
      'Pedido ' || new.folio || ' ' || v_label, new.title || coalesce(' — ' || new.status_comment, ''), '/orders');
  end if;
  return null;
end $$;
drop trigger if exists trg_order_notify on public.orders;
create trigger trg_order_notify after update on public.orders
  for each row execute function public.tg_order_notify();

-- Renglones editables solo mientras el pedido está "solicitado".
create or replace function public.tg_order_items_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.orders where id = coalesce(new.order_id, old.order_id);
  if not public.is_system_context() and v_status <> 'requested'
     and not (tg_op = 'UPDATE' and v_status = 'sent') then  -- en 'sent' se captura received_qty
    raise exception 'El pedido ya no admite cambios en sus productos';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
drop trigger if exists trg_order_items_guard on public.order_items;
create trigger trg_order_items_guard before insert or update or delete on public.order_items
  for each row execute function public.tg_order_items_guard();

-- ═════════════════════════════════════════════════════════════════════════════
-- I. TAREAS
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_task_rules()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_system_context() and not public.has_permission('manage_tasks') then
    -- El asignado solo puede mover el estado y dejar notas de cierre.
    if (to_jsonb(new) - array['status','completed_at','completion_notes','updated_at'])
       <> (to_jsonb(old) - array['status','completed_at','completion_notes','updated_at']) then
      raise exception 'Solo puedes cambiar el estado de tus tareas';
    end if;
    if new.status = 'cancelled' then
      raise exception 'Solo un supervisor puede cancelar tareas';
    end if;
  end if;

  if new.status = 'completed' and old.status <> 'completed' then
    if new.requires_evidence and not exists (
      select 1 from public.evidence_files where entity_type = 'task' and entity_id = new.id) then
      raise exception 'Esta tarea requiere evidencia antes de completarse';
    end if;
    new.completed_at := now();
  elsif new.status <> 'completed' then
    new.completed_at := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_task_rules on public.tasks;
create trigger trg_task_rules before update on public.tasks
  for each row execute function public.tg_task_rules();

create or replace function public.tg_task_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_to is not null
     and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to)
     and new.assigned_to is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.assigned_to, 'task', 'Nueva tarea asignada', new.title, '/tasks');
  end if;
  return null;
end $$;
drop trigger if exists trg_task_notify on public.tasks;
create trigger trg_task_notify after insert or update on public.tasks
  for each row execute function public.tg_task_notify();

-- ═════════════════════════════════════════════════════════════════════════════
-- J. MESA DE AYUDA (SOPORTE)
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_ticket_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_agent boolean;
begin
  if tg_op = 'INSERT' then
    new.branch_id := coalesce(new.branch_id, public.auth_branch_id());
    new.status := 'open';
    if not public.is_system_context() and not public.has_permission('manage_tickets') then
      new.assigned_to := null; -- solo soporte asigna
    end if;
    return new;
  end if;

  if not public.is_system_context() then
    v_agent := public.has_permission('manage_tickets');
    if not v_agent then
      -- El solicitante solo puede cerrar, reabrir o calificar su ticket.
      if (to_jsonb(new) - array['status','satisfaction','updated_at','resolved_at','closed_at'])
         <> (to_jsonb(old) - array['status','satisfaction','updated_at','resolved_at','closed_at']) then
        raise exception 'Solo el equipo de soporte puede editar el ticket';
      end if;
      if new.status is distinct from old.status and not (
           new.status = 'closed'
        or (old.status in ('resolved','closed') and new.status = 'open')) then
        raise exception 'Solo puedes cerrar o reabrir tu ticket';
      end if;
    end if;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'resolved' then new.resolved_at := now(); end if;
    if new.status = 'closed'   then new.closed_at := now(); new.resolved_at := coalesce(new.resolved_at, now()); end if;
    if new.status = 'open' and old.status in ('resolved','closed') then
      new.resolved_at := null; new.closed_at := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_ticket_before on public.support_tickets;
create trigger trg_ticket_before before insert or update on public.support_tickets
  for each row execute function public.tg_ticket_before();

create or replace function public.tg_ticket_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare agent record;
begin
  if tg_op = 'INSERT' then
    -- Avisar a todo el equipo de soporte de la empresa.
    for agent in
      select e.id from public.employees e
      join public.role_permissions rp on rp.role_id = e.role_id and rp.permission_code = 'manage_tickets'
      where e.company_id = new.company_id and e.status = 'active' and e.id is distinct from new.created_by
    loop
      perform public.notify_employee(agent.id, 'ticket', 'Nuevo ticket ' || new.folio, new.subject, '/support/' || new.id);
    end loop;
    return null;
  end if;

  if new.assigned_to is distinct from old.assigned_to and new.assigned_to is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.assigned_to, 'ticket', 'Ticket asignado ' || new.folio, new.subject, '/support/' || new.id);
  end if;
  if new.status is distinct from old.status and new.created_by is distinct from public.auth_employee_id() then
    perform public.notify_employee(new.created_by, 'ticket',
      'Ticket ' || new.folio || ': ' || case new.status
        when 'in_progress' then 'en atención' when 'waiting_user' then 'esperando tu respuesta'
        when 'resolved' then 'resuelto' when 'closed' then 'cerrado' else 'reabierto' end,
      new.subject, '/support/' || new.id);
  end if;
  return null;
end $$;
drop trigger if exists trg_ticket_notify on public.support_tickets;
create trigger trg_ticket_notify after insert or update on public.support_tickets
  for each row execute function public.tg_ticket_notify();

-- Mensajes: nota interna solo para soporte; no se escribe en tickets cerrados.
create or replace function public.tg_ticket_message_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.support_tickets where id = new.ticket_id;
  if v_status = 'closed' and not public.is_system_context() then
    raise exception 'El ticket está cerrado; reábrelo para responder';
  end if;
  if new.is_internal and not public.is_system_context() and not public.has_permission('manage_tickets') then
    new.is_internal := false;
  end if;
  return new;
end $$;
drop trigger if exists trg_ticket_message_before on public.support_ticket_messages;
create trigger trg_ticket_message_before before insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_before();

-- Tras un mensaje: primera respuesta, cambio de estado automático y avisos.
create or replace function public.tg_ticket_message_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t      public.support_tickets%rowtype;
  v_prev text;
begin
  select * into t from public.support_tickets where id = new.ticket_id;
  if new.is_internal then return null; end if;

  v_prev := public.set_bypass('on');
  if new.author_id is distinct from t.created_by then
    -- Respondió soporte
    update public.support_tickets
       set first_response_at = coalesce(first_response_at, now()),
           status = case when status = 'open' then 'in_progress' else status end
     where id = t.id;
    perform public.notify_employee(t.created_by, 'ticket', 'Respuesta en ' || t.folio, left(new.body, 140), '/support/' || t.id);
  else
    -- Respondió el solicitante
    update public.support_tickets
       set status = case when status in ('waiting_user','resolved') then 'in_progress' else status end
     where id = t.id;
    perform public.notify_employee(t.assigned_to, 'ticket', 'El usuario respondió ' || t.folio, left(new.body, 140), '/support/' || t.id);
  end if;
  perform public.set_bypass(v_prev);
  return null;
end $$;
drop trigger if exists trg_ticket_message_after on public.support_ticket_messages;
create trigger trg_ticket_message_after after insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_after();

-- ═════════════════════════════════════════════════════════════════════════════
-- K. EMPLEADOS Y CUENTAS
-- ═════════════════════════════════════════════════════════════════════════════

-- Evita escalamiento de privilegios:
--   * nadie cambia su propio rol, estado o sucursal
--   * solo alcance 'company' asigna roles de alcance 'company'
--   * un gerente solo gestiona empleados de su sucursal
--   * la cuenta de Auth (user_id) solo la liga el sistema
create or replace function public.tg_employee_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_target_scope text;
begin
  if public.is_system_context() then return new; end if;

  if (tg_op = 'INSERT' and new.user_id is not null)
     or (tg_op = 'UPDATE' and new.user_id is distinct from old.user_id) then
    raise exception 'La cuenta de acceso se liga automáticamente; no se puede asignar manualmente';
  end if;

  select scope into v_target_scope from public.roles where id = new.role_id and company_id = new.company_id;
  if v_target_scope is null then
    raise exception 'Rol inválido para esta empresa';
  end if;
  if v_target_scope = 'company' and public.auth_role_scope() <> 'company' then
    raise exception 'Solo un administrador puede asignar roles con alcance de empresa';
  end if;

  if tg_op = 'UPDATE' and old.user_id = auth.uid() and (
       new.role_id <> old.role_id or new.status <> old.status
    or new.branch_id is distinct from old.branch_id or new.company_id <> old.company_id) then
    raise exception 'No puedes modificar tu propio rol, estado o sucursal';
  end if;

  if public.auth_role_scope() <> 'company' and new.branch_id is distinct from public.auth_branch_id() then
    raise exception 'Solo puedes gestionar empleados de tu sucursal';
  end if;
  return new;
end $$;
drop trigger if exists trg_employee_guard on public.employees;
create trigger trg_employee_guard before insert or update on public.employees
  for each row execute function public.tg_employee_guard();

-- Cuando se crea un usuario en Supabase Auth, se liga al empleado
-- pre-registrado cuyo username coincide con la parte antes de la @.
-- Si no existe un empleado pre-registrado, la cuenta queda sin acceso.
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.employees
     set user_id = new.id,
         email = coalesce(email, new.email)
   where lower(username) = lower(split_part(new.email, '@', 1))
     and user_id is null
     and status = 'active';
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ═════════════════════════════════════════════════════════════════════════════
-- L. AUDITORÍA
-- ═════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then
    return null; -- no registrar updates sin cambios reales
  end if;
  insert into public.audit_logs (company_id, table_name, record_id, action, old_data, new_data, performed_by)
  values (
    coalesce((v_new ->> 'company_id')::uuid, (v_old ->> 'company_id')::uuid, public.auth_company_id()),
    tg_table_name,
    coalesce(v_new ->> 'id', v_old ->> 'id'),
    tg_op, v_old, v_new, public.auth_employee_id());
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'companies','branches','departments','roles','role_permissions','employees','employee_permissions',
    'products','price_changes','shelf_tags','suppliers','receiving_orders','orders',
    'tasks','checklist_templates','checklist_runs','evidence_files','product_expirations','support_tickets']
  loop
    execute format('drop trigger if exists trg_audit on public.%I', t);
    execute format('create trigger trg_audit after insert or update or delete on public.%I
                    for each row execute function public.tg_audit()', t);
  end loop;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- M. MANTENIMIENTO DIARIO (lo llama el frontend al iniciar sesión)
-- ═════════════════════════════════════════════════════════════════════════════
-- Idempotente y barato. Sin pg_cron: el primer usuario del día "despierta"
-- el proceso. Si se activa pg_cron puede programarse (ver docs/guias).
create or replace function public.run_daily_maintenance(p_company_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_company uuid := coalesce(public.auth_company_id(), p_company_id);
  v_today   date;
  v_now     time;
  v_tz      text;
  v_runs    int := 0;
  v_overdue int := 0;
  v_prices  int := 0;
  v_expired int := 0;
  v_prev    text;
  pc        record;
begin
  if v_company is null then
    raise exception 'Sin empresa asociada';
  end if;
  if auth.uid() is not null and p_company_id is not null and p_company_id <> public.auth_company_id() then
    raise exception 'No autorizado';
  end if;

  select timezone into v_tz from public.companies where id = v_company;
  v_today := (now() at time zone v_tz)::date;
  v_now   := (now() at time zone v_tz)::time;

  v_prev := public.set_bypass('on');

  v_runs := public.generate_checklist_runs(v_company, v_today);

  update public.checklist_runs
     set status = 'overdue'
   where company_id = v_company
     and status in ('pending','in_progress')
     and (scheduled_date < v_today or (scheduled_date = v_today and scheduled_end < v_now));
  get diagnostics v_overdue = row_count;

  for pc in
    select id from public.price_changes
    where company_id = v_company and status = 'scheduled' and effective_date <= v_today
  loop
    perform public.apply_price_change(pc.id);
    v_prices := v_prices + 1;
  end loop;

  update public.product_expirations
     set status = 'expired'
   where company_id = v_company and status = 'active' and expiration_date < v_today;
  get diagnostics v_expired = row_count;

  perform public.set_bypass(v_prev);

  return jsonb_build_object('date', v_today, 'runs_created', v_runs, 'runs_overdue', v_overdue,
                            'prices_applied', v_prices, 'lots_expired', v_expired);
end $$;
revoke all on function public.run_daily_maintenance(uuid) from public, anon;
grant execute on function public.run_daily_maintenance(uuid) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- N. REPORTE DE DIFERENCIA DE PRECIO (RPC)
-- ═════════════════════════════════════════════════════════════════════════════
-- Caja o piso detecta que el precio del anaquel no coincide con el sistema.
-- Crea una tarea de prioridad alta para el departamento de Escáner de la
-- sucursal, firmada por quien reporta. Así el cajero (que no puede crear
-- tareas) dispara el flujo de corrección sin depender de WhatsApp.
create or replace function public.report_price_difference(
  p_product_id uuid, p_branch_id uuid default null, p_observed_price numeric default null, p_comment text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_task    uuid;
  v_branch  uuid := coalesce(p_branch_id, public.auth_branch_id());
  v_product public.products%rowtype;
  v_dept    uuid;
begin
  if not public.has_permission('report_price_difference') then
    raise exception 'No tienes permiso para reportar diferencias de precio';
  end if;
  if not public.can_access_branch(v_branch) then
    raise exception 'Sucursal no permitida';
  end if;
  select * into v_product from public.products where id = p_product_id and company_id = public.auth_company_id();
  if not found then raise exception 'Producto no encontrado'; end if;

  select id into v_dept from public.departments
  where company_id = v_product.company_id and code = 'ESC' limit 1;

  insert into public.tasks (company_id, branch_id, department_id, title, description, created_by, due_date, priority)
  values (v_product.company_id, v_branch, coalesce(v_dept, v_product.department_id),
          'Diferencia de precio: ' || v_product.name,
          format('SKU %s. Precio en sistema %s%s.%s', v_product.sku, v_product.price,
                 coalesce(', precio observado ' || p_observed_price, ''), coalesce(' ' || p_comment, '')),
          public.auth_employee_id(), public.company_today(v_product.company_id), 'high')
  returning id into v_task;
  return v_task;
end $$;
revoke all on function public.report_price_difference(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.report_price_difference(uuid, uuid, numeric, text) to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0004_vistas.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0004 · VISTAS DE LECTURA
-- -----------------------------------------------------------------------------
-- Objetivo: entregar al frontend filas "planas" con los nombres ya resueltos
-- (producto, sucursal, empleado...) para no repetir joins en cada pantalla.
--
-- IMPORTANTE: todas usan security_invoker = on. Eso hace que la vista se
-- evalúe con los permisos del usuario que consulta, por lo que las políticas
-- RLS de las tablas base siguen aplicando (nadie ve más de lo que le toca).
--
-- Las escrituras siempre se hacen sobre las tablas base, nunca sobre vistas.
-- =============================================================================

-- Empleados con rol, sucursal y departamento.
-- Re-ejecución: migraciones posteriores agregan columnas a estas vistas o a sus
-- tablas (create or replace no permite quitar ni reordenar columnas), así que se
-- eliminan y se recrean; 0008+ vuelven a crear sus versiones extendidas.
drop view if exists public.v_employees, public.v_products, public.v_inventory, public.v_inventory_movements, public.v_supplier_visits, public.v_receiving_orders, public.v_receiving_items, public.v_price_changes, public.v_shelf_tags, public.v_expirations, public.v_checklist_runs, public.v_evidence, public.v_orders, public.v_order_items, public.v_tasks, public.v_support_tickets, public.v_support_ticket_messages, public.v_audit_logs cascade;

create or replace view public.v_employees with (security_invoker = on) as
select e.id, e.user_id, e.company_id, e.branch_id, e.department_id, e.role_id,
       e.employee_code, e.username, e.full_name, e.position, e.email, e.phone,
       e.status, e.hired_at, e.created_at, e.updated_at,
       (e.user_id is not null) as has_account,
       r.code as role_code, r.name as role_name, r.scope as role_scope,
       b.name as branch_name, d.name as department_name, d.color as department_color
from public.employees e
join public.roles r on r.id = e.role_id
left join public.branches b on b.id = e.branch_id
left join public.departments d on d.id = e.department_id;

-- Catálogo de productos con códigos de barras concatenados (para búsqueda).
create or replace view public.v_products with (security_invoker = on) as
select p.*, d.name as department_name,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes
from public.products p
left join public.departments d on d.id = p.department_id;

-- Inventario por sucursal con datos del producto y si tiene cenefa pendiente.
create or replace view public.v_inventory with (security_invoker = on) as
select i.id, i.company_id, i.branch_id, i.product_id, i.stock, i.min_stock, i.max_stock,
       i.location, i.status, i.last_movement_at, i.last_counted_at, i.updated_at,
       p.sku, p.name as product_name, p.category, p.unit, p.price, p.previous_price,
       p.price_updated_at, p.department_id, p.controls_expiration, p.status as product_status,
       d.name as department_name, b.name as branch_name,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       exists (select 1 from public.shelf_tags st
               where st.product_id = p.id and st.branch_id = i.branch_id
                 and st.status in ('pending','printed','placed')) as has_pending_tag
from public.inventory i
join public.products p on p.id = i.product_id
join public.branches b on b.id = i.branch_id
left join public.departments d on d.id = p.department_id;

create or replace view public.v_inventory_movements with (security_invoker = on) as
select m.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       e.full_name as created_by_name
from public.inventory_movements m
join public.products p on p.id = m.product_id
join public.branches b on b.id = m.branch_id
left join public.employees e on e.id = m.created_by;

create or replace view public.v_supplier_visits with (security_invoker = on) as
select v.*, s.code as supplier_code, s.name as supplier_name, b.name as branch_name,
       er.full_name as registered_by_name, ec.full_name as closed_by_name,
       extract(epoch from (coalesce(v.check_out_at, now()) - v.check_in_at)) / 60 as minutes_inside
from public.supplier_visits v
join public.suppliers s on s.id = v.supplier_id
join public.branches b on b.id = v.branch_id
left join public.employees er on er.id = v.registered_by
left join public.employees ec on ec.id = v.closed_by;

create or replace view public.v_receiving_orders with (security_invoker = on) as
select r.*, s.code as supplier_code, s.name as supplier_name, b.name as branch_name,
       er.full_name as received_by_name, ec.full_name as completed_by_name,
       (select count(*) from public.receiving_items ri where ri.receiving_order_id = r.id) as items_count
from public.receiving_orders r
join public.suppliers s on s.id = r.supplier_id
join public.branches b on b.id = r.branch_id
left join public.employees er on er.id = r.received_by
left join public.employees ec on ec.id = r.completed_by;

create or replace view public.v_receiving_items with (security_invoker = on) as
select ri.*, p.sku, p.name as product_name, p.unit
from public.receiving_items ri
join public.products p on p.id = ri.product_id;

create or replace view public.v_price_changes with (security_invoker = on) as
select pc.*, p.sku, p.name as product_name, b.name as branch_name,
       e.full_name as created_by_name,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id) as tags_total,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id and st.status = 'validated') as tags_validated
from public.price_changes pc
join public.products p on p.id = pc.product_id
left join public.branches b on b.id = pc.branch_id
left join public.employees e on e.id = pc.created_by;

create or replace view public.v_shelf_tags with (security_invoker = on) as
select st.*, p.sku, p.name as product_name, p.price as current_price,
       pc.old_price, pc.new_price, pc.effective_date, b.name as branch_name,
       d.name as department_name,
       ep.full_name as printed_by_name, epl.full_name as placed_by_name, ev.full_name as validated_by_name
from public.shelf_tags st
join public.products p on p.id = st.product_id
join public.branches b on b.id = st.branch_id
left join public.departments d on d.id = p.department_id
left join public.price_changes pc on pc.id = st.price_change_id
left join public.employees ep on ep.id = st.printed_by
left join public.employees epl on epl.id = st.placed_by
left join public.employees ev on ev.id = st.validated_by;

create or replace view public.v_expirations with (security_invoker = on) as
select x.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       d.name as department_name, e.full_name as registered_by_name,
       (x.expiration_date - public.company_today(x.company_id)) as days_left
from public.product_expirations x
join public.products p on p.id = x.product_id
join public.branches b on b.id = x.branch_id
left join public.departments d on d.id = p.department_id
left join public.employees e on e.id = x.registered_by;

create or replace view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;

create or replace view public.v_evidence with (security_invoker = on) as
select ev.*, eu.full_name as uploaded_by_name, er.full_name as reviewed_by_name, b.name as branch_name
from public.evidence_files ev
left join public.employees eu on eu.id = ev.uploaded_by
left join public.employees er on er.id = ev.reviewed_by
left join public.branches b on b.id = ev.branch_id;

create or replace view public.v_orders with (security_invoker = on) as
select o.*, d.name as department_name, b.name as branch_name,
       er.full_name as requested_by_name, ea.full_name as approved_by_name,
       (select count(*) from public.order_items oi where oi.order_id = o.id) as items_count,
       (select coalesce(sum(oi.quantity), 0) from public.order_items oi where oi.order_id = o.id) as total_quantity
from public.orders o
join public.branches b on b.id = o.branch_id
left join public.departments d on d.id = o.department_id
left join public.employees er on er.id = o.requested_by
left join public.employees ea on ea.id = o.approved_by;

create or replace view public.v_order_items with (security_invoker = on) as
select oi.*, p.sku, p.name as product_name, p.unit
from public.order_items oi
join public.products p on p.id = oi.product_id;

create or replace view public.v_tasks with (security_invoker = on) as
select t.*, d.name as department_name, b.name as branch_name,
       ea.full_name as assigned_to_name, ec.full_name as created_by_name,
       (select count(*) from public.evidence_files ev where ev.entity_type = 'task' and ev.entity_id = t.id) as evidence_count,
       (t.status in ('pending','in_progress') and t.due_date < public.company_today(t.company_id)) as is_late
from public.tasks t
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees ea on ea.id = t.assigned_to
left join public.employees ec on ec.id = t.created_by;

create or replace view public.v_support_tickets with (security_invoker = on) as
select t.*, b.name as branch_name,
       ec.full_name as created_by_name, ec.position as created_by_position,
       ea.full_name as assigned_to_name,
       (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id and not m.is_internal) as messages_count,
       (select max(m.created_at) from public.support_ticket_messages m where m.ticket_id = t.id) as last_message_at
from public.support_tickets t
left join public.branches b on b.id = t.branch_id
left join public.employees ec on ec.id = t.created_by
left join public.employees ea on ea.id = t.assigned_to;

create or replace view public.v_support_ticket_messages with (security_invoker = on) as
select m.*, e.full_name as author_name, e.position as author_position
from public.support_ticket_messages m
left join public.employees e on e.id = m.author_id;

create or replace view public.v_audit_logs with (security_invoker = on) as
select a.*, e.full_name as performed_by_name
from public.audit_logs a
left join public.employees e on e.id = a.performed_by;

-- Las vistas solo son accesibles para usuarios autenticados.
do $$
declare v text;
begin
  for v in select table_name from information_schema.views where table_schema = 'public' and table_name like 'v\_%'
  loop
    execute format('revoke all on public.%I from anon', v);
    execute format('grant select on public.%I to authenticated', v);
  end loop;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0005_politicas_rls.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0005 · ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
-- Objetivo: que cada usuario solo lea/escriba lo que le corresponde, aunque
-- llame a la API directamente con la llave pública.
--
-- Reglas base (definidas en Objetivos.md §15):
--   Admin / Auditor / Soporte (scope company) → toda la empresa
--   Gerente (scope branch)                    → su sucursal
--   Supervisor / Jefes (scope department)     → sus departamentos
--   Empleado (scope self)                     → su departamento; tareas propias
--
-- Patrón:
--   * SELECT  → filtra por empresa + can_access_branch / can_access_department
--   * INSERT/UPDATE/DELETE → además exige el permiso del módulo (has_permission)
--   * Las reglas de flujo (transiciones de estado) las validan los triggers 0003.
--
-- Las funciones se envuelven en (select ...) para que Postgres las evalúe una
-- sola vez por consulta (recomendación de rendimiento de Supabase).
-- El rol "anon" no tiene ninguna política: sin sesión no se ve nada.
-- =============================================================================

-- Activar RLS en todas las tablas del esquema public.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Limpia políticas previas para poder re-ejecutar este archivo.
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- ─── ORGANIZACIÓN ────────────────────────────────────────────────────────────

create policy companies_select on public.companies for select to authenticated
  using (id = (select public.auth_company_id()));
create policy companies_update on public.companies for update to authenticated
  using (id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

create policy branches_select on public.branches for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy branches_write on public.branches for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

create policy departments_select on public.departments for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy departments_write on public.departments for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

-- ─── SEGURIDAD ───────────────────────────────────────────────────────────────

create policy permissions_select on public.permissions for select to authenticated using (true);

create policy roles_select on public.roles for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy roles_write on public.roles for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_roles')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_roles')));

create policy role_permissions_select on public.role_permissions for select to authenticated
  using (exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));
create policy role_permissions_write on public.role_permissions for all to authenticated
  using ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));

-- Empleados: alcance company ve a todos; los demás a su sucursal (y a sí mismos).
create policy employees_select on public.employees for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (select public.auth_role_scope()) = 'company'
      or branch_id = (select public.auth_branch_id())
      or user_id = (select auth.uid())));
create policy employees_insert on public.employees for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees')));
create policy employees_update on public.employees for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees'))
         and ((select public.auth_role_scope()) = 'company' or branch_id = (select public.auth_branch_id())))
  with check (company_id = (select public.auth_company_id()));
-- No hay DELETE: los empleados se dan de baja con status = 'inactive' (trazabilidad).

create policy employee_permissions_select on public.employee_permissions for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
create policy employee_permissions_write on public.employee_permissions for all to authenticated
  using ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_roles'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

create policy employee_departments_select on public.employee_departments for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
create policy employee_departments_write on public.employee_departments for all to authenticated
  using ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

-- ─── PRODUCTOS E INVENTARIO ──────────────────────────────────────────────────

create policy products_select on public.products for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy products_write on public.products for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')));

create policy barcodes_select on public.product_barcodes for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy barcodes_write on public.product_barcodes for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_inventory')));

create policy inventory_select on public.inventory for select to authenticated
  using (public.can_access_branch(branch_id));
-- El stock NO se edita directo: se registra un movimiento (trigger). Aquí solo
-- se permite dar de alta el renglón y ajustar mínimo/máximo/ubicación.
create policy inventory_insert on public.inventory for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_inventory')) and stock = 0);
create policy inventory_update on public.inventory for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_inventory')))
  with check (public.can_access_branch(branch_id));

create policy movements_select on public.inventory_movements for select to authenticated
  using (public.can_access_branch(branch_id));
create policy movements_insert on public.inventory_movements for insert to authenticated
  with check (public.can_access_branch(branch_id) and (
                 (select public.has_permission('manage_inventory'))
              -- Caducidades puede dar de baja (merma) lotes vencidos o retirados.
              or (movement_type = 'waste' and (select public.has_permission('manage_expirations')))));
-- Sin UPDATE/DELETE: la bitácora de movimientos es inmutable.

-- ─── PROVEEDORES Y RECIBO ────────────────────────────────────────────────────

create policy suppliers_select on public.suppliers for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy suppliers_write on public.suppliers for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_suppliers')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_suppliers')));

create policy visits_select on public.supplier_visits for select to authenticated
  using (public.can_access_branch(branch_id));
create policy visits_insert on public.supplier_visits for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('register_supplier_visit')));
create policy visits_update on public.supplier_visits for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('register_supplier_visit')))
  with check (public.can_access_branch(branch_id));

create policy receiving_select on public.receiving_orders for select to authenticated
  using (public.can_access_branch(branch_id));
create policy receiving_insert on public.receiving_orders for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('receive_products')));
create policy receiving_update on public.receiving_orders for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('receive_products')))
  with check (public.can_access_branch(branch_id));

create policy receiving_items_select on public.receiving_items for select to authenticated
  using (exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)));
create policy receiving_items_write on public.receiving_items for all to authenticated
  using ((select public.has_permission('receive_products'))
         and exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)))
  with check ((select public.has_permission('receive_products'))
         and exists (select 1 from public.receiving_orders r where r.id = receiving_order_id and public.can_access_branch(r.branch_id)));

-- ─── PRECIOS, CENEFAS, CADUCIDADES ───────────────────────────────────────────

create policy price_changes_select on public.price_changes for select to authenticated
  using (company_id = (select public.auth_company_id()) and (branch_id is null or public.can_access_branch(branch_id)));
create policy price_changes_insert on public.price_changes for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
              and (branch_id is null and (select public.auth_role_scope()) = 'company' or public.can_access_branch(branch_id)));
create policy price_changes_update on public.price_changes for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes')) and status = 'scheduled')
  with check (company_id = (select public.auth_company_id()));

create policy shelf_tags_select on public.shelf_tags for select to authenticated
  using (public.can_access_branch(branch_id));
create policy shelf_tags_update on public.shelf_tags for update to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_shelf_tags')))
  with check (public.can_access_branch(branch_id));
-- Las cenefas las crea el trigger de cambios de precio (no hay INSERT directo).

create policy expirations_select on public.product_expirations for select to authenticated
  using (public.can_access_branch(branch_id));
create policy expirations_write on public.product_expirations for all to authenticated
  using (public.can_access_branch(branch_id) and (select public.has_permission('manage_expirations')))
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_expirations')));

-- ─── CHECKLISTS ──────────────────────────────────────────────────────────────

create policy templates_select on public.checklist_templates for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy templates_write on public.checklist_templates for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checklist_templates')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checklist_templates')));

create policy questions_select on public.checklist_questions for select to authenticated
  using (exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())));
create policy questions_write on public.checklist_questions for all to authenticated
  using ((select public.has_permission('manage_checklist_templates'))
         and exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_checklist_templates'))
         and exists (select 1 from public.checklist_templates t where t.id = template_id and t.company_id = (select public.auth_company_id())));

create policy runs_select on public.checklist_runs for select to authenticated
  using (public.can_access_department(branch_id, department_id));
create policy runs_insert on public.checklist_runs for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('manage_checklist_templates')));
create policy runs_update on public.checklist_runs for update to authenticated
  using (public.can_access_department(branch_id, department_id)
         and ((select public.has_permission('fill_checklists')) or (select public.has_permission('review_checklists'))))
  with check (public.can_access_department(branch_id, department_id));

create policy answers_select on public.checklist_answers for select to authenticated
  using (exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)));
create policy answers_insert on public.checklist_answers for insert to authenticated
  with check ((select public.has_permission('fill_checklists'))
         and exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)));
create policy answers_update on public.checklist_answers for update to authenticated
  using ((select public.has_permission('fill_checklists'))
         and exists (select 1 from public.checklist_runs r where r.id = run_id and public.can_access_department(r.branch_id, r.department_id)))
  with check (true);

-- ─── EVIDENCIAS ──────────────────────────────────────────────────────────────

create policy evidence_select on public.evidence_files for select to authenticated
  using (company_id = (select public.auth_company_id())
         and (branch_id is null or public.can_access_branch(branch_id) or uploaded_by = (select public.auth_employee_id())));
create policy evidence_insert on public.evidence_files for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (
                 (select public.has_permission('upload_evidence'))
              or (entity_type = 'support_ticket' and (select public.has_permission('create_tickets')))));
create policy evidence_update on public.evidence_files for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('review_evidence'))
         and (branch_id is null or public.can_access_branch(branch_id)))
  with check (company_id = (select public.auth_company_id()));
create policy evidence_delete on public.evidence_files for delete to authenticated
  using (uploaded_by = (select public.auth_employee_id()) and status = 'pending');

-- ─── PEDIDOS ─────────────────────────────────────────────────────────────────

create policy orders_select on public.orders for select to authenticated
  using (public.can_access_department(branch_id, department_id) or requested_by = (select public.auth_employee_id()));
create policy orders_insert on public.orders for insert to authenticated
  with check (public.can_access_branch(branch_id) and (select public.has_permission('create_orders')));
create policy orders_update on public.orders for update to authenticated
  using (public.can_access_department(branch_id, department_id)
         and (requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders'))))
  with check (public.can_access_branch(branch_id));

create policy orders_delete on public.orders for delete to authenticated
  using (requested_by = (select public.auth_employee_id()) and status = 'requested');

create policy order_items_select on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (public.can_access_department(o.branch_id, o.department_id) or o.requested_by = (select public.auth_employee_id()))));
create policy order_items_write on public.order_items for all to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders')))))
  with check (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id()) or (select public.has_permission('approve_orders')))));

-- ─── TAREAS ──────────────────────────────────────────────────────────────────

create policy tasks_select on public.tasks for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         assigned_to = (select public.auth_employee_id())
      or created_by = (select public.auth_employee_id())
      or ((select public.auth_role_scope()) <> 'self' and public.can_access_department(branch_id, department_id))));
create policy tasks_insert on public.tasks for insert to authenticated
  with check (public.can_access_department(branch_id, department_id) and (select public.has_permission('manage_tasks')));
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = (select public.auth_employee_id())
      or ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id)))
  with check (company_id = (select public.auth_company_id()));
create policy tasks_delete on public.tasks for delete to authenticated
  using ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id) and status = 'pending');

-- ─── MESA DE AYUDA ───────────────────────────────────────────────────────────

create policy tickets_select on public.support_tickets for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))));
create policy tickets_insert on public.support_tickets for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('create_tickets')));
create policy tickets_update on public.support_tickets for update to authenticated
  using (company_id = (select public.auth_company_id()) and (
         created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))))
  with check (company_id = (select public.auth_company_id()));

create policy ticket_messages_select on public.support_ticket_messages for select to authenticated
  using (exists (select 1 from public.support_tickets t where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                 and (t.created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets'))))
         and (not is_internal or (select public.has_permission('manage_tickets'))));
create policy ticket_messages_insert on public.support_ticket_messages for insert to authenticated
  with check (exists (select 1 from public.support_tickets t where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                 and (t.created_by = (select public.auth_employee_id()) or (select public.has_permission('manage_tickets')))));

-- ─── NOTIFICACIONES Y AUDITORÍA ──────────────────────────────────────────────

create policy notifications_select on public.notifications for select to authenticated
  using (employee_id = (select public.auth_employee_id()));
create policy notifications_update on public.notifications for update to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));
create policy notifications_delete on public.notifications for delete to authenticated
  using (employee_id = (select public.auth_employee_id()));

create policy audit_select on public.audit_logs for select to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('view_audit_logs')));
-- audit_logs solo la escribe el trigger (SECURITY DEFINER).

-- ─── PRIVILEGIOS DE TABLA ────────────────────────────────────────────────────
-- anon no puede tocar nada; authenticated pasa por las políticas de arriba.
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0006_storage_evidencias.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0006 · STORAGE (archivos de evidencia)
-- -----------------------------------------------------------------------------
-- Objetivo: bucket privado "evidence" para fotos y PDFs.
--
-- Estructura de rutas (la arma src/services/evidenceService.js):
--     {company_id}/{entity_type}/{yyyy-mm}/{uuid}.{ext}
--
-- La primera carpeta es la empresa → las políticas solo permiten leer/subir
-- dentro de la carpeta de tu propia empresa. Las imágenes se muestran con
-- URLs firmadas temporales (createSignedUrl), nunca públicas.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidence', 'evidence', false, 10485760, -- 10 MB
        array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists evidence_objects_select on storage.objects;
drop policy if exists evidence_objects_insert on storage.objects;
drop policy if exists evidence_objects_delete on storage.objects;

create policy evidence_objects_select on storage.objects for select to authenticated
  using (bucket_id = 'evidence'
         and (storage.foldername(name))[1] = (select public.auth_company_id())::text);

create policy evidence_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence'
              and (storage.foldername(name))[1] = (select public.auth_company_id())::text
              and ((select public.has_permission('upload_evidence')) or (select public.has_permission('create_tickets'))));

-- Solo quien subió el archivo puede borrarlo.
create policy evidence_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'evidence' and owner_id = (select auth.uid())::text);


-- >>>>>>>>>>>>>>>> migrations/0007_realtime.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0007 · REALTIME
-- -----------------------------------------------------------------------------
-- Objetivo: que la campana de notificaciones y los tickets se actualicen en
-- vivo sin recargar. Supabase Realtime respeta RLS: cada usuario solo recibe
-- sus propias notificaciones.
-- =============================================================================
do $$
declare t text;
begin
  foreach t in array array['notifications','support_ticket_messages'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; -- ya estaba agregada
    end;
  end loop;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0008_notificaciones_departamento.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0008 · NOTIFICACIONES PERSONALES Y POR DEPARTAMENTO
-- -----------------------------------------------------------------------------
-- Una notificación puede ser:
--   * personal          → employee_id = X
--   * de departamento   → employee_id NULL, department_id = D
--                         (branch_id NULL = todas las sucursales, o una en particular)
-- La lectura se guarda POR EMPLEADO en notification_reads, así un aviso de
-- departamento leído por una persona sigue "no leído" para sus compañeros.
-- El frontend lee la vista v_my_notifications y marca con las funciones
-- mark_notification_read / mark_all_notifications_read.
-- =============================================================================

alter table public.notifications alter column employee_id drop not null;
alter table public.notifications add column if not exists department_id uuid references public.departments(id) on delete cascade;
alter table public.notifications add column if not exists branch_id uuid references public.branches(id) on delete cascade;

do $$ begin
  alter table public.notifications add constraint notifications_target_chk
    check (employee_id is not null or department_id is not null);
exception when duplicate_object then null; end $$;

create index if not exists notifications_department_idx on public.notifications (department_id, created_at desc);

create table if not exists public.notification_reads (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  employee_id     uuid not null references public.employees(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (notification_id, employee_id)
);
alter table public.notification_reads enable row level security;

-- ¿Esta notificación es para mí? (personal, o de mi departamento en mi sucursal)
create or replace function public.is_my_notification(p_employee_id uuid, p_department_id uuid, p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_employee_id is not null then p_employee_id = public.auth_employee_id()
    else (p_branch_id is null or p_branch_id = public.auth_branch_id())
     and (p_department_id = public.auth_department_id()
          or exists (select 1 from public.employee_departments ed
                     where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id))
  end
$$;

-- Políticas: cada usuario ve las suyas y las de su(s) departamento(s).
drop policy if exists notifications_select on public.notifications;
drop policy if exists notifications_update on public.notifications;
drop policy if exists notifications_delete on public.notifications;
drop policy if exists notifications_insert on public.notifications;

create policy notifications_select on public.notifications for select to authenticated
  using (company_id = (select public.auth_company_id())
         and public.is_my_notification(employee_id, department_id, branch_id));
-- Solo se marcan/borran directamente las personales; las de departamento usan notification_reads.
create policy notifications_update on public.notifications for update to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));
create policy notifications_delete on public.notifications for delete to authenticated
  using (employee_id = (select public.auth_employee_id()));
-- Gerentes/supervisores pueden enviar avisos a un departamento de su sucursal.
create policy notifications_insert on public.notifications for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and department_id is not null and employee_id is null
              and (select public.has_permission('manage_tasks')));

drop policy if exists notification_reads_all on public.notification_reads;
create policy notification_reads_all on public.notification_reads for all to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));

grant select, insert, update, delete on public.notification_reads to authenticated;

-- Vista con el estado "leída" calculado para el usuario actual.
create or replace view public.v_my_notifications with (security_invoker = on) as
select n.id, n.company_id, n.employee_id, n.department_id, n.branch_id, n.type, n.title, n.body, n.link,
       n.created_at, d.name as department_name,
       (n.employee_id is null) as is_department,
       case when n.employee_id is not null then n.is_read
            else exists (select 1 from public.notification_reads r
                         where r.notification_id = n.id and r.employee_id = public.auth_employee_id())
       end as is_read
from public.notifications n
left join public.departments d on d.id = n.department_id;

revoke all on public.v_my_notifications from anon;
grant select on public.v_my_notifications to authenticated;

create or replace function public.mark_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n public.notifications%rowtype;
begin
  select * into n from public.notifications where id = p_id;
  if not found or not public.is_my_notification(n.employee_id, n.department_id, n.branch_id) then return; end if;
  if n.employee_id is not null then
    update public.notifications set is_read = true where id = p_id;
  else
    insert into public.notification_reads (notification_id, employee_id)
    values (p_id, public.auth_employee_id()) on conflict do nothing;
  end if;
end $$;

create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  update public.notifications set is_read = true
   where employee_id = public.auth_employee_id() and not is_read;
  get diagnostics v_count = row_count;

  insert into public.notification_reads (notification_id, employee_id)
  select n.id, public.auth_employee_id() from public.notifications n
  where n.employee_id is null and n.company_id = public.auth_company_id()
    and public.is_my_notification(n.employee_id, n.department_id, n.branch_id)
  on conflict do nothing;
  return v_count;
end $$;

revoke all on function public.is_my_notification(uuid, uuid, uuid) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.is_my_notification(uuid, uuid, uuid) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0009_checklists_evidencia.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0009 · CHECKLISTS: EVIDENCIA A NIVEL CHECKLIST
-- -----------------------------------------------------------------------------
-- Si la plantilla tiene "Evidencia requerida", el checklist no se puede
-- completar sin al menos una foto: ya sea general del checklist
-- (entity_type 'checklist_run') o ligada a alguna de sus respuestas.
-- La vista v_checklist_runs agrega evidence_count para historial y tarjetas.
-- Re-ejecutable.
-- =============================================================================

-- 1) Nuevo tipo de entidad para evidencias generales del checklist.
alter table public.evidence_files drop constraint if exists evidence_files_entity_type_check;
alter table public.evidence_files add constraint evidence_files_entity_type_check check (entity_type in (
  'checklist_run','checklist_answer','task','receiving_order','price_change','shelf_tag',
  'order','expiration','support_ticket','product','supplier_visit','other'));

-- 2) Validación al completar.
create or replace function public.tg_checklist_run_evidence()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'completed' and old.status <> 'completed' and not public.is_system_context()
     and (select requires_evidence from public.checklist_templates where id = new.template_id)
     and not exists (
       select 1 from public.evidence_files ev
       where (ev.entity_type = 'checklist_run' and ev.entity_id = new.id)
          or (ev.entity_type = 'checklist_answer'
              and ev.entity_id in (select a.id from public.checklist_answers a where a.run_id = new.id))) then
    raise exception 'Este checklist requiere evidencia fotográfica antes de completarse';
  end if;
  return new;
end $$;

-- Nombre elegido para correr DESPUÉS de trg_checklist_run_rules (orden alfabético):
-- así primero se informa si faltan respuestas y después si falta la foto.
drop trigger if exists trg_checklist_run_evidence on public.checklist_runs;
drop trigger if exists trg_checklist_run_rules_evidence on public.checklist_runs;
create trigger trg_checklist_run_rules_evidence before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_evidence();

-- 3) Conteo de evidencias en la vista (columna agregada al final).
create or replace view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;

revoke all on public.v_checklist_runs from anon;
grant select on public.v_checklist_runs to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0010_cancelar_checklist.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0010 · CANCELAR UN CHECKLIST DEL DÍA
-- -----------------------------------------------------------------------------
-- Caso: un departamento no abrió o el checklist no aplica hoy.
--   * Solo quien tiene review_checklists puede cancelar.
--   * Se exige motivo (se guarda en review_comment) y queda quién/cuándo.
--   * No se cancelan checklists completados (lo impide tg_checklist_run_rules).
-- Re-ejecutable.
-- =============================================================================
create or replace function public.tg_checklist_run_cancel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' and not public.is_system_context() then
    if not public.has_permission('review_checklists') then
      raise exception 'Solo un supervisor puede cancelar checklists';
    end if;
    if coalesce(trim(new.review_comment), '') = '' then
      raise exception 'Indica el motivo de la cancelación';
    end if;
    new.reviewed_by := public.auth_employee_id();
    new.reviewed_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_checklist_run_cancel on public.checklist_runs;
create trigger trg_checklist_run_cancel before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_cancel();


-- >>>>>>>>>>>>>>>> migrations/0011_soporte_temas_sla.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0011 · SOPORTE: TEMAS, SLA, RESPUESTAS PREDEFINIDAS Y VISIBILIDAD
-- -----------------------------------------------------------------------------
-- Extiende support_tickets (sin tablas paralelas):
--   * Categorías nuevas: network, pos, printer, scanner.
--   * support_topics: catálogo de temas con prioridad, SLA y autoayuda.
--   * Columnas: topic_id, location, blocks_operation, due_at, department_id.
--     due_at = created_at + sla_hours (la mitad si blocks_operation).
--   * support_canned_responses: respuestas rápidas para soporte.
--   * RLS: empleado → propios; jefes/supervisores → su departamento;
--     gerente → su sucursal; soporte/admin → todos. Notas internas solo soporte.
-- Re-ejecutable.
-- =============================================================================

alter table public.support_tickets drop constraint if exists support_tickets_category_check;
alter table public.support_tickets add constraint support_tickets_category_check
  check (category in ('bug','access','data','feature','training','hardware',
                      'network','pos','printer','scanner','other'));

create table if not exists public.support_topics (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  code              text not null,
  name              text not null,
  category          text not null default 'other'
                    check (category in ('bug','access','data','feature','training','hardware',
                                        'network','pos','printer','scanner','other')),
  default_priority  text not null default 'medium' check (default_priority in ('low','medium','high','critical')),
  sla_hours         numeric(6,2) not null default 24 check (sla_hours > 0),
  self_help         text,
  sort_order        int not null default 0,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (company_id, code)
);

alter table public.support_tickets
  add column if not exists topic_id         uuid references public.support_topics(id) on delete set null,
  add column if not exists location         text,
  add column if not exists blocks_operation boolean not null default false,
  add column if not exists due_at           timestamptz,
  add column if not exists department_id    uuid references public.departments(id) on delete set null;

create index if not exists tickets_branch_dept_idx on public.support_tickets (branch_id, department_id);
create index if not exists tickets_due_idx         on public.support_tickets (company_id, due_at) where status not in ('resolved','closed');
create index if not exists tickets_created_by_idx  on public.support_tickets (created_by);

create table if not exists public.support_canned_responses (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  title       text not null,
  body        text not null,
  is_active   boolean not null default true,
  created_by  uuid references public.employees(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, title)
);

drop trigger if exists trg_updated_at on public.support_topics;
create trigger trg_updated_at before update on public.support_topics
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_updated_at on public.support_canned_responses;
create trigger trg_updated_at before update on public.support_canned_responses
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_actor on public.support_canned_responses;
create trigger trg_actor before insert on public.support_canned_responses
  for each row execute function public.tg_set_actor('created_by');

-- ─── SLA Y DATOS DERIVADOS DEL TEMA ─────────────────────────────────────────
create or replace function public.tg_ticket_sla()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_topic public.support_topics%rowtype;
  v_hours numeric;
begin
  if new.topic_id is not null then
    select * into v_topic from public.support_topics
     where id = new.topic_id and company_id = new.company_id;
    if not found then raise exception 'El tema de soporte no existe'; end if;
  end if;

  if tg_op = 'INSERT' then
    new.department_id := coalesce(new.department_id,
      (select e.department_id from public.employees e where e.id = new.created_by),
      public.auth_department_id());
    if v_topic.id is not null then
      new.category := v_topic.category;
      if new.priority = 'medium' then new.priority := v_topic.default_priority; end if;
    end if;
    if new.blocks_operation and new.priority in ('low','medium') then
      new.priority := 'high';
    end if;
  end if;

  if tg_op = 'INSERT'
     or new.topic_id is distinct from old.topic_id
     or new.blocks_operation is distinct from old.blocks_operation
     or new.priority is distinct from old.priority then
    v_hours := coalesce(v_topic.sla_hours,
      case new.priority when 'critical' then 4 when 'high' then 8 when 'medium' then 24 else 72 end);
    if new.blocks_operation then v_hours := v_hours / 2; end if;
    new.due_at := coalesce(new.created_at, now()) + make_interval(secs => (v_hours * 3600)::double precision);
  end if;
  return new;
end $$;

drop trigger if exists trg_ticket_sla on public.support_tickets;
create trigger trg_ticket_sla before insert or update on public.support_tickets
  for each row execute function public.tg_ticket_sla();

-- ─── VISIBILIDAD ────────────────────────────────────────────────────────────
create or replace function public.can_view_ticket(p_created_by uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.auth_employee_id()
      or public.has_permission('manage_tickets')
      or (public.auth_role_scope() in ('company','branch','department')
          and public.can_access_department(p_branch_id, p_department_id))
$$;

drop policy if exists tickets_select on public.support_tickets;
create policy tickets_select on public.support_tickets for select to authenticated
  using (company_id = (select public.auth_company_id())
         and public.can_view_ticket(created_by, branch_id, department_id));

drop policy if exists ticket_messages_select on public.support_ticket_messages;
create policy ticket_messages_select on public.support_ticket_messages for select to authenticated
  using (exists (select 1 from public.support_tickets t
                 where t.id = ticket_id and t.company_id = (select public.auth_company_id())
                   and public.can_view_ticket(t.created_by, t.branch_id, t.department_id))
         and (not is_internal or (select public.has_permission('manage_tickets'))));

alter table public.support_topics enable row level security;
drop policy if exists support_topics_select on public.support_topics;
create policy support_topics_select on public.support_topics for select to authenticated
  using (company_id = (select public.auth_company_id())
         and (is_active or (select public.has_permission('manage_tickets'))));
drop policy if exists support_topics_write on public.support_topics;
create policy support_topics_write on public.support_topics for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')));

alter table public.support_canned_responses enable row level security;
drop policy if exists canned_responses_all on public.support_canned_responses;
create policy canned_responses_all on public.support_canned_responses for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_tickets')));

-- ─── VISTA ──────────────────────────────────────────────────────────────────
drop view if exists public.v_support_tickets;
create view public.v_support_tickets with (security_invoker = on) as
select t.*, b.name as branch_name, d.name as department_name,
       tp.name as topic_name, tp.code as topic_code,
       ec.full_name as created_by_name, ec.position as created_by_position,
       ea.full_name as assigned_to_name,
       (t.due_at is not null and t.due_at < now() and t.status not in ('resolved','closed')) as is_overdue,
       (select count(*) from public.support_ticket_messages m where m.ticket_id = t.id and not m.is_internal) as messages_count,
       (select max(m.created_at) from public.support_ticket_messages m where m.ticket_id = t.id) as last_message_at
from public.support_tickets t
left join public.branches b      on b.id = t.branch_id
left join public.departments d   on d.id = t.department_id
left join public.support_topics tp on tp.id = t.topic_id
left join public.employees ec    on ec.id = t.created_by
left join public.employees ea    on ea.id = t.assigned_to;

grant select, insert, update, delete on public.support_topics, public.support_canned_responses to authenticated;
grant select on public.v_support_tickets to authenticated;
grant execute on function public.can_view_ticket(uuid, uuid, uuid) to authenticated;

-- Los temas de soporte, respuestas rápidas y el permiso create_tickets por rol
-- se siembran por empresa con public.seed_company_base (migración 0023).


-- >>>>>>>>>>>>>>>> migrations/0012_propietario_contrasenas_checklists.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0012 · PROPIETARIO, CONTRASEÑAS, CHECKLISTS DIARIOS
-- -----------------------------------------------------------------------------
-- Sin tablas nuevas. Incluye:
--   1. employees.is_owner: gatopelon es el administrador más alto.
--      Nadie más puede editarlo, y solo él gestiona a otros administradores.
--      El rol admin siempre tiene todos los permisos.
--   2. Contraseñas:
--      * admin_set_password: admin o gerente pone una contraseña temporal
--        (o crea la cuenta si el empleado no tiene); al entrar se pide cambiarla.
--      * request_password_reset: "Olvidé mi contraseña" desde el login avisa
--        al propietario, administradores y gerente de la sucursal.
--   3. pg_cron: genera los checklists de cada día automáticamente (cada hora).
--   4. (Movido a seed_company_base en 0023: 4 checklists nuevos.)
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. PROPIETARIO ─────────────────────────────────────────────────────────
alter table public.employees add column if not exists is_owner boolean not null default false;
create unique index if not exists employees_one_owner_idx on public.employees (company_id) where is_owner;

do $$
declare v_prev text;
begin
  if not exists (select 1 from public.employees where is_owner) then
    v_prev := public.set_bypass('on');
    update public.employees set is_owner = true where username = 'gatopelon';
    perform public.set_bypass(v_prev);
  end if;
end $$;

create or replace function public.auth_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.is_owner from public.employees e
                   where e.user_id = auth.uid() and e.status = 'active' limit 1), false)
$$;
grant execute on function public.auth_is_owner() to authenticated;

create or replace function public.tg_employee_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_admin_role boolean;
begin
  if public.is_system_context() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'DELETE' then
    if old.is_owner then raise exception 'La cuenta propietaria no se puede eliminar'; end if;
    return old;
  end if;

  if (tg_op = 'INSERT' and new.is_owner) or (tg_op = 'UPDATE' and new.is_owner is distinct from old.is_owner) then
    raise exception 'La propiedad de la cuenta solo se transfiere desde la base de datos';
  end if;

  if tg_op = 'UPDATE' and old.is_owner and old.user_id is distinct from auth.uid() then
    raise exception 'Solo el propietario puede modificar su propia cuenta';
  end if;

  select exists (select 1 from public.roles r where r.code = 'admin'
                 and (r.id = new.role_id or (tg_op = 'UPDATE' and r.id = old.role_id)))
    into v_admin_role;
  if v_admin_role and not public.auth_is_owner()
     and (tg_op = 'INSERT' or old.user_id is distinct from auth.uid()) then
    raise exception 'Solo el propietario puede dar de alta o modificar administradores';
  end if;

  return new;
end $$;

drop trigger if exists trg_employee_owner_guard on public.employees;
create trigger trg_employee_owner_guard before insert or update or delete on public.employees
  for each row execute function public.tg_employee_owner_guard();

create or replace function public.tg_admin_role_protect()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_context() then return case when tg_op = 'DELETE' then old else new end; end if;

  if tg_table_name = 'role_permissions' then
    if exists (select 1 from public.roles r where r.id = old.role_id and r.code = 'admin') then
      raise exception 'El rol Administrador siempre conserva todos los permisos';
    end if;
    return old;
  end if;

  if tg_table_name = 'employee_permissions' then
    if exists (select 1 from public.employees e where e.id = new.employee_id and e.is_owner) and not new.is_granted then
      raise exception 'No se pueden revocar permisos al propietario';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' and old.code = 'admin' then raise exception 'El rol Administrador no se puede eliminar'; end if;
  if tg_op = 'UPDATE' and old.code = 'admin' and (new.code <> old.code or new.scope <> old.scope) then
    raise exception 'El rol Administrador no se puede cambiar de código ni de alcance';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists trg_admin_role_permissions on public.role_permissions;
create trigger trg_admin_role_permissions before delete on public.role_permissions
  for each row execute function public.tg_admin_role_protect();
drop trigger if exists trg_owner_permissions on public.employee_permissions;
create trigger trg_owner_permissions before insert or update on public.employee_permissions
  for each row execute function public.tg_admin_role_protect();
drop trigger if exists trg_admin_role on public.roles;
create trigger trg_admin_role before update or delete on public.roles
  for each row execute function public.tg_admin_role_protect();

create or replace function public.tg_permission_to_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.role_permissions (role_id, permission_code)
  select r.id, new.code from public.roles r where r.code = 'admin'
  on conflict do nothing;
  return null;
end $$;
drop trigger if exists trg_permission_to_admin on public.permissions;
create trigger trg_permission_to_admin after insert on public.permissions
  for each row execute function public.tg_permission_to_admin();

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code from public.roles r cross join public.permissions p
where r.code = 'admin'
on conflict do nothing;

create or replace view public.v_employees with (security_invoker = on) as
select e.id, e.user_id, e.company_id, e.branch_id, e.department_id, e.role_id,
       e.employee_code, e.username, e.full_name, e.position, e.email, e.phone,
       e.status, e.hired_at, e.created_at, e.updated_at,
       (e.user_id is not null) as has_account,
       r.code as role_code, r.name as role_name, r.scope as role_scope,
       b.name as branch_name, d.name as department_name, d.color as department_color,
       e.is_owner
from public.employees e
join public.roles r on r.id = e.role_id
left join public.branches b on b.id = e.branch_id
left join public.departments d on d.id = e.department_id;
grant select on public.v_employees to authenticated;

-- ─── 2. CONTRASEÑAS ─────────────────────────────────────────────────────────
create or replace function public.admin_set_password(p_employee_id uuid, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  t       public.employees%rowtype;
  v_scope text;
  v_email text;
  v_user  uuid;
  v_prev  text;
  v_new   boolean := false;
begin
  if not public.has_permission('manage_employees') then
    raise exception 'No tienes permiso para gestionar contraseñas';
  end if;
  if coalesce(length(p_password), 0) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;

  select * into t from public.employees where id = p_employee_id and company_id = public.auth_company_id();
  if not found then raise exception 'Empleado no encontrado'; end if;
  if t.status <> 'active' then raise exception 'El empleado está inactivo'; end if;

  select r.scope into v_scope from public.roles r where r.id = t.role_id;
  if t.user_id = auth.uid() then
    raise exception 'Para tu propia cuenta usa "Cambiar contraseña" en tu menú';
  end if;
  if t.is_owner then raise exception 'La contraseña del propietario solo la cambia él mismo'; end if;
  if v_scope = 'company' and not public.auth_is_owner() then
    raise exception 'Solo el propietario restablece contraseñas de administradores, soporte o auditoría';
  end if;
  if public.auth_role_scope() <> 'company' and t.branch_id is distinct from public.auth_branch_id() then
    raise exception 'Solo puedes gestionar empleados de tu sucursal';
  end if;

  if t.user_id is null then
    v_prev := public.set_bypass('on');
    v_email := lower(t.username) || '@operalia.local';
    select id into v_user from auth.users where email = v_email;
    if v_user is null then
      v_user := gen_random_uuid();
      v_new := true;
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token)
      values (
        '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email,
        crypt(p_password, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('username', lower(t.username), 'full_name', t.full_name, 'must_change_password', true),
        now(), now(), '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_user, v_user::text,
              jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
              'email', now(), now(), now());
    end if;
    update public.employees set user_id = v_user, email = coalesce(email, v_email) where id = t.id;
    perform public.set_bypass(v_prev);
  else
    v_user := t.user_id;
  end if;

  if not v_new then
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"must_change_password": true}'::jsonb,
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_user;
  end if;

  update public.notifications set is_read = true
   where company_id = t.company_id and link = '/employees?reset=' || t.id and not is_read;

  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, new_data)
  values (t.company_id, 'employees', t.id::text, 'UPDATE', public.auth_employee_id(),
          jsonb_build_object('evento', case when v_new then 'cuenta_creada' else 'contrasena_restablecida' end, 'username', t.username));

  return jsonb_build_object('username', t.username, 'created', v_new);
end $$;
revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;

create or replace function public.clear_must_change_password()
returns void language sql security definer set search_path = public as $$
  update auth.users set raw_user_meta_data = raw_user_meta_data - 'must_change_password'
  where id = auth.uid()
$$;
revoke all on function public.clear_must_change_password() from public, anon;
grant execute on function public.clear_must_change_password() to authenticated;

create or replace function public.request_password_reset(p_username text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t   public.employees%rowtype;
  ag  record;
  v_link text;
begin
  select * into t from public.employees
   where lower(username) = lower(split_part(trim(coalesce(p_username, '')), '@', 1))
     and status = 'active' limit 1;
  if not found then return; end if;

  v_link := '/employees?reset=' || t.id;
  if exists (select 1 from public.notifications
             where link = v_link and created_at > now() - interval '15 minutes') then
    return;
  end if;

  for ag in
    select distinct e.id from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = t.company_id and e.status = 'active' and e.id <> t.id
      and (e.is_owner
        or (r.code = 'admin' and not t.is_owner)
        or (exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'manage_employees')
            and r.scope = 'branch' and e.branch_id = t.branch_id
            and (select r2.scope from public.roles r2 where r2.id = t.role_id) not in ('company')))
  loop
    perform public.notify_employee(ag.id, 'password', 'Solicitud de contraseña: ' || t.full_name,
      '@' || t.username || ' olvidó su contraseña. Asígnale una temporal.', v_link);
  end loop;
end $$;
revoke all on function public.request_password_reset(text) from public;
grant execute on function public.request_password_reset(text) to anon, authenticated;

-- ─── 3. CHECKLISTS AUTOMÁTICOS CADA DÍA (pg_cron) ───────────────────────────
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.unschedule(jobid) from cron.job where jobname = 'operalia-mantenimiento';
  perform cron.schedule('operalia-mantenimiento', '5 * * * *',
    'select public.run_daily_maintenance(id) from public.companies');
exception when others then
  raise notice 'pg_cron no disponible (%). Actívalo en Database → Extensions y vuelve a ejecutar este archivo.', sqlerrm;
end $$;

-- ─── 4. CHECKLISTS NUEVOS ───────────────────────────────────────────────────
-- «Limpieza de cajas», «Recolección de carritos», «Recolección de devoluciones» y
-- «Revisión de tarimas y retornables» se siembran por empresa con
-- public.seed_company_base (migración 0023). La Sucursal Sur de Gato Pelón ya
-- se crea activa en seed/0008_catalogos.sql.


-- >>>>>>>>>>>>>>>> migrations/0013_checklists_criticos_y_horarios.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0013 · PREGUNTAS CRÍTICAS, TAREA AUTOMÁTICA Y HORARIOS POR SUCURSAL
-- -----------------------------------------------------------------------------
--   1. checklist_questions.is_critical: seguridad y valores (alarma, efectivo,
--      salidas de emergencia, caducados en exhibición...).
--   2. Tarea automática: una respuesta «No» crea una tarea para el departamento
--      del checklist (prioridad high si la pregunta es crítica) y avisa al jefe
--      del departamento; si es crítica también al gerente de la sucursal.
--      Si la respuesta se corrige a otra cosa, la tarea pendiente se cancela.
--      tasks.source_type/source_id ligan la tarea con su origen (sin duplicar).
--   3. Horarios relativos a la sucursal: checklist_templates.schedule_anchor
--      ('fixed' | 'opening' | 'closing') + desfases en minutos. Si la sucursal
--      no tiene opening_time/closing_time se usan start_time/end_time.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. PREGUNTAS CRÍTICAS ──────────────────────────────────────────────────
alter table public.checklist_questions add column if not exists is_critical boolean not null default false;

-- ─── 2. TAREA AUTOMÁTICA POR RESPUESTA «NO» ─────────────────────────────────
alter table public.tasks add column if not exists source_type text;
alter table public.tasks add column if not exists source_id uuid;
create unique index if not exists tasks_source_uidx on public.tasks (source_type, source_id) where source_id is not null;

create or replace function public.tg_checklist_answer_task()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_run   public.checklist_runs%rowtype;
  v_q     public.checklist_questions%rowtype;
  v_title text;
  v_task  uuid;
  v_actor uuid := public.auth_employee_id();
  v_prev  text;
  r       record;
begin
  select * into v_q from public.checklist_questions where id = new.question_id;
  if v_q.answer_type <> 'yes_no' then return null; end if;

  -- Corrección: dejó de ser «No» → cancelar la tarea si nadie la ha tomado.
  if tg_op = 'UPDATE' and old.answer_value = 'no' and new.answer_value is distinct from 'no' then
    v_prev := public.set_bypass('on');
    update public.tasks set status = 'cancelled', completion_notes = 'Se corrigió la respuesta del checklist'
     where source_type = 'checklist_answer' and source_id = new.id and status = 'pending';
    perform public.set_bypass(v_prev);
    return null;
  end if;

  if new.answer_value is distinct from 'no' or (tg_op = 'UPDATE' and old.answer_value = 'no') then
    return null;
  end if;

  select * into v_run from public.checklist_runs where id = new.run_id;
  select title into v_title from public.checklist_templates where id = v_run.template_id;

  v_prev := public.set_bypass('on');
  insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, created_by, source_type, source_id)
  values (v_run.company_id, v_run.branch_id, v_run.department_id,
          left((case when v_q.is_critical then 'CRÍTICO: ' else '' end) || v_q.text, 200),
          'Respuesta «No» en «' || v_title || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || ').'
            || coalesce(E'\nComentario: ' || nullif(trim(new.comment), ''), ''),
          case when v_q.is_critical then 'high' else 'medium' end,
          v_run.scheduled_date, v_actor, 'checklist_answer', new.id)
  on conflict (source_type, source_id) where source_id is not null
  do update set status = 'pending', completion_notes = null, completed_at = null
  returning id into v_task;
  perform public.set_bypass(v_prev);

  -- Avisos: jefes del departamento (revisan checklists) y, si es crítica, gerentes.
  for r in
    select distinct e.id
    from public.employees e
    join public.roles ro on ro.id = e.role_id
    where e.company_id = v_run.company_id and e.status = 'active'
      and e.id is distinct from v_actor
      and (e.branch_id = v_run.branch_id or ro.scope = 'company')
      and (
        (ro.code <> 'admin'
         and exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'review_checklists')
         and (e.department_id = v_run.department_id
              or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = v_run.department_id)))
        or (v_q.is_critical and ro.code = 'gerente' and e.branch_id = v_run.branch_id)
      )
  loop
    perform public.notify_employee(r.id, 'task',
      case when v_q.is_critical then 'Falla crítica en checklist' else 'Falla en checklist' end,
      v_title || ': ' || v_q.text, '/tasks');
  end loop;
  return null;
end $$;

drop trigger if exists trg_checklist_answer_task on public.checklist_answers;
create trigger trg_checklist_answer_task after insert or update of answer_value on public.checklist_answers
  for each row execute function public.tg_checklist_answer_task();

-- ─── 3. HORARIOS RELATIVOS A LA APERTURA / CIERRE DE LA SUCURSAL ────────────
alter table public.checklist_templates add column if not exists schedule_anchor text not null default 'fixed';
alter table public.checklist_templates add column if not exists start_offset_minutes integer;
alter table public.checklist_templates add column if not exists end_offset_minutes integer;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_anchor_chk
    check (schedule_anchor in ('fixed','opening','closing')
           and (schedule_anchor = 'fixed' or (start_offset_minutes is not null and end_offset_minutes is not null
                                              and end_offset_minutes > start_offset_minutes)));
exception when duplicate_object then null; end $$;

-- Ventana de una plantilla en una sucursal. Sin cruzar medianoche:
-- un inicio antes de las 00:00 se recorta a 00:00 y un fin después, a 23:59.
create or replace function public.checklist_window(
  p_anchor text, p_start time, p_end time, p_start_off int, p_end_off int, p_opening time, p_closing time,
  out win_start time, out win_end time)
language plpgsql immutable as $$
declare
  v_base time := case p_anchor when 'opening' then p_opening when 'closing' then p_closing end;
  v_base_min int;
begin
  if p_anchor = 'fixed' or v_base is null then
    win_start := p_start; win_end := p_end; return;
  end if;
  v_base_min := extract(hour from v_base)::int * 60 + extract(minute from v_base)::int;
  win_start := time '00:00' + make_interval(mins => greatest(0, least(1439, v_base_min + p_start_off)));
  win_end   := time '00:00' + make_interval(mins => greatest(0, least(1439, v_base_min + p_end_off)));
  if win_end <= win_start then
    win_start := p_start; win_end := p_end;
  end if;
end $$;

create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end)
  select t.company_id, t.id, b.id, t.department_id, p_date, w.win_start, w.win_end
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  cross join lateral public.checklist_window(t.schedule_anchor, t.start_time, t.end_time,
    t.start_offset_minutes, t.end_offset_minutes, b.opening_time, b.closing_time) w
  where t.company_id = p_company_id and t.is_active
    -- Las rondas de un día se generan juntas; si ya hay corridas de ese día no se agregan más
    -- (así cambiar la hora o la repetición de una plantilla aplica desde el día siguiente).
    and not exists (select 1 from public.checklist_runs x
                    where x.template_id = t.id and x.branch_id = b.id and x.scheduled_date = p_date)
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;
revoke all on function public.generate_checklist_runs(uuid, date) from public, anon, authenticated;


-- >>>>>>>>>>>>>>>> migrations/0014_temperaturas_y_mermas.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0014 · TEMPERATURAS (PREGUNTAS CON RANGO) Y MERMAS CON MOTIVO
-- -----------------------------------------------------------------------------
-- A) Temperaturas: no es un módulo aparte, es una pregunta numérica con rango.
--    * checklist_questions: min_value, max_value, unit, equipment_name.
--    * checklist_answers.out_of_range: lo calcula un trigger. Fuera de rango
--      cuenta como «No» en la calificación y crea la tarea automática de 0013
--      con prioridad high, avisando al jefe del departamento y al gerente.
--    * Una lectura fuera de rango exige comentario y foto para completar.
-- B) Mermas:
--    * inventory_movements: waste_reason (obligatorio en 'waste') y unit_cost
--      (copia products.cost al insertar si viene vacío).
--    * Permiso register_waste (los roles se asignan en seed/0012).
--    * Retirar o marcar vencido un lote de caducidades genera su merma
--      ('expired') automáticamente.
-- La conversión de las preguntas de temperatura existentes está en
-- seed/0012_temperaturas_y_mermas.sql (corre después de las semillas).
-- Re-ejecutable.
-- =============================================================================

-- ═══ A. TEMPERATURAS ═════════════════════════════════════════════════════════
alter table public.checklist_questions add column if not exists min_value numeric;
alter table public.checklist_questions add column if not exists max_value numeric;
alter table public.checklist_questions add column if not exists unit text;
alter table public.checklist_questions add column if not exists equipment_name text;
do $$ begin
  alter table public.checklist_questions add constraint checklist_questions_range_chk
    check (min_value is null or max_value is null or min_value <= max_value);
exception when duplicate_object then null; end $$;

alter table public.checklist_answers add column if not exists out_of_range boolean;

-- Calcula out_of_range y valida que la lectura sea un número.
create or replace function public.tg_checklist_answer_range()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  q public.checklist_questions%rowtype;
  v numeric;
begin
  select * into q from public.checklist_questions where id = new.question_id;
  new.out_of_range := null;
  if q.answer_type <> 'number' or (q.min_value is null and q.max_value is null)
     or coalesce(trim(new.answer_value), '') = '' then
    return new;
  end if;
  begin
    v := replace(trim(new.answer_value), ',', '.')::numeric;
  exception when others then
    raise exception 'La lectura de «%» debe ser un número', q.text;
  end;
  new.answer_value := v::text;
  new.out_of_range := (q.min_value is not null and v < q.min_value) or (q.max_value is not null and v > q.max_value);
  return new;
end $$;
drop trigger if exists trg_checklist_answer_range on public.checklist_answers;
create trigger trg_checklist_answer_range before insert or update on public.checklist_answers
  for each row execute function public.tg_checklist_answer_range();

-- Tarea automática (reemplaza la de 0013): «No» en sí/no o lectura fuera de rango.
create or replace function public.tg_checklist_answer_task()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_run    public.checklist_runs%rowtype;
  v_q      public.checklist_questions%rowtype;
  v_tmpl   text;
  v_actor  uuid := public.auth_employee_id();
  v_prev   text;
  v_fail   boolean;
  v_was    boolean;
  v_range  boolean;
  v_urgent boolean;
  v_title  text;
  v_desc   text;
  r        record;
begin
  select * into v_q from public.checklist_questions where id = new.question_id;
  v_range := v_q.answer_type = 'number' and (v_q.min_value is not null or v_q.max_value is not null);
  if v_q.answer_type <> 'yes_no' and not v_range then return null; end if;

  v_fail := case when v_range then coalesce(new.out_of_range, false) else new.answer_value = 'no' end;
  v_was  := tg_op = 'UPDATE' and case when v_range then coalesce(old.out_of_range, false) else old.answer_value = 'no' end;

  -- Corrección: ya no hay falla → cancelar la tarea si nadie la ha tomado.
  if v_was and not v_fail then
    v_prev := public.set_bypass('on');
    update public.tasks set status = 'cancelled', completion_notes = 'Se corrigió la respuesta del checklist'
     where source_type = 'checklist_answer' and source_id = new.id and status = 'pending';
    perform public.set_bypass(v_prev);
    return null;
  end if;
  if not v_fail or (v_was and not v_range) then return null; end if;

  select * into v_run from public.checklist_runs where id = new.run_id;
  select title into v_tmpl from public.checklist_templates where id = v_run.template_id;
  v_urgent := v_q.is_critical or v_range;

  if v_range then
    v_title := (case when v_q.unit ilike '%°%' then 'Temperatura fuera de rango: ' else 'Lectura fuera de rango: ' end)
               || coalesce(v_q.equipment_name, v_q.text) || ' ' || new.answer_value || coalesce(v_q.unit, '');
    v_desc  := 'Lectura en «' || v_tmpl || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || '). Rango permitido: '
               || coalesce(v_q.min_value::text, '−∞') || ' a ' || coalesce(v_q.max_value::text, '∞') || coalesce(' ' || v_q.unit, '') || '.';
  else
    v_title := (case when v_q.is_critical then 'CRÍTICO: ' else '' end) || v_q.text;
    v_desc  := 'Respuesta «No» en «' || v_tmpl || '» (' || to_char(v_run.scheduled_date, 'DD/MM/YYYY') || ').';
  end if;
  v_desc := v_desc || coalesce(E'\nComentario: ' || nullif(trim(new.comment), ''), '');

  v_prev := public.set_bypass('on');
  insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, created_by, source_type, source_id)
  values (v_run.company_id, v_run.branch_id, v_run.department_id, left(v_title, 200), v_desc,
          case when v_urgent then 'high' else 'medium' end, v_run.scheduled_date, v_actor, 'checklist_answer', new.id)
  on conflict (source_type, source_id) where source_id is not null
  do update set status = 'pending', title = excluded.title, description = excluded.description,
                completion_notes = null, completed_at = null;
  perform public.set_bypass(v_prev);

  for r in
    select distinct e.id
    from public.employees e
    join public.roles ro on ro.id = e.role_id
    where e.company_id = v_run.company_id and e.status = 'active'
      and e.id is distinct from v_actor
      and (e.branch_id = v_run.branch_id or ro.scope = 'company')
      and (
        (ro.code <> 'admin'
         and exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'review_checklists')
         and (e.department_id = v_run.department_id
              or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = v_run.department_id)))
        or (v_urgent and ro.code = 'gerente' and e.branch_id = v_run.branch_id)
      )
  loop
    perform public.notify_employee(r.id, 'task',
      case when v_range then left(v_title, 120) when v_q.is_critical then 'Falla crítica en checklist' else 'Falla en checklist' end,
      v_tmpl || ': ' || v_q.text, '/tasks');
  end loop;
  return null;
end $$;

-- Completar exige comentario y foto en cada lectura fuera de rango.
create or replace function public.tg_checklist_range_completion()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_missing int;
begin
  if new.status = 'completed' and old.status <> 'completed' then
    select count(*) into v_missing
    from public.checklist_answers a
    where a.run_id = new.id and a.out_of_range
      and (coalesce(trim(a.comment), '') = ''
           or not exists (select 1 from public.evidence_files ev where ev.entity_type = 'checklist_answer' and ev.entity_id = a.id));
    if v_missing > 0 then
      raise exception 'Hay % lectura(s) fuera de rango sin comentario o sin foto', v_missing;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_range_completion on public.checklist_runs;
create trigger trg_checklist_range_completion before update on public.checklist_runs
  for each row execute function public.tg_checklist_range_completion();

-- ═══ B. MERMAS ══════════════════════════════════════════════════════════════
alter table public.inventory_movements add column if not exists waste_reason text;
alter table public.inventory_movements add column if not exists unit_cost numeric(12,2);
do $$ begin
  alter table public.inventory_movements add constraint inventory_movements_waste_reason_chk
    check (waste_reason is null or waste_reason in ('expired','damaged','theft','mishandling','temperature','other'));
exception when duplicate_object then null; end $$;
create index if not exists movements_waste_idx on public.inventory_movements (branch_id, created_at) where movement_type = 'waste';

-- Históricos: costo actual del producto y motivo deducido del texto.
update public.inventory_movements m set unit_cost = p.cost
  from public.products p where p.id = m.product_id and m.unit_cost is null;
update public.inventory_movements set waste_reason = case when reason ilike '%caduc%' then 'expired' else 'other' end
 where movement_type = 'waste' and waste_reason is null;

create or replace function public.tg_movement_cost()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.unit_cost is null then
    select cost into new.unit_cost from public.products where id = new.product_id;
  end if;
  if new.movement_type = 'waste' and new.waste_reason is null then
    raise exception 'Indica el motivo de la merma';
  end if;
  if new.movement_type <> 'waste' then new.waste_reason := null; end if;
  return new;
end $$;
drop trigger if exists trg_movement_cost on public.inventory_movements;
create trigger trg_movement_cost before insert on public.inventory_movements
  for each row execute function public.tg_movement_cost();

insert into public.permissions (code, module, name, description) values
  ('register_waste', 'Inventario', 'Registrar mermas', 'Capturar merma con motivo, cantidad y foto')
on conflict (code) do nothing;

drop policy if exists movements_insert on public.inventory_movements;
create policy movements_insert on public.inventory_movements for insert to authenticated
  with check (public.can_access_branch(branch_id) and (
                 (select public.has_permission('manage_inventory'))
              or (movement_type = 'waste' and (select public.has_permission('register_waste')))
              or (movement_type = 'waste' and (select public.has_permission('manage_expirations')))));

-- Foto de la merma.
alter table public.evidence_files drop constraint if exists evidence_files_entity_type_check;
alter table public.evidence_files add constraint evidence_files_entity_type_check check (entity_type in (
  'checklist_run','checklist_answer','task','receiving_order','price_change','shelf_tag',
  'order','expiration','support_ticket','product','supplier_visit','inventory_movement','other'));

-- Caducidades: retirar (o marcar vencido a mano) genera la merma una sola vez.
-- El vencimiento automático del mantenimiento (contexto de sistema) no la genera:
-- el producto aún está en anaquel hasta que alguien lo retira.
create or replace function public.tg_expiration_waste()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_stock numeric; v_qty numeric;
begin
  if new.status in ('withdrawn','expired') and old.status is distinct from new.status
     and not public.is_system_context() and new.quantity > 0
     and not exists (select 1 from public.inventory_movements
                     where reference_type = 'product_expiration' and reference_id = new.id) then
    select stock into v_stock from public.inventory where branch_id = new.branch_id and product_id = new.product_id;
    v_qty := least(new.quantity, coalesce(v_stock, 0));
    if v_qty > 0 then
      insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity,
                                              waste_reason, reason, reference_type, reference_id)
      values (new.company_id, new.branch_id, new.product_id, 'waste', v_qty, 'expired',
              'Merma por caducidad · lote ' || coalesce(new.lot, 's/n'), 'product_expiration', new.id);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_expiration_waste on public.product_expirations;
create trigger trg_expiration_waste after update on public.product_expirations
  for each row execute function public.tg_expiration_waste();

-- La vista expone las columnas nuevas (m.* se fija al crear la vista).
drop view if exists public.v_inventory_movements;
create view public.v_inventory_movements with (security_invoker = on) as
select m.*, p.sku, p.name as product_name, p.unit, b.name as branch_name,
       e.full_name as created_by_name,
       round(m.quantity * coalesce(m.unit_cost, 0), 2) as total_cost
from public.inventory_movements m
join public.products p on p.id = m.product_id
join public.branches b on b.id = m.branch_id
left join public.employees e on e.id = m.created_by;
grant select on public.v_inventory_movements to authenticated;

-- v_tasks también fija t.*: se recrea para incluir source_type/source_id (0013).
drop view if exists public.v_tasks;
create view public.v_tasks with (security_invoker = on) as
select t.*, d.name as department_name, b.name as branch_name,
       ea.full_name as assigned_to_name, ec.full_name as created_by_name,
       (select count(*) from public.evidence_files ev where ev.entity_type = 'task' and ev.entity_id = t.id) as evidence_count,
       (t.status in ('pending','in_progress') and t.due_date < public.company_today(t.company_id)) as is_late
from public.tasks t
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees ea on ea.id = t.assigned_to
left join public.employees ec on ec.id = t.created_by;
grant select on public.v_tasks to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0015_zonas_jefe_escaner.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0015 · ZONAS, ALCANCE 'zone' Y OFERTAS POR ZONA
-- -----------------------------------------------------------------------------
--   1. zones + branches.zone_id. Las zonas demo y la asignación de sucursales
--      están en seed/0013_zonas_jefe_escaner.sql.
--   2. Alcance de rol 'zone' + employee_zones: un rol 'zone' ve todas las
--      sucursales de sus zonas, y dentro de ellas solo su(s) departamento(s)
--      (igual que el alcance 'department').
--      Revisado contra 0005 y posteriores: can_access_branch, empleados,
--      notificaciones por departamento, tickets, cambios de precio y guardas
--      de empleados.
--   3. price_changes.zone_id: el cambio aplica a las sucursales de esa zona.
--   4. branch_prices: precio por sucursal. Antes cualquier cambio (aunque fuera
--      de una sola sucursal) cambiaba products.price para todas las tiendas.
--      Ahora un cambio de sucursal o zona guarda el precio en branch_prices;
--      uno de toda la empresa sigue cambiando products.price.
--      v_inventory muestra el precio efectivo de cada sucursal.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. ZONAS ───────────────────────────────────────────────────────────────
create table if not exists public.zones (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete cascade,
  code        text not null,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (company_id, code)
);
alter table public.branches add column if not exists zone_id uuid references public.zones(id) on delete set null;
create index if not exists branches_zone_idx on public.branches (zone_id);

drop trigger if exists trg_updated_at on public.zones;
create trigger trg_updated_at before update on public.zones
  for each row execute function public.tg_set_updated_at();

-- ─── 2. ALCANCE 'zone' ──────────────────────────────────────────────────────
do $$
declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.roles'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%scope%'
  loop
    execute format('alter table public.roles drop constraint %I', c);
  end loop;
  alter table public.roles add constraint roles_scope_check check (scope in ('company','zone','branch','department','self'));
end $$;

create table if not exists public.employee_zones (
  employee_id uuid not null references public.employees(id) on delete cascade,
  zone_id     uuid not null references public.zones(id) on delete cascade,
  primary key (employee_id, zone_id)
);
create index if not exists employee_zones_zone_idx on public.employee_zones (zone_id);

-- Zonas del usuario actual (solo aplica a roles con alcance 'zone').
create or replace function public.auth_zone_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select ez.zone_id from public.employee_zones ez where ez.employee_id = public.auth_employee_id()
$$;

-- ¿Puede ver datos de esta sucursal?
--   company → cualquier sucursal de su empresa
--   zone    → las sucursales de sus zonas
--   demás   → solo la suya
create or replace function public.can_access_branch(p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_branch_id is null then false
    when public.auth_role_scope() = 'company' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id())
    when public.auth_role_scope() = 'zone' then exists (
      select 1 from public.branches b
      where b.id = p_branch_id and b.company_id = public.auth_company_id()
        and b.zone_id in (select public.auth_zone_ids()))
    else p_branch_id = public.auth_branch_id()
  end
$$;
-- can_access_department no cambia: 'zone' cae en la rama de departamento
-- (su departamento o los de employee_departments) después de validar la sucursal.

-- Notificaciones por departamento: el jefe de zona las recibe de sus sucursales.
create or replace function public.is_my_notification(p_employee_id uuid, p_department_id uuid, p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_employee_id is not null then p_employee_id = public.auth_employee_id()
    else (p_branch_id is null or p_branch_id = public.auth_branch_id()
          or (public.auth_role_scope() = 'zone' and public.can_access_branch(p_branch_id)))
     and (p_department_id = public.auth_department_id()
          or exists (select 1 from public.employee_departments ed
                     where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id))
  end
$$;

-- Tickets: el jefe de zona ve los de su departamento en sus sucursales.
create or replace function public.can_view_ticket(p_created_by uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_created_by = public.auth_employee_id()
      or public.has_permission('manage_tickets')
      or (public.auth_role_scope() in ('company','zone','branch','department')
          and public.can_access_department(p_branch_id, p_department_id))
$$;

-- Empleados: el jefe de zona ve (y, si tiene permiso, gestiona) a los de sus sucursales.
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (select public.auth_role_scope()) = 'company'
      or branch_id = (select public.auth_branch_id())
      or ((select public.auth_role_scope()) = 'zone' and public.can_access_branch(branch_id))
      or user_id = (select auth.uid())));
drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_employees'))
         and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(branch_id)))
  with check (company_id = (select public.auth_company_id()));

-- Guarda de empleados: solo un administrador asigna roles de empresa o de zona.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.tg_employee_guard()'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');  -- por si se instaló desde un archivo con CRLF
  if position('v_target_scope = ''zone''' in v_src) = 0 then
    v_src := replace(v_src,
      'if v_target_scope = ''company'' and public.auth_role_scope() <> ''company'' then',
      'if v_target_scope = ''zone'' and public.auth_role_scope() <> ''company'' then
    raise exception ''Solo un administrador puede asignar roles con alcance de zona'';
  end if;
  if v_target_scope = ''company'' and public.auth_role_scope() <> ''company'' then');
    v_src := replace(v_src,
      'if public.auth_role_scope() <> ''company'' and new.branch_id is distinct from public.auth_branch_id() then',
      'if public.auth_role_scope() <> ''company'' and not public.can_access_branch(new.branch_id) then');
    execute v_src;
  end if;
end $$;

-- Zonas y asignaciones: lectura en la empresa; escritura con manage_branches / manage_employees.
alter table public.zones enable row level security;
drop policy if exists zones_select on public.zones;
create policy zones_select on public.zones for select to authenticated
  using (company_id = (select public.auth_company_id()));
drop policy if exists zones_write on public.zones;
create policy zones_write on public.zones for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches')));

alter table public.employee_zones enable row level security;
drop policy if exists employee_zones_select on public.employee_zones;
create policy employee_zones_select on public.employee_zones for select to authenticated
  using (exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));
drop policy if exists employee_zones_write on public.employee_zones;
create policy employee_zones_write on public.employee_zones for all to authenticated
  using ((select public.has_permission('manage_employees')) and (select public.auth_role_scope()) = 'company'
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.has_permission('manage_employees')) and (select public.auth_role_scope()) = 'company'
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id()))
         and exists (select 1 from public.zones z where z.id = zone_id and z.company_id = (select public.auth_company_id())));

grant select, insert, update, delete on public.zones, public.employee_zones to authenticated;
grant execute on function public.auth_zone_ids() to authenticated;

-- Perfil: incluye las zonas del usuario.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;

-- ─── 3. CAMBIOS DE PRECIO POR ZONA ──────────────────────────────────────────
alter table public.price_changes add column if not exists zone_id uuid references public.zones(id) on delete set null;
do $$ begin
  alter table public.price_changes add constraint price_changes_scope_chk check (zone_id is null or branch_id is null);
exception when duplicate_object then null; end $$;

drop policy if exists price_changes_select on public.price_changes;
create policy price_changes_select on public.price_changes for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
         (branch_id is null and zone_id is null)
      or public.can_access_branch(branch_id)
      or (select public.auth_role_scope()) = 'company'
      or zone_id in (select public.auth_zone_ids())
      or exists (select 1 from public.branches b where b.id = (select public.auth_branch_id()) and b.zone_id = price_changes.zone_id)));
drop policy if exists price_changes_insert on public.price_changes;
create policy price_changes_insert on public.price_changes for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
              and (
                    (branch_id is null and zone_id is null and (select public.auth_role_scope()) = 'company')
                 or (zone_id is not null and ((select public.auth_role_scope()) = 'company' or zone_id in (select public.auth_zone_ids())))
                 or (branch_id is not null and public.can_access_branch(branch_id))));

-- ─── 4. PRECIO POR SUCURSAL ─────────────────────────────────────────────────
create table if not exists public.branch_prices (
  branch_id       uuid not null references public.branches(id) on delete cascade,
  product_id      uuid not null references public.products(id) on delete cascade,
  company_id      uuid not null references public.companies(id) on delete cascade,
  price           numeric(12,2) not null check (price > 0),
  previous_price  numeric(12,2),
  price_change_id uuid references public.price_changes(id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (branch_id, product_id)
);
alter table public.branch_prices enable row level security;
drop policy if exists branch_prices_select on public.branch_prices;
create policy branch_prices_select on public.branch_prices for select to authenticated
  using (company_id = (select public.auth_company_id()));
grant select on public.branch_prices to authenticated;

-- Precio vigente de un producto en una sucursal.
create or replace function public.effective_price(p_product_id uuid, p_branch_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select bp.price from public.branch_prices bp where bp.branch_id = p_branch_id and bp.product_id = p_product_id),
                  (select p.price from public.products p where p.id = p_product_id))
$$;
grant execute on function public.effective_price(uuid, uuid) to authenticated;

-- old_price = precio vigente en el alcance del cambio.
create or replace function public.tg_price_change_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.branch_id is not null then
    new.old_price := public.effective_price(new.product_id, new.branch_id);
  else
    select price into new.old_price from public.products where id = new.product_id;
  end if;
  if new.old_price is null then raise exception 'Producto no encontrado'; end if;
  if new.new_price = new.old_price then
    raise exception 'El precio nuevo es igual al actual (%)', new.old_price;
  end if;
  new.status := 'scheduled';
  new.applied_at := null;
  return new;
end $$;

create or replace function public.apply_price_change(p_price_change_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  pc     public.price_changes%rowtype;
  v_prev text;
begin
  select * into pc from public.price_changes where id = p_price_change_id for update;
  if not found or pc.status <> 'scheduled' then return; end if;

  v_prev := public.set_bypass('on');

  if pc.branch_id is null and pc.zone_id is null then
    -- Toda la empresa: precio base del producto.
    update public.products
       set previous_price = price, price = pc.new_price, price_updated_at = now()
     where id = pc.product_id;
  else
    -- Sucursal o zona: precio propio de cada sucursal afectada.
    insert into public.branch_prices (branch_id, product_id, company_id, price, previous_price, price_change_id, updated_at)
    select b.id, pc.product_id, pc.company_id, pc.new_price, public.effective_price(pc.product_id, b.id), pc.id, now()
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and (b.id = pc.branch_id or b.zone_id = pc.zone_id)
    on conflict (branch_id, product_id) do update
      set previous_price = public.branch_prices.price, price = excluded.price,
          price_change_id = excluded.price_change_id, updated_at = now();
  end if;

  update public.price_changes set status = 'applied', applied_at = now() where id = pc.id;

  if pc.requires_tag then
    update public.shelf_tags st
       set status = 'rejected', rejection_reason = 'Reemplazada por un cambio de precio más reciente'
     where st.product_id = pc.product_id and st.status in ('pending','printed')
       and ((pc.branch_id is null and pc.zone_id is null) or st.branch_id = pc.branch_id
            or st.branch_id in (select b.id from public.branches b where b.zone_id = pc.zone_id));

    insert into public.shelf_tags (company_id, branch_id, product_id, price_change_id)
    select pc.company_id, b.id, pc.product_id, pc.id
    from public.branches b
    where b.company_id = pc.company_id and b.status = 'active'
      and ((pc.branch_id is null and pc.zone_id is null) or b.id = pc.branch_id or b.zone_id = pc.zone_id);
  end if;

  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.apply_price_change(uuid) from public, anon, authenticated;

-- v_inventory con el precio efectivo de cada sucursal y su zona.
drop view if exists public.v_inventory;
create view public.v_inventory with (security_invoker = on) as
select i.id, i.company_id, i.branch_id, i.product_id, i.stock, i.min_stock, i.max_stock,
       i.location, i.status, i.last_movement_at, i.last_counted_at, i.updated_at,
       p.sku, p.name as product_name, p.category, p.unit,
       coalesce(bp.price, p.price) as price,
       case when bp.price is not null then bp.previous_price else p.previous_price end as previous_price,
       coalesce(bp.updated_at, p.price_updated_at) as price_updated_at,
       p.department_id, p.controls_expiration, p.status as product_status,
       d.name as department_name, b.name as branch_name, b.zone_id,
       (bp.price is not null) as has_branch_price,
       (select string_agg(pb.barcode, ' ' order by pb.is_primary desc)
          from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       exists (select 1 from public.shelf_tags st
               where st.product_id = p.id and st.branch_id = i.branch_id
                 and st.status in ('pending','printed','placed')) as has_pending_tag
from public.inventory i
join public.products p on p.id = i.product_id
join public.branches b on b.id = i.branch_id
left join public.branch_prices bp on bp.branch_id = i.branch_id and bp.product_id = i.product_id
left join public.departments d on d.id = p.department_id;
grant select on public.v_inventory to authenticated;

-- v_price_changes con la zona.
drop view if exists public.v_price_changes;
create view public.v_price_changes with (security_invoker = on) as
select pc.*, p.sku, p.name as product_name, b.name as branch_name, z.name as zone_name,
       e.full_name as created_by_name,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id) as tags_total,
       (select count(*) from public.shelf_tags st where st.price_change_id = pc.id and st.status = 'validated') as tags_validated
from public.price_changes pc
join public.products p on p.id = pc.product_id
left join public.branches b on b.id = pc.branch_id
left join public.zones z on z.id = pc.zone_id
left join public.employees e on e.id = pc.created_by;
grant select on public.v_price_changes to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0016_checklists_repetidos.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0016 · CHECKLISTS QUE SE REPITEN VARIAS VECES AL DÍA (RONDAS)
-- -----------------------------------------------------------------------------
--   * checklist_templates.repeat_every_minutes (null = una vez al día; mínimo
--     30) y repeat_until (último inicio permitido; por defecto la hora de
--     cierre de la sucursal o, si no tiene, el end_time de la plantilla).
--   * checklist_runs: la restricción única pasa de (plantilla, sucursal, fecha)
--     a (plantilla, sucursal, fecha, hora de inicio). Cada ronda guarda
--     round_no y rounds_total («Ronda 3 de 6»).
--   * generate_checklist_runs crea una corrida por intervalo; cada ronda tiene
--     la misma duración que la ventana original (sin pasar de 23:59).
--   * Lo demás ya trabajaba por corrida: el marcado de vencidos usa el
--     scheduled_end de cada ronda, la cancelación (0010) aplica a una ronda y
--     la tarea automática (0013/0014) se liga a la respuesta de esa ronda.
-- Ejemplo en seed/0014_checklists_repetidos.sql. Re-ejecutable.
-- =============================================================================

alter table public.checklist_templates add column if not exists repeat_every_minutes integer;
alter table public.checklist_templates add column if not exists repeat_until time;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_repeat_chk
    check (repeat_every_minutes is null or repeat_every_minutes >= 30);
exception when duplicate_object then null; end $$;

alter table public.checklist_runs add column if not exists round_no integer not null default 1;
alter table public.checklist_runs add column if not exists rounds_total integer not null default 1;

-- Restricción única: se busca por columnas (el nombre real puede variar).
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.checklist_runs'::regclass and con.contype = 'u'
      and (select array_agg(att.attname::text order by att.attname) from pg_attribute att
           where att.attrelid = con.conrelid and att.attnum = any(con.conkey))
          = array['branch_id','scheduled_date','template_id']
  loop
    execute format('alter table public.checklist_runs drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'checklist_runs_template_branch_date_start_key') then
    alter table public.checklist_runs add constraint checklist_runs_template_branch_date_start_key
      unique (template_id, branch_id, scheduled_date, scheduled_start);
  end if;
end $$;

create or replace function public.generate_checklist_runs(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  insert into public.checklist_runs
    (company_id, template_id, branch_id, department_id, scheduled_date, scheduled_start, scheduled_end, round_no, rounds_total)
  select t.company_id, t.id, b.id, t.department_id, p_date,
         r.starts_at::time,
         least(r.starts_at + (w.win_end - w.win_start), p_date + time '23:59')::time,
         r.n, r.total
  from public.checklist_templates t
  join public.branches b on b.company_id = t.company_id and b.status = 'active'
  cross join lateral public.checklist_window(t.schedule_anchor, t.start_time, t.end_time,
    t.start_offset_minutes, t.end_offset_minutes, b.opening_time, b.closing_time) w
  cross join lateral (
    select s.starts_at, s.n::int, count(*) over ()::int as total
    from generate_series(
           p_date + w.win_start,
           p_date + case when t.repeat_every_minutes is null then w.win_start
                         else greatest(w.win_start, coalesce(t.repeat_until, b.closing_time, t.end_time)) end,
           make_interval(mins => coalesce(t.repeat_every_minutes, 1440))
         ) with ordinality as s(starts_at, n)
    where s.starts_at < p_date + time '23:59'
  ) r
  where t.company_id = p_company_id and t.is_active
    -- Las rondas de un día se generan juntas; si ya hay corridas de ese día no se agregan más
    -- (así cambiar la hora o la repetición de una plantilla aplica desde el día siguiente).
    and not exists (select 1 from public.checklist_runs x
                    where x.template_id = t.id and x.branch_id = b.id and x.scheduled_date = p_date)
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows;
end $$;
revoke all on function public.generate_checklist_runs(uuid, date) from public, anon, authenticated;

-- v_checklist_runs fija r.* al crearse: se recrea para incluir round_no/rounds_total
-- y la configuración de repetición de la plantilla.
drop view if exists public.v_checklist_runs;
create view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       t.repeat_every_minutes,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;
grant select on public.v_checklist_runs to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0017_recordatorio_checklists.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0017 · RECORDATORIO 30 MINUTOS ANTES DE QUE VENZA UN CHECKLIST
-- -----------------------------------------------------------------------------
--   * checklist_runs.reminded_at: el aviso se manda una sola vez por corrida
--     (por ronda, en los checklists que se repiten).
--   * send_checklist_reminders(empresa): corridas de hoy que siguen en
--     pending / in_progress / reopened, ya empezaron y vencen en ≤ 30 min
--     (hora de la empresa). Avisa:
--       - a su departamento en esa sucursal (notificación de departamento, 0008);
--       - a quien lo inició, si no es de ese departamento;
--       - si el checklist no tiene departamento, a los gerentes de la sucursal.
--   * pg_cron: job 'operalia-recordatorios' cada 5 minutos (el de 0012 corre
--     cada hora, demasiado espaciado para avisar 30 minutos antes).
--   * run_daily_maintenance también envía los recordatorios, así funciona
--     aunque pg_cron no esté activo (cuando alguien abre Checklists).
-- Re-ejecutable.
-- =============================================================================

alter table public.checklist_runs add column if not exists reminded_at timestamptz;
create index if not exists checklist_runs_reminder_idx on public.checklist_runs (company_id, scheduled_date)
  where reminded_at is null and status in ('pending','in_progress','reopened');

create or replace function public.send_checklist_reminders(p_company_id uuid, p_minutes int default 30)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_tz    text;
  v_today date;
  v_now   time;
  v_prev  text;
  v_count int := 0;
  r       record;
  g       record;
  v_title text;
  v_body  text;
begin
  select timezone into v_tz from public.companies where id = p_company_id;
  if v_tz is null then return 0; end if;
  v_today := (now() at time zone v_tz)::date;
  v_now   := (now() at time zone v_tz)::time;

  v_prev := public.set_bypass('on');
  for r in
    update public.checklist_runs cr
       set reminded_at = now()
     where cr.company_id = p_company_id
       and cr.scheduled_date = v_today
       and cr.status in ('pending','in_progress','reopened')
       and cr.reminded_at is null
       and cr.scheduled_start <= v_now
       and cr.scheduled_end > v_now
       and cr.scheduled_end - v_now <= make_interval(mins => p_minutes)
    returning cr.*
  loop
    select t.title || case when r.rounds_total > 1 then ' (ronda ' || r.round_no || ' de ' || r.rounds_total || ')' else '' end
      into v_title from public.checklist_templates t where t.id = r.template_id;
    v_body := 'Vence a las ' || to_char(r.scheduled_end, 'HH24:MI')
              || case when r.status = 'pending' then ' y aún no se inicia.' else ' y aún no se completa.' end;

    if r.department_id is not null then
      insert into public.notifications (company_id, employee_id, department_id, branch_id, type, title, body, link)
      values (r.company_id, null, r.department_id, r.branch_id, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
    else
      for g in
        select e.id from public.employees e join public.roles ro on ro.id = e.role_id
        where e.branch_id = r.branch_id and e.status = 'active' and ro.code = 'gerente'
      loop
        perform public.notify_employee(g.id, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
      end loop;
    end if;

    -- Quien lo inició y no pertenece a ese departamento (p. ej. un gerente).
    if r.started_by is not null and not exists (
         select 1 from public.employees e where e.id = r.started_by
           and (e.department_id = r.department_id
                or exists (select 1 from public.employee_departments ed where ed.employee_id = e.id and ed.department_id = r.department_id))) then
      perform public.notify_employee(r.started_by, 'checklist', 'Checklist por vencer: ' || v_title, v_body, '/checklists');
    end if;
    v_count := v_count + 1;
  end loop;
  perform public.set_bypass(v_prev);
  return v_count;
end $$;
revoke all on function public.send_checklist_reminders(uuid, int) from public, anon, authenticated;

-- El mantenimiento diario también envía los recordatorios (sin depender de pg_cron).
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');  -- por si se instaló desde un archivo con CRLF
  if position('send_checklist_reminders' in v_src) = 0 then
    v_src := replace(v_src,
      '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(',
      '  perform public.send_checklist_reminders(v_company);' || chr(10)
      || '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(');
    if position('send_checklist_reminders' in v_src) = 0 then
      raise exception 'No se pudo extender run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- pg_cron: cada 5 minutos (si la extensión está activa).
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'operalia-recordatorios';
  perform cron.schedule('operalia-recordatorios', '*/5 * * * *',
    'select public.send_checklist_reminders(id) from public.companies');
exception when others then
  raise notice 'pg_cron no disponible (%). Los recordatorios se enviarán cuando alguien abra Checklists.', sqlerrm;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0018_puntos_qr.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0018 · PUNTOS DE CONTROL CON QR (ZONA O EQUIPO)
-- -----------------------------------------------------------------------------
--   * checkpoints: punto físico de una sucursal (p. ej. «Cámara de carnes»,
--     «Área de carritos») con un código único que va impreso en un QR.
--   * checklist_templates.checkpoint_required + checkpoint_id: la plantilla
--     exige escanear el QR del punto para iniciar.
--     Las plantillas son de toda la empresa y los puntos de cada sucursal:
--     checkpoint_id señala el punto «modelo» y en cada sucursal vale el punto
--     con el MISMO NOMBRE (cada tienda imprime su propio QR).
--   * start_checklist_with_checkpoint(run, código): valida el código contra
--     la sucursal de la corrida, guarda checkpoint_scanned_at y la inicia.
--   * Sin el escaneo no se puede iniciar ni responder (un trigger lo impide
--     también si alguien intenta iniciarla por otro camino).
--   * Permiso manage_checkpoints (roles en seed/0015_puntos_qr.sql).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.checkpoints (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  branch_id      uuid not null references public.branches(id) on delete cascade,
  department_id  uuid references public.departments(id) on delete set null,
  name           text not null,
  code           text not null unique default ('OPQ-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (branch_id, name)
);
create index if not exists checkpoints_branch_idx on public.checkpoints (branch_id);

drop trigger if exists trg_updated_at on public.checkpoints;
create trigger trg_updated_at before update on public.checkpoints
  for each row execute function public.tg_set_updated_at();

alter table public.checklist_templates add column if not exists checkpoint_required boolean not null default false;
alter table public.checklist_templates add column if not exists checkpoint_id uuid references public.checkpoints(id) on delete set null;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_checkpoint_chk
    check (not checkpoint_required or checkpoint_id is not null);
exception when duplicate_object then null; end $$;
alter table public.checklist_runs add column if not exists checkpoint_scanned_at timestamptz;
alter table public.checklist_runs add column if not exists checkpoint_id uuid references public.checkpoints(id) on delete set null;

insert into public.permissions (code, module, name, description) values
  ('manage_checkpoints', 'Checklists', 'Gestionar puntos QR', 'Crear puntos de control e imprimir sus códigos QR')
on conflict (code) do nothing;

alter table public.checkpoints enable row level security;
drop policy if exists checkpoints_select on public.checkpoints;
create policy checkpoints_select on public.checkpoints for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_branch(branch_id));
drop policy if exists checkpoints_write on public.checkpoints;
create policy checkpoints_write on public.checkpoints for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checkpoints'))
         and public.can_access_branch(branch_id))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checkpoints'))
         and public.can_access_branch(branch_id));
grant select, insert, update, delete on public.checkpoints to authenticated;

-- Punto válido para una corrida: el de su sucursal con el nombre del punto modelo.
create or replace function public.checkpoint_for_run(p_run_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select c.id
  from public.checklist_runs r
  join public.checklist_templates t on t.id = r.template_id
  join public.checkpoints model on model.id = t.checkpoint_id
  join public.checkpoints c on c.branch_id = r.branch_id and c.name = model.name and c.is_active
  where r.id = p_run_id
$$;

-- Sin escaneo no se inicia (incluye la respuesta que pasa la corrida a «en progreso»).
create or replace function public.tg_checklist_run_checkpoint()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'in_progress' and old.status in ('pending','reopened') and new.checkpoint_scanned_at is null
     and exists (select 1 from public.checklist_templates t where t.id = new.template_id and t.checkpoint_required)
     and coalesce(current_setting('operalia.bypass', true), '') <> 'on' then
    raise exception 'Escanea el código QR del punto para iniciar este checklist';
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_run_checkpoint on public.checklist_runs;
create trigger trg_checklist_run_checkpoint before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_checkpoint();

create or replace function public.start_checklist_with_checkpoint(p_run_id uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r          public.checklist_runs%rowtype;
  v_expected uuid;
  v_scanned  public.checkpoints%rowtype;
begin
  select * into r from public.checklist_runs where id = p_run_id;
  if not found or r.company_id <> public.auth_company_id()
     or not public.has_permission('fill_checklists')
     or not public.can_access_department(r.branch_id, r.department_id) then
    raise exception 'No puedes iniciar este checklist';
  end if;
  if r.status not in ('pending','reopened','in_progress') then
    raise exception 'Este checklist ya no se puede iniciar';
  end if;

  v_expected := public.checkpoint_for_run(p_run_id);
  if v_expected is null then
    raise exception 'Esta sucursal no tiene registrado el punto QR de este checklist; pide al gerente que lo cree';
  end if;
  select * into v_scanned from public.checkpoints where upper(code) = upper(trim(p_code));
  if not found or v_scanned.id <> v_expected then
    raise exception 'Código incorrecto: escanea el QR de «%»', (select name from public.checkpoints where id = v_expected);
  end if;

  update public.checklist_runs
     set checkpoint_scanned_at = now(), checkpoint_id = v_scanned.id,
         status = case when status in ('pending','reopened') then 'in_progress' else status end
   where id = p_run_id;
  return jsonb_build_object('run_id', p_run_id, 'checkpoint', v_scanned.name);
end $$;
revoke all on function public.start_checklist_with_checkpoint(uuid, text) from public, anon;
grant execute on function public.start_checklist_with_checkpoint(uuid, text) to authenticated;

-- v_checklist_runs: datos del punto QR.
drop view if exists public.v_checklist_runs;
create view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       t.repeat_every_minutes, t.checkpoint_required,
       (select m.name from public.checkpoints m where m.id = t.checkpoint_id) as checkpoint_name,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;
grant select on public.v_checklist_runs to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0019_conteo_ciclico.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0019 · CONTEO CÍCLICO DE INVENTARIO
-- -----------------------------------------------------------------------------
--   * cycle_count_plans: qué contar (sucursal + departamento o categoría,
--     opcionales), cada cuándo y cuántos productos por conteo.
--   * cycle_count_tasks: una tarea por plan y día con una lista corta
--     (cycle_count_items). Orden de prioridad:
--       1. productos con más diferencias en conteos de los últimos 90 días;
--       2. mayor rotación (salidas y mermas de los últimos 30 días);
--       3. los que llevan más tiempo sin contarse.
--     Se generan con generate_cycle_counts (lo llama run_daily_maintenance,
--     que pg_cron corre cada hora desde 0012).
--   * record_cycle_count(item, cantidad): conteo a ciegas. Registra un
--     movimiento 'count' (deja la existencia en lo contado) y guarda la
--     diferencia en piezas y en pesos (unit_cost de 0014).
--   * Permisos: perform_cycle_counts (contar) y manage_cycle_counts (planes).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.cycle_count_plans (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete set null,
  category         text,
  name             text not null,
  frequency        text not null default 'daily' check (frequency in ('daily','weekdays','weekly')),
  weekday          smallint check (weekday between 0 and 6),
  items_per_count  integer not null default 10 check (items_per_count between 1 and 100),
  is_active        boolean not null default true,
  created_by       uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (frequency <> 'weekly' or weekday is not null)
);

create table if not exists public.cycle_count_tasks (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  plan_id          uuid not null references public.cycle_count_plans(id) on delete cascade,
  branch_id        uuid not null references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete set null,
  scheduled_date   date not null,
  status           text not null default 'pending' check (status in ('pending','in_progress','completed','cancelled')),
  items_total      integer not null default 0,
  items_counted    integer not null default 0,
  items_with_diff  integer not null default 0,
  diff_value       numeric(12,2) not null default 0,
  started_at       timestamptz,
  completed_at     timestamptz,
  completed_by     uuid references public.employees(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (plan_id, scheduled_date)
);
create index if not exists cycle_count_tasks_branch_idx on public.cycle_count_tasks (branch_id, scheduled_date);

create table if not exists public.cycle_count_items (
  id                uuid primary key default gen_random_uuid(),
  task_id           uuid not null references public.cycle_count_tasks(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  position          integer not null,
  priority_reason   text not null check (priority_reason in ('differences','rotation','oldest')),
  expected_qty      numeric(12,3),
  counted_qty       numeric(12,3),
  difference        numeric(12,3),
  difference_value  numeric(12,2),
  movement_id       uuid references public.inventory_movements(id) on delete set null,
  counted_by        uuid references public.employees(id) on delete set null,
  counted_at        timestamptz,
  unique (task_id, product_id)
);
create index if not exists cycle_count_items_product_idx on public.cycle_count_items (product_id, counted_at);

do $$
declare t text;
begin
  foreach t in array array['cycle_count_plans','cycle_count_tasks'] loop
    execute format('drop trigger if exists trg_updated_at on public.%I', t);
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()', t);
  end loop;
end $$;
drop trigger if exists trg_actor on public.cycle_count_plans;
create trigger trg_actor before insert on public.cycle_count_plans
  for each row execute function public.tg_set_actor('created_by');

insert into public.permissions (code, module, name, description) values
  ('perform_cycle_counts', 'Inventario', 'Hacer conteos cíclicos', 'Contar los productos de las tareas de conteo del día'),
  ('manage_cycle_counts',  'Inventario', 'Planear conteos cíclicos', 'Crear planes de conteo cíclico y ver diferencias')
on conflict (code) do nothing;

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.cycle_count_plans enable row level security;
alter table public.cycle_count_tasks enable row level security;
alter table public.cycle_count_items enable row level security;

drop policy if exists cycle_plans_select on public.cycle_count_plans;
create policy cycle_plans_select on public.cycle_count_plans for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_department(branch_id, department_id));
drop policy if exists cycle_plans_write on public.cycle_count_plans;
create policy cycle_plans_write on public.cycle_count_plans for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_cycle_counts'))
         and public.can_access_branch(branch_id))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_cycle_counts'))
         and public.can_access_branch(branch_id));

-- Tareas y renglones solo se leen; se escriben con las funciones de abajo.
drop policy if exists cycle_tasks_select on public.cycle_count_tasks;
create policy cycle_tasks_select on public.cycle_count_tasks for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_department(branch_id, department_id)
         and ((select public.has_permission('perform_cycle_counts')) or (select public.has_permission('manage_cycle_counts'))
              or (select public.has_permission('view_reports'))));
drop policy if exists cycle_items_select on public.cycle_count_items;
create policy cycle_items_select on public.cycle_count_items for select to authenticated
  using (exists (select 1 from public.cycle_count_tasks t where t.id = task_id
                 and t.company_id = (select public.auth_company_id())
                 and public.can_access_department(t.branch_id, t.department_id)));

grant select, insert, update, delete on public.cycle_count_plans to authenticated;
grant select on public.cycle_count_tasks, public.cycle_count_items to authenticated;

-- ─── GENERACIÓN ─────────────────────────────────────────────────────────────
create or replace function public.generate_cycle_counts(p_company_id uuid, p_date date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  pl     record;
  v_task uuid;
  v_n    int;
  v_made int := 0;
begin
  for pl in
    select * from public.cycle_count_plans p
    where p.company_id = p_company_id and p.is_active
      and exists (select 1 from public.branches b where b.id = p.branch_id and b.status = 'active')
      and (p.frequency = 'daily'
        or (p.frequency = 'weekdays' and extract(isodow from p_date) < 6)
        or (p.frequency = 'weekly' and extract(dow from p_date) = p.weekday))
      and not exists (select 1 from public.cycle_count_tasks t where t.plan_id = p.id and t.scheduled_date = p_date)
  loop
    insert into public.cycle_count_tasks (company_id, plan_id, branch_id, department_id, scheduled_date)
    values (pl.company_id, pl.id, pl.branch_id, pl.department_id, p_date)
    on conflict (plan_id, scheduled_date) do nothing
    returning id into v_task;
    if v_task is null then continue; end if;

    insert into public.cycle_count_items (task_id, product_id, position, priority_reason)
    select v_task, c.product_id, row_number() over (order by c.diffs desc, c.rotation desc, c.last_counted_at nulls first, c.name),
           case when c.diffs > 0 then 'differences' when c.rotation > 0 then 'rotation' else 'oldest' end
    from (
      select i.product_id, p.name, i.last_counted_at,
             (select count(*) from public.cycle_count_items ci join public.cycle_count_tasks ct on ct.id = ci.task_id
               where ci.product_id = i.product_id and ct.branch_id = pl.branch_id
                 and ci.difference <> 0 and ci.counted_at > now() - interval '90 days') as diffs,
             coalesce((select sum(m.quantity) from public.inventory_movements m
               where m.product_id = i.product_id and m.branch_id = pl.branch_id
                 and m.movement_type in ('out','waste','transfer_out') and m.created_at > now() - interval '30 days'), 0) as rotation
      from public.inventory i
      join public.products p on p.id = i.product_id and p.status = 'active'
      where i.branch_id = pl.branch_id
        and (pl.department_id is null or p.department_id = pl.department_id)
        and (pl.category is null or p.category ilike pl.category)
        -- No repetir lo contado en los últimos 3 días.
        and (i.last_counted_at is null or i.last_counted_at < now() - interval '3 days')
      order by diffs desc, rotation desc, i.last_counted_at nulls first, p.name
      limit pl.items_per_count
    ) c;
    get diagnostics v_n = row_count;
    update public.cycle_count_tasks set items_total = v_n where id = v_task;
    v_made := v_made + 1;
  end loop;
  return v_made;
end $$;
revoke all on function public.generate_cycle_counts(uuid, date) from public, anon, authenticated;

-- ─── CAPTURA (conteo a ciegas) ──────────────────────────────────────────────
create or replace function public.record_cycle_count(p_item_id uuid, p_counted numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  it     public.cycle_count_items%rowtype;
  tk     public.cycle_count_tasks%rowtype;
  mv     public.inventory_movements%rowtype;
  v_diff numeric;
begin
  select * into it from public.cycle_count_items where id = p_item_id for update;
  if not found then raise exception 'Producto de conteo no encontrado'; end if;
  select * into tk from public.cycle_count_tasks where id = it.task_id for update;
  if tk.company_id <> public.auth_company_id() or not public.has_permission('perform_cycle_counts')
     or not public.can_access_department(tk.branch_id, tk.department_id) then
    raise exception 'No puedes capturar este conteo';
  end if;
  if tk.status in ('completed','cancelled') then raise exception 'Este conteo ya está cerrado'; end if;
  if p_counted is null or p_counted < 0 then raise exception 'Escribe la cantidad contada (0 o más)'; end if;

  insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity, reason, reference_type, reference_id)
  values (tk.company_id, tk.branch_id, it.product_id, 'count', p_counted, 'Conteo cíclico', 'cycle_count_item', it.id)
  returning * into mv;

  -- Si se recuenta, la diferencia se mide contra lo esperado del primer conteo.
  v_diff := p_counted - coalesce(it.expected_qty, mv.stock_before);
  update public.cycle_count_items
     set expected_qty = coalesce(expected_qty, mv.stock_before),
         counted_qty = p_counted, difference = v_diff,
         difference_value = round(v_diff * coalesce(mv.unit_cost, 0), 2),
         movement_id = mv.id, counted_by = public.auth_employee_id(), counted_at = now()
   where id = it.id;

  update public.cycle_count_tasks t
     set items_counted   = x.counted,
         items_with_diff = x.with_diff,
         diff_value      = x.value,
         status          = case when x.counted >= t.items_total then 'completed' else 'in_progress' end,
         started_at      = coalesce(t.started_at, now()),
         completed_at    = case when x.counted >= t.items_total then now() end,
         completed_by    = case when x.counted >= t.items_total then public.auth_employee_id() end
    from (select count(*) filter (where counted_at is not null) as counted,
                 count(*) filter (where difference <> 0) as with_diff,
                 coalesce(sum(difference_value), 0) as value
            from public.cycle_count_items where task_id = tk.id) x
   where t.id = tk.id;

  return jsonb_build_object('difference', v_diff, 'difference_value', round(v_diff * coalesce(mv.unit_cost, 0), 2));
end $$;
revoke all on function public.record_cycle_count(uuid, numeric) from public, anon;
grant execute on function public.record_cycle_count(uuid, numeric) to authenticated;

-- Conteo a ciegas: quien solo cuenta no ve existencia ni diferencias; con
-- manage_cycle_counts (o manage_inventory) se ven completas.
create or replace view public.v_cycle_count_items with (security_invoker = on) as
select ci.id, ci.task_id, ci.product_id, ci.position, ci.priority_reason, ci.counted_qty, ci.counted_at,
       p.sku, p.name as product_name, p.unit, p.category,
       (select string_agg(pb.barcode, ' ') from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       e.full_name as counted_by_name,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.expected_qty end as expected_qty,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.difference end as difference,
       case when public.has_permission('manage_cycle_counts') or public.has_permission('manage_inventory') then ci.difference_value end as difference_value
from public.cycle_count_items ci
join public.products p on p.id = ci.product_id
left join public.employees e on e.id = ci.counted_by;
grant select on public.v_cycle_count_items to authenticated;

create or replace view public.v_cycle_count_tasks with (security_invoker = on) as
select t.*, pl.name as plan_name, pl.category, b.name as branch_name, d.name as department_name,
       e.full_name as completed_by_name
from public.cycle_count_tasks t
join public.cycle_count_plans pl on pl.id = t.plan_id
join public.branches b on b.id = t.branch_id
left join public.departments d on d.id = t.department_id
left join public.employees e on e.id = t.completed_by;
grant select on public.v_cycle_count_tasks to authenticated;

-- El mantenimiento diario genera los conteos del día (pg_cron lo corre cada hora).
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');  -- por si se instaló desde un archivo con CRLF
  if position('generate_cycle_counts' in v_src) = 0 then
    v_src := replace(v_src,
      '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(',
      '  perform public.generate_cycle_counts(v_company, v_today);' || chr(10)
      || '  perform public.set_bypass(v_prev);' || chr(10) || chr(10) || '  return jsonb_build_object(');
    if position('generate_cycle_counts' in v_src) = 0 then
      raise exception 'No se pudo extender run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;


-- >>>>>>>>>>>>>>>> migrations/0020_huecos_anaquel.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0020 · HUECOS EN ANAQUEL (FALTANTES EN PISO)
-- -----------------------------------------------------------------------------
--   * shelf_gaps: el empleado escanea un producto que no está en piso.
--     report_shelf_gap(sucursal, producto) cruza con inventory.stock:
--       - hay existencia → tarea a Almacén «Surtir a piso: <producto>»
--         (tasks.source_type = 'shelf_gap') y aviso al departamento;
--       - no hay → sugiere pedido; create_order_from_shelf_gap lo crea.
--     Un mismo producto no abre dos huecos en la sucursal: si ya hay uno
--     abierto se suma el reporte (report_count).
--   * Se cierra solo: al completar la tarea o al recibir/cerrar el pedido.
--     Quien gestiona huecos también puede resolverlos o descartarlos.
--   * Permisos: report_shelf_gaps (reportar) y manage_shelf_gaps (ver los de
--     toda la sucursal y cerrarlos).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.shelf_gaps (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references public.companies(id) on delete cascade,
  branch_id         uuid not null references public.branches(id) on delete cascade,
  department_id     uuid references public.departments(id) on delete set null,
  product_id        uuid not null references public.products(id) on delete cascade,
  system_stock      numeric(12,3) not null default 0,  -- existencia al reportar
  has_stock         boolean not null,                  -- «hay en bodega, no en piso»
  status            text not null default 'open' check (status in ('open','resolved','dismissed')),
  task_id           uuid references public.tasks(id) on delete set null,
  order_id          uuid references public.orders(id) on delete set null,
  notes             text,
  report_count      integer not null default 1,
  reported_by       uuid references public.employees(id) on delete set null,
  reported_at       timestamptz not null default now(),
  last_reported_at  timestamptz not null default now(),
  resolved_by       uuid references public.employees(id) on delete set null,
  resolved_at       timestamptz,
  updated_at        timestamptz not null default now()
);
create unique index if not exists shelf_gaps_open_uidx on public.shelf_gaps (branch_id, product_id) where status = 'open';
create index if not exists shelf_gaps_branch_idx on public.shelf_gaps (branch_id, reported_at desc);

drop trigger if exists trg_updated_at on public.shelf_gaps;
create trigger trg_updated_at before update on public.shelf_gaps
  for each row execute function public.tg_set_updated_at();

insert into public.permissions (code, module, name, description) values
  ('report_shelf_gaps', 'Inventario', 'Reportar huecos en anaquel', 'Escanear productos que no están en piso'),
  ('manage_shelf_gaps', 'Inventario', 'Gestionar huecos en anaquel', 'Ver los huecos de la sucursal, resolverlos o descartarlos')
on conflict (code) do nothing;

-- ─── RLS ────────────────────────────────────────────────────────────────────
-- Solo lectura: se escriben con las funciones de abajo.
alter table public.shelf_gaps enable row level security;
drop policy if exists shelf_gaps_select on public.shelf_gaps;
create policy shelf_gaps_select on public.shelf_gaps for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
    reported_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_shelf_gaps')) and public.can_access_branch(branch_id))
    or ((select public.has_permission('view_reports')) and public.can_access_department(branch_id, department_id))));
grant select on public.shelf_gaps to authenticated;

-- «Surtir a piso» no lleva responsable: la puede cerrar cualquiera de Almacén
-- con manage_shelf_gaps (trg_task_rules le deja cambiar solo el estado).
drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = (select public.auth_employee_id())
      or ((select public.has_permission('manage_tasks')) and public.can_access_department(branch_id, department_id))
      or (source_type = 'shelf_gap' and (select public.has_permission('manage_shelf_gaps'))
          and public.can_access_department(branch_id, department_id)))
  with check (company_id = (select public.auth_company_id()));

-- ─── REPORTE ────────────────────────────────────────────────────────────────
create or replace function public.report_shelf_gap(p_branch_id uuid, p_product_id uuid, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prod    public.products%rowtype;
  v_inv     public.inventory%rowtype;
  v_gap     public.shelf_gaps%rowtype;
  v_stock   numeric := 0;
  v_alm     uuid;
  v_task    uuid;
  v_prev    text;
  v_repeat  boolean := false;
begin
  if not public.has_permission('report_shelf_gaps') or not public.can_access_branch(p_branch_id) then
    raise exception 'No puedes reportar huecos en esta sucursal';
  end if;
  select * into v_prod from public.products where id = p_product_id and company_id = public.auth_company_id();
  if not found then raise exception 'Producto no encontrado'; end if;

  select * into v_inv from public.inventory where branch_id = p_branch_id and product_id = p_product_id;
  v_stock := coalesce(v_inv.stock, 0);

  select * into v_gap from public.shelf_gaps
   where branch_id = p_branch_id and product_id = p_product_id and status = 'open' for update;
  if found then
    v_repeat := true;
    update public.shelf_gaps
       set report_count = report_count + 1, last_reported_at = now(), system_stock = v_stock,
           has_stock = has_stock or v_stock > 0,
           notes = coalesce(nullif(trim(p_notes), ''), notes)
     where id = v_gap.id returning * into v_gap;
  else
    insert into public.shelf_gaps (company_id, branch_id, department_id, product_id, system_stock, has_stock, notes, reported_by)
    values (v_prod.company_id, p_branch_id, v_prod.department_id, p_product_id, v_stock, v_stock > 0,
            nullif(trim(p_notes), ''), public.auth_employee_id())
    returning * into v_gap;
  end if;

  -- Hay existencia: tarea a Almacén (una sola por hueco).
  if v_stock > 0 and v_gap.task_id is null then
    select id into v_alm from public.departments where company_id = v_prod.company_id and code = 'ALM' and is_active;
    v_prev := public.set_bypass('on');
    insert into public.tasks (company_id, branch_id, department_id, title, description, priority, due_date, source_type, source_id)
    values (v_prod.company_id, p_branch_id, coalesce(v_alm, v_prod.department_id),
            left('Surtir a piso: ' || v_prod.name, 200),
            'Hueco en anaquel reportado. Sistema: ' || trim_scale(v_stock)::text || ' ' || v_prod.unit
              || coalesce(' · ubicación ' || nullif(trim(v_inv.location), ''), '') || ' · SKU ' || v_prod.sku || '.'
              || coalesce(E'\nNota: ' || nullif(trim(p_notes), ''), ''),
            'high', public.company_today(v_prod.company_id), 'shelf_gap', v_gap.id)
    on conflict (source_type, source_id) where source_id is not null
    do update set status = 'pending', completed_at = null, completion_notes = null
    returning id into v_task;
    update public.shelf_gaps set task_id = v_task where id = v_gap.id;
    insert into public.notifications (company_id, employee_id, department_id, branch_id, type, title, body, link)
    select v_prod.company_id, null, coalesce(v_alm, v_prod.department_id), p_branch_id, 'task',
           'Surtir a piso: ' || v_prod.name, 'Hay ' || trim_scale(v_stock)::text || ' ' || v_prod.unit
             || ' en sistema y no está en anaquel.', '/tasks'
    where coalesce(v_alm, v_prod.department_id) is not null;
    perform public.set_bypass(v_prev);
    v_gap.task_id := v_task;
  end if;

  return jsonb_build_object(
    'gap_id', v_gap.id, 'repeat', v_repeat, 'has_stock', v_stock > 0, 'stock', v_stock, 'unit', v_prod.unit,
    'product_name', v_prod.name, 'task_id', v_gap.task_id, 'order_id', v_gap.order_id,
    'suggested_qty', greatest(coalesce(v_inv.max_stock, 0) - v_stock, coalesce(v_inv.min_stock, 0), 1));
end $$;
revoke all on function public.report_shelf_gap(uuid, uuid, text) from public, anon;
grant execute on function public.report_shelf_gap(uuid, uuid, text) to authenticated;

-- Sin existencia: pedido interno del departamento del producto.
create or replace function public.create_order_from_shelf_gap(p_gap_id uuid, p_quantity numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_gap   public.shelf_gaps%rowtype;
  v_name  text;
  v_order uuid;
begin
  select * into v_gap from public.shelf_gaps where id = p_gap_id for update;
  if not found or v_gap.company_id <> public.auth_company_id() then raise exception 'Hueco no encontrado'; end if;
  if not public.has_permission('create_orders') or not public.can_access_branch(v_gap.branch_id) then
    raise exception 'No puedes crear pedidos en esta sucursal';
  end if;
  if v_gap.status <> 'open' then raise exception 'Este hueco ya está cerrado'; end if;
  if v_gap.order_id is not null
     and exists (select 1 from public.orders o where o.id = v_gap.order_id and o.status not in ('rejected','cancelled')) then
    raise exception 'Este hueco ya tiene un pedido en curso';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Escribe la cantidad a pedir'; end if;

  select name into v_name from public.products where id = v_gap.product_id;
  insert into public.orders (company_id, branch_id, department_id, title, priority, notes)
  values (v_gap.company_id, v_gap.branch_id, v_gap.department_id, left('Faltante en anaquel: ' || v_name, 200), 'high',
          'Generado desde Huecos en anaquel: sin existencia en sistema.')
  returning id into v_order;
  insert into public.order_items (order_id, product_id, quantity) values (v_order, v_gap.product_id, p_quantity);
  update public.shelf_gaps set order_id = v_order where id = v_gap.id;
  return v_order;
end $$;
revoke all on function public.create_order_from_shelf_gap(uuid, numeric) from public, anon;
grant execute on function public.create_order_from_shelf_gap(uuid, numeric) to authenticated;

create or replace function public.close_shelf_gap(p_gap_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_gap  public.shelf_gaps%rowtype;
  v_prev text;
begin
  select * into v_gap from public.shelf_gaps where id = p_gap_id for update;
  if not found or v_gap.company_id <> public.auth_company_id() then raise exception 'Hueco no encontrado'; end if;
  if not public.has_permission('manage_shelf_gaps') or not public.can_access_branch(v_gap.branch_id) then
    raise exception 'No puedes cerrar huecos en esta sucursal';
  end if;
  if p_status not in ('resolved','dismissed') then raise exception 'Estado no válido'; end if;
  if v_gap.status <> 'open' then raise exception 'Este hueco ya está cerrado'; end if;
  update public.shelf_gaps set status = p_status, resolved_at = now(), resolved_by = public.auth_employee_id()
   where id = v_gap.id;
  -- La tarea «Surtir a piso» pendiente se cierra con el hueco.
  if v_gap.task_id is not null then
    v_prev := public.set_bypass('on');
    update public.tasks
       set status = case when p_status = 'resolved' then 'completed' else 'cancelled' end,
           completion_notes = case when p_status = 'resolved' then 'Hueco resuelto' else 'Hueco descartado' end
     where id = v_gap.task_id and status in ('pending','in_progress');
    perform public.set_bypass(v_prev);
  end if;
end $$;
revoke all on function public.close_shelf_gap(uuid, text) from public, anon;
grant execute on function public.close_shelf_gap(uuid, text) to authenticated;

-- ─── CIERRE AUTOMÁTICO ──────────────────────────────────────────────────────
-- Tarea completada → resuelto; tarea cancelada → descartado.
create or replace function public.tg_shelf_gap_task_done()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.source_type = 'shelf_gap' and new.status is distinct from old.status
     and new.status in ('completed','cancelled') then
    update public.shelf_gaps
       set status = case when new.status = 'completed' then 'resolved' else 'dismissed' end,
           resolved_at = now(), resolved_by = public.auth_employee_id()
     where id = new.source_id and status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists trg_shelf_gap_task_done on public.tasks;
create trigger trg_shelf_gap_task_done after update of status on public.tasks
  for each row execute function public.tg_shelf_gap_task_done();

-- Pedido recibido o cerrado → resuelto.
create or replace function public.tg_shelf_gap_order_done()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('received','closed') then
    update public.shelf_gaps set status = 'resolved', resolved_at = now(), resolved_by = public.auth_employee_id()
     where order_id = new.id and status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists trg_shelf_gap_order_done on public.orders;
create trigger trg_shelf_gap_order_done after update of status on public.orders
  for each row execute function public.tg_shelf_gap_order_done();

-- ─── VISTA ──────────────────────────────────────────────────────────────────
drop view if exists public.v_shelf_gaps;
create view public.v_shelf_gaps with (security_invoker = on) as
select g.*, p.sku, p.name as product_name, p.unit,
       (select string_agg(pb.barcode, ' ') from public.product_barcodes pb where pb.product_id = p.id) as barcodes,
       d.name as department_name, b.name as branch_name, i.location, i.stock as current_stock,
       er.full_name as reported_by_name, ev.full_name as resolved_by_name,
       t.status as task_status, o.folio as order_folio, o.status as order_status
from public.shelf_gaps g
join public.products p on p.id = g.product_id
join public.branches b on b.id = g.branch_id
left join public.departments d on d.id = g.department_id
left join public.inventory i on i.branch_id = g.branch_id and i.product_id = g.product_id
left join public.employees er on er.id = g.reported_by
left join public.employees ev on ev.id = g.resolved_by
left join public.tasks t on t.id = g.task_id
left join public.orders o on o.id = g.order_id;
grant select on public.v_shelf_gaps to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0021_comunicados.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0021 · COMUNICADOS CON ACUSE DE LECTURA
-- -----------------------------------------------------------------------------
--   * announcements: título, cuerpo, adjunto opcional (bucket privado
--     «announcements»), alcance (empresa, zona, sucursal o departamento) y
--     fecha de vigencia. Departamento sin sucursal = ese departamento en
--     todas las sucursales.
--   * announcement_reads: cada empleado confirma «Leído»
--     (mark_announcement_read).
--   * Al publicar se notifica a cada empleado activo del alcance.
--   * announcement_progress: el publicador (o quien tiene
--     manage_announcements) ve quién falta, por sucursal y persona.
--   * Permisos: publish_announcements y manage_announcements.
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.announcements (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  title            text not null check (length(trim(title)) > 0),
  body             text not null,
  scope            text not null default 'company' check (scope in ('company','zone','branch','department')),
  zone_id          uuid references public.zones(id) on delete cascade,
  branch_id        uuid references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete cascade,
  valid_until      date,
  attachment_path  text,
  attachment_name  text,
  attachment_type  text,
  status           text not null default 'active' check (status in ('active','archived')),
  published_by     uuid references public.employees(id) on delete set null,
  published_at     timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
do $$ begin
  alter table public.announcements add constraint announcements_scope_chk check (
       (scope = 'company'    and zone_id is null and branch_id is null and department_id is null)
    or (scope = 'zone'       and zone_id is not null and branch_id is null and department_id is null)
    or (scope = 'branch'     and branch_id is not null and zone_id is null and department_id is null)
    or (scope = 'department' and department_id is not null and zone_id is null));
exception when duplicate_object then null; end $$;
create index if not exists announcements_company_idx on public.announcements (company_id, published_at desc);

create table if not exists public.announcement_reads (
  announcement_id  uuid not null references public.announcements(id) on delete cascade,
  employee_id      uuid not null references public.employees(id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (announcement_id, employee_id)
);

drop trigger if exists trg_updated_at on public.announcements;
create trigger trg_updated_at before update on public.announcements
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_actor on public.announcements;
create trigger trg_actor before insert on public.announcements
  for each row execute function public.tg_set_actor('published_by');

insert into public.permissions (code, module, name, description) values
  ('publish_announcements', 'Comunicados', 'Publicar comunicados', 'Publicar comunicados dentro de su alcance y ver quién falta de leer'),
  ('manage_announcements',  'Comunicados', 'Gestionar comunicados', 'Ver el avance de lectura de todos los comunicados y archivarlos')
on conflict (code) do nothing;

-- ─── ALCANCE ────────────────────────────────────────────────────────────────
-- ¿El comunicado le llega a este empleado?
create or replace function public.announcement_matches(
  p_employee_id uuid, p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    left join public.branches b on b.id = e.branch_id
    where e.id = p_employee_id
      and case p_scope
            when 'company' then true
            when 'zone' then b.zone_id = p_zone_id
                          or exists (select 1 from public.employee_zones ez where ez.employee_id = e.id and ez.zone_id = p_zone_id)
            when 'branch' then e.branch_id = p_branch_id
            when 'department' then (p_branch_id is null or e.branch_id = p_branch_id)
                               and (e.department_id = p_department_id
                                    or exists (select 1 from public.employee_departments ed
                                               where ed.employee_id = e.id and ed.department_id = p_department_id))
            else false
          end)
$$;
revoke all on function public.announcement_matches(uuid, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.announcement_matches(uuid, text, uuid, uuid, uuid) to authenticated;

-- ¿Puede el usuario publicar con este alcance?
create or replace function public.can_publish_announcement(p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_permission('publish_announcements') and case p_scope
    when 'company' then public.auth_role_scope() = 'company'
    when 'zone' then public.auth_role_scope() = 'company' or p_zone_id in (select public.auth_zone_ids())
    when 'branch' then public.can_access_branch(p_branch_id)
    when 'department' then case when p_branch_id is null then public.auth_role_scope() = 'company'
                                else public.can_access_department(p_branch_id, p_department_id) end
    else false
  end
$$;
revoke all on function public.can_publish_announcement(text, uuid, uuid, uuid) from public, anon;
grant execute on function public.can_publish_announcement(text, uuid, uuid, uuid) to authenticated;

-- ¿Puede ver quién falta? El publicador, o manage_announcements con alcance de empresa.
create or replace function public.can_track_announcement(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.announcements a where a.id = p_id and a.company_id = public.auth_company_id()
                 and (a.published_by = public.auth_employee_id()
                      or (public.has_permission('manage_announcements') and public.auth_role_scope() = 'company')))
$$;
revoke all on function public.can_track_announcement(uuid) from public, anon;
grant execute on function public.can_track_announcement(uuid) to authenticated;

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
    published_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_announcements')) and (select public.auth_role_scope()) = 'company')
    or (status = 'active' and public.announcement_matches((select public.auth_employee_id()), scope, zone_id, branch_id, department_id))));
drop policy if exists announcements_insert on public.announcements;
create policy announcements_insert on public.announcements for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and public.can_publish_announcement(scope, zone_id, branch_id, department_id));
drop policy if exists announcements_update on public.announcements;
create policy announcements_update on public.announcements for update to authenticated
  using (company_id = (select public.auth_company_id()) and (
    published_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_announcements')) and (select public.auth_role_scope()) = 'company')))
  with check (company_id = (select public.auth_company_id()));
drop policy if exists announcements_delete on public.announcements;
create policy announcements_delete on public.announcements for delete to authenticated
  using (company_id = (select public.auth_company_id()) and published_by = (select public.auth_employee_id()));

-- Lecturas: cada quien ve las suyas; el publicador ve las de su comunicado.
-- Se escriben con mark_announcement_read.
drop policy if exists announcement_reads_select on public.announcement_reads;
create policy announcement_reads_select on public.announcement_reads for select to authenticated
  using (employee_id = (select public.auth_employee_id()) or public.can_track_announcement(announcement_id));

grant select, insert, update, delete on public.announcements to authenticated;
grant select on public.announcement_reads to authenticated;

-- El alcance y el publicador no cambian al editar (solo texto, vigencia, adjunto y estado).
create or replace function public.tg_announcement_guard()
returns trigger language plpgsql as $$
begin
  if (new.scope, new.zone_id, new.branch_id, new.department_id, new.published_by, new.company_id)
     is distinct from (old.scope, old.zone_id, old.branch_id, old.department_id, old.published_by, old.company_id) then
    raise exception 'El alcance de un comunicado no se puede cambiar: publícalo de nuevo';
  end if;
  return new;
end $$;
drop trigger if exists trg_announcement_guard on public.announcements;
create trigger trg_announcement_guard before update on public.announcements
  for each row execute function public.tg_announcement_guard();

-- ─── PUBLICAR: aviso a cada empleado del alcance ────────────────────────────
create or replace function public.tg_announcement_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (company_id, employee_id, type, title, body, link)
  select new.company_id, e.id, 'announcement', left('Comunicado: ' || new.title, 200),
         left(regexp_replace(new.body, '\s+', ' ', 'g'), 160), '/announcements?id=' || new.id
  from public.employees e
  where e.company_id = new.company_id and e.status = 'active'
    and e.id is distinct from new.published_by
    and public.announcement_matches(e.id, new.scope, new.zone_id, new.branch_id, new.department_id);
  -- Quien publica y también está en el alcance queda como leído.
  if new.published_by is not null
     and public.announcement_matches(new.published_by, new.scope, new.zone_id, new.branch_id, new.department_id) then
    insert into public.announcement_reads (announcement_id, employee_id) values (new.id, new.published_by)
    on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists trg_announcement_notify on public.announcements;
create trigger trg_announcement_notify after insert on public.announcements
  for each row execute function public.tg_announcement_notify();

-- ─── LEÍDO ──────────────────────────────────────────────────────────────────
create or replace function public.mark_announcement_read(p_id uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  a      public.announcements%rowtype;
  v_at   timestamptz;
begin
  select * into a from public.announcements where id = p_id;
  if not found or a.company_id <> public.auth_company_id()
     or not public.announcement_matches(public.auth_employee_id(), a.scope, a.zone_id, a.branch_id, a.department_id) then
    raise exception 'Este comunicado no es para ti';
  end if;
  insert into public.announcement_reads (announcement_id, employee_id) values (p_id, public.auth_employee_id())
  on conflict (announcement_id, employee_id) do nothing;
  select read_at into v_at from public.announcement_reads where announcement_id = p_id and employee_id = public.auth_employee_id();
  -- Su aviso también queda leído.
  update public.notifications set is_read = true
   where employee_id = public.auth_employee_id() and type = 'announcement'
     and link = '/announcements?id=' || p_id and not is_read;
  return v_at;
end $$;
revoke all on function public.mark_announcement_read(uuid) from public, anon;
grant execute on function public.mark_announcement_read(uuid) to authenticated;

-- ─── AVANCE DE LECTURA ──────────────────────────────────────────────────────
create or replace function public.announcement_progress(p_id uuid)
returns table (employee_id uuid, full_name text, job_title text, branch_id uuid, branch_name text,
               department_name text, read_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare a public.announcements%rowtype;
begin
  if not public.can_track_announcement(p_id) then raise exception 'No puedes ver el avance de este comunicado'; end if;
  select * into a from public.announcements where id = p_id;
  return query
  select e.id, e.full_name, e.position, e.branch_id, b.name, d.name, r.read_at
  from public.employees e
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  left join public.announcement_reads r on r.announcement_id = a.id and r.employee_id = e.id
  where e.company_id = a.company_id
    and (e.status = 'active' or r.read_at is not null)
    and public.announcement_matches(e.id, a.scope, a.zone_id, a.branch_id, a.department_id)
  order by b.name nulls last, r.read_at is not null, e.full_name;
end $$;
revoke all on function public.announcement_progress(uuid) from public, anon;
grant execute on function public.announcement_progress(uuid) to authenticated;

-- Totales para la lista (solo para quien puede ver el avance).
create or replace function public.announcement_counts(p_id uuid)
returns table (audience integer, read_count integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_track_announcement(p_id) then
    return query select null::int, null::int;
    return;
  end if;
  return query
  select count(*)::int, count(r.read_at)::int
  from public.announcements a
  join public.employees e on e.company_id = a.company_id
  left join public.announcement_reads r on r.announcement_id = a.id and r.employee_id = e.id
  where a.id = p_id
    and (e.status = 'active' or r.read_at is not null)
    and public.announcement_matches(e.id, a.scope, a.zone_id, a.branch_id, a.department_id);
end $$;
revoke all on function public.announcement_counts(uuid) from public, anon;
grant execute on function public.announcement_counts(uuid) to authenticated;

drop view if exists public.v_announcements;
create view public.v_announcements with (security_invoker = on) as
select a.*, p.full_name as published_by_name, z.name as zone_name, b.name as branch_name, d.name as department_name,
       (a.valid_until is not null and a.valid_until < public.company_today(a.company_id)) as is_expired,
       (select r.read_at from public.announcement_reads r
         where r.announcement_id = a.id and r.employee_id = public.auth_employee_id()) as my_read_at,
       public.announcement_matches(public.auth_employee_id(), a.scope, a.zone_id, a.branch_id, a.department_id) as is_for_me,
       c.audience, c.read_count
from public.announcements a
left join public.employees p on p.id = a.published_by
left join public.zones z on z.id = a.zone_id
left join public.branches b on b.id = a.branch_id
left join public.departments d on d.id = a.department_id
left join lateral public.announcement_counts(a.id) c on true;
grant select on public.v_announcements to authenticated;

-- ─── ADJUNTOS ───────────────────────────────────────────────────────────────
-- Bucket privado: {company_id}/{uuid}.{ext}. Lo lee cualquiera de la empresa
-- (URL firmada); solo sube quien publica.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('announcements', 'announcements', false, 10485760,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists announcements_objects_select on storage.objects;
drop policy if exists announcements_objects_insert on storage.objects;
drop policy if exists announcements_objects_delete on storage.objects;
create policy announcements_objects_select on storage.objects for select to authenticated
  using (bucket_id = 'announcements' and (storage.foldername(name))[1] = (select public.auth_company_id())::text);
create policy announcements_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'announcements' and (storage.foldername(name))[1] = (select public.auth_company_id())::text
              and (select public.has_permission('publish_announcements')));
create policy announcements_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'announcements' and owner_id = (select auth.uid())::text);


-- >>>>>>>>>>>>>>>> migrations/0022_multiempresa_login.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0022 · VARIAS EMPRESAS: CÓDIGO DE EMPRESA EN EL LOGIN
-- -----------------------------------------------------------------------------
--   * companies: code (único, [a-z0-9-]), status ('active' | 'suspended') y
--     plan. Solo se cambian desde el SQL Editor (modo sistema).
--   * El usuario es único por empresa: (company_id, lower(username)).
--   * Correo interno de Auth: usuario@<code>.operalia.local (antes
--     usuario@operalia.local). Se migran las cuentas existentes.
--   * handle_new_auth_user liga por usuario Y empresa; admin_set_password arma
--     el correo con el código de la empresa; request_password_reset recibe
--     (código de empresa, usuario).
--   * Empresa suspendida: las funciones auth_* devuelven null, así que RLS
--     corta todo el acceso sin borrar datos.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. EMPRESAS ────────────────────────────────────────────────────────────
alter table public.companies add column if not exists code text;
alter table public.companies add column if not exists status text not null default 'active';
alter table public.companies add column if not exists plan text not null default 'basico';

update public.companies set code = 'gatopelon'
 where id = 'c0000000-0000-4000-8000-000000000001' and code is null;
-- Cualquier otra empresa sin código recibe uno provisional (cámbialo en el SQL Editor).
update public.companies set code = 'empresa-' || left(id::text, 8) where code is null;
alter table public.companies alter column code set not null;

do $$ begin
  alter table public.companies add constraint companies_code_chk check (code ~ '^[a-z0-9-]+$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.companies add constraint companies_status_chk check (status in ('active','suspended'));
exception when duplicate_object then null; end $$;
create unique index if not exists companies_code_key on public.companies (code);

-- Código, estado y plan los administra la plataforma, no el cliente.
create or replace function public.tg_company_platform_guard()
returns trigger language plpgsql as $$
begin
  if not public.is_system_context()
     and (new.code, new.status, new.plan) is distinct from (old.code, old.status, old.plan) then
    raise exception 'El código, estado y plan de la empresa solo se cambian desde la plataforma';
  end if;
  return new;
end $$;
drop trigger if exists trg_company_platform_guard on public.companies;
create trigger trg_company_platform_guard before update on public.companies
  for each row execute function public.tg_company_platform_guard();

-- ─── 2. USUARIO ÚNICO POR EMPRESA ───────────────────────────────────────────
drop index if exists public.employees_username_lower_key;
create unique index if not exists employees_company_username_key on public.employees (company_id, lower(username));

-- ─── 3. CORREO INTERNO DE AUTH ──────────────────────────────────────────────
create or replace function public.employee_auth_email(p_company_id uuid, p_username text)
returns text language sql stable security definer set search_path = public as $$
  select lower(trim(p_username)) || '@' || c.code || '.operalia.local'
  from public.companies c where c.id = p_company_id
$$;
revoke all on function public.employee_auth_email(uuid, text) from public, anon, authenticated;

-- Liga la cuenta nueva con su empleado:
--   usuario@<code>.operalia.local → por usuario dentro de esa empresa;
--   correo real → por el correo registrado (o por usuario si es único).
create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_local  text := lower(split_part(new.email, '@', 1));
  v_domain text := lower(split_part(new.email, '@', 2));
begin
  if v_domain like '%.operalia.local' then
    update public.employees e
       set user_id = new.id, email = coalesce(e.email, new.email)
      from public.companies c
     where c.id = e.company_id and c.code = left(v_domain, length(v_domain) - length('.operalia.local'))
       and lower(e.username) = v_local and e.user_id is null and e.status = 'active';
  elsif v_domain <> 'operalia.local' then
    update public.employees
       set user_id = new.id
     where lower(email) = lower(new.email) and user_id is null and status = 'active';
    if not found then
      update public.employees
         set user_id = new.id, email = coalesce(email, new.email)
       where lower(username) = v_local and user_id is null and status = 'active'
         and (select count(*) from public.employees x
               where lower(x.username) = v_local and x.user_id is null and x.status = 'active') = 1;
    end if;
  end if;
  -- usuario@operalia.local (formato anterior, sin empresa): no se liga.
  return new;
end $$;

-- admin_set_password (0012) arma el correo con el código de la empresa.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.admin_set_password(uuid, text)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');
  if position('employee_auth_email' in v_src) = 0 then
    v_src := replace(v_src, 'v_email := lower(t.username) || ''@operalia.local'';',
                            'v_email := public.employee_auth_email(t.company_id, t.username);');
    if position('employee_auth_email' in v_src) = 0 then
      raise exception 'No se pudo actualizar admin_set_password: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- «Olvidé mi contraseña» desde el login: ahora con el código de empresa.
drop function if exists public.request_password_reset(text);
create or replace function public.request_password_reset(p_company_code text, p_username text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t      public.employees%rowtype;
  ag     record;
  v_link text;
begin
  select e.* into t from public.employees e
  join public.companies c on c.id = e.company_id
  where c.code = lower(trim(coalesce(p_company_code, ''))) and c.status = 'active'
    and lower(e.username) = lower(split_part(trim(coalesce(p_username, '')), '@', 1))
    and e.status = 'active'
  limit 1;
  if not found then return; end if;

  v_link := '/employees?reset=' || t.id;
  if exists (select 1 from public.notifications
             where link = v_link and created_at > now() - interval '15 minutes') then
    return;
  end if;

  for ag in
    select distinct e.id from public.employees e
    join public.roles r on r.id = e.role_id
    where e.company_id = t.company_id and e.status = 'active' and e.id <> t.id
      and (e.is_owner
        or (r.code = 'admin' and not t.is_owner)
        or (exists (select 1 from public.role_permissions rp where rp.role_id = e.role_id and rp.permission_code = 'manage_employees')
            and r.scope = 'branch' and e.branch_id = t.branch_id
            and (select r2.scope from public.roles r2 where r2.id = t.role_id) not in ('company')))
  loop
    perform public.notify_employee(ag.id, 'password', 'Solicitud de contraseña: ' || t.full_name,
      '@' || t.username || ' olvidó su contraseña. Asígnale una temporal.', v_link);
  end loop;
end $$;
revoke all on function public.request_password_reset(text, text) from public;
grant execute on function public.request_password_reset(text, text) to anon, authenticated;

-- Migración de cuentas: usuario@operalia.local → usuario@<code>.operalia.local
-- (la empresa del empleado ligado; si la cuenta no está ligada, Gato Pelón).
do $$
declare v_prev text;
begin
  v_prev := public.set_bypass('on');
  update auth.users u
     set email = split_part(u.email, '@', 1) || '@'
                 || coalesce((select c.code from public.employees e join public.companies c on c.id = e.company_id
                               where e.user_id = u.id limit 1), 'gatopelon') || '.operalia.local',
         raw_user_meta_data = case when u.raw_user_meta_data ? 'email'
           then jsonb_set(u.raw_user_meta_data, '{email}', to_jsonb(split_part(u.email, '@', 1) || '@'
                 || coalesce((select c.code from public.employees e join public.companies c on c.id = e.company_id
                               where e.user_id = u.id limit 1), 'gatopelon') || '.operalia.local'))
           else u.raw_user_meta_data end,
         updated_at = now()
   where lower(u.email) like '%@operalia.local';

  update auth.identities i
     set identity_data = jsonb_set(i.identity_data, '{email}', to_jsonb(u.email)),
         updated_at = now()
    from auth.users u
   where u.id = i.user_id and i.provider = 'email'
     and lower(i.identity_data ->> 'email') like '%@operalia.local';

  update public.employees e
     set email = split_part(e.email, '@', 1) || '@' || c.code || '.operalia.local'
    from public.companies c
   where c.id = e.company_id and lower(e.email) like '%@operalia.local';
  perform public.set_bypass(v_prev);
end $$;

-- ─── 4. EMPRESA SUSPENDIDA = SIN ACCESO ─────────────────────────────────────
-- Todas las funciones auth_* parten del empleado de la sesión en una empresa activa.
create or replace function public.auth_employee_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_company_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.company_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_branch_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.branch_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_department_id()
returns uuid language sql stable security definer set search_path = public as $$
  select e.department_id from public.employees e join public.companies c on c.id = e.company_id and c.status = 'active'
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_scope()
returns text language sql stable security definer set search_path = public as $$
  select r.scope
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.auth_role_code()
returns text language sql stable security definer set search_path = public as $$
  select r.code
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  where e.user_id = auth.uid() and e.status = 'active' limit 1
$$;

create or replace function public.my_permissions()
returns setof text language sql stable security definer set search_path = public as $$
  with me as (
    select e.id, e.role_id from public.employees e
    join public.companies c on c.id = e.company_id and c.status = 'active'
    where e.user_id = auth.uid() and e.status = 'active' limit 1
  )
  select rp.permission_code from public.role_permissions rp join me on me.role_id = rp.role_id
  where not exists (
    select 1 from public.employee_permissions ep
    where ep.employee_id = (select id from me)
      and ep.permission_code = rp.permission_code and not ep.is_granted)
  union
  select ep.permission_code from public.employee_permissions ep join me on me.id = ep.employee_id
  where ep.is_granted
$$;

create or replace function public.auth_is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select e.is_owner from public.employees e
                   join public.companies c on c.id = e.company_id and c.status = 'active'
                   where e.user_id = auth.uid() and e.status = 'active' limit 1), false)
$$;

-- Perfil (0015) + código de empresa. Con la empresa suspendida no hay perfil.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name, 'company_code', c.code,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;


-- >>>>>>>>>>>>>>>> migrations/0023_plataforma_roles_semillas.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0023 · SUPERADMIN DE PLATAFORMA, ROLES DEL PROPIETARIO Y
--                   SEMILLA BASE POR EMPRESA
-- -----------------------------------------------------------------------------
--   A. platform_admins + is_platform_admin(): el superadmin de la plataforma,
--      distinto del propietario de cada empresa (employees.is_owner).
--   B. Roles y permisos (roles, role_permissions, employee_permissions) solo los
--      edita quien tiene manage_roles Y es propietario o superadmin.
--      Correcciones de RLS que dependían solo de un permiso (ver diario).
--   C. seed_company_base(empresa): todo lo que una empresa necesita para operar
--      (departamentos, zonas, roles y sus permisos, temas de soporte,
--      plantillas de checklist, puntos QR). Re-ejecutable; solo agrega lo que
--      falta. Las semillas de seed/ la llaman para Gato Pelón.
-- Re-ejecutable.
-- =============================================================================

-- ─── A. SUPERADMIN DE PLATAFORMA ────────────────────────────────────────────
create table if not exists public.platform_admins (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;
grant select on public.platform_admins to authenticated;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.platform_admins where user_id = auth.uid())
$$;
revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- Solo un superadmin la lee; nadie la escribe desde la API (se administra en el SQL Editor).
drop policy if exists platform_admins_select on public.platform_admins;
create policy platform_admins_select on public.platform_admins for select to authenticated
  using ((select public.is_platform_admin()));

-- Perfil (0022) + is_owner e is_platform_admin.
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name, 'company_code', c.code,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'is_owner', e.is_owner,
    'is_platform_admin', public.is_platform_admin(),
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;

-- ─── B. ROLES Y PERMISOS: SOLO PROPIETARIO O SUPERADMIN ─────────────────────
create or replace function public.can_manage_roles()
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_permission('manage_roles') and (public.auth_is_owner() or public.is_platform_admin())
$$;
revoke all on function public.can_manage_roles() from public, anon;
grant execute on function public.can_manage_roles() to authenticated;

drop policy if exists roles_write on public.roles;
create policy roles_write on public.roles for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.can_manage_roles()))
  with check (company_id = (select public.auth_company_id()) and (select public.can_manage_roles()));

drop policy if exists role_permissions_write on public.role_permissions;
create policy role_permissions_write on public.role_permissions for all to authenticated
  using ((select public.can_manage_roles())
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())))
  with check ((select public.can_manage_roles())
         and exists (select 1 from public.roles r where r.id = role_id and r.company_id = (select public.auth_company_id())));

drop policy if exists employee_permissions_write on public.employee_permissions;
create policy employee_permissions_write on public.employee_permissions for all to authenticated
  using ((select public.can_manage_roles())
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())))
  with check ((select public.can_manage_roles())
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())));

-- ─── B. CORRECCIONES DE RLS (permisos que hoy alcanzaban de más) ────────────
-- Datos de la empresa: solo propietario o superadmin (antes bastaba manage_branches).
drop policy if exists companies_update on public.companies;
create policy companies_update on public.companies for update to authenticated
  using (id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and ((select public.auth_is_owner()) or (select public.is_platform_admin())))
  with check (id = (select public.auth_company_id()));

-- Sucursales, departamentos y zonas son de toda la empresa: además del permiso,
-- alcance de empresa (un rol de sucursal con manage_branches no edita las demás).
drop policy if exists branches_write on public.branches;
create policy branches_write on public.branches for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');
drop policy if exists departments_write on public.departments;
create policy departments_write on public.departments for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');
drop policy if exists zones_write on public.zones;
create policy zones_write on public.zones for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company')
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_branches'))
         and (select public.auth_role_scope()) = 'company');

-- Departamentos extra de un empleado: solo de empleados que el usuario puede gestionar.
drop policy if exists employee_departments_write on public.employee_departments;
create policy employee_departments_write on public.employee_departments for all to authenticated
  using ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())
                     and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(e.branch_id))))
  with check ((select public.has_permission('manage_employees'))
         and exists (select 1 from public.employees e where e.id = employee_id and e.company_id = (select public.auth_company_id())
                     and ((select public.auth_role_scope()) = 'company' or public.can_access_branch(e.branch_id))));

-- Renglones de pedido: quien aprueba solo toca pedidos de sus sucursales/departamentos.
drop policy if exists order_items_write on public.order_items;
create policy order_items_write on public.order_items for all to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id())
              or ((select public.has_permission('approve_orders')) and public.can_access_department(o.branch_id, o.department_id)))))
  with check (exists (select 1 from public.orders o where o.id = order_id
         and (o.requested_by = (select public.auth_employee_id())
              or ((select public.has_permission('approve_orders')) and public.can_access_department(o.branch_id, o.department_id)))));

-- Cambios de precio programados: editar con el mismo alcance que para crearlos (0015).
drop policy if exists price_changes_update on public.price_changes;
create policy price_changes_update on public.price_changes for update to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_price_changes'))
         and status = 'scheduled'
         and (   (branch_id is null and zone_id is null and (select public.auth_role_scope()) = 'company')
              or (zone_id is not null and ((select public.auth_role_scope()) = 'company' or zone_id in (select public.auth_zone_ids())))
              or (branch_id is not null and public.can_access_branch(branch_id))))
  with check (company_id = (select public.auth_company_id()));

-- Avisos a un departamento (0008): solo de una sucursal a la que se tiene acceso
-- (antes, con manage_tasks se podía avisar a cualquier sucursal o a toda la empresa).
drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and department_id is not null and employee_id is null
              and (select public.has_permission('manage_tasks'))
              and branch_id is not null and public.can_access_branch(branch_id));

-- ─── B. CUENTA DEL PROPIETARIO ──────────────────────────────────────────────
-- admin_set_password (0012/0022) no dejaba crear la cuenta de un propietario
-- pre-registrado (ej. chee). Ahora:
--   * desde el SQL Editor (modo sistema) se crea o restablece cualquier cuenta;
--   * un superadmin crea la cuenta de un propietario que aún no la tiene y
--     gestiona administradores.
-- Una vez que el propietario tiene cuenta, su contraseña solo la cambia él.
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.admin_set_password(uuid, text)'::regprocedure) into v_src;
  v_src := replace(v_src, chr(13), '');
  if position('is_platform_admin' in v_src) = 0 then
    v_src := replace(v_src,
      'if not public.has_permission(''manage_employees'') then',
      'if not public.is_system_context() and not public.has_permission(''manage_employees'') then');
    v_src := replace(v_src,
      'select * into t from public.employees where id = p_employee_id and company_id = public.auth_company_id();',
      'select * into t from public.employees where id = p_employee_id
     and (public.is_system_context() or company_id = public.auth_company_id());');
    v_src := replace(v_src,
      'if t.is_owner then raise exception',
      'if t.is_owner and not public.is_system_context() and not (t.user_id is null and public.is_platform_admin()) then raise exception');
    v_src := replace(v_src,
      'if v_scope = ''company'' and not public.auth_is_owner() then',
      'if v_scope = ''company'' and not public.auth_is_owner() and not public.is_system_context() and not public.is_platform_admin() then');
    if position('is_platform_admin' in v_src) = 0 or position('is_system_context() and not public.has_permission' in v_src) = 0 then
      raise exception 'No se pudo actualizar admin_set_password: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- ─── C. SEMILLA BASE POR EMPRESA ────────────────────────────────────────────
-- Lo que antes sembraban seed/0008…0018 (y las migraciones 0011 y 0012) para
-- cada empresa. Solo AGREGA lo que falta: no quita permisos que el propietario
-- haya cambiado ni duplica plantillas. No crea sucursales (son de cada empresa);
-- crea los puntos QR de las sucursales que ya existan.
-- Regla: si una migración agrega un permiso, lo asigna a los roles de todas
-- las empresas y lo agrega también a la matriz de aquí.
create or replace function public.seed_company_base(p_company_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_prev text;
begin
  if not exists (select 1 from public.companies where id = p_company_id) then
    raise exception 'Empresa % no existe', p_company_id;
  end if;
  v_prev := public.set_bypass('on');

  -- Departamentos
  insert into public.departments (company_id, code, name, color, description)
  select p_company_id, v.code, v.name, v.color, v.descr
  from (values
    ('ADM', 'Administración', '#0f172a', 'Oficina y administración general'),
    ('GER', 'Gerencia',       '#1e40af', 'Gerencia de sucursal'),
    ('CAJ', 'Cajas',          '#2563eb', 'Línea de cajas y atención'),
    ('ABA', 'Abarrotes',      '#16a34a', 'Piso de venta abarrotes'),
    ('REC', 'Recibo',         '#9333ea', 'Andén y recibo de mercancía'),
    ('ALM', 'Almacén',        '#78350f', 'Bodega y resguardo'),
    ('PRO', 'Protección',     '#dc2626', 'Seguridad y prevención de pérdidas'),
    ('CAD', 'Caducidades',    '#ea580c', 'Control de fechas de caducidad'),
    ('ESC', 'Escáner',        '#0891b2', 'Precios, escaneo y cenefas'),
    ('CAR', 'Carnicería',     '#b91c1c', 'Cárnicos'),
    ('PES', 'Pescadería',     '#0e7490', 'Pescados y mariscos'),
    ('JUG', 'Juguetería',     '#db2777', 'Juguetes y temporada'),
    ('TI',  'Soporte TI',     '#475569', 'Mantenimiento de la plataforma')
  ) as v(code, name, color, descr)
  on conflict (company_id, code) do nothing;

  -- Zonas
  insert into public.zones (company_id, code, name)
  select p_company_id, v.code, v.name
  from (values ('NOR', 'Norte'), ('SUR', 'Sur'), ('EST', 'Este'), ('OES', 'Oeste'), ('CEN', 'Centro')) as v(code, name)
  on conflict (company_id, code) do nothing;

  -- Roles de sistema
  insert into public.roles (company_id, code, name, scope, is_system, description)
  select p_company_id, v.code, v.name, v.scope, true, v.descr
  from (values
    ('admin',        'Administrador general', 'company',    'Control total de la empresa'),
    ('soporte',      'Soporte TI',            'company',    'Atiende la mesa de ayuda'),
    ('auditor',      'Auditor',               'company',    'Solo lectura de reportes y evidencias'),
    ('jefe_escaner', 'Jefe de Escáner',       'zone',       'Supervisa ofertas, precios, señalización y cabeceras de las tiendas de sus zonas'),
    ('gerente',      'Gerente de sucursal',   'branch',     'Supervisa toda su sucursal'),
    ('supervisor',   'Supervisor',            'department', 'Revisa departamentos asignados'),
    ('jefe_cajas',   'Jefe de cajas',         'department', 'Responsable de la línea de cajas'),
    ('cajas',        'Cajero(a)',             'self',       'Consulta de precios y checklists de caja'),
    ('abarrotes',    'Abarrotes',             'department', 'Inventario y pedidos de abarrotes'),
    ('recibo',       'Recibo',                'department', 'Proveedores y recibo de mercancía'),
    ('almacen',      'Almacén',               'department', 'Entradas, salidas y ajustes'),
    ('proteccion',   'Protección',            'department', 'Rondines y control de accesos'),
    ('caducidades',  'Caducidades',           'department', 'Control de lotes y fechas'),
    ('escaner',      'Escáner',               'department', 'Cambios de precio y cenefas')
  ) as v(code, name, scope, descr)
  on conflict (company_id, code) do nothing;

  -- Permisos por rol (matriz completa hasta 0021; el admin recibe todos).
  insert into public.role_permissions (role_id, permission_code)
  select r.id, p.code from public.roles r cross join public.permissions p
  where r.company_id = p_company_id and r.code = 'admin'
  on conflict do nothing;

  insert into public.role_permissions (role_id, permission_code)
  select r.id, perm
  from (values
    ('soporte',      array['view_dashboard','create_tickets','manage_tickets','view_reports','view_audit_logs']),
    ('auditor',      array['view_dashboard','view_inventory','view_prices','view_suppliers','view_tasks',
                           'view_reports','view_audit_logs','create_tickets']),
    ('jefe_escaner', array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                           'manage_price_changes','manage_shelf_tags','validate_shelf_tags','fill_checklists',
                           'upload_evidence','view_tasks','manage_tasks','view_reports','create_tickets',
                           'publish_announcements']),
    ('gerente',      array['view_dashboard','view_inventory','manage_inventory','view_prices','scan_products',
                           'report_price_difference','create_orders','approve_orders','view_suppliers','manage_suppliers',
                           'register_supplier_visit','receive_products','close_receiving','fill_checklists',
                           'review_checklists','manage_checklist_templates','upload_evidence','review_evidence',
                           'manage_expirations','manage_price_changes','manage_shelf_tags','validate_shelf_tags',
                           'view_tasks','manage_tasks','view_reports','view_audit_logs','manage_employees','create_tickets',
                           'register_waste','manage_checkpoints','perform_cycle_counts','manage_cycle_counts',
                           'report_shelf_gaps','manage_shelf_gaps','publish_announcements']),
    ('supervisor',   array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                           'view_suppliers','fill_checklists','review_checklists','upload_evidence','review_evidence',
                           'manage_expirations','validate_shelf_tags','view_tasks','manage_tasks','view_reports','create_tickets',
                           'perform_cycle_counts','report_shelf_gaps','manage_shelf_gaps','publish_announcements']),
    ('jefe_cajas',   array['view_dashboard','view_prices','scan_products','report_price_difference',
                           'fill_checklists','review_checklists','upload_evidence','review_evidence',
                           'view_tasks','manage_tasks','view_reports','create_tickets','report_shelf_gaps']),
    ('cajas',        array['view_dashboard','view_prices','scan_products','report_price_difference',
                           'fill_checklists','upload_evidence','view_tasks','create_tickets','report_shelf_gaps']),
    ('abarrotes',    array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                           'fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps']),
    ('recibo',       array['view_dashboard','view_inventory','view_suppliers','register_supplier_visit',
                           'receive_products','close_receiving','fill_checklists','upload_evidence','view_tasks','create_tickets']),
    ('almacen',      array['view_dashboard','view_inventory','manage_inventory','view_prices','create_orders',
                           'receive_products','fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps','manage_shelf_gaps']),
    ('proteccion',   array['view_dashboard','view_suppliers','register_supplier_visit','fill_checklists',
                           'upload_evidence','view_tasks','create_tickets']),
    ('caducidades',  array['view_dashboard','view_inventory','view_prices','scan_products','manage_expirations',
                           'create_orders','fill_checklists','upload_evidence','view_tasks','create_tickets','register_waste',
                           'perform_cycle_counts','report_shelf_gaps']),
    ('escaner',      array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                           'manage_price_changes','manage_shelf_tags','fill_checklists','upload_evidence','view_tasks',
                           'create_tickets','report_shelf_gaps'])
  ) as m(role_code, perms)
  join public.roles r on r.company_id = p_company_id and r.code = m.role_code
  cross join lateral unnest(m.perms) as perm
  where exists (select 1 from public.permissions p where p.code = perm)
  on conflict do nothing;

  -- Mesa de ayuda: temas con autoayuda y respuestas rápidas (antes en 0011).
  insert into public.support_topics (company_id, code, name, category, default_priority, sla_hours, self_help, sort_order)
  select p_company_id, v.code, v.name, v.category, v.priority, v.sla, v.help, v.ord
  from (values
    ('no_signal_pos', 'Sin señal en caja', 'network', 'high', 4,
     E'1. Revisa que el cable de red esté conectado en la terminal y en la pared.\n2. Verifica si otras cajas tienen señal.\n3. Apaga y enciende el módem o switch del área (espera 1 minuto).\n4. Si usas WiFi, confirma que estés en la red de la tienda.', 1),
    ('slow_wifi', 'WiFi lento en piso de venta', 'network', 'medium', 24,
     E'1. Acércate al repetidor más cercano y vuelve a probar.\n2. Olvida la red y vuelve a conectarte.\n3. Cierra apps que descarguen en segundo plano.\n4. Anota en qué pasillo o zona falla.', 2),
    ('repeater_down', 'Repetidor o antena sin conexión', 'network', 'high', 8,
     E'1. Revisa que el repetidor tenga luz encendida.\n2. Desconéctalo de la corriente 10 segundos y vuelve a conectarlo.\n3. Verifica que nadie lo haya movido o desconectado.', 3),
    ('pos_no_power', 'Terminal de cobro no enciende', 'pos', 'critical', 2,
     E'1. Revisa que el cable de corriente esté bien conectado.\n2. Prueba en otro contacto o regulador.\n3. Mantén presionado el botón de encendido 10 segundos.\n4. Si hay otra caja libre, usa esa mientras tanto.', 4),
    ('ticket_printer', 'Impresora de tickets', 'printer', 'high', 8,
     E'1. Verifica que tenga papel y que el rollo esté bien colocado.\n2. Cierra bien la tapa.\n3. Apágala y enciéndela.\n4. Revisa que el cable USB esté conectado.', 5),
    ('scanner_no_read', 'Lector no lee', 'scanner', 'medium', 8,
     E'1. Limpia la ventana del lector con un paño seco.\n2. Desconecta y vuelve a conectar el cable.\n3. Prueba con otro código de barras.\n4. Mientras tanto captura el código a mano.', 6),
    ('scale_no_connect', 'Báscula no conecta', 'scanner', 'high', 8,
     E'1. Revisa que la báscula esté encendida y en cero.\n2. Revisa el cable entre la báscula y la caja.\n3. Reinicia la báscula y luego la aplicación de caja.', 7),
    ('cant_login', 'No puedo iniciar sesión', 'access', 'high', 4,
     E'1. Revisa que la empresa y tu usuario estén bien escritos (sin espacios).\n2. Revisa mayúsculas en la contraseña.\n3. Prueba en otro dispositivo.\n4. Pide a tu jefe que confirme que tu cuenta está activa.', 8),
    ('app_error', 'Error en la app', 'bug', 'medium', 24,
     E'1. Recarga la página.\n2. Cierra sesión y vuelve a entrar.\n3. Toma una foto o captura del mensaje de error.', 9),
    ('feature_request', 'Solicitud de mejora', 'feature', 'low', 120,
     E'Describe qué te gustaría mejorar y cómo te ayudaría en tu trabajo diario.', 10)
  ) as v(code, name, category, priority, sla, help, ord)
  on conflict (company_id, code) do nothing;

  insert into public.support_canned_responses (company_id, title, body)
  select p_company_id, v.title, v.body
  from (values
    ('Recibido, en revisión', 'Hola, recibimos tu reporte y ya lo estamos revisando. Te avisamos en cuanto tengamos novedades.'),
    ('Necesitamos más información', 'Para ayudarte mejor, ¿nos puedes enviar una foto del problema y decirnos desde cuándo ocurre?'),
    ('Técnico en camino', 'Un técnico va en camino a tu sucursal. Por favor mantén el equipo como está para poder revisarlo.'),
    ('Prueba reiniciar', 'Por favor apaga el equipo, espera 30 segundos y vuelve a encenderlo. Cuéntanos si el problema continúa.'),
    ('Resuelto', 'El problema quedó resuelto. Si vuelve a ocurrir, reabre este ticket y lo atendemos de inmediato.')
  ) as v(title, body)
  on conflict (company_id, title) do nothing;

  -- Plantillas: Gerencia (apertura/cierre), Cajas y Protección (antes 0012) y la ronda de carritos.
  insert into public.checklist_templates
    (company_id, department_id, title, description, shift, start_time, end_time, frequency, requires_evidence,
     schedule_anchor, start_offset_minutes, end_offset_minutes, repeat_every_minutes, repeat_until)
  select p_company_id, d.id, v.title, v.descr, v.shift, v.st::time, v.et::time, 'daily', v.ev,
         coalesce(v.anchor, 'fixed'), v.so, v.eo, v.rep, v.until::time
  from (values
    ('GER', 'Apertura · Exterior y seguridad', 'Revisión exterior y de seguridad antes de abrir', 'apertura', '06:00', '07:00', true,  'opening', -60,  0, null::int, null),
    ('GER', 'Apertura · Piso de venta',        'Piso de venta listo para recibir clientes',        'apertura', '06:30', '07:30', true,  'opening', -30, 30, null, null),
    ('GER', 'Apertura · Perecederos y frío',   'Perecederos exhibidos y equipos de frío en rango', 'apertura', '06:30', '07:30', true,  'opening', -30, 30, null, null),
    ('GER', 'Apertura · Cajas y personal',     'Personal, cajas y servicios listos',               'apertura', '06:45', '07:30', false, 'opening', -15, 30, null, null),
    ('GER', 'Cierre · Piso y perecederos',     'Resguardo de perecederos y piso en orden',         'cierre',   '21:00', '22:00', false, 'closing', -60,  0, null, null),
    ('GER', 'Cierre · Cajas y valores',        'Cortes de caja y resguardo de efectivo',           'cierre',   '21:30', '22:30', true,  'closing', -30, 30, null, null),
    ('GER', 'Cierre · Seguridad',              'Tienda cerrada y asegurada',                       'cierre',   '22:00', '23:00', true,  'closing',   0, 60, null, null),
    ('CAJ', 'Limpieza de cajas', 'Canastillas, inicio y fin de cajas, y carritos de servicio (silla de ruedas, carrito eléctrico)', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Recolección de carritos', 'Foto de la hoja firmada de recolección de carritos de 7:00 a 22:00', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Recolección de devoluciones', 'Foto de la hoja firmada por todas las áreas de 7:00 a 22:00', 'especial', '07:00', '22:30', true, null, null, null, null, null),
    ('PRO', 'Revisión de tarimas y retornables', 'Existencias en recibo: tarimas azules y cafés, javas de fruta y pacas de cartón', 'cierre', '20:00', '22:30', true, null, null, null, null, null),
    ('CAJ', 'Ronda de carritos y canastillas', 'Recolectar carritos del estacionamiento y acomodar canastillas en la entrada', 'especial', '08:00', '10:00', false, null, null, null, 120, '20:00')
  ) as v(dept, title, descr, shift, st, et, ev, anchor, so, eo, rep, until)
  join public.departments d on d.company_id = p_company_id and d.code = v.dept
  where not exists (select 1 from public.checklist_templates t where t.company_id = p_company_id and t.title = v.title);

  -- Preguntas (solo a plantillas que aún no tienen ninguna).
  insert into public.checklist_questions (template_id, position, text, answer_type, options, is_required, is_critical, requires_photo)
  select t.id, q.pos, q.txt, q.typ, q.opts::jsonb, q.req, q.crit, q.photo
  from public.checklist_templates t
  join (values
    ('Apertura · Exterior y seguridad', 1, 'Estacionamiento limpio e iluminado', 'yes_no', null, true, false, false),
    ('Apertura · Exterior y seguridad', 2, 'Fachada y anuncios encendidos', 'yes_no', null, true, false, false),
    ('Apertura · Exterior y seguridad', 3, 'Accesos y salidas de emergencia libres', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 4, 'Alarma desactivada correctamente', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 5, 'Cámaras de vigilancia grabando', 'yes_no', null, true, true, false),
    ('Apertura · Exterior y seguridad', 6, 'Carritos y canastillas en su lugar', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 1, 'Pisos limpios y secos', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 2, 'Pasillos sin obstáculos ni tarimas', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 3, 'Anaqueles surtidos sin huecos visibles', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 4, 'Cabeceras armadas según la promoción vigente', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 5, 'Cenefas y precios de oferta colocados', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 6, 'Señalización correcta', 'yes_no', null, true, false, false),
    ('Apertura · Piso de venta', 7, 'Música y aire acondicionado funcionando', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 2, 'Fruta y verdura surtida y sin producto en mal estado', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 3, 'Carnes y salchichonería exhibidas correctamente', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 4, 'Panadería y tortillería listas', 'yes_no', null, true, false, false),
    ('Apertura · Perecederos y frío', 5, 'Sin producto caducado en exhibición', 'yes_no', null, true, true, false),
    ('Apertura · Cajas y personal', 1, 'Personal completo y uniformado', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 2, 'Cajas con fondo asignado', 'yes_no', null, true, true, false),
    ('Apertura · Cajas y personal', 3, 'Terminales y básculas funcionando', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 4, 'Bolsas e insumos en cajas', 'yes_no', null, true, false, false),
    ('Apertura · Cajas y personal', 5, 'Baños limpios y surtidos', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 1, 'Perecederos retirados o resguardados', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 2, 'Merma del día registrada', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 4, 'Piso limpio', 'yes_no', null, true, false, false),
    ('Cierre · Piso y perecederos', 5, 'Producto devuelto a su lugar', 'yes_no', null, true, false, false),
    ('Cierre · Cajas y valores', 1, 'Cortes de caja realizados', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 2, 'Efectivo resguardado en caja fuerte', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 3, 'Diferencias de caja reportadas', 'yes_no', null, true, true, false),
    ('Cierre · Cajas y valores', 4, 'Terminales cerradas', 'yes_no', null, true, false, false),
    ('Cierre · Seguridad', 1, 'Equipos no esenciales apagados', 'yes_no', null, true, false, false),
    ('Cierre · Seguridad', 2, 'Puertas y accesos cerrados', 'yes_no', null, true, true, false),
    ('Cierre · Seguridad', 3, 'Alarma activada', 'yes_no', null, true, true, false),
    ('Cierre · Seguridad', 4, 'Pendientes para el turno de mañana', 'text', null, false, false, false),
    ('Limpieza de cajas', 1, 'Inicio de cajas: banda, escáner, monitor y mostrador limpios', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 2, 'Canastillas limpias, completas y acomodadas', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 3, 'Sillas de ruedas limpias y en buen estado', 'yes_no', null, true, false, false),
    ('Limpieza de cajas', 4, 'Carritos eléctricos limpios y con batería cargada', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 5, 'Fin de cajas: área limpia, sin basura ni producto olvidado', 'yes_no', null, true, false, true),
    ('Limpieza de cajas', 6, 'Observaciones (equipo dañado, faltantes)', 'text', null, false, false, false),
    ('Recolección de carritos', 1, 'Foto de la hoja de recolección firmada (7:00 a 22:00)', 'photo', null, true, false, true),
    ('Recolección de carritos', 2, '¿Todas las horas tienen firma?', 'yes_no', null, true, false, false),
    ('Recolección de carritos', 3, 'Número de rondas realizadas', 'number', null, true, false, false),
    ('Recolección de carritos', 4, 'Observaciones', 'text', null, false, false, false),
    ('Recolección de devoluciones', 1, 'Foto de la hoja de devoluciones firmada (7:00 a 22:00)', 'photo', null, true, false, true),
    ('Recolección de devoluciones', 2, '¿Firmaron todas las áreas?', 'yes_no', null, true, false, false),
    ('Recolección de devoluciones', 3, 'Áreas que no firmaron (si aplica)', 'text', null, false, false, false),
    ('Recolección de devoluciones', 4, 'Piezas devueltas recolectadas', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 1, 'Tarimas azules en recibo (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 2, 'Tarimas cafés en recibo (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 3, 'Javas de fruta (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 4, 'Pacas de cartón sobrante (cantidad)', 'number', null, true, false, false),
    ('Revisión de tarimas y retornables', 5, 'Estado del área de retornables', 'option', '["Ordenada","Con exceso","Obstruye el paso"]', true, false, false),
    ('Revisión de tarimas y retornables', 6, 'Foto del área de tarimas y retornables', 'photo', null, true, false, true),
    ('Revisión de tarimas y retornables', 7, 'Observaciones', 'text', null, false, false, false),
    ('Ronda de carritos y canastillas', 1, 'Carritos recolectados del estacionamiento', 'yes_no', null, true, false, false),
    ('Ronda de carritos y canastillas', 2, 'Canastillas acomodadas en la entrada', 'yes_no', null, true, false, false),
    ('Ronda de carritos y canastillas', 3, 'Carritos dañados encontrados (cantidad)', 'number', null, false, false, false),
    ('Ronda de carritos y canastillas', 4, 'Foto del área de carritos', 'photo', null, true, false, true)
  ) as q(title, pos, txt, typ, opts, req, crit, photo) on q.title = t.title
  where t.company_id = p_company_id
    and not exists (select 1 from public.checklist_questions x where x.template_id = t.id);

  -- Lecturas de temperatura con rango (0014); se agregan por texto, sin duplicar.
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
  where t.company_id = p_company_id
    and not exists (select 1 from public.checklist_questions x where x.template_id = t.id and x.text = v.txt);

  -- Preguntas sí/no de temperatura retiradas en 0014 (empresas que ya las tenían).
  update public.checklist_questions q set is_active = false
    from public.checklist_templates t
   where t.id = q.template_id and t.company_id = p_company_id and q.is_active
     and (t.title, q.text) in (('Apertura · Perecederos y frío', 'Temperaturas de cámaras y vitrinas en rango'),
                               ('Cierre · Piso y perecederos', 'Cámaras cerradas y en rango'));

  -- Puntos QR en cada sucursal; la ronda de carritos exige el del Área de carritos (0018).
  insert into public.checkpoints (company_id, branch_id, department_id, name)
  select b.company_id, b.id, d.id, v.name
  from public.branches b
  cross join (values ('Área de carritos', 'CAJ'), ('Cámara de carnes', null)) as v(name, dept)
  left join public.departments d on d.company_id = b.company_id and d.code = v.dept
  where b.company_id = p_company_id
  on conflict (branch_id, name) do nothing;

  update public.checklist_templates t
     set checkpoint_required = true,
         checkpoint_id = (select c.id from public.checkpoints c join public.branches b on b.id = c.branch_id
                          where c.company_id = t.company_id and c.name = 'Área de carritos' order by b.code limit 1)
   where t.company_id = p_company_id and t.title = 'Ronda de carritos y canastillas' and t.checkpoint_id is null
     and exists (select 1 from public.checkpoints c where c.company_id = t.company_id and c.name = 'Área de carritos');

  -- Los gerentes sin departamento pertenecen a Gerencia.
  update public.employees e set department_id = d.id
    from public.departments d, public.roles r
   where e.company_id = p_company_id and r.id = e.role_id and r.code = 'gerente' and e.department_id is null
     and d.company_id = e.company_id and d.code = 'GER';

  perform public.generate_checklist_runs(p_company_id, public.company_today(p_company_id));
  perform public.set_bypass(v_prev);
end $$;
revoke all on function public.seed_company_base(uuid) from public, anon, authenticated;

-- Empresas que ya existen: completa lo que les falte.
select public.seed_company_base(id) from public.companies;


-- >>>>>>>>>>>>>>>> migrations/0024_plataforma_empresas_soporte.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0024 · PLATAFORMA: ALTA DE EMPRESAS Y SOPORTE ENTRE EMPRESAS
-- -----------------------------------------------------------------------------
--   A. provision_company(...): da de alta una empresa cliente completa en una
--      sola llamada (empresa, semilla base, primera sucursal, propietario con
--      su cuenta y, opcional, datos demo).
--      platform_list_companies() y platform_set_company_status().
--   B. Soporte Operalia: el superadmin atiende los tickets de todas las
--      empresas con RPCs (platform_list_tickets, platform_get_ticket,
--      platform_reply_ticket). Las políticas RLS de support_tickets NO se
--      abren a otras empresas. Sus respuestas se firman "Soporte Operalia".
-- Todas son SECURITY DEFINER y fallan si not is_platform_admin().
-- Re-ejecutable.
-- =============================================================================

-- ─── A. EMPRESAS ────────────────────────────────────────────────────────────
-- Alta de empresa. Todo ocurre en la misma transacción: si algo falla
-- (código repetido, contraseña corta…) no queda nada a medias.
-- La sucursal se crea ANTES de seed_company_base para que reciba sus puntos QR
-- y los checklists del día. La cuenta del propietario la crea
-- admin_set_password en modo sistema (correo usuario@<code>.operalia.local,
-- must_change_password = true).
create or replace function public.provision_company(
  p_name text, p_legal_name text, p_rfc text, p_code text, p_timezone text,
  p_branch_code text, p_branch_name text,
  p_owner_username text, p_owner_full_name text, p_owner_password text,
  p_with_demo boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_code     text := lower(trim(coalesce(p_code, '')));
  v_tz       text := coalesce(nullif(trim(p_timezone), ''), 'America/Tijuana');
  v_username text := lower(trim(coalesce(p_owner_username, '')));
  v_company  uuid;
  v_branch   uuid;
  v_emp      uuid;
  v_prev     text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma da de alta empresas';
  end if;

  if coalesce(trim(p_name), '') = '' then raise exception 'Escribe el nombre de la empresa'; end if;
  if v_code !~ '^[a-z0-9][a-z0-9-]{0,28}[a-z0-9]$' then
    raise exception 'Código de empresa inválido: de 2 a 30 caracteres, solo minúsculas, números y guiones (sin guion al inicio o al final)';
  end if;
  if exists (select 1 from public.companies where code = v_code) then
    raise exception 'Ya existe una empresa con el código %', v_code;
  end if;
  if not exists (select 1 from pg_timezone_names where name = v_tz) then
    raise exception 'Zona horaria desconocida: %', v_tz;
  end if;
  if coalesce(trim(p_branch_code), '') = '' or coalesce(trim(p_branch_name), '') = '' then
    raise exception 'Escribe la clave y el nombre de la primera sucursal';
  end if;
  if v_username !~ '^[a-z0-9][a-z0-9._-]{2,39}$' then
    raise exception 'Usuario del propietario inválido: de 3 a 40 caracteres, minúsculas, números, punto, guion o guion bajo';
  end if;
  if coalesce(trim(p_owner_full_name), '') = '' then raise exception 'Escribe el nombre del propietario'; end if;
  if coalesce(length(p_owner_password), 0) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  if p_with_demo and to_regprocedure('public.seed_company_demo(uuid)') is null then
    raise exception 'Los datos demo no están instalados en esta base (demo/0009)';
  end if;

  v_prev := public.set_bypass('on');

  insert into public.companies (name, legal_name, rfc, timezone, code, status)
  values (trim(p_name), nullif(trim(p_legal_name), ''), nullif(upper(trim(p_rfc)), ''), v_tz, v_code, 'active')
  returning id into v_company;

  insert into public.branches (company_id, code, name)
  values (v_company, trim(p_branch_code), trim(p_branch_name))
  returning id into v_branch;

  perform public.seed_company_base(v_company);

  insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                username, full_name, position, is_owner)
  values (v_company, v_branch,
          (select id from public.departments where company_id = v_company and code = 'ADM'),
          (select id from public.roles where company_id = v_company and code = 'admin'),
          'EMP-0001', v_username, trim(p_owner_full_name), 'Propietario', true)
  returning id into v_emp;

  perform public.admin_set_password(v_emp, p_owner_password);

  if p_with_demo then
    execute 'select public.seed_company_demo($1)' using v_company;
  end if;

  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, new_data)
  values (v_company, 'companies', v_company::text, 'INSERT', public.auth_employee_id(),
          jsonb_build_object('evento', 'empresa_provisionada', 'code', v_code,
                             'sucursal', trim(p_branch_code), 'propietario', v_username,
                             'con_demo', p_with_demo, 'por', auth.uid()));

  perform public.set_bypass(v_prev);
  return jsonb_build_object('id', v_company, 'code', v_code, 'branch_id', v_branch,
                            'owner_employee_id', v_emp, 'owner_username', v_username);
end $$;
revoke all on function public.provision_company(text, text, text, text, text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.provision_company(text, text, text, text, text, text, text, text, text, text, boolean) to authenticated;

-- Resumen por empresa para la pantalla Plataforma → Empresas.
create or replace function public.platform_list_companies()
returns table (
  id uuid, name text, legal_name text, rfc text, code text, status text, plan text, timezone text,
  branches integer, active_employees integer, owner_name text, owner_username text,
  last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve las empresas';
  end if;
  return query
  select c.id, c.name, c.legal_name, c.rfc, c.code, c.status, c.plan, c.timezone,
         (select count(*)::int from public.branches b where b.company_id = c.id and b.status = 'active'),
         (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active'),
         o.full_name, o.username,
         (select max(u.last_sign_in_at) from public.employees e join auth.users u on u.id = e.user_id
           where e.company_id = c.id),
         c.created_at
  from public.companies c
  left join public.employees o on o.company_id = c.id and o.is_owner
  order by c.created_at;
end $$;
revoke all on function public.platform_list_companies() from public, anon;
grant execute on function public.platform_list_companies() to authenticated;

-- Suspender / reactivar. Suspendida: sus empleados pierden el acceso (0022)
-- sin borrar datos. No se suspende la empresa de un superadmin (se quedaría
-- fuera de la plataforma).
create or replace function public.platform_set_company_status(p_company_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c      public.companies%rowtype;
  v_prev text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma cambia el estado de una empresa';
  end if;
  if p_status not in ('active', 'suspended') then raise exception 'Estado inválido: %', p_status; end if;
  select * into c from public.companies where id = p_company_id;
  if not found then raise exception 'Empresa no encontrada'; end if;
  if p_status = 'suspended' and exists (
       select 1 from public.employees e join public.platform_admins pa on pa.user_id = e.user_id
        where e.company_id = c.id) then
    raise exception 'No se puede suspender la empresa de un superadmin de la plataforma';
  end if;
  if c.status = p_status then
    return jsonb_build_object('id', c.id, 'code', c.code, 'status', c.status);
  end if;

  v_prev := public.set_bypass('on');
  update public.companies set status = p_status where id = c.id;
  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, old_data, new_data)
  values (c.id, 'companies', c.id::text, 'UPDATE', public.auth_employee_id(),
          jsonb_build_object('status', c.status),
          jsonb_build_object('evento', case when p_status = 'suspended' then 'empresa_suspendida' else 'empresa_reactivada' end,
                             'status', p_status, 'por', auth.uid()));
  perform public.set_bypass(v_prev);
  return jsonb_build_object('id', c.id, 'code', c.code, 'status', p_status);
end $$;
revoke all on function public.platform_set_company_status(uuid, text) from public, anon;
grant execute on function public.platform_set_company_status(uuid, text) to authenticated;

-- ─── B. SOPORTE OPERALIA ────────────────────────────────────────────────────
-- Mensaje de la plataforma: sin autor (author_id null) y firmado
-- "Soporte Operalia" en la vista. Solo se escribe en modo sistema
-- (platform_reply_ticket); desde la API nadie puede marcarlo.
alter table public.support_ticket_messages add column if not exists is_platform boolean not null default false;

-- 0003 + is_platform. Corre después de trg_actor (orden alfabético), así que
-- anula el autor que trg_actor puso.
create or replace function public.tg_ticket_message_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select status into v_status from public.support_tickets where id = new.ticket_id;
  if v_status = 'closed' and not public.is_system_context() then
    raise exception 'El ticket está cerrado; reábrelo para responder';
  end if;
  if new.is_internal and not public.is_system_context() and not public.has_permission('manage_tickets') then
    new.is_internal := false;
  end if;
  if new.is_platform then
    if not public.is_system_context() then
      raise exception 'Solo Soporte Operalia responde como plataforma';
    end if;
    new.author_id := null;
    new.is_internal := false;
  end if;
  return new;
end $$;

drop view if exists public.v_support_ticket_messages;
create view public.v_support_ticket_messages with (security_invoker = on) as
select m.*,
       case when m.is_platform then 'Soporte Operalia' else e.full_name end as author_name,
       case when m.is_platform then 'Plataforma' else e.position end as author_position
from public.support_ticket_messages m
left join public.employees e on e.id = m.author_id;
grant select on public.v_support_ticket_messages to authenticated;

-- Empleados (en su propia empresa) que son superadmin: a ellos llegan los avisos.
create or replace function public.platform_admin_employees()
returns setof uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e
  join public.platform_admins pa on pa.user_id = e.user_id
  where e.status = 'active'
$$;
revoke all on function public.platform_admin_employees() from public, anon, authenticated;

-- Ticket nuevo de otra empresa → aviso al superadmin (los de su propia
-- empresa ya le llegan por tg_ticket_notify).
create or replace function public.tg_ticket_platform_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_emp uuid;
  v_co  text;
begin
  select name into v_co from public.companies where id = new.company_id;
  for v_emp in
    select x from public.platform_admin_employees() x
    where (select company_id from public.employees where id = x) <> new.company_id
  loop
    perform public.notify_employee(v_emp, 'ticket', 'Nuevo ticket ' || new.folio || ' · ' || v_co,
                                   new.subject, '/plataforma/soporte/' || new.id);
  end loop;
  return null;
end $$;
drop trigger if exists trg_ticket_platform_notify on public.support_tickets;
create trigger trg_ticket_platform_notify after insert on public.support_tickets
  for each row execute function public.tg_ticket_platform_notify();

-- El solicitante respondió en un ticket que atiende Soporte Operalia → aviso.
create or replace function public.tg_ticket_message_platform_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t     public.support_tickets%rowtype;
  v_emp uuid;
begin
  if new.is_platform or new.is_internal then return null; end if;
  select * into t from public.support_tickets where id = new.ticket_id;
  if new.author_id is distinct from t.created_by
     or not exists (select 1 from public.support_ticket_messages m where m.ticket_id = t.id and m.is_platform) then
    return null;
  end if;
  for v_emp in select x from public.platform_admin_employees() x loop
    perform public.notify_employee(v_emp, 'ticket', 'El usuario respondió ' || t.folio,
                                   left(new.body, 140), '/plataforma/soporte/' || t.id);
  end loop;
  return null;
end $$;
drop trigger if exists trg_ticket_message_platform_notify on public.support_ticket_messages;
create trigger trg_ticket_message_platform_notify after insert on public.support_ticket_messages
  for each row execute function public.tg_ticket_message_platform_notify();

-- Bandeja de todas las empresas. p_status: un estado, 'active' (abiertos),
-- 'done' (resueltos y cerrados) u 'overdue' (vencidos).
create or replace function public.platform_list_tickets(
  p_company_id uuid default null, p_status text default null,
  p_search text default null, p_limit integer default 200)
returns table (
  id uuid, folio text, company_id uuid, company_name text, company_code text,
  branch_name text, department_name text, subject text, category text, topic_name text,
  priority text, status text, blocks_operation boolean, created_by_name text, assigned_to_name text,
  due_at timestamptz, is_overdue boolean, first_response_at timestamptz,
  messages_count bigint, last_message_at timestamptz, platform_replied boolean,
  created_at timestamptz, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_term text := '%' || nullif(trim(coalesce(p_search, '')), '') || '%';
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia ve los tickets de todas las empresas';
  end if;
  return query
  select v.id, v.folio, v.company_id, c.name, c.code,
         v.branch_name, v.department_name, v.subject, v.category, v.topic_name,
         v.priority, v.status, v.blocks_operation, v.created_by_name, v.assigned_to_name,
         v.due_at, v.is_overdue, v.first_response_at,
         v.messages_count, v.last_message_at,
         exists (select 1 from public.support_ticket_messages m where m.ticket_id = v.id and m.is_platform),
         v.created_at, v.updated_at
  from public.v_support_tickets v
  join public.companies c on c.id = v.company_id
  where (p_company_id is null or v.company_id = p_company_id)
    and (p_status is null
      or (p_status = 'active'  and v.status in ('open', 'in_progress', 'waiting_user'))
      or (p_status = 'done'    and v.status in ('resolved', 'closed'))
      or (p_status = 'overdue' and v.is_overdue)
      or v.status = p_status)
    and (v_term is null or v.folio ilike v_term or v.subject ilike v_term or v.description ilike v_term)
  order by v.updated_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 500));
end $$;
revoke all on function public.platform_list_tickets(uuid, text, text, integer) from public, anon;
grant execute on function public.platform_list_tickets(uuid, text, text, integer) to authenticated;

-- Ticket con su empresa y la conversación completa (incluye notas internas
-- del equipo de soporte de la tienda, marcadas).
create or replace function public.platform_get_ticket(p_ticket_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ticket jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia ve los tickets de todas las empresas';
  end if;
  select to_jsonb(v) || jsonb_build_object('company_name', c.name, 'company_code', c.code, 'company_status', c.status)
    into v_ticket
  from public.v_support_tickets v join public.companies c on c.id = v.company_id
  where v.id = p_ticket_id;
  if v_ticket is null then raise exception 'Ticket no encontrado'; end if;

  return jsonb_build_object(
    'ticket', v_ticket,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'body', m.body, 'created_at', m.created_at,
               'is_internal', m.is_internal, 'is_platform', m.is_platform,
               'author_name', m.author_name, 'author_position', m.author_position)
             order by m.created_at)
      from public.v_support_ticket_messages m where m.ticket_id = p_ticket_id), '[]'::jsonb));
end $$;
revoke all on function public.platform_get_ticket(uuid) from public, anon;
grant execute on function public.platform_get_ticket(uuid) to authenticated;

-- Responde como "Soporte Operalia" y, opcionalmente, cambia el estado. Los
-- triggers de 0003 marcan la primera respuesta, pasan el ticket a "en
-- atención" y avisan a quien lo levantó.
create or replace function public.platform_reply_ticket(p_ticket_id uuid, p_body text, p_status text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t      public.support_tickets%rowtype;
  v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_msg  uuid;
  v_prev text;
begin
  if not public.is_platform_admin() then
    raise exception 'Solo Soporte Operalia responde tickets de otras empresas';
  end if;
  select * into t from public.support_tickets where id = p_ticket_id;
  if not found then raise exception 'Ticket no encontrado'; end if;
  if v_body is null and p_status is null then raise exception 'Escribe una respuesta'; end if;
  if p_status is not null and p_status not in ('open', 'in_progress', 'waiting_user', 'resolved', 'closed') then
    raise exception 'Estado inválido: %', p_status;
  end if;
  if t.status = 'closed' and v_body is not null and coalesce(p_status, 'closed') = 'closed' then
    raise exception 'El ticket está cerrado; reábrelo para responder';
  end if;

  -- Primero el estado (así reabre antes de responder y el aviso de "en
  -- atención" automático no se suma al del estado elegido).
  v_prev := public.set_bypass('on');
  if p_status is not null then
    update public.support_tickets set status = p_status where id = t.id and status is distinct from p_status;
  end if;
  if v_body is not null then
    insert into public.support_ticket_messages (ticket_id, body, is_platform)
    values (t.id, v_body, true)
    returning id into v_msg;
  end if;
  perform public.set_bypass(v_prev);

  return jsonb_build_object('message_id', v_msg,
                            'status', (select status from public.support_tickets where id = t.id));
end $$;
revoke all on function public.platform_reply_ticket(uuid, text, text) from public, anon;
grant execute on function public.platform_reply_ticket(uuid, text, text) to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0025_plataforma_rendimiento.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0025 · PLATAFORMA: RENDIMIENTO DE LAS TIENDAS Y PROSPECTOS
-- -----------------------------------------------------------------------------
--   A. Indicadores por empresa y sucursal para el superadmin. Solo devuelven
--      AGREGADOS (conteos, sumas y porcentajes), nunca filas de una empresa.
--        platform_company_kpis(desde, hasta)
--        platform_company_trend(empresa, métrica, desde, hasta)
--        platform_checklist_heatmap(desde, hasta, empresa)
--      Las definiciones son las de Estadísticas (src/services/reportService.js):
--        * checklists: corridas del periodo sin canceladas; completados ÷ total
--          (runCompliance). «A tiempo» = completado antes del fin de su
--          horario (isLate del reporte de checklists, al revés). Solo cuentan
--          las corridas cuyo horario ya terminó: las de hoy que siguen en su
--          ventana aún no se pueden calificar (si no, «hoy» saldría en 0 %).
--        * tareas vencidas: abiertas con fecha límite pasada (v_tasks.is_late).
--        * tareas a tiempo: completadas el día de su fecha límite o antes (taskOnTime).
--        * mermas: movimientos 'waste'; valor = cantidad × (unit_cost o costo del producto).
--        * exactitud del conteo cíclico: productos contados sin diferencia ÷ contados.
--        * SLA de soporte: tickets del periodo con vencimiento; cumplido si se
--          resolvió/cerró antes de due_at o si sigue abierto y aún no vence (slaOf).
--      Nuevo (Estadísticas no lo tenía): tiempo de atención de huecos en
--      anaquel = horas de reported_at a resolved_at de los resueltos, con la
--      misma fórmula que las horas de cierre de tareas.
--      Los días se cuentan en la zona horaria de cada empresa.
--   B. platform_company_health(): salud de la cuenta (verde, amarillo, rojo) y
--      avance de arranque por empresa.
--   C. platform_leads: prospectos de la plataforma.
-- Todas las funciones son SECURITY DEFINER y fallan si not is_platform_admin().
-- Re-ejecutable.
-- =============================================================================

-- ─── C. PROSPECTOS (va primero: la salud de la cuenta lo consulta) ──────────
create table if not exists public.platform_leads (
  id            uuid primary key default gen_random_uuid(),
  chain_name    text not null,                 -- nombre de la cadena
  contact_name  text,
  contact_email text,
  contact_phone text,
  branch_count  integer check (branch_count is null or branch_count >= 0),
  business_type text,                          -- giro: abarrotes, farmacia, ferretería…
  status        text not null default 'new'
                check (status in ('new','demo','negotiation','won','lost')),
  notes         text,
  company_id    uuid references public.companies(id) on delete set null, -- al darla de alta
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists platform_leads_status_idx on public.platform_leads (status, updated_at desc);

drop trigger if exists trg_updated_at on public.platform_leads;
create trigger trg_updated_at before update on public.platform_leads
  for each row execute function public.tg_set_updated_at();

create or replace function public.tg_platform_lead_actor()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null then new.created_by := auth.uid(); end if;
  return new;
end $$;
drop trigger if exists trg_platform_lead_actor on public.platform_leads;
create trigger trg_platform_lead_actor before insert on public.platform_leads
  for each row execute function public.tg_platform_lead_actor();

-- Solo superadmins, desde la app; ninguna empresa los ve.
alter table public.platform_leads enable row level security;
revoke all on public.platform_leads from anon;
grant select, insert, update, delete on public.platform_leads to authenticated;
drop policy if exists platform_leads_all on public.platform_leads;
create policy platform_leads_all on public.platform_leads for all to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

-- ─── A. INDICADORES POR EMPRESA Y SUCURSAL ──────────────────────────────────
-- Una fila por empresa (branch_id null) y una por sucursal. Trae numeradores y
-- denominadores para que el frontend sume la plataforma completa sin promediar
-- porcentajes. Las métricas «actuales» (tareas vencidas, huecos y tickets
-- abiertos, empleados, accesos de 7 días) no dependen del periodo.
create or replace function public.platform_company_kpis(p_from date, p_to date)
returns table (
  company_id uuid, company_name text, company_code text, company_status text,
  branch_id uuid, branch_name text, branch_code text, branch_status text,
  runs_total integer, runs_completed integer, runs_on_time integer,
  checklist_pct integer, checklist_on_time_pct integer,
  tasks_late integer,
  waste_count integer, waste_qty numeric, waste_value numeric,
  counts_total integer, counts_exact integer, count_accuracy_pct integer,
  gaps_open integer, gaps_resolved integer, gap_hours numeric,
  tickets_open integer, tickets_overdue integer, sla_total integer, sla_met integer, sla_pct integer,
  employees_active integer, users_7d integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 366 then raise exception 'El periodo máximo es de un año'; end if;

  return query
  with keys as (
    select b.company_id as cid, b.id as bid from public.branches b
    union all
    select c.id, null::uuid from public.companies c
  ),
  runs as (
    select r.company_id as cid, r.branch_id as bid,
           count(*) as total,
           count(*) filter (where r.status = 'completed') as done,
           count(*) filter (where r.status = 'completed'
                              and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone c.timezone)) as on_time
    from public.checklist_runs r join public.companies c on c.id = r.company_id
    where r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
      and ((r.scheduled_date + r.scheduled_end) at time zone c.timezone) <= now()
    group by 1, 2
  ),
  late as (
    select t.company_id as cid, t.branch_id as bid, count(*) as n
    from public.tasks t
    where t.status in ('pending', 'in_progress') and t.due_date < public.company_today(t.company_id)
    group by 1, 2
  ),
  waste as (
    select m.company_id as cid, m.branch_id as bid, count(*) as n, sum(m.quantity) as qty,
           sum(m.quantity * coalesce(m.unit_cost, p.cost, 0)) as val
    from public.inventory_movements m
    join public.companies c on c.id = m.company_id
    join public.products p on p.id = m.product_id
    where m.movement_type = 'waste' and (m.created_at at time zone c.timezone)::date between p_from and p_to
    group by 1, 2
  ),
  counts as (
    select k.company_id as cid, k.branch_id as bid, count(*) as total, count(*) filter (where i.difference = 0) as exact
    from public.cycle_count_items i
    join public.cycle_count_tasks k on k.id = i.task_id
    join public.companies c on c.id = k.company_id
    where i.counted_at is not null and (i.counted_at at time zone c.timezone)::date between p_from and p_to
    group by 1, 2
  ),
  gaps as (
    select g.company_id as cid, g.branch_id as bid,
           count(*) filter (where g.status = 'open') as open_n,
           count(*) filter (where g.status = 'resolved' and (g.resolved_at at time zone c.timezone)::date between p_from and p_to) as resolved_n,
           coalesce(sum(extract(epoch from g.resolved_at - g.reported_at) / 3600)
             filter (where g.status = 'resolved' and (g.resolved_at at time zone c.timezone)::date between p_from and p_to), 0) as hours_sum
    from public.shelf_gaps g join public.companies c on c.id = g.company_id
    group by 1, 2
  ),
  tickets as (
    select s.company_id as cid, s.branch_id as bid,
           count(*) filter (where s.status in ('open', 'in_progress', 'waiting_user')) as open_n,
           count(*) filter (where s.status in ('open', 'in_progress', 'waiting_user') and s.due_at < now()) as overdue_n,
           count(*) filter (where s.due_at is not null and (s.created_at at time zone c.timezone)::date between p_from and p_to) as sla_total,
           count(*) filter (where s.due_at is not null and (s.created_at at time zone c.timezone)::date between p_from and p_to
                              and case when coalesce(s.resolved_at, s.closed_at) is not null
                                       then coalesce(s.resolved_at, s.closed_at) <= s.due_at
                                       else now() <= s.due_at end) as sla_met
    from public.support_tickets s join public.companies c on c.id = s.company_id
    group by 1, 2
  ),
  people as (
    select e.company_id as cid, e.branch_id as bid, count(*) as active_n,
           count(*) filter (where u.last_sign_in_at >= now() - interval '7 days') as recent_n
    from public.employees e left join auth.users u on u.id = e.user_id
    where e.status = 'active'
    group by 1, 2
  ),
  agg as (
    select k.cid, k.bid,
           grouping(k.bid) as is_total,
           sum(coalesce(ru.total, 0))::int as runs_total,
           sum(coalesce(ru.done, 0))::int as runs_completed,
           sum(coalesce(ru.on_time, 0))::int as runs_on_time,
           sum(coalesce(la.n, 0))::int as tasks_late,
           sum(coalesce(wa.n, 0))::int as waste_count,
           round(sum(coalesce(wa.qty, 0)), 3) as waste_qty,
           round(sum(coalesce(wa.val, 0)), 2) as waste_value,
           sum(coalesce(co.total, 0))::int as counts_total,
           sum(coalesce(co.exact, 0))::int as counts_exact,
           sum(coalesce(ga.open_n, 0))::int as gaps_open,
           sum(coalesce(ga.resolved_n, 0))::int as gaps_resolved,
           sum(coalesce(ga.hours_sum, 0)) as gap_hours_sum,
           sum(coalesce(ti.open_n, 0))::int as tickets_open,
           sum(coalesce(ti.overdue_n, 0))::int as tickets_overdue,
           sum(coalesce(ti.sla_total, 0))::int as sla_total,
           sum(coalesce(ti.sla_met, 0))::int as sla_met,
           sum(coalesce(pe.active_n, 0))::int as employees_active,
           sum(coalesce(pe.recent_n, 0))::int as users_7d
    from keys k
    left join runs ru    on ru.cid = k.cid and ru.bid is not distinct from k.bid
    left join late la    on la.cid = k.cid and la.bid is not distinct from k.bid
    left join waste wa   on wa.cid = k.cid and wa.bid is not distinct from k.bid
    left join counts co  on co.cid = k.cid and co.bid is not distinct from k.bid
    left join gaps ga    on ga.cid = k.cid and ga.bid is not distinct from k.bid
    left join tickets ti on ti.cid = k.cid and ti.bid is not distinct from k.bid
    left join people pe  on pe.cid = k.cid and pe.bid is not distinct from k.bid
    group by grouping sets ((k.cid), (k.cid, k.bid))
    having grouping(k.bid) = 1 or k.bid is not null
  )
  select a.cid, c.name, c.code, c.status,
         case when a.is_total = 1 then null else a.bid end, b.name, b.code, b.status,
         a.runs_total, a.runs_completed, a.runs_on_time,
         round(100.0 * a.runs_completed / nullif(a.runs_total, 0))::int,
         round(100.0 * a.runs_on_time / nullif(a.runs_total, 0))::int,
         a.tasks_late,
         a.waste_count, a.waste_qty, a.waste_value,
         a.counts_total, a.counts_exact,
         round(100.0 * a.counts_exact / nullif(a.counts_total, 0))::int,
         a.gaps_open, a.gaps_resolved,
         round((a.gap_hours_sum / nullif(a.gaps_resolved, 0))::numeric, 1),
         a.tickets_open, a.tickets_overdue, a.sla_total, a.sla_met,
         round(100.0 * a.sla_met / nullif(a.sla_total, 0))::int,
         a.employees_active, a.users_7d
  from agg a
  join public.companies c on c.id = a.cid
  left join public.branches b on b.id = a.bid and a.is_total = 0
  order by c.name, a.is_total desc, b.code;
end $$;
revoke all on function public.platform_company_kpis(date, date) from public, anon;
grant execute on function public.platform_company_kpis(date, date) to authenticated;

-- Serie diaria de una métrica (p_company_id null = toda la plataforma).
-- value: el valor del día (null si no hubo base para calcularlo); base: cuántos
-- registros lo forman (corridas, tareas, mermas, productos contados…).
--   checklist_pct · checklist_on_time_pct · tasks_on_time_pct · waste_value ·
--   waste_count · count_accuracy_pct · gaps_reported · gap_hours · tickets_created
create or replace function public.platform_company_trend(p_company_id uuid, p_metric text, p_from date, p_to date)
returns table (day date, value numeric, base integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 366 then raise exception 'El periodo máximo es de un año'; end if;
  if p_metric not in ('checklist_pct', 'checklist_on_time_pct', 'tasks_on_time_pct', 'waste_value', 'waste_count',
                      'count_accuracy_pct', 'gaps_reported', 'gap_hours', 'tickets_created') then
    raise exception 'Métrica desconocida: %', p_metric;
  end if;

  return query
  with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
  co as (select c.id, c.timezone from public.companies c where p_company_id is null or c.id = p_company_id),
  src as (
    -- Checklists (por fecha programada)
    select r.scheduled_date as day,
           case when p_metric = 'checklist_pct' then (r.status = 'completed')
                else (r.status = 'completed' and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone co.timezone)) end::int::numeric as v
    from public.checklist_runs r join co on co.id = r.company_id
    where p_metric in ('checklist_pct', 'checklist_on_time_pct')
      and r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
      and ((r.scheduled_date + r.scheduled_end) at time zone co.timezone) <= now()
    union all
    -- Tareas completadas ese día: a tiempo si no tenían fecha límite o se cerraron a más tardar ese día
    select (t.completed_at at time zone co.timezone)::date,
           (t.due_date is null or (t.completed_at at time zone co.timezone)::date <= t.due_date)::int::numeric
    from public.tasks t join co on co.id = t.company_id
    where p_metric = 'tasks_on_time_pct' and t.status = 'completed' and t.completed_at is not null
      and (t.completed_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Mermas
    select (m.created_at at time zone co.timezone)::date,
           case when p_metric = 'waste_value' then m.quantity * coalesce(m.unit_cost, p.cost, 0) else 1 end
    from public.inventory_movements m join co on co.id = m.company_id join public.products p on p.id = m.product_id
    where p_metric in ('waste_value', 'waste_count') and m.movement_type = 'waste'
      and (m.created_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Conteo cíclico
    select (i.counted_at at time zone co.timezone)::date, (i.difference = 0)::int::numeric
    from public.cycle_count_items i join public.cycle_count_tasks k on k.id = i.task_id join co on co.id = k.company_id
    where p_metric = 'count_accuracy_pct' and i.counted_at is not null
      and (i.counted_at at time zone co.timezone)::date between p_from and p_to
    union all
    -- Huecos reportados ese día / horas de atención de los resueltos ese día
    select case when p_metric = 'gaps_reported' then (g.reported_at at time zone co.timezone)::date
                else (g.resolved_at at time zone co.timezone)::date end,
           case when p_metric = 'gaps_reported' then 1
                else (extract(epoch from g.resolved_at - g.reported_at) / 3600)::numeric end
    from public.shelf_gaps g join co on co.id = g.company_id
    where (p_metric = 'gaps_reported' and (g.reported_at at time zone co.timezone)::date between p_from and p_to)
       or (p_metric = 'gap_hours' and g.status = 'resolved' and (g.resolved_at at time zone co.timezone)::date between p_from and p_to)
    union all
    -- Tickets creados
    select (s.created_at at time zone co.timezone)::date, 1::numeric
    from public.support_tickets s join co on co.id = s.company_id
    where p_metric = 'tickets_created' and (s.created_at at time zone co.timezone)::date between p_from and p_to
  )
  select d.day,
         case
           when p_metric in ('waste_value') then round(coalesce(sum(s.v), 0), 2)
           when p_metric in ('waste_count', 'gaps_reported', 'tickets_created') then coalesce(sum(s.v), 0)
           when p_metric = 'gap_hours' then round(avg(s.v), 1)
           else round(100.0 * sum(s.v) / nullif(count(s.v), 0))
         end,
         count(s.v)::int
  from days d left join src s on s.day = d.day
  group by d.day
  order by d.day;
end $$;
revoke all on function public.platform_company_trend(uuid, text, date, date) from public, anon;
grant execute on function public.platform_company_trend(uuid, text, date, date) to authenticated;

-- Cumplimiento de checklists (runCompliance) por sucursal y día.
create or replace function public.platform_checklist_heatmap(p_from date, p_to date, p_company_id uuid default null)
returns table (company_id uuid, company_name text, branch_id uuid, branch_name text, day date, runs_total integer, pct integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve el rendimiento de las tiendas';
  end if;
  if p_from is null or p_to is null or p_from > p_to then raise exception 'Periodo inválido'; end if;
  if p_to - p_from > 92 then raise exception 'El mapa de calor abarca hasta 93 días'; end if;
  return query
  select c.id, c.name, b.id, b.name, r.scheduled_date, count(*)::int,
         round(100.0 * count(*) filter (where r.status = 'completed') / count(*))::int
  from public.checklist_runs r
  join public.branches b on b.id = r.branch_id
  join public.companies c on c.id = r.company_id
  where r.scheduled_date between p_from and p_to and r.status <> 'cancelled'
    and ((r.scheduled_date + r.scheduled_end) at time zone c.timezone) <= now()
    and (p_company_id is null or r.company_id = p_company_id)
  group by c.id, c.name, b.id, b.name, b.code, r.scheduled_date
  order by c.name, b.code, r.scheduled_date;
end $$;
revoke all on function public.platform_checklist_heatmap(date, date, uuid) from public, anon;
grant execute on function public.platform_checklist_heatmap(date, date, uuid) to authenticated;

-- ─── B. SALUD DE LA CUENTA Y AVANCE DE ARRANQUE ─────────────────────────────
-- Salud (últimos 7 días de cada empresa); gana el peor de los tres criterios:
--   uso:         % de empleados con cuenta que entraron  · verde ≥ 60, amarillo ≥ 30, rojo < 30
--   checklists:  % completados a tiempo, solo de los que  · verde ≥ 60, amarillo ≥ 45, rojo < 45 (sin corridas: amarillo)
--                ya terminaron su horario (los de hoy aún abiertos no cuentan)
--   tickets:     abiertos por sucursal activa            · verde ≤ 1, amarillo ≤ 2, rojo > 2
-- Arranque: 5 pasos (sucursales creadas, empleados con cuenta, productos
-- cargados, primera plantilla usada, primer recibo cerrado).
create or replace function public.platform_company_health()
returns table (
  company_id uuid, health text, reasons text[],
  accounts integer, users_7d integer, usage_pct integer,
  runs_7d integer, checklist_on_time_pct integer, tickets_open integer, branches integer,
  onboarding_pct integer, onboarding jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve la salud de las cuentas';
  end if;

  return query
  with base as (
    select c.id as cid, c.timezone as tz, public.company_today(c.id) as today,
           (select count(*)::int from public.branches b where b.company_id = c.id and b.status = 'active') as branches,
           (select l.branch_count from public.platform_leads l where l.company_id = c.id
             order by l.updated_at desc limit 1) as target_branches,
           (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active' and e.user_id is not null) as accounts,
           (select count(*)::int from public.employees e where e.company_id = c.id and e.status = 'active'
               and e.user_id is not null and not e.is_owner) as staff_accounts,
           (select count(*)::int from public.employees e join auth.users u on u.id = e.user_id
             where e.company_id = c.id and e.status = 'active' and u.last_sign_in_at >= now() - interval '7 days') as users_7d,
           (select count(*)::int from public.products p where p.company_id = c.id) as products,
           (select min(r.completed_at) from public.checklist_runs r where r.company_id = c.id and r.status = 'completed') as first_run,
           (select min(o.completed_at) from public.receiving_orders o where o.company_id = c.id and o.status = 'completed') as first_receipt,
           (select count(*)::int from public.support_tickets s where s.company_id = c.id
               and s.status in ('open', 'in_progress', 'waiting_user')) as tickets_open
    from public.companies c
  ),
  week as (
    select b.cid,
           count(r.id)::int as runs_7d,
           round(100.0 * count(r.id) filter (where r.status = 'completed'
                   and r.completed_at <= ((r.scheduled_date + r.scheduled_end) at time zone b.tz)) / nullif(count(r.id), 0))::int as on_time
    from base b
    left join public.checklist_runs r on r.company_id = b.cid and r.status <> 'cancelled'
         and r.scheduled_date between b.today - 6 and b.today
         and ((r.scheduled_date + r.scheduled_end) at time zone b.tz) <= now()
    group by b.cid
  ),
  scored as (
    select b.*, w.runs_7d, w.on_time,
           round(100.0 * b.users_7d / nullif(b.accounts, 0))::int as usage_pct,
           case when coalesce(round(100.0 * b.users_7d / nullif(b.accounts, 0)), 0) >= 60 then 0
                when coalesce(round(100.0 * b.users_7d / nullif(b.accounts, 0)), 0) >= 30 then 1 else 2 end as s_usage,
           case when w.on_time is null then 1 when w.on_time >= 60 then 0 when w.on_time >= 45 then 1 else 2 end as s_runs,
           case when b.tickets_open <= greatest(b.branches, 1) then 0
                when b.tickets_open <= 2 * greatest(b.branches, 1) then 1 else 2 end as s_tickets
    from base b join week w on w.cid = b.cid
  )
  select s.cid,
         (array['green', 'yellow', 'red'])[greatest(s.s_usage, s.s_runs, s.s_tickets) + 1],
         array_remove(array[
           case when s.s_usage > 0 then
             case when s.accounts = 0 then 'Nadie tiene cuenta todavía'
                  else coalesce(s.usage_pct, 0) || ' % de los usuarios entró en 7 días' end end,
           case when s.s_runs > 0 then
             case when s.on_time is null then 'Sin checklists en 7 días'
                  else s.on_time || ' % de checklists a tiempo' end end,
           case when s.s_tickets > 0 then s.tickets_open || ' tickets abiertos' end
         ], null),
         s.accounts, s.users_7d, s.usage_pct, s.runs_7d, s.on_time, s.tickets_open, s.branches,
         (100 * ((s.branches >= greatest(coalesce(s.target_branches, 1), 1))::int
               + (s.staff_accounts >= greatest(s.branches, 1))::int
               + (s.products > 0)::int
               + (s.first_run is not null)::int
               + (s.first_receipt is not null)::int) / 5)::int,
         jsonb_build_array(
           jsonb_build_object('key', 'branches', 'label', 'Sucursales creadas',
             'done', s.branches >= greatest(coalesce(s.target_branches, 1), 1),
             'detail', s.branches || coalesce(' de ' || s.target_branches, '')),
           jsonb_build_object('key', 'accounts', 'label', 'Empleados con cuenta',
             'done', s.staff_accounts >= greatest(s.branches, 1),
             'detail', s.staff_accounts || ' además del propietario (mínimo 1 por sucursal)'),
           jsonb_build_object('key', 'products', 'label', 'Productos cargados',
             'done', s.products > 0, 'detail', s.products || ' productos'),
           jsonb_build_object('key', 'first_run', 'label', 'Primera plantilla usada',
             'done', s.first_run is not null,
             'detail', coalesce(to_char(s.first_run at time zone s.tz, 'DD/MM/YYYY'), 'ningún checklist completado')),
           jsonb_build_object('key', 'first_receipt', 'label', 'Primer recibo cerrado',
             'done', s.first_receipt is not null,
             'detail', coalesce(to_char(s.first_receipt at time zone s.tz, 'DD/MM/YYYY'), 'ningún recibo cerrado')))
  from scored s;
end $$;
revoke all on function public.platform_company_health() from public, anon;
grant execute on function public.platform_company_health() to authenticated;


-- >>>>>>>>>>>>>>>> migrations/0026_aislamiento_empresas.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0026 · AISLAMIENTO ENTRE EMPRESAS: CORRECCIONES
-- -----------------------------------------------------------------------------
-- Lo que encontró supabase/pruebas/aislamiento.sql (detalle en el diario
-- 2026-10-30):
--   1. run_daily_maintenance comparaba `p_company_id <> auth_company_id()`.
--      Con la empresa suspendida (o un usuario sin empleado) auth_company_id()
--      es null, la comparación da null y dejaba correr el mantenimiento de
--      OTRA empresa. Ahora `is distinct from`; el mismo cambio, por higiene, en
--      toda función SECURITY DEFINER que compare `<> public.auth_company_id()`.
--   2. pg_cron procesaba empresas suspendidas: run_daily_maintenance y
--      send_checklist_reminders ahora se las saltan, y los jobs solo recorren
--      las activas.
--   3. effective_price, checkpoint_for_run y announcement_matches respondían
--      con ids de otra empresa (las dos primeras, incluso sin sesión). Ahora
--      solo responden sobre la empresa de quien llama (o en modo sistema).
--   4. anon podía ejecutar funciones que no necesita. Se le revoca EXECUTE en
--      todas las de public salvo request_password_reset (pantalla de login).
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. `<> auth_company_id()` → `is distinct from` ─────────────────────────
do $$
declare
  f     record;
  v_src text;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosecdef
      and pg_get_functiondef(p.oid) like '%<> public.auth_company_id()%'
  loop
    v_src := replace(pg_get_functiondef(f.oid), chr(13), '');
    v_src := replace(v_src, '<> public.auth_company_id()', 'is distinct from public.auth_company_id()');
    execute v_src;
  end loop;
end $$;

-- ─── 2. Empresas suspendidas: el mantenimiento y los recordatorios las saltan ─
do $$
declare v_src text;
begin
  select replace(pg_get_functiondef('public.run_daily_maintenance(uuid)'::regprocedure), chr(13), '') into v_src;
  if position('empresa suspendida' in v_src) = 0 then
    v_src := replace(v_src,
      'select timezone into v_tz from public.companies where id = v_company;',
      'select timezone into v_tz from public.companies where id = v_company;
  if v_tz is null or not exists (select 1 from public.companies where id = v_company and status = ''active'') then
    return jsonb_build_object(''company_id'', v_company, ''skipped'', ''empresa suspendida'');
  end if;');
    if position('empresa suspendida' in v_src) = 0 then
      raise exception 'No se pudo actualizar run_daily_maintenance: cambió su código';
    end if;
    execute v_src;
  end if;

  select replace(pg_get_functiondef('public.send_checklist_reminders(uuid, integer)'::regprocedure), chr(13), '') into v_src;
  if position('p_company_id and status = ''active''' in v_src) = 0 then
    v_src := replace(v_src,
      'select timezone into v_tz from public.companies where id = p_company_id;',
      'select timezone into v_tz from public.companies where id = p_company_id and status = ''active'';');
    if position('p_company_id and status = ''active''' in v_src) = 0 then
      raise exception 'No se pudo actualizar send_checklist_reminders: cambió su código';
    end if;
    execute v_src;
  end if;
end $$;

-- Los jobs de pg_cron (0012 y 0017) solo recorren las empresas activas.
do $$
begin
  perform cron.schedule('operalia-mantenimiento', '5 * * * *',
    'select public.run_daily_maintenance(id) from public.companies where status = ''active''');
  perform cron.schedule('operalia-recordatorios', '*/5 * * * *',
    'select public.send_checklist_reminders(id) from public.companies where status = ''active''');
exception when others then
  raise notice 'pg_cron no disponible (%). Las funciones ya se saltan las empresas suspendidas.', sqlerrm;
end $$;

-- ─── 3. Funciones auxiliares que recibían ids de otra empresa ──────────────
-- Precio vigente (0015): lo usan triggers de cambios de precio, como el
-- usuario que inserta o en modo sistema (aplicar cambios programados).
create or replace function public.effective_price(p_product_id uuid, p_branch_id uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(
    (select bp.price from public.branch_prices bp
       join public.products p on p.id = bp.product_id
      where bp.branch_id = p_branch_id and bp.product_id = p_product_id
        and (public.is_system_context() or p.company_id = public.auth_company_id())),
    (select p.price from public.products p
      where p.id = p_product_id
        and (public.is_system_context() or p.company_id = public.auth_company_id())))
$$;

-- Punto QR que corresponde a un checklist (0018).
create or replace function public.checkpoint_for_run(p_run_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select c.id
  from public.checklist_runs r
  join public.checklist_templates t on t.id = r.template_id
  join public.checkpoints model on model.id = t.checkpoint_id
  join public.checkpoints c on c.branch_id = r.branch_id and c.name = model.name and c.is_active
  where r.id = p_run_id
    and (public.is_system_context() or r.company_id = public.auth_company_id())
$$;

-- ¿Un comunicado le llega a este empleado? (0021). Solo empleados de la
-- empresa de quien pregunta.
create or replace function public.announcement_matches(
  p_employee_id uuid, p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    left join public.branches b on b.id = e.branch_id
    where e.id = p_employee_id
      and (public.is_system_context() or e.company_id = public.auth_company_id())
      and case p_scope
            when 'company' then true
            when 'zone' then b.zone_id = p_zone_id
                          or exists (select 1 from public.employee_zones ez where ez.employee_id = e.id and ez.zone_id = p_zone_id)
            when 'branch' then e.branch_id = p_branch_id
            when 'department' then (p_branch_id is null or e.branch_id = p_branch_id)
                               and (e.department_id = p_department_id
                                    or exists (select 1 from public.employee_departments ed
                                               where ed.employee_id = e.id and ed.department_id = p_department_id))
            else false
          end)
$$;

-- ─── 4. anon solo ejecuta request_password_reset ────────────────────────────
-- Supabase da EXECUTE a anon (y a PUBLIC) en cada función nueva. Se conserva
-- el acceso de authenticated donde ya lo tenía y se quita el de PUBLIC y anon.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and p.proname <> 'request_password_reset'
      and has_function_privilege('anon', p.oid, 'execute')
  loop
    if has_function_privilege('authenticated', f.sig::oid, 'execute') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    execute format('revoke execute on function %s from public, anon', f.sig);
  end loop;
end $$;
-- Funciones futuras de postgres: sin EXECUTE automático para anon.
alter default privileges in schema public revoke execute on functions from anon;


-- >>>>>>>>>>>>>>>> seed/0008_catalogos.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · SEMILLA 0008 · CATÁLOGO DE PERMISOS Y EMPRESA GATO PELÓN
-- -----------------------------------------------------------------------------
--   * Catálogo global de permisos (los posteriores los agrega cada migración).
--   * Empresa Gato Pelón (code gatopelon) y sus sucursales; zona de cada una.
--   * public.seed_company_base (migración 0023) le siembra departamentos,
--     zonas, roles y sus permisos, temas de soporte, plantillas de checklist y
--     puntos QR. Antes eso estaba repartido en seed/0008…0018.
-- IDs fijos para la empresa y sucursales. Re-ejecutable.
-- =============================================================================

-- ─── PERMISOS ────────────────────────────────────────────────────────────────
insert into public.permissions (code, module, name, description) values
  ('view_dashboard',             'General',       'Ver dashboard',                  'Acceso al panel principal'),
  ('view_inventory',             'Inventario',    'Ver inventario',                 'Consultar existencias y movimientos'),
  ('manage_inventory',           'Inventario',    'Gestionar inventario',           'Altas de producto, ajustes, conteos y mínimos'),
  ('view_prices',                'Inventario',    'Consultar precios',              'Buscar productos y ver su precio'),
  ('scan_products',              'Inventario',    'Escanear productos',             'Usar lector / cámara para buscar'),
  ('report_price_difference',    'Inventario',    'Reportar diferencia de precio',  'Levantar tarea por precio incorrecto'),
  ('create_orders',              'Pedidos',       'Crear pedidos internos',         'Solicitar mercancía o insumos'),
  ('approve_orders',             'Pedidos',       'Aprobar pedidos',                'Revisar, aprobar, rechazar y enviar pedidos'),
  ('view_suppliers',             'Proveedores',   'Ver proveedores',                'Consultar catálogo de proveedores'),
  ('manage_suppliers',           'Proveedores',   'Gestionar proveedores',          'Alta y edición de proveedores'),
  ('register_supplier_visit',    'Proveedores',   'Registrar accesos',              'Entrada y salida de proveedores'),
  ('receive_products',           'Recibo',        'Recibir mercancía',              'Capturar recibos y productos recibidos'),
  ('close_receiving',            'Recibo',        'Cerrar recibos',                 'Cerrar recibo y afectar inventario'),
  ('fill_checklists',            'Checklists',    'Llenar checklists',              'Responder checklists y bitácoras'),
  ('review_checklists',          'Checklists',    'Revisar checklists',             'Aprobar, rechazar y reabrir checklists'),
  ('manage_checklist_templates', 'Checklists',    'Diseñar checklists',             'Crear y editar plantillas'),
  ('upload_evidence',            'Evidencias',    'Subir evidencias',               'Adjuntar fotos y archivos'),
  ('review_evidence',            'Evidencias',    'Revisar evidencias',             'Aprobar o rechazar evidencias'),
  ('manage_expirations',         'Caducidades',   'Gestionar caducidades',          'Registrar lotes, rebajas y retiros'),
  ('manage_price_changes',       'Precios',       'Gestionar cambios de precio',    'Registrar cambios de precio'),
  ('manage_shelf_tags',          'Precios',       'Gestionar cenefas',              'Imprimir y colocar cenefas'),
  ('validate_shelf_tags',        'Precios',       'Validar cenefas',                'Validar que la cenefa está correcta'),
  ('view_tasks',                 'Tareas',        'Ver tareas',                     'Ver y avanzar tareas asignadas'),
  ('manage_tasks',               'Tareas',        'Gestionar tareas',               'Crear, asignar y cancelar tareas'),
  ('view_reports',               'Reportes',      'Ver reportes',                   'Indicadores y exportación'),
  ('view_audit_logs',            'Reportes',      'Ver bitácora de auditoría',      'Historial de cambios del sistema'),
  ('manage_employees',           'Configuración', 'Gestionar empleados',            'Alta, baja y edición de empleados'),
  ('manage_branches',            'Configuración', 'Gestionar sucursales',           'Sucursales, departamentos y empresa'),
  ('manage_roles',               'Configuración', 'Gestionar roles y permisos',     'Editar roles y permisos especiales'),
  ('create_tickets',             'Soporte',       'Solicitar ayuda',                'Levantar tickets en la mesa de ayuda'),
  ('manage_tickets',             'Soporte',       'Atender tickets',                'Responder, asignar y resolver tickets')
on conflict (code) do update set module = excluded.module, name = excluded.name, description = excluded.description;

-- ─── EMPRESA ─────────────────────────────────────────────────────────────────
insert into public.companies (id, code, name, legal_name, timezone)
values ('c0000000-0000-4000-8000-000000000001', 'gatopelon', 'Gato Pelón', 'Gato Pelón S.A. de C.V.', 'America/Tijuana')
on conflict (id) do nothing;

-- ─── SUCURSALES ──────────────────────────────────────────────────────────────
insert into public.branches (id, company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status) values
  ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', '001', 'Sucursal Centro', 'tienda',  'Av. Principal 100',  'Tijuana', '664-100-0001', '07:00', '23:00', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', '002', 'Sucursal Norte',  'tienda',  'Blvd. Norte 250',    'Tijuana', '664-100-0002', '07:00', '22:00', 'active'),
  ('b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', '003', 'Sucursal Sur',    'express', 'Calle Sur 45',       'Tijuana', '664-100-0003', '08:00', '21:00', 'active')
on conflict (id) do nothing;

-- ─── SEMILLA BASE ────────────────────────────────────────────────────────────
select public.seed_company_base('c0000000-0000-4000-8000-000000000001');

-- Zona de cada sucursal (001 Centro, 002 Norte, 003 Sur).
update public.branches b set zone_id = z.id
  from public.zones z
 where z.company_id = b.company_id and b.zone_id is null and b.company_id = 'c0000000-0000-4000-8000-000000000001'
   and z.code = case b.code when '001' then 'CEN' when '002' then 'NOR' when '003' then 'SUR' end;


-- >>>>>>>>>>>>>>>> seed/0010_propietario.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · SEMILLA 0010 · PROPIETARIO Y SUPERADMIN DE GATO PELÓN
-- -----------------------------------------------------------------------------
-- Re-ejecutable.
--   * marcos.yeran.guerra: administrador con correo real (se liga al crear su
--     cuenta en Supabase Auth).
--   * chee: propietario de Gato Pelón (is_owner). Queda pre-registrado SIN
--     cuenta: la contraseña se pone desde la app (Empleados → chee → Crear
--     cuenta) o con admin_set_password. Ver el diario 2026-10-27.
--   * gatopelon (usuario demo): deja de ser propietario y queda como
--     superadmin de la plataforma (platform_admins), si existe.
-- Las notificaciones de prueba están en
-- demo/0010_notificaciones_prueba.sql.
-- =============================================================================

-- ─── 1. Vincular la cuenta ya creada en Supabase Auth ───────────────────────
-- marcos.yeran.guerra@gmail.com → Administrador general, Administración,
-- Sucursal Centro. Si la cuenta aún no existe en Auth, el empleado queda
-- pre-registrado y se liga solo cuando se cree (trigger on_auth_user_created,
-- que empata el usuario "marcos.yeran.guerra" con la parte antes de la @).
insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                              username, full_name, position, email)
select c.id,
       (select id from public.branches    where company_id = c.id and code = '001'),
       (select id from public.departments where company_id = c.id and code = 'ADM'),
       (select id from public.roles       where company_id = c.id and code = 'admin'),
       'EMP-0100', 'marcos.yeran.guerra', 'Marcos Yerán Ramírez Guerra', 'Administrador general',
       'marcos.yeran.guerra@gmail.com'
from public.companies c
where c.id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.employees where lower(username) = 'marcos.yeran.guerra');

update public.employees e
   set user_id = u.id
  from auth.users u
 where lower(u.email) = 'marcos.yeran.guerra@gmail.com'
   and lower(e.username) = 'marcos.yeran.guerra'
   and e.user_id is null;

-- ─── 2. chee, propietario de Gato Pelón ─────────────────────────────────────
insert into public.employees (company_id, branch_id, department_id, role_id, employee_code, username, full_name, position)
select c.id,
       (select id from public.branches    where company_id = c.id and code = '001'),
       (select id from public.departments where company_id = c.id and code = 'ADM'),
       (select id from public.roles       where company_id = c.id and code = 'admin'),
       'EMP-0101', 'chee', 'Chee', 'Propietario'
from public.companies c
where c.id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.employees where company_id = c.id and lower(username) = 'chee');

-- Solo un propietario por empresa (índice employees_one_owner_idx de 0012):
-- primero se quita a los demás y luego se marca a chee. Modo sistema, porque
-- tg_employee_owner_guard solo permite transferirlo desde la base de datos.
do $$
declare v_prev text;
begin
  v_prev := public.set_bypass('on');
  update public.employees set is_owner = false
   where company_id = 'c0000000-0000-4000-8000-000000000001' and is_owner and lower(username) <> 'chee';
  update public.employees set is_owner = true
   where company_id = 'c0000000-0000-4000-8000-000000000001' and lower(username) = 'chee' and not is_owner;
  perform public.set_bypass(v_prev);
end $$;

-- ─── 3. gatopelon, superadmin de la plataforma ──────────────────────────────
-- Sigue siendo administrador dentro de Gato Pelón. Solo aplica si su cuenta
-- existe (la crea demo/0009).
insert into public.platform_admins (user_id)
select e.user_id from public.employees e
where e.company_id = 'c0000000-0000-4000-8000-000000000001' and lower(e.username) = 'gatopelon' and e.user_id is not null
on conflict do nothing;
