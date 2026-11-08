/**
 * Servicio de organización: empresa (y su marca), sucursales y departamentos.
 *
 * Tablas: companies, branches, departments (RLS: lectura para toda la
 * empresa, escritura con permiso manage_branches).
 */
import { supabase, unwrap, friendlyError } from '../lib/supabaseClient'
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

// ─── Empresa y marca (0028) ─────────────────────────────────────────────────
const BRANDING_BUCKET = 'company-branding'
export const LOGO_TYPES = ['image/png', 'image/svg+xml', 'image/webp']
export const LOGO_MAX_BYTES = 500 * 1024

export const getMyCompany = (companyId) =>
  unwrap(supabase.from('companies').select('id, name, code, display_name, logo_url, brand_color').eq('id', companyId).single())

/** Marca pública para el login (sin sesión): { name, display_name, logo_url, brand_color } o null. */
export async function getCompanyBranding(code) {
  const rows = await unwrap(supabase.rpc('get_company_branding', { p_code: code }))
  return rows?.[0] ?? null
}

/** Sube el logo a company-branding/{empresa}/ y devuelve su URL pública. */
export async function uploadCompanyLogo(companyId, file) {
  if (!LOGO_TYPES.includes(file.type)) throw new Error('El logo debe ser PNG, SVG o WebP')
  if (file.size > LOGO_MAX_BYTES) throw new Error('El logo pesa más de 500 KB')
  const ext = { 'image/png': 'png', 'image/svg+xml': 'svg', 'image/webp': 'webp' }[file.type]
  const path = `${companyId}/logo-${Date.now()}.${ext}`
  const { error } = await supabase.storage.from(BRANDING_BUCKET).upload(path, file, { contentType: file.type, upsert: false })
  if (error) throw new Error(friendlyError(error))
  return supabase.storage.from(BRANDING_BUCKET).getPublicUrl(path).data.publicUrl
}

/** Borra un logo anterior del bucket (si es de este bucket). No falla si no puede. */
export async function removeCompanyLogo(url) {
  const marker = `/object/public/${BRANDING_BUCKET}/`
  const i = url?.indexOf(marker) ?? -1
  if (i < 0) return
  await supabase.storage.from(BRANDING_BUCKET).remove([decodeURIComponent(url.slice(i + marker.length))])
}

/** Guarda nombre visible, color y logo (solo propietario o superadmin). */
export const saveCompanyBranding = ({ companyId, displayName, brandColor, logoUrl }) =>
  unwrap(supabase.rpc('set_company_branding', {
    p_company_id: companyId,
    p_display_name: displayName?.trim() || null,
    p_brand_color: brandColor,
    p_logo_url: logoUrl || null,
  }))
