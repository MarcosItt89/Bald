/**
 * Heatmap — matriz de porcentajes (0–100) en un solo tono: más oscuro = mayor valor.
 *   <Heatmap rows={[{ key, label }]} cols={[{ key, label }]}
 *            cell={(rowKey, colKey) => ({ value, title, to }) | null} />
 */
import { Link } from 'react-router-dom'

export default function Heatmap({ rows, cols, cell, format = (v) => `${v}%`, emptyText = 'Sin datos en este periodo' }) {
  if (!rows?.length || !cols?.length) return <p className="chart-empty">{emptyText}</p>
  return (
    <div className="heatmap-wrap">
      <div className="heatmap" style={{ gridTemplateColumns: `minmax(72px, 1.4fr) repeat(${cols.length}, minmax(28px, 1fr))` }} role="table">
        <span />
        {cols.map((c) => <span key={c.key} className="heatmap-col" role="columnheader">{c.label}</span>)}
        {rows.map((r) => (
          <div key={r.key} className="heatmap-row" role="row">
            <span className="heatmap-row-label" role="rowheader" title={r.label}>{r.label}</span>
            {cols.map((c) => {
              const d = cell(r.key, c.key)
              if (!d || d.value == null) return <span key={c.key} className="heatmap-cell heatmap-empty" role="cell" title="Sin datos" />
              const style = { '--heat': `${12 + d.value * 0.88}%` }
              const cls = `heatmap-cell ${d.value >= 60 ? 'heatmap-dark' : ''}`
              const title = d.title ?? `${r.label} · ${c.label}: ${format(d.value)}`
              return d.to
                ? <Link key={c.key} to={d.to} className={`${cls} chart-clickable`} style={style} title={title} role="cell">{format(d.value)}</Link>
                : <span key={c.key} className={cls} style={style} title={title} role="cell">{format(d.value)}</span>
            })}
          </div>
        ))}
      </div>
      <div className="heatmap-scale"><span>0%</span><span className="heatmap-gradient" /><span>100%</span></div>
    </div>
  )
}
