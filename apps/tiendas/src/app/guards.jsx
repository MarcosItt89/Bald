/**
 * Guardas de ruta.
 *
 *   <RequireAuth>        → exige sesión iniciada y empleado ligado; si no, manda a /login
 *   <RequireAccess item> → exige el permiso del ítem de navegación; si no, muestra 403
 *   <HomeRedirect>       → página de inicio (Dashboard)
 *
 * Corrige el error del prototipo: antes cualquier usuario podía abrir
 * /employees escribiendo la URL aunque el menú no mostrara la opción.
 */
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { canAccess } from '../config/navigation'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
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

/** Inicio: el Dashboard. La plataforma de superadmin vive en la Consola Operalia. */
export function HomeRedirect() {
  return <Navigate to="/dashboard" replace />
}

export function RequireAccess({ item, children }) {
  const auth = useAuth()
  if (!canAccess(item, auth)) return <ForbiddenPage />
  return children
}
