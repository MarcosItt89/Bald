const COLORS = {
  default: 'badge-default',
  success: 'badge-success',
  warning: 'badge-warning',
  danger:  'badge-danger',
  info:    'badge-info',
  primary: 'badge-primary',
}

export default function Badge({ children, color = 'default', className = '' }) {
  return (
    <span className={`badge ${COLORS[color] ?? 'badge-default'} ${className}`.trim()}>
      {children}
    </span>
  )
}
