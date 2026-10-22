-- =============================================================================
-- OPERALIA · pendiente.sql — INSTALACIÓN COMPLETA (pegar y ejecutar en SQL Editor)
-- Generado por supabase/build-pendiente.mjs a partir de migrations/* y seed/*.
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
create unique index if not exists employees_username_lower_key on public.employees (lower(username));

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
    and (t.frequency = 'daily'
      or (t.frequency = 'weekdays' and extract(isodow from p_date) < 6)
      or (t.frequency = 'weekly' and extract(dow from p_date) = t.weekday))
  on conflict (template_id, branch_id, scheduled_date) do nothing;
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


-- >>>>>>>>>>>>>>>> seed/0008_catalogos.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0008 · CATÁLOGOS INICIALES
-- -----------------------------------------------------------------------------
-- Objetivo: dejar la empresa lista para operar: permisos, roles con sus
-- permisos, empresa demo, sucursales y departamentos.
--
-- IDs fijos para la empresa y sucursales → los demás scripts pueden
-- referenciarlos sin búsquedas. Idempotente (ON CONFLICT).
--
-- Si se agrega un permiso nuevo en el frontend (src/config/permissions.js)
-- también debe agregarse aquí.
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
insert into public.companies (id, name, legal_name, timezone)
values ('c0000000-0000-4000-8000-000000000001', 'Gato Pelón', 'Gato Pelón S.A. de C.V.', 'America/Tijuana')
on conflict (id) do nothing;

-- ─── SUCURSALES ──────────────────────────────────────────────────────────────
insert into public.branches (id, company_id, code, name, branch_type, address, city, phone, opening_time, closing_time, status) values
  ('b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', '001', 'Sucursal Centro', 'tienda',  'Av. Principal 100',  'Tijuana', '664-100-0001', '07:00', '23:00', 'active'),
  ('b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', '002', 'Sucursal Norte',  'tienda',  'Blvd. Norte 250',    'Tijuana', '664-100-0002', '07:00', '22:00', 'active'),
  ('b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', '003', 'Sucursal Sur',    'express', 'Calle Sur 45',       'Tijuana', '664-100-0003', '08:00', '21:00', 'inactive')
on conflict (id) do nothing;

-- ─── DEPARTAMENTOS ───────────────────────────────────────────────────────────
insert into public.departments (company_id, code, name, color, description) values
  ('c0000000-0000-4000-8000-000000000001', 'ADM', 'Administración', '#0f172a', 'Oficina y administración general'),
  ('c0000000-0000-4000-8000-000000000001', 'GER', 'Gerencia',       '#1e40af', 'Gerencia de sucursal'),
  ('c0000000-0000-4000-8000-000000000001', 'CAJ', 'Cajas',          '#2563eb', 'Línea de cajas y atención'),
  ('c0000000-0000-4000-8000-000000000001', 'ABA', 'Abarrotes',      '#16a34a', 'Piso de venta abarrotes'),
  ('c0000000-0000-4000-8000-000000000001', 'REC', 'Recibo',         '#9333ea', 'Andén y recibo de mercancía'),
  ('c0000000-0000-4000-8000-000000000001', 'ALM', 'Almacén',        '#78350f', 'Bodega y resguardo'),
  ('c0000000-0000-4000-8000-000000000001', 'PRO', 'Protección',     '#dc2626', 'Seguridad y prevención de pérdidas'),
  ('c0000000-0000-4000-8000-000000000001', 'CAD', 'Caducidades',    '#ea580c', 'Control de fechas de caducidad'),
  ('c0000000-0000-4000-8000-000000000001', 'ESC', 'Escáner',        '#0891b2', 'Precios, escaneo y cenefas'),
  ('c0000000-0000-4000-8000-000000000001', 'CAR', 'Carnicería',     '#b91c1c', 'Cárnicos'),
  ('c0000000-0000-4000-8000-000000000001', 'PES', 'Pescadería',     '#0e7490', 'Pescados y mariscos'),
  ('c0000000-0000-4000-8000-000000000001', 'JUG', 'Juguetería',     '#db2777', 'Juguetes y temporada'),
  ('c0000000-0000-4000-8000-000000000001', 'TI',  'Soporte TI',     '#475569', 'Mantenimiento de la plataforma')
on conflict (company_id, code) do nothing;

-- ─── ROLES ───────────────────────────────────────────────────────────────────
insert into public.roles (company_id, code, name, scope, is_system, description) values
  ('c0000000-0000-4000-8000-000000000001', 'admin',       'Administrador general', 'company',    true, 'Control total de la empresa'),
  ('c0000000-0000-4000-8000-000000000001', 'soporte',     'Soporte TI',            'company',    true, 'Atiende la mesa de ayuda'),
  ('c0000000-0000-4000-8000-000000000001', 'auditor',     'Auditor',               'company',    true, 'Solo lectura de reportes y evidencias'),
  ('c0000000-0000-4000-8000-000000000001', 'gerente',     'Gerente de sucursal',   'branch',     true, 'Supervisa toda su sucursal'),
  ('c0000000-0000-4000-8000-000000000001', 'supervisor',  'Supervisor',            'department', true, 'Revisa departamentos asignados'),
  ('c0000000-0000-4000-8000-000000000001', 'jefe_cajas',  'Jefe de cajas',         'department', true, 'Responsable de la línea de cajas'),
  ('c0000000-0000-4000-8000-000000000001', 'cajas',       'Cajero(a)',             'self',       true, 'Consulta de precios y checklists de caja'),
  ('c0000000-0000-4000-8000-000000000001', 'abarrotes',   'Abarrotes',             'department', true, 'Inventario y pedidos de abarrotes'),
  ('c0000000-0000-4000-8000-000000000001', 'recibo',      'Recibo',                'department', true, 'Proveedores y recibo de mercancía'),
  ('c0000000-0000-4000-8000-000000000001', 'almacen',     'Almacén',               'department', true, 'Entradas, salidas y ajustes'),
  ('c0000000-0000-4000-8000-000000000001', 'proteccion',  'Protección',            'department', true, 'Rondines y control de accesos'),
  ('c0000000-0000-4000-8000-000000000001', 'caducidades', 'Caducidades',           'department', true, 'Control de lotes y fechas'),
  ('c0000000-0000-4000-8000-000000000001', 'escaner',     'Escáner',               'department', true, 'Cambios de precio y cenefas')
on conflict (company_id, code) do nothing;

-- ─── PERMISOS POR ROL ────────────────────────────────────────────────────────
with matrix(role_code, perms) as (values
  ('admin', (select array_agg(code) from public.permissions)),
  ('soporte', array['view_dashboard','create_tickets','manage_tickets','view_reports','view_audit_logs']),
  ('auditor', array['view_dashboard','view_inventory','view_prices','view_suppliers','view_tasks',
                    'view_reports','view_audit_logs']),
  ('gerente', array['view_dashboard','view_inventory','manage_inventory','view_prices','scan_products',
                    'report_price_difference','create_orders','approve_orders','view_suppliers','manage_suppliers',
                    'register_supplier_visit','receive_products','close_receiving','fill_checklists',
                    'review_checklists','manage_checklist_templates','upload_evidence','review_evidence',
                    'manage_expirations','manage_price_changes','manage_shelf_tags','validate_shelf_tags',
                    'view_tasks','manage_tasks','view_reports','view_audit_logs','manage_employees','create_tickets']),
  ('supervisor', array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                    'view_suppliers','fill_checklists','review_checklists','upload_evidence','review_evidence',
                    'manage_expirations','validate_shelf_tags','view_tasks','manage_tasks','view_reports','create_tickets']),
  ('jefe_cajas', array['view_dashboard','view_prices','scan_products','report_price_difference',
                    'fill_checklists','review_checklists','upload_evidence','review_evidence',
                    'view_tasks','manage_tasks','view_reports','create_tickets']),
  ('cajas', array['view_dashboard','view_prices','scan_products','report_price_difference',
                    'fill_checklists','upload_evidence','view_tasks']),
  ('abarrotes', array['view_dashboard','view_inventory','view_prices','scan_products','create_orders',
                    'fill_checklists','upload_evidence','view_tasks']),
  ('recibo', array['view_dashboard','view_inventory','view_suppliers','register_supplier_visit',
                    'receive_products','close_receiving','fill_checklists','upload_evidence','view_tasks']),
  ('almacen', array['view_dashboard','view_inventory','manage_inventory','view_prices','create_orders',
                    'receive_products','fill_checklists','upload_evidence','view_tasks']),
  ('proteccion', array['view_dashboard','view_suppliers','register_supplier_visit','fill_checklists',
                    'upload_evidence','view_tasks']),
  ('caducidades', array['view_dashboard','view_inventory','view_prices','scan_products','manage_expirations',
                    'create_orders','fill_checklists','upload_evidence','view_tasks']),
  ('escaner', array['view_dashboard','view_inventory','view_prices','scan_products','report_price_difference',
                    'manage_price_changes','manage_shelf_tags','fill_checklists','upload_evidence','view_tasks'])
)
insert into public.role_permissions (role_id, permission_code)
select r.id, unnest(m.perms)
from matrix m
join public.roles r on r.code = m.role_code and r.company_id = 'c0000000-0000-4000-8000-000000000001'
on conflict do nothing;


-- >>>>>>>>>>>>>>>> seed/0009_usuarios_y_demo.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0009 · USUARIOS DE PRUEBA Y DATOS DEMO
-- -----------------------------------------------------------------------------
-- Objetivo: dejar el sistema listo para probar cada rol.
--
-- Inicio de sesión: se usa el USUARIO (no el correo). Internamente Supabase
-- Auth necesita un correo, así que se genera  usuario@operalia.local
-- (el dominio debe coincidir con VITE_AUTH_EMAIL_DOMAIN del .env).
--
--   Usuario            Contraseña   Rol                    Sucursal
--   ─────────────────  ───────────  ─────────────────────  ───────────────
--   gatopelon          tulipan23    Administrador general  Centro
--   soporte            prueba123    Soporte TI             Centro
--   auditor            prueba123    Auditor                Centro
--   gerente.centro     prueba123    Gerente                Centro
--   gerente.norte      prueba123    Gerente                Norte  (prueba aislamiento)
--   supervisor         prueba123    Supervisor (ABA + CAD) Centro
--   jefe.cajas         prueba123    Jefe de cajas          Centro
--   cajero             prueba123    Cajero                 Centro
--   abarrotes          prueba123    Abarrotes              Centro
--   recibo             prueba123    Recibo                 Centro
--   almacen            prueba123    Almacén                Centro
--   proteccion         prueba123    Protección             Centro
--   caducidades        prueba123    Caducidades            Centro
--   escaner            prueba123    Escáner                Centro
--
-- ⚠ Cambia las contraseñas de prueba antes de usar el sistema en producción.
-- Idempotente: si el usuario ya existe no lo duplica.
-- =============================================================================

-- Función temporal para crear empleado + cuenta de Auth ligada.
create or replace function public._seed_user(
  p_username text, p_password text, p_full_name text, p_role text,
  p_branch_code text, p_dept_code text, p_position text, p_employee_code text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_company uuid := 'c0000000-0000-4000-8000-000000000001';
  v_email   text := lower(p_username) || '@operalia.local';
  v_emp     uuid;
  v_user    uuid;
begin
  -- 1) Empleado
  select id into v_emp from public.employees where lower(username) = lower(p_username);
  if v_emp is null then
    insert into public.employees (company_id, branch_id, department_id, role_id, employee_code,
                                  username, full_name, position, email)
    values (
      v_company,
      (select id from public.branches where company_id = v_company and code = p_branch_code),
      (select id from public.departments where company_id = v_company and code = p_dept_code),
      (select id from public.roles where company_id = v_company and code = p_role),
      p_employee_code, lower(p_username), p_full_name, p_position, v_email)
    returning id into v_emp;
  end if;

  -- 2) Cuenta de Supabase Auth (el trigger on_auth_user_created la liga al empleado)
  select id into v_user from auth.users where email = v_email;
  if v_user is null then
    v_user := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token)
    values (
      '00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated', v_email,
      crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('username', lower(p_username), 'full_name', p_full_name),
      now(), now(), '', '', '', '');

    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_user, v_user::text,
            jsonb_build_object('sub', v_user::text, 'email', v_email, 'email_verified', true),
            'email', now(), now(), now());
  end if;

  -- 3) Asegurar el vínculo (por si el empleado se creó después que la cuenta)
  update public.employees set user_id = v_user where id = v_emp and user_id is null;
  return v_emp;
end $$;

select public._seed_user('gatopelon',      'tulipan23', 'Gato Pelón',             'admin',       '001', 'ADM', 'Administrador general', 'EMP-0001');
select public._seed_user('soporte',        'prueba123', 'Equipo de Soporte',      'soporte',     '001', 'TI',  'Soporte de plataforma', 'EMP-0002');
select public._seed_user('auditor',        'prueba123', 'Elena Auditora',         'auditor',     '001', 'ADM', 'Auditora interna',      'EMP-0003');
select public._seed_user('gerente.centro', 'prueba123', 'Laura Gerente',          'gerente',     '001', 'GER', 'Gerente de sucursal',   'EMP-0004');
select public._seed_user('gerente.norte',  'prueba123', 'Pedro López',            'gerente',     '002', 'GER', 'Gerente de sucursal',   'EMP-0005');
select public._seed_user('supervisor',     'prueba123', 'Sofía Supervisora',      'supervisor',  '001', 'ABA', 'Supervisora de piso',   'EMP-0006');
select public._seed_user('jefe.cajas',     'prueba123', 'Ana Jefa de Cajas',      'jefe_cajas',  '001', 'CAJ', 'Jefa de cajas',         'EMP-0007');
select public._seed_user('cajero',         'prueba123', 'Luis Cajero',            'cajas',       '001', 'CAJ', 'Cajero',                'EMP-0008');
select public._seed_user('abarrotes',      'prueba123', 'Pedro Abarrotes',        'abarrotes',   '001', 'ABA', 'Auxiliar de abarrotes', 'EMP-0009');
select public._seed_user('recibo',         'prueba123', 'Mario Recibo',           'recibo',      '001', 'REC', 'Jefe de recibo',        'EMP-0010');
select public._seed_user('almacen',        'prueba123', 'Jorge Almacén',          'almacen',     '001', 'ALM', 'Almacenista',           'EMP-0011');
select public._seed_user('proteccion',     'prueba123', 'Juan Soria',             'proteccion',  '001', 'PRO', 'Oficial de protección', 'EMP-0012');
select public._seed_user('caducidades',    'prueba123', 'María Torres',           'caducidades', '001', 'CAD', 'Auxiliar de caducidades','EMP-0013');
select public._seed_user('escaner',        'prueba123', 'Rosa Escáner',           'escaner',     '001', 'ESC', 'Auxiliar de escáner',   'EMP-0014');

drop function public._seed_user(text, text, text, text, text, text, text, text);

-- La supervisora cubre Abarrotes y además Caducidades.
insert into public.employee_departments (employee_id, department_id)
select e.id, d.id from public.employees e, public.departments d
where e.username = 'supervisor' and d.code = 'CAD' and d.company_id = e.company_id
on conflict do nothing;

-- Gerentes asignados a sus sucursales.
update public.branches b set manager_id = e.id
from public.employees e
where (b.code, e.username) in (('001','gerente.centro'), ('002','gerente.norte'))
  and b.company_id = e.company_id;

-- =============================================================================
-- DATOS DEMO (productos, inventario, proveedores, checklists, tareas...)
-- Se envuelve en un bloque que solo corre si aún no hay productos.
-- =============================================================================
do $$
declare
  c   uuid := 'c0000000-0000-4000-8000-000000000001';
  cen uuid := 'b0000000-0000-4000-8000-000000000001';
  nor uuid := 'b0000000-0000-4000-8000-000000000002';
  e_admin uuid; e_ger uuid; e_jcaj uuid; e_esc uuid; e_aba uuid; e_cad uuid; e_rec uuid; e_sup uuid; e_prot uuid; e_sop uuid;
  t_id uuid; o_id uuid; tk uuid;
begin
  if exists (select 1 from public.products where company_id = c) then
    raise notice 'Datos demo ya existen; se omiten.';
    return;
  end if;

  select id into e_admin from public.employees where username = 'gatopelon';
  select id into e_ger   from public.employees where username = 'gerente.centro';
  select id into e_jcaj  from public.employees where username = 'jefe.cajas';
  select id into e_esc   from public.employees where username = 'escaner';
  select id into e_aba   from public.employees where username = 'abarrotes';
  select id into e_cad   from public.employees where username = 'caducidades';
  select id into e_rec   from public.employees where username = 'recibo';
  select id into e_sup   from public.employees where username = 'supervisor';
  select id into e_prot  from public.employees where username = 'proteccion';
  select id into e_sop   from public.employees where username = 'soporte';

  -- ── Productos + códigos de barras ─────────────────────────────────────────
  insert into public.products (company_id, department_id, sku, name, category, unit, cost, price, controls_expiration, is_weighable)
  select c, (select id from public.departments where company_id = c and code = v.dept), v.sku, v.name, v.cat, v.unit, v.cost, v.price, v.exp, v.weigh
  from (values
    ('ABA','ABR-001','Arroz 1 kg',              'Granos',     'pz', 19.00,  28.50, false, false),
    ('ABA','ABR-002','Frijol negro 1 kg',       'Granos',     'pz', 23.00,  32.00, false, false),
    ('ABA','ABR-003','Aceite vegetal 1 L',      'Aceites',    'pz', 33.00,  45.00, false, false),
    ('ABA','ABR-004','Azúcar estándar 1 kg',    'Endulzantes','pz', 15.00,  22.00, false, false),
    ('ABA','ABR-006','Atún en agua 140 g',      'Enlatados',  'pz', 13.00,  19.90, true,  false),
    ('ABA','ABR-007','Café soluble 200 g',      'Bebidas',    'pz', 61.00,  89.00, false, false),
    ('ABA','BEB-001','Agua natural 1.5 L',      'Bebidas',    'pz',  8.00,  14.00, false, false),
    ('ABA','LIM-001','Detergente en polvo 1 kg','Limpieza',   'pz', 29.00,  42.00, false, false),
    ('CAD','LAC-001','Leche entera 1 L',        'Lácteos',    'pz', 18.00,  24.00, true,  false),
    ('CAD','LAC-002','Yogur fresa 200 g',       'Lácteos',    'pz', 11.00,  18.50, true,  false),
    ('CAD','EMB-001','Jamón de pavo 250 g',     'Embutidos',  'pz', 33.00,  48.00, true,  false),
    ('CAR','CAR-001','Bistec de res',           'Res',        'kg',140.00, 189.00, true,  true),
    ('PES','PES-001','Filete de tilapia',       'Pescado',    'kg', 92.00, 129.00, true,  true),
    ('JUG','JUG-001','Pelota de vinil',         'Juguetes',   'pz', 21.00,  35.00, false, false)
  ) as v(dept, sku, name, cat, unit, cost, price, exp, weigh);

  insert into public.product_barcodes (company_id, product_id, barcode)
  select c, p.id, '75010553' || lpad(row_number() over (order by p.sku)::text, 5, '0')
  from public.products p where p.company_id = c;

  -- ── Inventario (el trigger calcula el estado: normal / bajo / crítico / sin existencia)
  insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock, location)
  select c, cen, p.id, v.stock, v.min, v.max, v.loc
  from (values
    ('ABR-001', 45, 20, 120, 'Pasillo 3'), ('ABR-002', 12, 15, 80, 'Pasillo 3'),
    ('ABR-003', 60, 25, 100, 'Pasillo 4'), ('ABR-004',  3, 20, 90, 'Pasillo 4'),
    ('ABR-006', 80, 30, 150, 'Pasillo 5'), ('ABR-007', 25, 10, 50, 'Pasillo 6'),
    ('BEB-001',  0, 40, 200, 'Pasillo 8'), ('LIM-001', 34, 15, 60, 'Pasillo 10'),
    ('LAC-001', 18, 30, 120, 'Refrigerador 1'), ('LAC-002', 22, 10, 60, 'Refrigerador 1'),
    ('EMB-001', 14, 8, 40, 'Salchichonería'),   ('CAR-001', 36.5, 20, 80, 'Vitrina carnes'),
    ('PES-001', 9.2, 10, 40, 'Vitrina pescados'), ('JUG-001', 50, 10, 100, 'Juguetería')
  ) as v(sku, stock, min, max, loc)
  join public.products p on p.sku = v.sku and p.company_id = c;

  insert into public.inventory (company_id, branch_id, product_id, stock, min_stock, max_stock)
  select c, nor, p.id, (random() * 80)::int, 15, 100 from public.products p where p.company_id = c;

  -- ── Proveedores y una visita abierta ──────────────────────────────────────
  insert into public.suppliers (company_id, code, name, legal_name, merchandise_type, contact_name, phone, email, status) values
    (c, 'PROV-001', 'Distribuidora Nacional',  'Distribuidora Nacional S.A.',  'Abarrotes',  'Jorge Martínez', '664-123-4567', 'ventas@disnacional.mx', 'active'),
    (c, 'PROV-002', 'Lácteos del Noroeste',    'Lácteos del Noroeste S.A.',    'Lácteos',    'Rosa Sánchez',   '664-234-5678', 'pedidos@lacteosno.mx',  'active'),
    (c, 'PROV-003', 'Congelados y Frescos',    'Congelados y Frescos S.A.',    'Cárnicos',   'Manuel Cruz',    '664-345-6789', 'contacto@cyf.mx',       'active'),
    (c, 'PROV-004', 'Bebidas y Refrescos MX',  'Bebidas y Refrescos MX S.A.',  'Bebidas',    'Patricia León',  '664-456-7890', null,                    'inactive');

  insert into public.supplier_visits (company_id, branch_id, supplier_id, check_in_at, driver_name, vehicle_plate, purpose, registered_by)
  select c, cen, s.id, now() - interval '40 minutes', 'Raúl Pérez', 'BC-12-345', 'entrega', e_prot
  from public.suppliers s where s.code = 'PROV-002' and s.company_id = c;

  -- ── Plantillas de checklist + preguntas ───────────────────────────────────
  -- (dept, título, turno, inicio, fin, requiere evidencia, preguntas[texto|tipo|foto])
  insert into public.checklist_templates (company_id, department_id, title, shift, start_time, end_time, requires_evidence, description)
  select c, (select id from public.departments where company_id = c and code = v.dept), v.title, v.shift, v.st::time, v.et::time, v.ev, v.descr
  from (values
    ('CAJ','Apertura de cajas',            'apertura','07:00','08:30', true,  'Validar que la línea de cajas abre en orden'),
    ('ABA','Apertura de abarrotes',        'apertura','07:00','08:30', false, 'Surtido y limpieza antes de abrir'),
    ('PRO','Rondín de seguridad mañana',   'manana',  '08:00','09:00', true,  'Recorrido de seguridad del inmueble'),
    ('CAD','Revisión de caducidades',      'manana',  '08:00','10:00', true,  'Revisión de fechas en exhibición'),
    ('REC','Preparación de andén de recibo','manana', '09:00','11:00', false, 'Andén listo para proveedores'),
    ('ESC','Actualización de precios',     'manana',  '07:30','09:00', true,  'Cambios de precio y cenefas del día'),
    ('CAD','Control de temperaturas',      'especial','06:00','23:59', false, 'Registro de temperatura de refrigeradores'),
    ('ABA','Cierre de abarrotes',          'cierre',  '21:00','22:00', false, 'Acomodo y reporte de faltantes'),
    ('CAJ','Cierre de cajas',              'cierre',  '21:30','22:30', true,  'Corte y resguardo de la línea de cajas')
  ) as v(dept, title, shift, st, et, ev, descr);

  insert into public.checklist_questions (template_id, position, text, answer_type, requires_photo, is_required)
  select t.id, q.pos, q.txt, q.typ, q.photo, true
  from public.checklist_templates t
  join (values
    ('Apertura de cajas', 1, '¿Las cajas están limpias y operativas?', 'yes_no', false),
    ('Apertura de cajas', 2, '¿El punto de venta inicia correctamente?', 'yes_no', false),
    ('Apertura de cajas', 3, '¿El fondo de caja está completo?', 'yes_no', false),
    ('Apertura de cajas', 4, '¿El área está despejada y señalizada?', 'yes_no', false),
    ('Apertura de cajas', 5, 'Fotografía de la línea de cajas abierta', 'photo', true),
    ('Apertura de abarrotes', 1, '¿Los anaqueles están surtidos?', 'yes_no', false),
    ('Apertura de abarrotes', 2, '¿Los precios están actualizados en anaquel?', 'yes_no', false),
    ('Apertura de abarrotes', 3, '¿No hay productos caducados en exhibición?', 'yes_no', false),
    ('Apertura de abarrotes', 4, '¿El área está limpia y ordenada?', 'yes_no', false),
    ('Rondín de seguridad mañana', 1, '¿Todas las salidas de emergencia están libres?', 'yes_no', false),
    ('Rondín de seguridad mañana', 2, '¿Las cámaras de seguridad funcionan?', 'yes_no', false),
    ('Rondín de seguridad mañana', 3, '¿Sin incidencias en estacionamiento?', 'yes_no', false),
    ('Rondín de seguridad mañana', 4, 'Evidencia fotográfica del rondín', 'photo', true),
    ('Revisión de caducidades', 1, '¿Se revisaron lácteos?', 'yes_no', false),
    ('Revisión de caducidades', 2, '¿Se revisaron embutidos?', 'yes_no', false),
    ('Revisión de caducidades', 3, '¿Se revisaron enlatados?', 'yes_no', false),
    ('Revisión de caducidades', 4, 'Cantidad de productos próximos a vencer (≤ 3 días)', 'number', false),
    ('Revisión de caducidades', 5, 'Foto de productos detectados', 'photo', true),
    ('Preparación de andén de recibo', 1, '¿El andén está limpio y despejado?', 'yes_no', false),
    ('Preparación de andén de recibo', 2, '¿La báscula está calibrada?', 'yes_no', false),
    ('Preparación de andén de recibo', 3, '¿Se tienen las órdenes de compra del día?', 'yes_no', false),
    ('Preparación de andén de recibo', 4, 'Observaciones', 'text', false),
    ('Actualización de precios', 1, '¿Se aplicaron todos los cambios de precio del día?', 'yes_no', false),
    ('Actualización de precios', 2, '¿Las cenefas pendientes fueron colocadas?', 'yes_no', false),
    ('Actualización de precios', 3, 'Foto de anaquel con cenefas actualizadas', 'photo', true),
    ('Control de temperaturas', 1, 'Temperatura refrigerador lácteos (°C)', 'number', false),
    ('Control de temperaturas', 2, 'Temperatura vitrina carnes (°C)', 'number', false),
    ('Control de temperaturas', 3, '¿Alguna temperatura fuera de rango?', 'yes_no', false),
    ('Cierre de abarrotes', 1, '¿Se acomodó y surtió el anaquel?', 'yes_no', false),
    ('Cierre de abarrotes', 2, '¿Se reportaron faltantes del día?', 'yes_no', false),
    ('Cierre de abarrotes', 3, '¿El área quedó limpia?', 'yes_no', false),
    ('Cierre de abarrotes', 4, 'Estado general del área', 'option', false),
    ('Cierre de cajas', 1, '¿Se realizó el corte de todas las cajas?', 'yes_no', false),
    ('Cierre de cajas', 2, '¿El efectivo se resguardó en bóveda?', 'yes_no', false),
    ('Cierre de cajas', 3, '¿Las terminales quedaron apagadas?', 'yes_no', false),
    ('Cierre de cajas', 4, 'Foto del corte firmado', 'photo', true)
  ) as q(title, pos, txt, typ, photo) on q.title = t.title and t.company_id = c;

  update public.checklist_questions set options = '["Excelente","Bueno","Regular","Malo"]'::jsonb
  where answer_type = 'option' and options is null;

  -- Ejecuciones de hoy para todas las sucursales activas.
  perform public.generate_checklist_runs(c, public.company_today(c));

  -- ── Tareas ────────────────────────────────────────────────────────────────
  insert into public.tasks (company_id, branch_id, department_id, title, description, assigned_to, created_by, due_date, priority, status, requires_evidence)
  select c, cen, (select id from public.departments where company_id = c and code = v.dept),
         v.title, v.descr, v.assignee, e_ger, public.company_today(c) + v.days, v.prio, v.status, v.ev
  from (values
    ('ESC','Actualizar cenefas de lácteos',        'Colocar cenefas del nuevo precio de leche', e_esc, 1, 'high',     'pending',     true),
    ('CAD','Revisar temperatura de cámaras de frío','Registrar lecturas cada 4 horas',          e_cad, 0, 'critical', 'in_progress', false),
    ('ABA','Conteo cíclico de abarrotes',          'Contar pasillos 3 y 4',                     e_aba, 2, 'medium',   'pending',     false),
    ('CAJ','Capacitar a cajero nuevo en devoluciones','Proceso de devolución con ticket',        e_jcaj,3, 'low',      'pending',     false),
    ('PRO','Verificar sellos de seguridad del almacén','',                                       e_prot,-1,'medium',   'pending',     true)
  ) as v(dept, title, descr, assignee, days, prio, status, ev);

  -- ── Pedidos internos ──────────────────────────────────────────────────────
  insert into public.orders (company_id, branch_id, department_id, title, status, priority, requested_by, notes)
  values (c, cen, (select id from public.departments where company_id = c and code = 'ABA'),
          'Resurtido abarrotes semana', 'requested', 'high', e_aba, 'Faltante en pasillo 3 y 4')
  returning id into o_id;
  insert into public.order_items (order_id, product_id, quantity)
  select o_id, p.id, v.q from (values ('ABR-002', 40), ('ABR-004', 60), ('BEB-001', 120)) as v(sku, q)
  join public.products p on p.sku = v.sku and p.company_id = c;

  insert into public.orders (company_id, branch_id, department_id, title, status, priority, requested_by, approved_by, approved_at)
  values (c, cen, (select id from public.departments where company_id = c and code = 'CAD'),
          'Reposición lácteos', 'approved', 'medium', e_cad, e_ger, now() - interval '3 hours')
  returning id into o_id;
  insert into public.order_items (order_id, product_id, quantity)
  select o_id, p.id, 48 from public.products p where p.sku = 'LAC-001' and p.company_id = c;

  -- ── Cambios de precio (hoy → se aplican y generan cenefas; mañana → programado)
  insert into public.price_changes (company_id, branch_id, product_id, old_price, new_price, effective_date, reason, requires_tag, created_by)
  select c, null, p.id, p.price, v.np, public.company_today(c) + v.days, v.reason, true, e_esc
  from (values ('LAC-001', 25.50, 0, 'Ajuste de proveedor'),
               ('ABR-001', 27.00, 0, 'Promoción semanal'),
               ('ABR-007', 92.00, 1, 'Incremento de lista')) as v(sku, np, days, reason)
  join public.products p on p.sku = v.sku and p.company_id = c;

  -- ── Caducidades ───────────────────────────────────────────────────────────
  insert into public.product_expirations (company_id, branch_id, product_id, lot, quantity, expiration_date, registered_by)
  select c, cen, p.id, v.lot, v.q, public.company_today(c) + v.days, e_cad
  from (values ('LAC-002','L2401', 12, 2), ('LAC-001','L2402', 18, 5), ('EMB-001','E9001', 6, -1),
               ('ABR-006','A7788', 40, 120), ('CAR-001','C0101', 8.5, 1)) as v(sku, lot, q, days)
  join public.products p on p.sku = v.sku and p.company_id = c;

  -- ── Tickets de mesa de ayuda ──────────────────────────────────────────────
  insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
  values (c, cen, 'No me deja cerrar el checklist de apertura',
          'Al presionar "Completar" aparece un error de evidencia aunque ya tomé la foto.',
          'bug', 'Checklists', 'high', e_jcaj)
  returning id into tk;
  insert into public.support_ticket_messages (ticket_id, author_id, body) values
    (tk, e_jcaj, 'Adjunto captura del error. Sucede en la caja 3.'),
    (tk, e_sop,  'Gracias, ¿la foto se subió desde la pregunta 5 o desde Evidencias?');
  update public.support_tickets set assigned_to = e_sop, status = 'waiting_user' where id = tk;

  insert into public.support_tickets (company_id, branch_id, subject, description, category, module, priority, created_by)
  values (c, cen, 'Solicitud: reporte de mermas por semana',
          'Nos serviría un reporte semanal de mermas por departamento para la junta de los lunes.',
          'feature', 'Reportes', 'low', e_ger);
end $$;

-- Mantenimiento inicial (marca vencidos según la hora actual, aplica precios del día).
select public.run_daily_maintenance('c0000000-0000-4000-8000-000000000001');


-- >>>>>>>>>>>>>>>> seed/0010_notificaciones_y_marcos.sql <<<<<<<<<<<<<<<<
-- =============================================================================
-- OPERALIA · 0010 · NOTIFICACIONES DE PRUEBA + VÍNCULO DE CUENTA EXISTENTE
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

-- ─── 2. Dos notificaciones de prueba por departamento ───────────────────────
insert into public.notifications (company_id, department_id, type, title, body, link)
select d.company_id, d.id, v.type, v.title || ' · ' || d.name, v.body, v.link
from public.departments d
cross join (values
  ('info',      'Bienvenidos a Operalia', 'Desde hoy los checklists y tareas del área se registran aquí.', '/dashboard'),
  ('checklist', 'Recordatorio de checklist', 'Revisa los checklists pendientes de tu departamento antes de la hora límite.', '/checklists')
) as v(type, title, body, link)
where d.company_id = 'c0000000-0000-4000-8000-000000000001'
  and not exists (select 1 from public.notifications n
                  where n.department_id = d.id and n.employee_id is null and n.title = v.title || ' · ' || d.name);
