/**
 * Marca de una empresa (migración 0028): logo en el bucket company-branding,
 * color principal y nombre visible. Lo usan la app de tiendas (propietario)
 * y la Consola (superadmin, cualquier empresa).
 */
import { supabase, unwrap, friendlyError } from '../lib/supabaseClient'

const BRANDING_BUCKET = 'company-branding'
export const LOGO_TYPES = ['image/png', 'image/svg+xml', 'image/webp']
export const LOGO_MAX_BYTES = 500 * 1024

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
