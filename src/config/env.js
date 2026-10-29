/**
 * Variables de entorno de Operalia.
 *
 * Objetivo: un solo lugar donde se leen las variables VITE_* (definidas en
 * .env localmente y en Settings → Environment Variables de Vercel).
 * Vite solo expone al navegador las variables que empiezan con VITE_.
 *
 * La llave publishable de Supabase es segura en el navegador SOLO porque todas
 * las tablas están protegidas con RLS (ver supabase/migrations/0005).
 * Nunca pongas aquí la service_role / secret key.
 */
export const env = {
  // También se aceptan los nombres NEXT_PUBLIC_* que crea la integración Supabase ↔ Vercel.
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL || import.meta.env.NEXT_PUBLIC_SUPABASE_URL,
  supabaseKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY
    || import.meta.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  appName: 'Operalia',
}

export const isSupabaseConfigured = Boolean(env.supabaseUrl && env.supabaseKey)

// Dominio "virtual" del correo de Supabase Auth. Lo arman igual las funciones
// SQL (employee_auth_email en la migración 0022): usuario@<empresa>.operalia.local
export const AUTH_EMAIL_DOMAIN = 'operalia.local'

/** Normaliza el código de empresa: minúsculas, sin acentos, solo [a-z0-9-]. */
export const normalizeCompanyCode = (code) => (code ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '')
  .trim().toLowerCase().replace(/[^a-z0-9-]/g, '')

/**
 * Convierte empresa + lo que escribe el usuario en el correo de Auth:
 * ("gatopelon", "cajero") → cajero@gatopelon.operalia.local. Un correo real
 * (con @) se usa tal cual y no necesita empresa.
 */
export const usernameToEmail = (companyCode, identifier) => {
  const clean = identifier.trim().toLowerCase()
  return clean.includes('@') ? clean : `${clean}@${normalizeCompanyCode(companyCode)}.${AUTH_EMAIL_DOMAIN}`
}

// Empresa recordada en este dispositivo: el empleado la escribe una sola vez.
const COMPANY_KEY = 'operalia.companyCode'
export const readRememberedCompany = () => {
  try { return localStorage.getItem(COMPANY_KEY) ?? '' } catch { return '' }
}
export const rememberCompany = (code) => {
  try { code ? localStorage.setItem(COMPANY_KEY, code) : localStorage.removeItem(COMPANY_KEY) } catch { /* modo privado */ }
}
