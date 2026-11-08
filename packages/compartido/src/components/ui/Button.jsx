/**
 * Button — botón estándar de la app.
 *   variant: primary | secondary | danger | ghost | outline | success
 *   size: sm | md | lg
 *   loading: muestra spinner y deshabilita (evita doble clic al guardar)
 */
const VARIANTS = {
  primary:   'btn-primary',
  secondary: 'btn-secondary',
  danger:    'btn-danger',
  ghost:     'btn-ghost',
  outline:   'btn-outline',
  success:   'btn-success',
}

const SIZES = { sm: 'btn-sm', md: '', lg: 'btn-lg' }

export default function Button({
  children,
  variant = 'primary',
  size = 'md',
  disabled = false,
  loading = false,
  type = 'button',
  className = '',
  ...props
}) {
  return (
    <button
      type={type}
      className={`btn ${VARIANTS[variant] ?? ''} ${SIZES[size] ?? ''} ${className}`.trim()}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? <span className={`spinner-sm ${variant === 'primary' || variant === 'danger' || variant === 'success' ? '' : 'spinner-dark'}`} /> : null}
      {children}
    </button>
  )
}
