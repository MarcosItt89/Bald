/**
 * Servicio de organización: empresa, sucursales y departamentos.
 *
 * Tablas: companies, branches, departments (RLS: lectura para toda la
 * empresa, escritura con permiso manage_branches).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { saveRow, emptyToNull } from '../lib/queryHelpers'

// ─── Sucursales ──────────────────────────────────────────────────────────────
export const getBranches = ({ onlyActive = false, zoneIds } = {}) => {
  let q = supabase.from('branches').select('*, manager:employees!branches_manager_id_fkey(full_name), zone:zones(name)').order('code')
  if (onlyActive) q = q.eq('status', 'active')
  if (zoneIds) q = q.in('zone_id', zoneIds.length ? zoneIds : ['00000000-0000-0000-0000-000000000000'])
  return unwrap(q)
}

/** Sucursales que el usuario puede elegir: todas (company) o las de sus zonas (zone). */
export const getMyBranches = ({ isCompanyScope, isZoneScope, zoneIds }) =>
  isCompanyScope ? getBranches({ onlyActive: true })
    : isZoneScope ? getBranches({ onlyActive: true, zoneIds })
    : Promise.resolve([])

export const saveBranch = (branch) => {
  const { manager, zone, ...row } = branch // "manager" y "zone" vienen del join, no son columnas
  return saveRow('branches', emptyToNull(row))
}

// ─── Departamentos ───────────────────────────────────────────────────────────
export const getDepartments = ({ onlyActive = false } = {}) => {
  let q = supabase.from('departments').select('*').order('name')
  if (onlyActive) q = q.eq('is_active', true)
  return unwrap(q)
}

export const saveDepartment = (dept) => saveRow('departments', emptyToNull(dept))

// ─── Zonas ───────────────────────────────────────────────────────────────────
export const getZones = ({ onlyActive = false } = {}) => {
  let q = supabase.from('zones').select('*, branches(id, code, name)').order('name')
  if (onlyActive) q = q.eq('is_active', true)
  return unwrap(q)
}

export const saveZone = (zone) => {
  const { branches, ...row } = zone
  return saveRow('zones', emptyToNull(row))
}

/** Zonas asignadas a un empleado (solo roles con alcance 'zone'). */
export const getEmployeeZones = async (employeeId) =>
  (await unwrap(supabase.from('employee_zones').select('zone_id').eq('employee_id', employeeId))).map((r) => r.zone_id)

export async function setEmployeeZones(employeeId, zoneIds) {
  await unwrap(supabase.from('employee_zones').delete().eq('employee_id', employeeId))
  if (zoneIds.length) {
    await unwrap(supabase.from('employee_zones').insert(zoneIds.map((zone_id) => ({ employee_id: employeeId, zone_id }))))
  }
}
