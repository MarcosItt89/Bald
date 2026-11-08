/** Deja pasar solo a superadmins; sin sesión → /login; otra cuenta → «Sin acceso». */
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import NoAccessPage from './NoAccessPage'

export default function RequireConsola({ children }) {
  const { status } = useAuth()
  const location = useLocation()
  if (status === 'loading') return <Loader full text="Cargando sesión…" />
  if (status === 'noAccess' || status === 'error') return <NoAccessPage />
  if (status !== 'signedIn') return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />
  return children
}
