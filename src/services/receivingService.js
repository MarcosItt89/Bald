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
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, emptyToNull, dayStart, dayEnd } from '../lib/queryHelpers'

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

export const updateReceivingHeader = (id, { invoice_number, notes }) =>
  unwrap(supabase.from('receiving_orders').update(emptyToNull({ invoice_number, notes })).eq('id', id))

export const closeReceiving = (id) =>
  unwrap(supabase.from('receiving_orders').update({ status: 'completed' }).eq('id', id).select().single())

export const cancelReceiving = (id, reason) =>
  unwrap(supabase.from('receiving_orders').update({ status: 'cancelled', notes: reason }).eq('id', id))
