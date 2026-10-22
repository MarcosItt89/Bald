/**
 * Servicio de caducidades (lotes con fecha de vencimiento).
 *
 * Los lotes llegan de dos formas: captura manual o automáticamente al
 * cerrar un recibo que trae fecha de caducidad. El trigger marca 'expired'
 * los lotes activos con fecha pasada.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, emptyToNull } from '../lib/queryHelpers'

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
 * Marca el lote como retirado. La merma (motivo «Caducado») la registra la
 * base de datos (trigger trg_expiration_waste, 0014) en la misma operación,
 * hasta la existencia disponible y una sola vez por lote.
 */
export const withdrawAsWaste = (lot, notes) => updateExpirationStatus(lot.id, 'withdrawn', notes)
