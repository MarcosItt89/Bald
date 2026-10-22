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
  // Dominio "virtual" para convertir usuario → correo de Supabase Auth.
  // Debe coincidir con el usado en supabase/seed/0008_usuarios_y_demo.sql.
  authEmailDomain: import.meta.env.VITE_AUTH_EMAIL_DOMAIN || 'operalia.local',
  appName: 'Operalia',
}

export const isSupabaseConfigured = Boolean(env.supabaseUrl && env.supabaseKey)

/** Convierte lo que escribe el usuario ("gatopelon" o un correo) en el correo de Auth. */
export const usernameToEmail = (identifier) => {
  const clean = identifier.trim().toLowerCase()
  return clean.includes('@') ? clean : `${clean}@${env.authEmailDomain}`
}
