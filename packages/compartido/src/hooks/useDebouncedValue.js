/**
 * useDebouncedValue — retrasa un valor (p. ej. texto de búsqueda) para no
 * consultar Supabase en cada tecla.
 *
 *   const debounced = useDebouncedValue(query, 300)
 */
import { useEffect, useState } from 'react'

export function useDebouncedValue(value, delay = 300) {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(id)
  }, [value, delay])
  return debounced
}
