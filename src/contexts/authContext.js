/**
 * Contexto de autenticación (solo el objeto).
 *
 * Se separa del Provider para que React Fast Refresh funcione (un archivo
 * .jsx solo debe exportar componentes). Úsalo mediante el hook useAuth().
 */
import { createContext } from 'react'

export const AuthContext = createContext(null)
