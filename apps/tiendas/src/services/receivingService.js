/**
 * Servicio de recibo de mercancía.
 *
 * Flujo:
 *   1. createReceivingOrder → encabezado 'in_progress' (folio automático REC-000001)
 *   2. addItem / updateItem / deleteItem → productos esperados vs recibidos
 *   3. closeReceiving → status 'completed'. El trigger SQL:
 *        - valida permiso close_receiving y que haya productos
 *        - calcula totales y diferencias
 *        - genera movimientos de inventario (entrada por recibo)
 *        - registra lotes con caducidad en product_expirations
 */
import { supabase, unwrap } from '@operalia/compartido/lib/supabaseClient.js'
import { byBranch, emptyToNull, dayStart, dayEnd } from '@operalia/compartido/lib/queryHelpers.js'

export const getReceivingOrders = ({ branchId, status, from, to, supplierId, limit = 200 } = {}) => {
  let q = byBranch(supabase.from('v_receiving_orders').select('*'), branchId)
    .order('created_at', { ascending: false }).limit(limit)
  if (status) q = q.eq('status', status)
  if (supplierId) q = q.eq('supplier_id', supplierId)
  if (from) q = q.gte('created_at', dayStart(from))
  if (to) q = q.lte('created_at', dayEnd(to))
  return unwrap(q)
}

export async function getReceivingOrder(id) {
  const [order, items] = await Promise.all([
    unwrap(supabase.from('v_receiving_orders').select('*').eq('id', id).single()),
    unwrap(supabase.from('v_receiving_items').select('*').eq('receiving_order_id', id).order('created_at')),
  ])
  return { order, items }
}

export const createReceivingOrder = (payload) =>
  unwrap(supabase.from('receiving_orders').insert(emptyToNull(payload)).select().single())

const cleanItem = ({ expected_qty, received_qty, damaged_qty, weight_kg, ...rest }) => emptyToNull({
  ...rest,
  expected_qty: Number(expected_qty) || 0,
  received_qty: Number(received_qty) || 0,
  damaged_qty: Number(damaged_qty) || 0,
  weight_kg: weight_kg === '' || weight_kg == null ? null : Number(weight_kg),
})

export const addItem = (item) =>
  unwrap(supabase.from('receiving_items').insert(cleanItem(item)).select().single())

export const updateItem = (id, item) =>
  unwrap(supabase.from('receiving_items').update(cleanItem(item)).eq('id', id).select().single())

export const deleteItem = (id) => unwrap(supabase.from('receiving_items').delete().eq('id', id))

export const closeReceiving = (id) =>
  unwrap(supabase.from('receiving_orders').update({ status: 'completed' }).eq('id', id).select().single())

export const cancelReceiving = (id, reason) =>
  unwrap(supabase.from('receiving_orders').update({ status: 'cancelled', notes: reason }).eq('id', id))

// ─── Recibo desde factura CFDI (0031) ────────────────────────────────────────
/** Recibo no cancelado que ya tenga esta factura (de las sucursales visibles). */
export async function findReceivingByUuid(uuid) {
  const rows = await unwrap(supabase.from('receiving_orders').select('id, folio, status')
    .eq('cfdi_uuid', uuid).neq('status', 'cancelled').limit(1))
  return rows[0] ?? null
}

/** Claves de este proveedor ya emparejadas: Map(clave → producto). */
export async function getSupplierCodes(supplierId) {
  const rows = await unwrap(supabase.from('supplier_product_codes')
    .select('supplier_code, product:products(id, sku, name, unit, status)').eq('supplier_id', supplierId))
  return new Map(rows.filter((r) => r.product).map((r) => [r.supplier_code, r.product]))
}

/** Sugerencias para claves sin emparejar: la clave del proveedor coincide con un código de barras o un SKU. */
export async function findProductsByCodes(codes) {
  const found = new Map()
  const unique = [...new Set(codes.filter(Boolean))]
  for (let i = 0; i < unique.length; i += 100) {
    const part = unique.slice(i, i + 100)
    const [byBarcode, bySku] = await Promise.all([
      unwrap(supabase.from('product_barcodes').select('barcode, product:products(id, sku, name, unit, status)').in('barcode', part)),
      unwrap(supabase.from('products').select('id, sku, name, unit, status').in('sku', part)),
    ])
    bySku.forEach((p) => found.set(p.sku, { product: p, via: 'SKU' }))
    byBarcode.forEach((b) => { if (b.product) found.set(b.barcode, { product: b.product, via: 'código de barras' }) })
  }
  return found
}

/**
 * Crea el recibo EN CAPTURA con las partidas de la factura (esperado = cantidad,
 * recibido = 0) y recuerda las claves marcadas. No mueve existencias.
 * items: [{ product_id, cantidad, valor_unitario, clave, descripcion, unidad, recordar }]
 */
export const createReceivingFromCfdi = ({ branchId, supplierId, invoice, items, notes }) =>
  unwrap(supabase.rpc('create_receiving_from_cfdi', {
    p_branch_id: branchId, p_supplier_id: supplierId, p_invoice: invoice, p_items: items, p_notes: notes || null,
  }))
