/**
 * ProgressBar — barra de avance (checklists, cumplimiento en reportes).
 * El color cambia según el porcentaje si `semaphore` es true
 * (≥ 90 verde, ≥ 70 ámbar, menor rojo).
 */
export default function ProgressBar({ value, total, percent, label, semaphore = false, width }) {
  const pct = percent ?? (total > 0 ? Math.round((value / total) * 100) : 0)
  const tone = !semaphore ? '' : pct >= 90 ? 'progress-ok' : pct >= 70 ? 'progress-warn' : 'progress-bad'
  return (
    <div className="progress">
      <div className="progress-track" style={width ? { width } : undefined}>
        <div className={`progress-fill ${tone}`} style={{ width: `${Math.min(100, pct)}%` }} />
      </div>
      <span className="progress-label">{label ?? `${pct}%`}</span>
    </div>
  )
}
