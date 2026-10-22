/**
 * Cliente de Supabase y utilidades para manejar sus respuestas.
 *
 * Objetivo: una sola instancia del cliente para toda la app, y una forma
 * uniforme de convertir los errores técnicos de PostgREST/Postgres en
 * mensajes entendibles para el usuario.
 */
import { createClient } from '@supabase/supabase-js'
import { env, isSupabaseConfigured } from '../config/env'

export const supabase = isSupabaseConfigured
  ? createClient(env.supabaseUrl, env.supabaseKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
    })
  : null

/**
 * Cliente "desechable" SIN sesión persistente. Se usa para dar de alta la
 * cuenta de un empleado (auth.signUp) sin cerrar la sesión del administrador.
 */
export const createIsolatedClient = () =>
  createClient(env.supabaseUrl, env.supabaseKey, {
    auth: { persistSession: false, autoRefreshToken: false, storageKey: 'operalia-signup' },
  })

/** Traduce errores de Supabase/Postgres a español. */
export function friendlyError(error) {
  if (!error) return 'Error desconocido'
  const msg = error.message ?? String(error)
  switch (error.code) {
    case '42501': return 'No tienes permiso para realizar esta acción.'
    case '23505': return 'Ya existe un registro con ese valor (duplicado).'
    case '23503': return 'El registro está relacionado con otros datos y no se puede completar la acción.'
    case '23514': return 'Algún dato no cumple las reglas (valor fuera de rango o inválido).'
    case '23502': return 'Falta un dato obligatorio.'
    case 'PGRST116': return 'No se encontró el registro.'
    case 'P0001': return msg // mensajes de RAISE EXCEPTION en los triggers (ya en español)
    default: break
  }
  if (/row-level security/i.test(msg)) return 'No tienes permiso para realizar esta acción.'
  if (/Failed to fetch|NetworkError/i.test(msg)) return 'Sin conexión con el servidor. Revisa tu internet.'
  if (/JWT expired/i.test(msg)) return 'Tu sesión expiró. Vuelve a iniciar sesión.'
  return msg
}

/**
 * Espera una consulta de supabase-js y devuelve `data` o lanza un Error con
 * mensaje amigable. Así los servicios se escriben con async/await + try/catch.
 *
 *   const rows = await unwrap(supabase.from('v_tasks').select('*'))
 */
export async function unwrap(query) {
  if (!supabase) throw new Error('Supabase no está configurado (revisa el archivo .env).')
  const { data, error } = await query
  if (error) {
    const err = new Error(friendlyError(error))
    err.cause = error
    throw err
  }
  return data
}
