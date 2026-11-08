/**
 * Select — lista desplegable con etiqueta.
 *   options: [{ value, label }]
 *   placeholder: primera opción vacía (value '')
 */
import { useId } from 'react'
import { Field } from './Input'

export default function Select({
  label, error, hint, options = [], placeholder, className = '', id, required, ...props
}) {
  const autoId = useId()
  const selectId = id ?? autoId
  return (
    <Field label={label} error={error} hint={hint} htmlFor={selectId} required={required} className={className}>
      <select id={selectId} required={required} className={`form-select ${error ? 'input-error' : ''}`.trim()} {...props}>
        {placeholder !== undefined && <option value="">{placeholder}</option>}
        {options.map((opt) => (
          <option key={opt.value} value={opt.value} disabled={opt.disabled}>{opt.label}</option>
        ))}
      </select>
    </Field>
  )
}
