/**
 * FilterChip — filtro activo que llegó por la URL (p. ej. desde Estadísticas), con botón para quitarlo.
 *   <FilterChip label="Solo atrasadas" onClear={() => setLate(false)} />
 */
import { X } from 'lucide-react'

export default function FilterChip({ label, onClear }) {
  return (
    <span className="filter-chip">
      {label}
      <button type="button" onClick={onClear} aria-label={`Quitar filtro: ${label}`}><X size={12} /></button>
    </span>
  )
}
