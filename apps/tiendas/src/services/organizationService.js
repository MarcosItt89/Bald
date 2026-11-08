/**
 * Servicio de organización: empresa (y su marca), sucursales y departamentos.
 *
 * Tablas: companies, branches, departments (RLS: lectura para toda la
 * empresa, escritura con permiso manage_branches).
 */
import { supabase, unwrap } from '@operalia/compartido/lib/supabaseClient.js'
import { saveRow, emptyToNull } from '@operalia/compartido/lib/queryHelpers.js'

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

// ─── Empresa y marca (0028) ─────────────────────────────────────────────────
// Logo, color y nombre visible viven en el paquete compartido (también los usa la Consola).
export {
  LOGO_MAX_BYTES, LOGO_TYPES, getCompanyBranding, removeCompanyLogo, saveCompanyBranding, uploadCompanyLogo,
} from '@operalia/compartido/branding/brandingService.js'

export const getMyCompany = (companyId) =>
  unwrap(supabase.from('companies').select('id, name, code, display_name, logo_url, brand_color').eq('id', companyId).single())
