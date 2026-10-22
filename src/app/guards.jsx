/**
 * Guardas de ruta.
 *
 *   <RequireAuth>        → exige sesión iniciada y empleado ligado; si no, manda a /login
 *   <RequireAccess item> → exige el permiso del ítem de navegación; si no, muestra 403
 *
 * Corrige el error del prototipo: antes cualquier usuario podía abrir
 * /employees escribiendo la URL aunque el menú no mostrara la opción.
 */
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { canAccess } from '../config/navigation'
import { Loader } from '../components/ui/Feedback'
import ForbiddenPage from '../features/errors/ForbiddenPage'
import AccountProblemPage from '../features/errors/AccountProblemPage'

export function RequireAuth({ children }) {
  const { status } = useAuth()
  const location = useLocation()

  if (status === 'loading') return <Loader full text="Cargando sesión…" />
  if (status === 'noProfile' || status === 'error') return <AccountProblemPage />
  if (status !== 'signedIn') return <Navigate to="/login" replace state={{ from: location.pathname }} />
  return children
}

export function RequireAccess({ item, children }) {
  const auth = useAuth()
  if (!canAccess(item, auth)) return <ForbiddenPage />
  return children
}
