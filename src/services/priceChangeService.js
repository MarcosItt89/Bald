/**
 * Servicio de cambios de precio y cenefas.
 *
 * Al insertar un cambio de precio con fecha efectiva de hoy (o pasada), el
 * trigger SQL lo aplica: actualiza products.price, guarda previous_price y,
 * si requiere cenefa, crea una cenefa 'pending' por sucursal. Los cambios con
 * fecha futura quedan 'scheduled' y se aplican con run_daily_maintenance().
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch } from '../lib/queryHelpers'

export const getPriceChanges = ({ branchId, status, limit = 200 } = {}) => {
  let q = supabase.from('v_price_changes').select('*').order('created_at', { ascending: false }).limit(limit)
  // Cambios globales (branch_id null) + los de la sucursal seleccionada.
  if (branchId) q = q.or(`branch_id.is.null,branch_id.eq.${branchId}`)
  if (status) q = q.eq('status', status)
  return unwrap(q)
}

export const createPriceChange = ({ product_id, branch_id, new_price, effective_date, reason, requires_tag }) =>
  unwrap(supabase.from('price_changes').insert({
    product_id,
    branch_id: branch_id || null,
    new_price: Number(new_price),
    old_price: 0, // el trigger lo reemplaza por el precio actual real
    effective_date,
    reason: reason || null,
    requires_tag,
  }).select().single())

export const cancelPriceChange = (id) =>
  unwrap(supabase.from('price_changes').update({ status: 'cancelled' }).eq('id', id))

export const getShelfTags = ({ branchId, status, limit = 300 } = {}) => {
  let q = byBranch(supabase.from('v_shelf_tags').select('*'), branchId)
    .order('created_at', { ascending: false }).limit(limit)
  if (status) q = q.eq('status', status)
  return unwrap(q)
}

/** Avanza la cenefa: pending → printed → placed → validated (o rejected). */
export const updateTagStatus = (id, status, rejectionReason) =>
  unwrap(supabase.from('shelf_tags')
    .update({ status, ...(status === 'rejected' ? { rejection_reason: rejectionReason || 'Sin motivo' } : {}) })
    .eq('id', id).select().single())

export const updateTagsStatus = (ids, status) =>
  unwrap(supabase.from('shelf_tags').update({ status }).in('id', ids))
