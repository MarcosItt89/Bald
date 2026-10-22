/**
 * <Can> — muestra su contenido solo si el usuario tiene el permiso.
 *
 *   <Can permission={P.MANAGE_TASKS}><Button>Nueva tarea</Button></Can>
 *   <Can anyOf={[P.APPROVE_ORDERS, P.CREATE_ORDERS]}>...</Can>
 *
 * Es solo para la interfaz: la base de datos vuelve a validar con RLS.
 */
import { useAuth } from '../../hooks/useAuth'

export default function Can({ permission, anyOf, fallback = null, children }) {
  const { hasPermission, hasAny } = useAuth()
  const allowed = permission ? hasPermission(permission) : anyOf ? hasAny(anyOf) : true
  return allowed ? children : fallback
}
