/** 404 — ruta inexistente dentro de la app. */
import { Link } from 'react-router-dom'
import { MapPinOff } from 'lucide-react'
import { EmptyState } from '../../components/ui/Feedback'

export default function NotFoundPage() {
  return (
    <div className="page">
      <EmptyState
        icon={MapPinOff}
        title="Página no encontrada"
        message="La dirección no existe o fue movida."
        action={<Link className="btn btn-outline btn-sm" to="/dashboard">Ir al inicio</Link>}
      />
    </div>
  )
}
