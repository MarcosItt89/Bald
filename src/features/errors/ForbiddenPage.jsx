/** 403 — el usuario abrió una ruta para la que no tiene permiso. */
import { Link } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { EmptyState } from '../../components/ui/Feedback'

export default function ForbiddenPage() {
  return (
    <div className="page">
      <EmptyState
        icon={ShieldAlert}
        title="No tienes acceso a este módulo"
        message="Si lo necesitas para tu trabajo, pide a tu gerente o al administrador que te asigne el permiso."
        action={<Link className="btn btn-outline btn-sm" to="/dashboard">Ir al inicio</Link>}
      />
    </div>
  )
}
