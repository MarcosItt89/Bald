/**
 * SearchInput — caja de búsqueda con ícono y botón para limpiar.
 * Compatible con lectores de código de barras USB (escriben + Enter):
 * onEnter se dispara al presionar Enter.
 */
import { Search, X } from 'lucide-react'

export default function SearchInput({ value, onChange, onEnter, placeholder = 'Buscar…', autoFocus, large = false }) {
  return (
    <div className={`search-bar ${large ? 'search-bar-lg' : ''}`}>
      <Search size={large ? 18 : 15} className="search-icon" />
      <input
        type="search"
        className="search-input"
        placeholder={placeholder}
        value={value}
        autoFocus={autoFocus}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') onEnter?.(e.currentTarget.value) }}
      />
      {value && (
        <button type="button" className="search-clear" onClick={() => onChange('')} aria-label="Limpiar">
          <X size={14} />
        </button>
      )}
    </div>
  )
}
