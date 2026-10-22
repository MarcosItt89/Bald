/**
 * Servicio de caducidades (lotes con fecha de vencimiento).
 *
 * Los lotes llegan de dos formas: captura manual o automáticamente al
 * cerrar un recibo que trae fecha de caducidad. El trigger marca 'expired'
 * los lotes activos con fecha pasada.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, emptyToNull } from '../lib/queryHelpers'
import { createMovement } from './inventoryService'

export const getExpirations = ({ branchId, status, maxDays } = {}) => {
  let q = byBranch(supabase.from('v_expirations').select('*'), branchId).order('expiration_date')
  if (status) q = q.eq('status', status)
  if (maxDays != null) q = q.lte('days_left', maxDays)
  return unwrap(q)
}

export const createExpiration = (lot) =>
  unwrap(supabase.from('product_expirations').insert(emptyToNull({
    ...lot, quantity: Number(lot.quantity) || 0,
  })).select().single())

export const updateExpirationStatus = (id, status, action_notes) =>
  unwrap(supabase.from('product_expirations')
    .update({ status, action_notes: action_notes || null }).eq('id', id).select().single())

/**
 * Descuenta la cantidad del inventario como merma y después marca el lote
 * como retirado. Primero el movimiento: si falla (p. ej. stock insuficiente)
 * el lote no queda marcado como retirado sin haber afectado el inventario.
 */
export async function withdrawAsWaste(lot, notes) {
  if (Number(lot.quantity) > 0) {
    await createMovement({
      branch_id: lot.branch_id,
      product_id: lot.product_id,
      movement_type: 'waste',
      quantity: lot.quantity,
      reason: `Merma por caducidad · lote ${lot.lot ?? 's/n'}`,
    })
  }
  await updateExpirationStatus(lot.id, 'withdrawn', notes)
}
