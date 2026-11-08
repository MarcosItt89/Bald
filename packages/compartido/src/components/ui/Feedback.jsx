/**
 * Componentes de estado de pantalla:
 *   <Loader />                       spinner centrado mientras carga
 *   <EmptyState icon title message action />   cuando no hay datos
 *   <ErrorState error onRetry />     cuando falló la consulta (con "Reintentar")
 */
import { AlertTriangle, Inbox } from 'lucide-react'
import Button from './Button'

export function Loader({ text = 'Cargando…', full = false }) {
  return (
    <div className={`loader ${full ? 'loader-full' : ''}`}>
      <span className="spinner-md" />
      <span>{text}</span>
    </div>
  )
}

export function EmptyState({ icon: Icon = Inbox, title = 'Sin información', message, action }) {
  return (
    <div className="empty-state">
      <Icon size={36} />
      <strong>{title}</strong>
      {message && <p>{message}</p>}
      {action}
    </div>
  )
}

export function ErrorState({ error, onRetry }) {
  return (
    <div className="error-state">
      <AlertTriangle size={20} />
      <div>
        <strong>No se pudo cargar la información</strong>
        <p>{error?.message ?? String(error)}</p>
      </div>
      {onRetry && <Button variant="outline" size="sm" onClick={onRetry}>Reintentar</Button>}
    </div>
  )
}
