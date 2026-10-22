/**
 * BarList — barras horizontales con etiqueta y valor; cada fila puede ser un enlace.
 *   <BarList items={[{ key, label, value, hint, to, tone }]} format={(v) => `${v}%`} max={100} />
 *   tone: primary | good | warn | bad | neutral
 */
import { Link } from 'react-router-dom'

export default function BarList({ items, format = (v) => v, max, tone = 'primary', emptyText = 'Sin datos en este periodo' }) {
  if (!items?.length) return <p className="chart-empty">{emptyText}</p>
  const top = max ?? (Math.max(...items.map((i) => i.value ?? 0)) || 1)
  return (
    <ul className="barlist">
      {items.map((it) => {
        const width = Math.max(0, Math.min(100, ((it.value ?? 0) / top) * 100))
        const shown = it.value == null ? '—' : format(it.value, it)
        const body = (
          <>
            <span className="barlist-label">{it.label}{it.hint && <small>{it.hint}</small>}</span>
            <span className="barlist-value">{shown}</span>
            <span className="barlist-track"><span className={`barlist-bar chart-tone-${it.tone ?? tone}`} style={{ width: `${width}%` }} /></span>
          </>
        )
        return (
          <li key={it.key}>
            {it.to
              ? <Link to={it.to} className="barlist-row barlist-link" title={`${it.label}: ${shown}`}>{body}</Link>
              : <div className="barlist-row" title={`${it.label}: ${shown}`}>{body}</div>}
          </li>
        )
      })}
    </ul>
  )
}
