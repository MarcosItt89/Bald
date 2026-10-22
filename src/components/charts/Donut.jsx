/**
 * Donut — proporción de pocas categorías (≤ 5) con leyenda clicable.
 *   <Donut segments={[{ key, label, value, tone, to }]} center={{ value: '82%', label: 'completados' }} />
 */
import { useNavigate, Link } from 'react-router-dom'

const SIZE = 136
const STROKE = 18
const GAP = 2

export default function Donut({ segments, center, format = (v) => v, emptyText = 'Sin datos en este periodo' }) {
  const navigate = useNavigate()
  const items = (segments ?? []).filter((s) => s.value > 0)
  const total = items.reduce((s, x) => s + x.value, 0)
  if (!total) return <p className="chart-empty">{emptyText}</p>

  const r = (SIZE - STROKE) / 2
  const c = 2 * Math.PI * r
  const arcs = items.map((s, i) => {
    const offset = items.slice(0, i).reduce((sum, x) => sum + (x.value / total) * c, 0)
    const len = (s.value / total) * c
    return { ...s, len: Math.max(len - (items.length > 1 ? GAP : 0), 0.5), offset }
  })
  const pctOf = (v) => `${Math.round((v / total) * 100)}%`

  return (
    <div className="donut">
      <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`} role="img"
        aria-label={items.map((s) => `${s.label}: ${format(s.value)}`).join(', ')}>
        <g transform={`rotate(-90 ${SIZE / 2} ${SIZE / 2})`}>
          {arcs.map((a) => (
            <circle key={a.key} cx={SIZE / 2} cy={SIZE / 2} r={r} fill="none" strokeWidth={STROKE}
              className={`donut-arc chart-stroke-${a.tone ?? 'primary'} ${a.to ? 'chart-clickable' : ''}`}
              strokeDasharray={`${a.len} ${c}`} strokeDashoffset={-a.offset}
              onClick={a.to ? () => navigate(a.to) : undefined}>
              <title>{`${a.label}: ${format(a.value)} (${pctOf(a.value)})${a.hint ? ` · ${a.hint}` : ''}`}</title>
            </circle>
          ))}
        </g>
        {center && (
          <>
            <text x="50%" y="48%" textAnchor="middle" className="donut-center-value">{center.value}</text>
            <text x="50%" y="62%" textAnchor="middle" className="donut-center-label">{center.label}</text>
          </>
        )}
      </svg>
      <ul className="chart-legend chart-legend-col">
        {items.map((s) => {
          const body = (
            <>
              <span className={`chart-swatch chart-bg-${s.tone ?? 'primary'}`} />
              <span className="chart-legend-label">{s.label}</span>
              <strong>{format(s.value)}</strong>
              <span className="text-muted">{pctOf(s.value)}</span>
            </>
          )
          return <li key={s.key}>{s.to ? <Link to={s.to} className="chart-legend-item chart-legend-link">{body}</Link> : <span className="chart-legend-item">{body}</span>}</li>
        })}
      </ul>
    </div>
  )
}
