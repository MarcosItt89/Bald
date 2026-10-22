/**
 * AccountProblemPage — la sesión existe en Supabase Auth pero no hay un
 * empleado ACTIVO ligado a esa cuenta (o falló la carga del perfil).
 *
 * Causas típicas:
 *   - Aún no se ejecutaron los scripts SQL (supabase/setup_completo.sql).
 *   - El empleado fue dado de baja (status inactive).
 *   - La cuenta se creó sin pre-registrar al empleado.
 */
import { UserX } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'

export default function AccountProblemPage() {
  const { status, error, logout, session } = useAuth()
  return (
    <div className="fatal-error">
      <UserX size={40} />
      <h2>{status === 'error' ? 'No se pudo cargar tu perfil' : 'Tu cuenta no tiene acceso'}</h2>
      <p>
        {status === 'error'
          ? error
          : `La cuenta ${session?.user?.email ?? ''} no está ligada a un empleado activo. Contacta al administrador.`}
      </p>
      {status === 'error' && (
        <p className="text-muted text-sm">
          Si es la primera vez, verifica que ya se ejecutó supabase/setup_completo.sql en el SQL Editor.
        </p>
      )}
      <div className="fatal-actions">
        <button className="btn btn-outline" onClick={logout}>Cerrar sesión</button>
      </div>
    </div>
  )
}
