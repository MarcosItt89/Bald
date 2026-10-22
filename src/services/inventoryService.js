/**
 * Servicio de productos, inventario y movimientos.
 *
 * Regla clave: el stock NUNCA se edita directo. Se registra un movimiento en
 * inventory_movements y el trigger tg_apply_inventory_movement actualiza la
 * existencia (con bloqueo de fila y sin permitir negativos). Así cada cambio
 * queda con quién, cuándo y por qué.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, ilikeTerm, emptyToNull, dayStart, dayEnd } from '../lib/queryHelpers'

const searchFilter = (text) => {
  const t = ilikeTerm(text)
  return `product_name.ilike.${t},sku.ilike.${t},barcodes.ilike.${t}`
}

export const getInventory = ({ branchId, search, status, departmentId } = {}) => {
  let q = byBranch(supabase.from('v_inventory').select('*'), branchId).order('product_name')
  if (search) q = q.or(searchFilter(search))
  if (status) q = q.eq('status', status)
  if (departmentId) q = q.eq('department_id', departmentId)
  return unwrap(q)
}

/** Consulta de precios: búsqueda rápida por nombre, SKU o código de barras. */
export const lookupPrice = ({ branchId, search }) =>
  unwrap(byBranch(supabase.from('v_inventory').select('*'), branchId)
    .or(searchFilter(search)).order('product_name').limit(20))

/** Catálogo (para selectores de producto en recibos, pedidos, precios). */
export const searchProducts = (search, limit = 15) => {
  let q = supabase.from('v_products').select('id, sku, name, unit, price, barcodes, department_id')
    .eq('status', 'active').order('name').limit(limit)
  if (search) {
    const t = ilikeTerm(search)
    q = q.or(`name.ilike.${t},sku.ilike.${t},barcodes.ilike.${t}`)
  }
  return unwrap(q)
}

export const getMovements = ({ branchId, type, from, to, search, limit = 300 } = {}) => {
  let q = byBranch(supabase.from('v_inventory_movements').select('*'), branchId)
    .order('created_at', { ascending: false }).limit(limit)
  if (type) q = q.eq('movement_type', type)
  if (from) q = q.gte('created_at', dayStart(from))
  if (to) q = q.lte('created_at', dayEnd(to))
  if (search) {
    const t = ilikeTerm(search)
    q = q.or(`product_name.ilike.${t},sku.ilike.${t}`)
  }
  return unwrap(q)
}

export const createMovement = ({ branch_id, product_id, movement_type, quantity, reason }) =>
  unwrap(supabase.from('inventory_movements')
    .insert({ branch_id, product_id, movement_type, quantity: Number(quantity), reason: reason || null })
    .select().single())

export const updateInventorySettings = (id, { min_stock, max_stock, location, status }) =>
  unwrap(supabase.from('inventory')
    .update(emptyToNull({ min_stock, max_stock, location, status }))
    .eq('id', id).select().single())

/**
 * Alta de producto: producto + código de barras + renglón de inventario en la
 * sucursal + (opcional) existencia inicial vía movimiento de entrada.
 */
export async function createProduct({ barcode, branch_id, min_stock, initial_stock, ...product }) {
  const saved = await unwrap(supabase.from('products').insert(emptyToNull(product)).select().single())
  if (barcode) {
    await unwrap(supabase.from('product_barcodes').insert({ product_id: saved.id, barcode: barcode.trim() }))
  }
  if (branch_id) {
    await unwrap(supabase.from('inventory')
      .insert({ branch_id, product_id: saved.id, min_stock: Number(min_stock) || 0 }))
    if (Number(initial_stock) > 0) {
      await createMovement({
        branch_id, product_id: saved.id, movement_type: 'in', quantity: initial_stock, reason: 'Existencia inicial',
      })
    }
  }
  return saved
}

/**
 * Caja / piso reporta que el precio del anaquel no coincide con el sistema.
 * La función SQL crea una tarea para el departamento de Escáner.
 */
export const reportPriceDifference = ({ productId, branchId, observedPrice, comment }) =>
  unwrap(supabase.rpc('report_price_difference', {
    p_product_id: productId,
    p_branch_id: branchId,
    p_observed_price: observedPrice === '' ? null : Number(observedPrice),
    p_comment: comment || null,
  }))
