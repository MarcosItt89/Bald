/**
 * Servicio de organización: empresa, sucursales y departamentos.
 *
 * Tablas: companies, branches, departments (RLS: lectura para toda la
 * empresa, escritura con permiso manage_branches).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { saveRow, emptyToNull } from '../lib/queryHelpers'

// ─── Sucursales ──────────────────────────────────────────────────────────────
export const getBranches = ({ onlyActive = false } = {}) => {
  let q = supabase.from('branches').select('*, manager:employees!branches_manager_id_fkey(full_name)').order('code')
  if (onlyActive) q = q.eq('status', 'active')
  return unwrap(q)
}

export const saveBranch = (branch) => {
  const { manager, ...row } = branch // "manager" viene del join, no es columna
  return saveRow('branches', emptyToNull(row))
}

// ─── Departamentos ───────────────────────────────────────────────────────────
export const getDepartments = ({ onlyActive = false } = {}) => {
  let q = supabase.from('departments').select('*').order('name')
  if (onlyActive) q = q.eq('is_active', true)
  return unwrap(q)
}

export const saveDepartment = (dept) => saveRow('departments', emptyToNull(dept))
