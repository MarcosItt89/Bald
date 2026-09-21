export default function Input({
  label,
  id,
  error,
  className = '',
  ...props
}) {
  return (
    <div className={`form-group ${className}`.trim()}>
      {label && <label htmlFor={id} className="form-label">{label}</label>}
      <input id={id} className={`form-input ${error ? 'input-error' : ''}`.trim()} {...props} />
      {error && <span className="form-error">{error}</span>}
    </div>
  )
}
