/**
 * Card — contenedor blanco con encabezado opcional.
 *   <Card title="Tareas" action={<Button/>} flush>...</Card>
 *   flush: sin padding interno (para tablas de borde a borde)
 */
export default function Card({ children, className = '', title, subtitle, action, flush = false }) {
  return (
    <div className={`card ${className}`.trim()}>
      {(title || action) && (
        <div className="card-header">
          <div>
            {title && <h3 className="card-title">{title}</h3>}
            {subtitle && <p className="card-subtitle">{subtitle}</p>}
          </div>
          {action && <div className="card-action">{action}</div>}
        </div>
      )}
      <div className={`card-body ${flush ? 'p-0' : ''}`.trim()}>{children}</div>
    </div>
  )
}
