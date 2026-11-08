/**
 * Rutas de la Consola. En la Consola cuelgan de la raíz (/nueva, /soporte…);
 * la app de tiendas todavía monta estas mismas páginas bajo /plataforma y
 * para eso envuelve sus rutas con <PlatformBaseContext.Provider value="/plataforma">.
 */
import { createContext, useCallback, useContext } from 'react'

export const PlatformBaseContext = createContext('')

/** path('nueva') → '/nueva' en la Consola, '/plataforma/nueva' en tiendas. */
export function usePlatformPath() {
  const base = useContext(PlatformBaseContext)
  return useCallback((sub = '') => (sub ? `${base}/${sub}` : base || '/'), [base])
}
