/**
 * Marca por empresa: color principal y logo (migración 0028).
 *
 * applyBrand(color) escribe en :root las variables que usa toda la app:
 *   --primary        el color de la empresa (oscurecido si con texto blanco
 *                    no llega a contraste AA 4.5:1: los botones llevan texto blanco)
 *   --primary-dark   hover de botones, texto de insignias
 *   --primary-light  fondos suaves (insignias, selección)
 *   --primary-deep   tono más oscuro: menú activo, degradado del login, filtros
 *
 * La última marca se guarda en localStorage y bootBrand() la aplica antes
 * del primer render (main.jsx), así no parpadea el azul por defecto.
 */
export const DEFAULT_BRAND_COLOR = '#2563eb'
const STORAGE_KEY = 'operalia.brand'
const AA = 4.5

const isHex = (v) => /^#[0-9a-f]{6}$/i.test(v ?? '')

const toRgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
const toHex = (rgb) => `#${rgb.map((c) => Math.round(Math.min(255, Math.max(0, c))).toString(16).padStart(2, '0')).join('')}`

/** Mezcla un color con otro (t = 0 → a, t = 1 → b). */
const mix = (a, b, t) => toHex(toRgb(a).map((c, i) => c + (toRgb(b)[i] - c) * t))

/** Luminancia relativa WCAG 2.1. */
const luminance = (hex) => {
  const [r, g, b] = toRgb(hex).map((c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/** Contraste de un color contra el texto blanco (1 a 21). */
export const contrastWithWhite = (hex) => 1.05 / (luminance(hex) + 0.05)

/**
 * Tonos de la marca a partir del color elegido.
 * adjusted = true si hubo que oscurecerlo para el contraste AA con blanco.
 */
export function brandPalette(color) {
  const base = isHex(color) ? color.toLowerCase() : DEFAULT_BRAND_COLOR
  let primary = base
  for (let t = 0.05; contrastWithWhite(primary) < AA && t <= 1; t += 0.05) primary = mix(base, '#000000', t)
  return {
    primary,
    primaryDark: mix(primary, '#000000', 0.18),
    primaryLight: mix(base, '#ffffff', 0.85),
    primaryDeep: mix(primary, '#000000', 0.32),
    adjusted: primary !== base,
    contrast: Math.round(contrastWithWhite(primary) * 10) / 10,
  }
}

/** Aplica el color de la marca a toda la app. null/inválido = azul de Operalia. */
export function applyBrand(color) {
  const root = document.documentElement
  if (!isHex(color) || color.toLowerCase() === DEFAULT_BRAND_COLOR) {
    ['--primary', '--primary-dark', '--primary-light', '--primary-deep'].forEach((v) => root.style.removeProperty(v))
    return brandPalette(DEFAULT_BRAND_COLOR)
  }
  const p = brandPalette(color)
  root.style.setProperty('--primary', p.primary)
  root.style.setProperty('--primary-dark', p.primaryDark)
  root.style.setProperty('--primary-light', p.primaryLight)
  root.style.setProperty('--primary-deep', p.primaryDeep)
  return p
}

/** Marca guardada en el dispositivo: { code, color, logoUrl, name } o null. */
export function readSavedBrand() {
  try {
    const v = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? 'null')
    return v && typeof v === 'object' ? v : null
  } catch { return null }
}

export function saveBrand(brand) {
  try {
    if (brand) localStorage.setItem(STORAGE_KEY, JSON.stringify(brand))
    else localStorage.removeItem(STORAGE_KEY)
  } catch { /* modo privado */ }
}

/** Marca a partir del perfil del empleado (get_my_profile). */
export const brandFromProfile = (profile) => (profile ? {
  code: profile.company_code,
  color: profile.company_brand_color ?? DEFAULT_BRAND_COLOR,
  logoUrl: profile.company_logo_url ?? null,
  name: profile.company_display_name || profile.company_name,
} : null)

/** Antes del primer render: aplica la última marca usada en este dispositivo. */
export function bootBrand() {
  applyBrand(readSavedBrand()?.color)
}
