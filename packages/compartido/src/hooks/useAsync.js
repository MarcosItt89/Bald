/**
 * useAsync — carga datos asíncronos con estados de carga y error.
 *
 * Objetivo: que cada página cargue datos de Supabase con el mismo patrón,
 * sin repetir useState/useEffect/try-catch.
 *
 *   const load = useCallback(() => getTasks({ branchId }), [branchId])
 *   const { data, loading, error, reload, mutate } = useAsync(load)
 *
 * IMPORTANTE: la función debe estar memorizada con useCallback; cuando sus
 * dependencias cambian (p. ej. un filtro) se vuelve a cargar sola.
 *
 * `loading` se deriva comparando qué petición produjo los datos actuales, así
 * no hace falta llamar setState de forma síncrona dentro del efecto.
 */
import { useCallback, useEffect, useState } from 'react'

export function useAsync(asyncFn) {
  const [nonce, setNonce] = useState(0)
  const [state, setState] = useState({ source: null, nonce: -1, data: undefined, error: null })

  useEffect(() => {
    let active = true
    Promise.resolve()
      .then(asyncFn)
      .then(
        (data) => active && setState({ source: asyncFn, nonce, data, error: null }),
        (error) => active && setState((s) => ({ source: asyncFn, nonce, data: s.data, error })),
      )
    return () => { active = false }
  }, [asyncFn, nonce])

  const reload = useCallback(() => setNonce((n) => n + 1), [])

  /** Actualiza los datos en memoria sin volver a consultar (actualización optimista). */
  const mutate = useCallback((updater) => {
    setState((s) => ({ ...s, data: typeof updater === 'function' ? updater(s.data) : updater }))
  }, [])

  return {
    data: state.data,
    error: state.error,
    loading: state.source !== asyncFn || state.nonce !== nonce,
    reload,
    mutate,
  }
}
