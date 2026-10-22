/**
 * Servicio de proveedores y de su acceso físico a la sucursal (caseta).
 *   suppliers        → catálogo (manage_suppliers para editar)
 *   supplier_visits  → entrada/salida (register_supplier_visit)
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, ilikeTerm, saveRow, emptyToNull, dayStart } from '../lib/queryHelpers'

export const getSuppliers = ({ search, status } = {}) => {
  let q = supabase.from('suppliers').select('*').order('name')
  if (status) q = q.eq('status', status)
  if (search) {
    const t = ilikeTerm(search)
    q = q.or(`name.ilike.${t},code.ilike.${t},merchandise_type.ilike.${t}`)
  }
  return unwrap(q)
}

export const saveSupplier = (supplier) => saveRow('suppliers', emptyToNull(supplier))

export const getVisits = ({ branchId, onlyOpen = false, from, limit = 200 } = {}) => {
  let q = byBranch(supabase.from('v_supplier_visits').select('*'), branchId)
    .order('check_in_at', { ascending: false }).limit(limit)
  if (onlyOpen) q = q.is('check_out_at', null)
  if (from) q = q.gte('check_in_at', dayStart(from))
  return unwrap(q)
}

export const registerVisit = (visit) =>
  unwrap(supabase.from('supplier_visits').insert(emptyToNull(visit)).select().single())

export const closeVisit = (id, employeeId) =>
  unwrap(supabase.from('supplier_visits')
    .update({ check_out_at: new Date().toISOString(), closed_by: employeeId })
    .eq('id', id).select().single())
