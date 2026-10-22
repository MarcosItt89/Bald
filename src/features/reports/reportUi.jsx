import { BarChart3, Download, Minus, TrendingDown, TrendingUp } from 'lucide-react'
import { downloadCsv } from '../../utils/csv'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'

/** Variación contra el periodo anterior. better: 'up' (más es mejor) | 'down'. format: cómo mostrar la diferencia. */
export function Delta({ d, better = 'up', unit = '', format }) {
  const show = (v) => (format ? format(v) : `${v}${unit}`)
  if (!d || d.prev == null) return null
  if (!d.diff) return <span className="delta delta-flat"><Minus size={12} /> igual que el periodo anterior</span>
  const good = better === 'up' ? d.diff > 0 : d.diff < 0
  const Icon = d.diff > 0 ? TrendingUp : TrendingDown
  return (
    <span className={`delta ${good ? 'delta-good' : 'delta-bad'}`} title={`Periodo anterior: ${show(d.prev)}`}>
      <Icon size={12} /> {d.diff > 0 ? '+' : '−'}{show(Math.abs(d.diff))} vs. anterior
    </span>
  )
}

/** Tarjeta de sección con botón "Exportar CSV". csv = { name, rows, columns } */
export function ReportSection({ title, subtitle, csv, wide = false, children }) {
  return (
    <Card className={wide ? 'report-wide' : ''} title={title} subtitle={subtitle}
      action={csv && (
        <Button variant="ghost" size="sm" disabled={!csv.rows?.length}
          onClick={() => downloadCsv(`${csv.name}.csv`, csv.rows, csv.columns)}>
          <Download size={14} /> Exportar CSV
        </Button>
      )}>
      {children}
    </Card>
  )
}

/** Carga / error / vacío comunes a todas las pestañas. */
export function ReportState({ loading, error, reload, data, empty, children }) {
  if (error) return <ErrorState error={error} onRetry={reload} />
  if (loading && !data) return <Loader text="Calculando estadísticas…" />
  if (!data) return null
  if (empty) return <EmptyState icon={BarChart3} title="Sin datos en este periodo" message="Prueba con un periodo más largo u otra sucursal o departamento." />
  return children
}
