/**
 * Campos de formulario: Input, Textarea y Field (envoltura con etiqueta).
 * Todos aceptan label, error (mensaje rojo) y hint (ayuda gris).
 */
import { useId } from 'react'

export function Field({ label, error, hint, htmlFor, required, className = '', children }) {
  return (
    <div className={`form-group ${className}`.trim()}>
      {label && (
        <label htmlFor={htmlFor} className="form-label">
          {label}{required && <span className="form-required"> *</span>}
        </label>
      )}
      {children}
      {error ? <span className="form-error">{error}</span> : hint && <span className="form-hint">{hint}</span>}
    </div>
  )
}

export default function Input({ label, error, hint, className = '', id, required, ...props }) {
  const autoId = useId()
  const inputId = id ?? autoId
  return (
    <Field label={label} error={error} hint={hint} htmlFor={inputId} required={required} className={className}>
      <input id={inputId} required={required} className={`form-input ${error ? 'input-error' : ''}`.trim()} {...props} />
    </Field>
  )
}

export function Textarea({ label, error, hint, className = '', id, required, rows = 3, ...props }) {
  const autoId = useId()
  const inputId = id ?? autoId
  return (
    <Field label={label} error={error} hint={hint} htmlFor={inputId} required={required} className={className}>
      <textarea id={inputId} rows={rows} required={required}
        className={`form-input form-textarea ${error ? 'input-error' : ''}`.trim()} {...props} />
    </Field>
  )
}
