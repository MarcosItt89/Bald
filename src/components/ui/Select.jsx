export default function Select({ label, id, options = [], error, className = '', ...props }) {
  return (
    <div className={`form-group ${className}`.trim()}>
      {label && <label htmlFor={id} className="form-label">{label}</label>}
      <select id={id} className={`form-select ${error ? 'input-error' : ''}`.trim()} {...props}>
        {options.map(opt => (
          <option key={opt.value} value={opt.value}>{opt.label}</option>
        ))}
      </select>
      {error && <span className="form-error">{error}</span>}
    </div>
  )
}
