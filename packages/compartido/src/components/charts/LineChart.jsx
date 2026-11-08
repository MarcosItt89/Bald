/**
 * LineChart — evolución en el tiempo (una o dos series) en SVG propio.
 *   <LineChart series={[{ key: 'pct', label: 'Cumplimiento', slot: 1 }]}
 *              data={[{ x: '2026-10-01', label: '1 oct', values: { pct: 80 }, to }]}
 *              yMax={100} format={(v) => `${v}%`} />
 * band={{ min, max }} sombrea el rango permitido (p. ej. temperaturas); con band
 * o valores negativos el eje se ajusta a los datos en lugar de empezar en 0.
 * Al pasar el cursor muestra cruz + tooltip; clic en un punto navega a `to`.
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useElementWidth } from '../../hooks/useElementWidth'

const H = 200
const PAD = { top: 12, bottom: 26, left: 38 }

export default function LineChart({ series, data, yMax, band, format = (v) => v, emptyText = 'Sin datos en este periodo' }) {
  const navigate = useNavigate()
  const [ref, width] = useElementWidth()
  const [hover, setHover] = useState(null)
  const multi = series.length > 1
  const hasData = data?.some((d) => series.some((s) => d.values[s.key] != null))

  if (!hasData) return <div ref={ref}><p className="chart-empty">{emptyText}</p></div>

  const right = multi ? 64 : 14
  const innerW = width - PAD.left - right
  const innerH = H - PAD.top - PAD.bottom
  const vals = data.flatMap((d) => series.map((s) => d.values[s.key])).filter((v) => v != null)
  let lo = 0
  let top = yMax
  if (yMax == null) {
    const ext = band ? [...vals, band.min, band.max].filter((v) => v != null) : vals
    if (band || Math.min(...ext) < 0) {
      const mn = Math.min(...ext)
      const mx = Math.max(...ext)
      const pad = Math.max(1, (mx - mn) * 0.15)
      lo = Math.floor(mn - pad)
      top = Math.ceil(mx + pad)
    } else {
      top = niceMax(Math.max(1, ...ext))
    }
  }
  const x = (i) => PAD.left + (data.length === 1 ? innerW / 2 : (i / (data.length - 1)) * innerW)
  const y = (v) => PAD.top + innerH - ((v - lo) / (top - lo)) * innerH
  const ticks = top - lo >= 2 ? [lo, (lo + top) / 2, top] : [lo, top]
  const outside = (v) => !!band && ((band.min != null && v < band.min) || (band.max != null && v > band.max))
  const tickLabel = (t) => format(Number.isInteger(t) ? t : Math.round(t * 10) / 10)
  const labelEvery = Math.max(1, Math.ceil(data.length / Math.max(2, Math.floor(innerW / 64))))

  const pathFor = (key) => {
    let d = ''
    let pen = false
    data.forEach((p, i) => {
      const v = p.values[key]
      if (v == null) { pen = false; return }
      d += `${pen ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`
      pen = true
    })
    return d
  }

  const pick = (e) => {
    const box = e.currentTarget.getBoundingClientRect()
    const px = e.clientX - box.left
    const i = data.length === 1 ? 0 : Math.round(((px - PAD.left) / innerW) * (data.length - 1))
    setHover(Math.max(0, Math.min(data.length - 1, i)))
  }

  const lastIndex = (key) => data.reduce((acc, p, i) => (p.values[key] != null ? i : acc), -1)
  const hp = hover != null ? data[hover] : null

  return (
    <div className="linechart" ref={ref}>
      {multi && (
        <ul className="chart-legend">
          {series.map((s) => <li key={s.key} className="chart-legend-item"><span className={`chart-swatch chart-bg-s${s.slot ?? 1}`} />{s.label}</li>)}
        </ul>
      )}
      <svg width={width} height={H} role="img"
        aria-label={series.map((s) => s.label).join(' y ')}
        onPointerMove={pick} onPointerLeave={() => setHover(null)}
        onClick={() => hp?.to && navigate(hp.to)}
        className={hp?.to ? 'chart-clickable' : undefined}>
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PAD.left} x2={width - right} y1={y(t)} y2={y(t)} className="chart-grid" />
            <text x={PAD.left - 6} y={y(t) + 4} textAnchor="end" className="chart-axis">{tickLabel(t)}</text>
          </g>
        ))}
        {data.map((p, i) => (i % labelEvery === 0 || i === data.length - 1) && (
          <text key={p.x} x={x(i)} y={H - 8} textAnchor="middle" className="chart-axis">{p.label}</text>
        ))}
        {band && (
          <g>
            <rect x={PAD.left} width={width - right - PAD.left} y={y(band.max ?? top)} height={Math.max(0, y(band.min ?? lo) - y(band.max ?? top))} className="chart-band" />
            {band.max != null && <line x1={PAD.left} x2={width - right} y1={y(band.max)} y2={y(band.max)} className="chart-band-edge" />}
            {band.min != null && <line x1={PAD.left} x2={width - right} y1={y(band.min)} y2={y(band.min)} className="chart-band-edge" />}
          </g>
        )}
        {hp && <line x1={x(hover)} x2={x(hover)} y1={PAD.top} y2={PAD.top + innerH} className="chart-crosshair" />}
        {series.map((s) => (
          <g key={s.key}>
            <path d={pathFor(s.key)} className={`chart-line chart-stroke-s${s.slot ?? 1}`} />
            {data.map((p, i) => p.values[s.key] != null && (data.length <= 16 || isolated(data, i, s.key) || outside(p.values[s.key])) && (
              <circle key={p.x} cx={x(i)} cy={y(p.values[s.key])} r={outside(p.values[s.key]) ? 4.5 : 3.5}
                className={`chart-dot ${outside(p.values[s.key]) ? 'chart-dot-bad' : `chart-fill-s${s.slot ?? 1}`}`} />
            ))}
            {hp && hp.values[s.key] != null && (
              <circle cx={x(hover)} cy={y(hp.values[s.key])} r={5} className={`chart-dot chart-fill-s${s.slot ?? 1}`} />
            )}
            {multi && lastIndex(s.key) >= 0 && (
              <text x={x(lastIndex(s.key)) + 8} y={y(data[lastIndex(s.key)].values[s.key]) + 4} className="chart-direct-label">{s.label}</text>
            )}
          </g>
        ))}
      </svg>
      {hp && (
        <div className="chart-tooltip" style={{ left: Math.min(Math.max(x(hover), 70), width - 70) }}>
          <strong>{hp.label}</strong>
          {series.map((s) => (
            <span key={s.key}><i className={`chart-swatch chart-bg-s${s.slot ?? 1}`} />{s.label}: {hp.values[s.key] == null ? '—' : format(hp.values[s.key])}</span>
          ))}
          {hp.to && <small>Clic para ver detalle</small>}
        </div>
      )}
    </div>
  )
}

/** Tope del eje con mitad entera (2, 4, 6, 8, 10 × 10ⁿ). */
function niceMax(v) {
  const p = 10 ** Math.floor(Math.log10(v))
  const n = v / p
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 4 ? 4 : n <= 6 ? 6 : n <= 8 ? 8 : 10) * p
}

/** Punto sin vecinos con dato: sin marcador no se vería (la línea necesita dos puntos). */
const isolated = (data, i, key) => data[i - 1]?.values[key] == null && data[i + 1]?.values[key] == null
