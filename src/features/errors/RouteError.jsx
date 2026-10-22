/**
 * RouteError — pantalla cuando una página lanza un error inesperado.
 * Evita la pantalla en blanco y ofrece reportarlo a la mesa de ayuda.
 */
import { Link, useRouteError } from 'react-router-dom'
import { Bug } from 'lucide-react'

export default function RouteError() {
  const error = useRouteError()
  console.error('[Operalia] Error de ruta:', error)
  return (
    <div className="fatal-error">
      <Bug size={40} />
      <h2>Algo salió mal</h2>
      <p>{error?.message ?? error?.statusText ?? 'Error desconocido'}</p>
      <div className="fatal-actions">
        <button className="btn btn-primary" onClick={() => window.location.reload()}>Recargar</button>
        <Link className="btn btn-outline" to="/support">Reportar en Mesa de ayuda</Link>
      </div>
    </div>
  )
}
