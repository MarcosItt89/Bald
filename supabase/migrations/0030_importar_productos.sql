-- =============================================================================
-- OPERALIA · 0030 · IMPORTAR PRODUCTOS (CSV)
-- -----------------------------------------------------------------------------
--   import_products(sucursal, filas, modo): alta y/o actualización masiva del
--   catálogo de la empresa desde Inventario → Importar (en bloques de 500).
--
--   * SECURITY INVOKER: cada insert/update pasa por el RLS de siempre
--     (products_write, barcodes_write, inventory_insert/update y
--     movements_insert exigen manage_inventory y su empresa/sucursal). Además
--     revisa explícitamente: rol de alcance empresa (propietario o
--     administrador) con manage_inventory, y que la sucursal sea de su empresa.
--   * modo: 'crear' (solo SKU nuevos), 'actualizar' (solo existentes) o 'ambos'.
--     Upsert por (company_id, sku). Celda vacía al actualizar = no se cambia.
--   * Código de barras → product_barcodes (error si ya es de otro producto).
--   * Departamento por código o nombre (de su empresa).
--   * Existencia inicial → movimiento adjustment_in «Carga inicial» (el
--     kardex cuadra). Solo si el producto aún no tiene movimientos en esa
--     sucursal: repetir la misma importación no duplica existencias.
--   * Mínimo → inventory.min_stock de esa sucursal.
--   * Devuelve una fila por renglón: { fila, sku, estado: creado|actualizado|error, motivo, producto_id }.
--     Cada renglón va en su propio bloque: un error no deshace los demás.
-- Re-ejecutable. No cambia tablas ni políticas.
-- =============================================================================

-- Número de una celda ('12.50'). Vacío → null. Lo demás, error con el campo.
create or replace function public.import_parse_num(p_value text, p_field text)
returns numeric language plpgsql immutable set search_path = public as $$
declare v text := nullif(trim(coalesce(p_value, '')), '');
begin
  if v is null then return null; end if;
  if v !~ '^-?[0-9]+(\.[0-9]+)?$' then
    raise exception '% inválido: «%»', p_field, v;
  end if;
  if v::numeric < 0 then raise exception '% no puede ser negativo', p_field; end if;
  return v::numeric;
end $$;
revoke all on function public.import_parse_num(text, text) from public, anon;
grant execute on function public.import_parse_num(text, text) to authenticated;

-- Sí/no de una celda. Vacío → null.
create or replace function public.import_parse_bool(p_value text, p_field text)
returns boolean language plpgsql immutable set search_path = public as $$
declare v text := lower(nullif(trim(coalesce(p_value, '')), ''));
begin
  if v is null then return null; end if;
  if v in ('si', 'sí', 's', 'true', 'verdadero', '1', 'x', 'yes', 'y') then return true; end if;
  if v in ('no', 'n', 'false', 'falso', '0') then return false; end if;
  raise exception '% inválido: «%» (usa sí o no)', p_field, v;
end $$;
revoke all on function public.import_parse_bool(text, text) from public, anon;
grant execute on function public.import_parse_bool(text, text) to authenticated;

create or replace function public.import_products(p_branch_id uuid, p_rows jsonb, p_mode text default 'ambos')
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_company uuid := public.auth_company_id();
  v_out     jsonb := '[]'::jsonb;
  r         jsonb;
  v_fila    jsonb;
  v_sku     text;
  v_name    text;
  v_barcode text;
  v_dept_in text;
  v_dept    uuid;
  v_unit    text;
  v_cost    numeric;
  v_price   numeric;
  v_stock   numeric;
  v_min     numeric;
  v_exp     boolean;
  v_cat     text;
  v_brand   text;
  v_prod    public.products%rowtype;
  v_found   boolean;
  v_other   text;
  v_estado  text;
  v_notas   text[];
  v_changed boolean;
  v_n       int;
