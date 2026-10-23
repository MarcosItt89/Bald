/**
 * Huecos en anaquel (0020): productos que no están en piso.
 * report_shelf_gap cruza con la existencia: si hay, crea la tarea a Almacén
 * «Surtir a piso»; si no, sugiere un pedido (create_order_from_shelf_gap).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch } from '../lib/queryHelpers'

export const getShelfGaps = ({ branchId, open = true, limit = 200 } = {}) => {
  let q = byBranch(supabase.from('v_shelf_gaps').select('*'), branchId)
    .order('last_reported_at', { ascending: false }).limit(limit)
  q = open ? q.eq('status', 'open') : q.neq('status', 'open')
  return unwrap(q)
}

export const reportShelfGap = ({ branchId, productId, notes }) =>
  unwrap(supabase.rpc('report_shelf_gap', { p_branch_id: branchId, p_product_id: productId, p_notes: notes || null }))

export const createOrderFromGap = (gapId, quantity) =>
  unwrap(supabase.rpc('create_order_from_shelf_gap', { p_gap_id: gapId, p_quantity: Number(quantity) }))

export const closeShelfGap = (gapId, status) =>
  unwrap(supabase.rpc('close_shelf_gap', { p_gap_id: gapId, p_status: status }))
