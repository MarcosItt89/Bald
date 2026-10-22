/**
 * Servicio de pedidos internos (solicitud de mercancía o insumos).
 *
 * Estados y transiciones: ver ORDER_TRANSITIONS en src/constants/status.js
 * (la base de datos las vuelve a validar en tg_order_flow).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, emptyToNull } from '../lib/queryHelpers'

export const getOrders = ({ branchId, status, limit = 200 } = {}) => {
  let q = byBranch(supabase.from('v_orders').select('*'), branchId)
    .order('created_at', { ascending: false }).limit(limit)
  if (status) q = q.eq('status', status)
  return unwrap(q)
}

export const getOrderItems = (orderId) =>
  unwrap(supabase.from('v_order_items').select('*').eq('order_id', orderId))

/** Crea el pedido y sus renglones. Si fallan los renglones, se borra el pedido. */
export async function createOrder({ items, ...order }) {
  if (!items.length) throw new Error('Agrega al menos un producto al pedido.')
  const saved = await unwrap(supabase.from('orders').insert(emptyToNull(order)).select().single())
  try {
    await unwrap(supabase.from('order_items').insert(items.map((it) => ({
      order_id: saved.id, product_id: it.product_id, quantity: Number(it.quantity), notes: it.notes || null,
    }))))
  } catch (err) {
    await supabase.from('orders').delete().eq('id', saved.id)
    throw err
  }
  return saved
}

export const changeOrderStatus = (id, status, comment) =>
  unwrap(supabase.from('orders')
    .update({ status, status_comment: comment || null })
    .eq('id', id).select().single())

export const setReceivedQty = (itemId, qty) =>
  unwrap(supabase.from('order_items').update({ received_qty: Number(qty) }).eq('id', itemId))
