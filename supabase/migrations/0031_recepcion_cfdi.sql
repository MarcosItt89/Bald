-- =============================================================================
-- OPERALIA · 0031 · RECIBO DESDE FACTURA CFDI 4.0 (XML)
-- -----------------------------------------------------------------------------
--   El navegador lee el XML de la factura del proveedor (emisor, folio, fecha,
--   UUID y conceptos). Aquí:
--   1. supplier_product_codes: qué clave del proveedor (NoIdentificacion) es
--      qué producto de la empresa. La primera vez se empareja a mano; después
--      se empareja solo. RLS por empresa; un trigger exige que proveedor y
--      producto sean de la misma empresa que la fila.
--   2. receiving_orders: cfdi_uuid, fecha y total de la factura, y origen
--      (manual | cfdi). Una factura (UUID) no se registra dos veces en recibos
--      que no estén cancelados. receiving_items: clave, descripción, unidad y
--      valor unitario del proveedor. Se recrean v_receiving_orders y
--      v_receiving_items (usan r.* / ri.*).
--   3. create_receiving_from_cfdi(): crea el recibo EN CAPTURA (in_progress)
--      con sus partidas (esperado = cantidad de la factura, recibido = 0) y
--      recuerda las claves. SECURITY INVOKER: pasa por el RLS de siempre.
--      No mueve existencias: eso sigue pasando solo al cerrar el recibo.
--   4. Evidencia: el bucket acepta XML, y quien recibe mercancía
--      (receive_products) puede adjuntar archivos a su recibo.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. Claves del proveedor ↔ productos ────────────────────────────────────
create table if not exists public.supplier_product_codes (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  supplier_id    uuid not null references public.suppliers(id) on delete cascade,
  supplier_code  text not null check (length(trim(supplier_code)) between 1 and 200),
  product_id     uuid not null references public.products(id) on delete cascade,
  created_by     uuid references public.employees(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (company_id, supplier_id, supplier_code)
);
create index if not exists supplier_product_codes_product_idx on public.supplier_product_codes (product_id);
alter table public.supplier_product_codes enable row level security;

-- La empresa sale del proveedor; proveedor y producto deben ser de esa empresa
-- (RLS solo revisa company_id: sin esto se podría ligar un id de otra empresa).
create or replace function public.tg_supplier_product_codes_company()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_supplier uuid; v_product uuid;
begin
  select company_id into v_supplier from public.suppliers where id = new.supplier_id;
  select company_id into v_product from public.products where id = new.product_id;
  if new.company_id is null then new.company_id := v_supplier; end if;
  if v_supplier is distinct from new.company_id or v_product is distinct from new.company_id then
    raise exception 'El proveedor y el producto deben ser de la misma empresa';
  end if;
  new.supplier_code := trim(new.supplier_code);
  return new;
end $$;
revoke all on function public.tg_supplier_product_codes_company() from public, anon, authenticated;
drop trigger if exists trg_supplier_product_codes_company on public.supplier_product_codes;
create trigger trg_supplier_product_codes_company before insert or update on public.supplier_product_codes
  for each row execute function public.tg_supplier_product_codes_company();
drop trigger if exists trg_updated_at on public.supplier_product_codes;
create trigger trg_updated_at before update on public.supplier_product_codes
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_actor on public.supplier_product_codes;
create trigger trg_actor before insert on public.supplier_product_codes
  for each row execute function public.tg_set_actor('created_by');

drop policy if exists supplier_codes_select on public.supplier_product_codes;
drop policy if exists supplier_codes_write on public.supplier_product_codes;
create policy supplier_codes_select on public.supplier_product_codes for select to authenticated
  using (company_id = (select public.auth_company_id()));
create policy supplier_codes_write on public.supplier_product_codes for all to authenticated
  using (company_id = (select public.auth_company_id())
         and ((select public.has_permission('receive_products')) or (select public.has_permission('manage_suppliers'))
              or (select public.has_permission('manage_inventory'))))
  with check (company_id = (select public.auth_company_id())
         and ((select public.has_permission('receive_products')) or (select public.has_permission('manage_suppliers'))
              or (select public.has_permission('manage_inventory'))));
revoke all on public.supplier_product_codes from anon;
grant select, insert, update, delete on public.supplier_product_codes to authenticated;

-- ─── 2. Datos de la factura en el recibo ────────────────────────────────────
alter table public.receiving_orders add column if not exists cfdi_uuid text;
alter table public.receiving_orders add column if not exists invoice_date timestamp;      -- hora local de la factura
alter table public.receiving_orders add column if not exists invoice_total numeric(14,2);
alter table public.receiving_orders add column if not exists invoice_currency text;
alter table public.receiving_orders add column if not exists source text not null default 'manual';
do $$ begin
  alter table public.receiving_orders add constraint receiving_orders_source_chk check (source in ('manual', 'cfdi'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.receiving_orders add constraint receiving_orders_cfdi_uuid_chk
    check (cfdi_uuid is null or cfdi_uuid ~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$');
exception when duplicate_object then null; end $$;
-- Una factura no entra dos veces (salvo que el recibo anterior se haya cancelado).
create unique index if not exists receiving_orders_cfdi_uuid_key on public.receiving_orders (company_id, cfdi_uuid)
  where cfdi_uuid is not null and status <> 'cancelled';

alter table public.receiving_items add column if not exists supplier_code text;
alter table public.receiving_items add column if not exists supplier_description text;
alter table public.receiving_items add column if not exists supplier_unit text;
alter table public.receiving_items add column if not exists unit_cost numeric(14,4);
do $$ begin
  alter table public.receiving_items add constraint receiving_items_unit_cost_chk check (unit_cost is null or unit_cost >= 0);
exception when duplicate_object then null; end $$;

-- Las vistas usan r.* / ri.*: se recrean para que traigan las columnas nuevas.
drop view if exists public.v_receiving_orders;
create view public.v_receiving_orders with (security_invoker = on) as
select r.*, s.code as supplier_code, s.name as supplier_name, b.name as branch_name,
       er.full_name as received_by_name, ec.full_name as completed_by_name,
       (select count(*) from public.receiving_items ri where ri.receiving_order_id = r.id) as items_count
from public.receiving_orders r
join public.suppliers s on s.id = r.supplier_id
join public.branches b on b.id = r.branch_id
left join public.employees er on er.id = r.received_by
left join public.employees ec on ec.id = r.completed_by;

drop view if exists public.v_receiving_items;
create view public.v_receiving_items with (security_invoker = on) as
select ri.*, p.sku, p.name as product_name, p.unit
from public.receiving_items ri
join public.products p on p.id = ri.product_id;

revoke all on public.v_receiving_orders, public.v_receiving_items from anon;
grant select on public.v_receiving_orders, public.v_receiving_items to authenticated;

-- ─── 3. Crear el recibo desde la factura ────────────────────────────────────
-- p_invoice: { uuid, serie, folio, fecha ('YYYY-MM-DDTHH:MM:SS'), total, moneda }
-- p_items:   [{ product_id, cantidad, valor_unitario, clave, descripcion, unidad, recordar }]
--            recordar = true → guarda clave → producto para este proveedor.
create or replace function public.create_receiving_from_cfdi(
  p_branch_id uuid, p_supplier_id uuid, p_invoice jsonb, p_items jsonb, p_notes text default null)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_company uuid := public.auth_company_id();
  v_uuid    text := upper(nullif(trim(coalesce(p_invoice->>'uuid', '')), ''));
  v_folio   text := nullif(trim(concat_ws('-', nullif(trim(p_invoice->>'serie'), ''), nullif(trim(p_invoice->>'folio'), ''))), '');
  v_order   public.receiving_orders%rowtype;
  v_prev    text;
  it        jsonb;
  v_qty     numeric;
  v_cost    numeric;
  v_code    text;
  v_n       int := 0;
  v_saved   int := 0;
begin
  if v_company is null then raise exception 'Necesitas una sesión de empleado activo'; end if;
  if not public.has_permission('receive_products') then
    raise exception 'No tienes permiso para recibir mercancía';
  end if;
  if not exists (select 1 from public.branches b where b.id = p_branch_id and b.company_id = v_company)
     or not public.can_access_branch(p_branch_id) then
    raise exception 'La sucursal no es de tu empresa';
  end if;
  if not exists (select 1 from public.suppliers s where s.id = p_supplier_id and s.company_id = v_company) then
    raise exception 'El proveedor no es de tu empresa';
  end if;
  if v_uuid is null or v_uuid !~ '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' then
    raise exception 'La factura no trae un UUID (folio fiscal) válido';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La factura no tiene partidas para recibir';
  end if;
  if jsonb_array_length(p_items) > 1000 then raise exception 'Máximo 1000 partidas por factura'; end if;

  select r.folio into v_prev from public.receiving_orders r
   where r.company_id = v_company and r.cfdi_uuid = v_uuid and r.status <> 'cancelled' limit 1;
  if v_prev is not null then
    raise exception 'Esta factura ya está en el recibo %', v_prev;
  end if;

  begin
    insert into public.receiving_orders (company_id, branch_id, supplier_id, invoice_number, status, source,
                                         cfdi_uuid, invoice_date, invoice_total, invoice_currency, notes)
    values (v_company, p_branch_id, p_supplier_id, coalesce(v_folio, left(v_uuid, 8)), 'in_progress', 'cfdi',
            v_uuid, nullif(p_invoice->>'fecha', '')::timestamp, nullif(p_invoice->>'total', '')::numeric,
            nullif(trim(coalesce(p_invoice->>'moneda', '')), ''), nullif(trim(coalesce(p_notes, '')), ''))
    returning * into v_order;
  exception when unique_violation then
    -- El recibo anterior es de una sucursal que quien llama no ve.
    raise exception 'Esta factura ya se registró en otro recibo de la empresa';
  end;

  for it in select value from jsonb_array_elements(p_items) loop
    v_n := v_n + 1;
    if not exists (select 1 from public.products p where p.id = (it->>'product_id')::uuid and p.company_id = v_company) then
      raise exception 'Partida %: el producto no es de tu empresa', v_n;
    end if;
    v_qty  := (it->>'cantidad')::numeric;
    v_cost := nullif(it->>'valor_unitario', '')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Partida %: cantidad inválida', v_n; end if;
    if v_cost is not null and v_cost < 0 then raise exception 'Partida %: valor unitario inválido', v_n; end if;
    v_code := nullif(trim(coalesce(it->>'clave', '')), '');

    insert into public.receiving_items (receiving_order_id, product_id, expected_qty, received_qty, damaged_qty,
                                        supplier_code, supplier_description, supplier_unit, unit_cost)
    values (v_order.id, (it->>'product_id')::uuid, v_qty, 0, 0, v_code,
            left(nullif(trim(coalesce(it->>'descripcion', '')), ''), 1000),
            left(nullif(trim(coalesce(it->>'unidad', '')), ''), 60), v_cost);

    if v_code is not null and coalesce((it->>'recordar')::boolean, false) then
      insert into public.supplier_product_codes (company_id, supplier_id, supplier_code, product_id)
      values (v_company, p_supplier_id, v_code, (it->>'product_id')::uuid)
      on conflict (company_id, supplier_id, supplier_code) do update
        set product_id = excluded.product_id
        where public.supplier_product_codes.product_id is distinct from excluded.product_id;
      v_saved := v_saved + 1;
    end if;
  end loop;

  return jsonb_build_object('id', v_order.id, 'folio', v_order.folio, 'partidas', v_n, 'claves_guardadas', v_saved);
end $$;
revoke all on function public.create_receiving_from_cfdi(uuid, uuid, jsonb, jsonb, text) from public, anon;
grant execute on function public.create_receiving_from_cfdi(uuid, uuid, jsonb, jsonb, text) to authenticated;

-- ─── 4. El XML como evidencia del recibo ────────────────────────────────────
update storage.buckets
   set allowed_mime_types = (select array_agg(distinct m order by m)
                               from unnest(coalesce(allowed_mime_types, '{}') || array['application/xml', 'text/xml']) m)
 where id = 'evidence';

-- Quien recibe mercancía puede adjuntar archivos a su recibo (antes solo upload_evidence).
drop policy if exists evidence_insert on public.evidence_files;
create policy evidence_insert on public.evidence_files for insert to authenticated
  with check (company_id = (select public.auth_company_id()) and (
                 (select public.has_permission('upload_evidence'))
              or (entity_type = 'support_ticket' and (select public.has_permission('create_tickets')))
              or (entity_type = 'receiving_order' and (select public.has_permission('receive_products')))));

drop policy if exists evidence_objects_insert on storage.objects;
create policy evidence_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence'
              and (storage.foldername(name))[1] = (select public.auth_company_id())::text
              and ((select public.has_permission('upload_evidence')) or (select public.has_permission('create_tickets'))
                   or ((storage.foldername(name))[2] = 'receiving_order' and (select public.has_permission('receive_products')))));
