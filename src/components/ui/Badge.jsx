/**
 * Badge — etiqueta pequeña de color para estados y categorías.
 * Colores: default | success | warning | danger | info | primary
 */
const COLORS = {
  default: 'badge-default',
  success: 'badge-success',
  warning: 'badge-warning',
  danger:  'badge-danger',
  info:    'badge-info',
  primary: 'badge-primary',
}

export default function Badge({ children, color = 'default', className = '', title }) {
  return (
    <span className={`badge ${COLORS[color] ?? 'badge-default'} ${className}`.trim()} title={title}>
      {children}
    </span>
  )
}
