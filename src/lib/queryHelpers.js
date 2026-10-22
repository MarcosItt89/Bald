/**
 * Pequeñas utilidades para armar consultas de supabase-js.
 * Las usan los archivos de src/services/.
 */
import { supabase, unwrap } from './supabaseClient'

/** Aplica el filtro de sucursal solo si hay una seleccionada (null = todas las visibles). */
export const byBranch = (query, branchId) => (branchId ? query.eq('branch_id', branchId) : query)

/**
 * Limpia un texto de búsqueda para usarlo dentro de .or('col.ilike.%x%').
 * Las comas, paréntesis y asteriscos rompen la sintaxis de PostgREST.
 */
export const ilikeTerm = (text) => `%${String(text).trim().replace(/[,()*%\\]/g, ' ')}%`

/** Cuenta filas sin descargarlas (HEAD + count exact). */
export async function countOf(query) {
  const { count, error } = await query
  if (error) throw error
  return count ?? 0
}

/** head:true evita descargar filas cuando solo interesa el conteo. */
export const countQuery = (table) => supabase.from(table).select('*', { count: 'exact', head: true })

/**
 * Inserta o actualiza según exista `id`. Devuelve la fila guardada.
 *   await saveRow('suppliers', { id?, name, ... })
 */
export async function saveRow(table, row) {
  const { id, ...fields } = row
  const query = id
    ? supabase.from(table).update(fields).eq('id', id)
    : supabase.from(table).insert(fields)
  return unwrap(query.select().single())
}

/**
 * Límites de un día LOCAL convertidos a ISO/UTC para filtrar columnas
 * timestamptz (created_at, check_in_at...). Sin esto, en Tijuana (UTC−7)
 * el filtro "hoy" se recorría 7 horas.
 */
export const dayStart = (isoDate) => new Date(`${isoDate}T00:00:00`).toISOString()
export const dayEnd = (isoDate) => new Date(`${isoDate}T23:59:59.999`).toISOString()

/** Quita propiedades con string vacío (los inputs devuelven '' y la BD espera null). */
export const emptyToNull = (obj) =>
  Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, v === '' ? null : v]))