begin
  if v_company is null then
    raise exception 'Necesitas una sesión de empleado activo';
  end if;
  if p_mode is null or p_mode not in ('crear', 'actualizar', 'ambos') then
    raise exception 'Modo inválido: usa crear, actualizar o ambos';
  end if;
  if not public.has_permission('manage_inventory') or public.auth_role_scope() is distinct from 'company' then
    raise exception 'Solo el propietario o un administrador de la empresa importa productos';
  end if;
  if not exists (select 1 from public.branches b where b.id = p_branch_id and b.company_id = v_company)
     or not public.can_access_branch(p_branch_id) then
    raise exception 'La sucursal no es de tu empresa';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Las filas deben venir en una lista';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'Máximo 1000 filas por llamada (la app manda bloques de 500)';
  end if;

  for r in select value from jsonb_array_elements(p_rows) loop
    v_fila := r->'fila';
    v_sku := nullif(trim(coalesce(r->>'sku', '')), '');
    begin
      v_notas := '{}';
      if v_sku is null then raise exception 'Falta el SKU'; end if;
      if length(v_sku) > 64 then raise exception 'SKU demasiado largo (máximo 64)'; end if;

      v_name    := nullif(trim(coalesce(r->>'nombre', '')), '');
      v_barcode := nullif(trim(coalesce(r->>'codigo_barras', '')), '');
      v_dept_in := nullif(trim(coalesce(r->>'departamento', '')), '');
      v_cat     := nullif(trim(coalesce(r->>'categoria', '')), '');
      v_brand   := nullif(trim(coalesce(r->>'marca', '')), '');
      v_unit    := lower(nullif(trim(coalesce(r->>'unidad', '')), ''));
      v_cost    := public.import_parse_num(r->>'costo', 'Costo');
      v_price   := public.import_parse_num(r->>'precio', 'Precio');
      v_stock   := public.import_parse_num(r->>'existencia', 'Existencia');
      v_min     := public.import_parse_num(r->>'minimo', 'Mínimo');
      v_exp     := public.import_parse_bool(r->>'controla_caducidad', 'Controla caducidad');

      if v_name is not null and length(v_name) > 200 then raise exception 'Nombre demasiado largo (máximo 200)'; end if;
      if v_unit is not null and v_unit not in ('pz', 'kg', 'g', 'l', 'ml', 'caja', 'paquete') then
        raise exception 'Unidad no permitida: «%» (pz, kg, g, l, ml, caja o paquete)', v_unit;
      end if;
      if v_barcode is not null and length(v_barcode) > 50 then raise exception 'Código de barras demasiado largo (máximo 50)'; end if;

      v_dept := null;
      if v_dept_in is not null then
        select d.id into v_dept from public.departments d
         where d.company_id = v_company and (lower(d.code) = lower(v_dept_in) or lower(d.name) = lower(v_dept_in))
         order by (lower(d.code) = lower(v_dept_in)) desc
         limit 1;
        if v_dept is null then raise exception 'El departamento «%» no existe', v_dept_in; end if;
      end if;

      select * into v_prod from public.products p
       where p.company_id = v_company and p.sku = v_sku
       for update;
      v_found := found;

      if v_found and p_mode = 'crear' then raise exception 'El SKU ya existe (modo: solo crear)'; end if;
      if not v_found and p_mode = 'actualizar' then raise exception 'El SKU no existe (modo: solo actualizar)'; end if;

      -- El código de barras no puede ser de otro producto de la empresa.
      if v_barcode is not null then
        select p.sku into v_other from public.product_barcodes b join public.products p on p.id = b.product_id
         where b.company_id = v_company and b.barcode = v_barcode
           and (not v_found or b.product_id <> v_prod.id)
         limit 1;
        if v_other is not null then
          raise exception 'El código de barras % ya es del producto %', v_barcode, v_other;
        end if;
      end if;

      if not v_found then
        if v_name is null then raise exception 'Falta el nombre (producto nuevo)'; end if;
        insert into public.products (company_id, department_id, sku, name, category, brand, unit, cost, price, controls_expiration)
        values (v_company, v_dept, v_sku, v_name, v_cat, v_brand, coalesce(v_unit, 'pz'),
                coalesce(v_cost, 0), coalesce(v_price, 0), coalesce(v_exp, false))
        returning * into v_prod;
        v_estado := 'creado';
      else
        v_changed := (coalesce(v_name, v_prod.name), coalesce(v_dept, v_prod.department_id), coalesce(v_cat, v_prod.category),
                      coalesce(v_brand, v_prod.brand), coalesce(v_unit, v_prod.unit), coalesce(v_cost, v_prod.cost),
                      coalesce(v_price, v_prod.price), coalesce(v_exp, v_prod.controls_expiration))
          is distinct from
                     (v_prod.name, v_prod.department_id, v_prod.category, v_prod.brand, v_prod.unit, v_prod.cost,
                      v_prod.price, v_prod.controls_expiration);
        if v_changed then
          update public.products p set
            name = coalesce(v_name, p.name),
            department_id = coalesce(v_dept, p.department_id),
            category = coalesce(v_cat, p.category),
            brand = coalesce(v_brand, p.brand),
            unit = coalesce(v_unit, p.unit),
            cost = coalesce(v_cost, p.cost),
            previous_price = case when v_price is not null and v_price <> p.price then p.price else p.previous_price end,
            price_updated_at = case when v_price is not null and v_price <> p.price then now() else p.price_updated_at end,
            price = coalesce(v_price, p.price),
            controls_expiration = coalesce(v_exp, p.controls_expiration)
          where p.id = v_prod.id;
        else
          v_notas := array_append(v_notas, 'sin cambios en el producto');
        end if;
        v_estado := 'actualizado';
      end if;

      if v_barcode is not null then
        insert into public.product_barcodes (company_id, product_id, barcode, is_primary)
        select v_company, v_prod.id, v_barcode,
               not exists (select 1 from public.product_barcodes b where b.product_id = v_prod.id)
        where not exists (select 1 from public.product_barcodes b
                           where b.company_id = v_company and b.barcode = v_barcode);
      end if;

      -- Renglón de inventario en la sucursal (stock 0; lo mueve el kardex).
      insert into public.inventory (company_id, branch_id, product_id, stock, min_stock)
      values (v_company, p_branch_id, v_prod.id, 0, coalesce(v_min, 0))
      on conflict (branch_id, product_id) do update
        set min_stock = excluded.min_stock
        where v_min is not null and public.inventory.min_stock is distinct from excluded.min_stock;

      -- Existencia inicial: solo una vez por producto y sucursal.
      if coalesce(v_stock, 0) > 0 then
        select count(*)::int into v_n from public.inventory_movements m
         where m.branch_id = p_branch_id and m.product_id = v_prod.id;
        if v_n = 0 then
          insert into public.inventory_movements (company_id, branch_id, product_id, movement_type, quantity, reason, reference_type)
          values (v_company, p_branch_id, v_prod.id, 'adjustment_in', v_stock, 'Carga inicial', 'import');
        else
          v_notas := array_append(v_notas, 'existencia no aplicada: el producto ya tiene movimientos en esta sucursal');
        end if;
      end if;

      v_out := v_out || jsonb_build_object('fila', v_fila, 'sku', v_sku, 'estado', v_estado,
        'motivo', nullif(array_to_string(v_notas, '; '), ''), 'producto_id', v_prod.id);
    exception when others then
      v_out := v_out || jsonb_build_object('fila', v_fila, 'sku', v_sku, 'estado', 'error', 'motivo', sqlerrm, 'producto_id', null);
    end;
  end loop;
  return v_out;
end $$;
revoke all on function public.import_products(uuid, jsonb, text) from public, anon;
grant execute on function public.import_products(uuid, jsonb, text) to authenticated;
