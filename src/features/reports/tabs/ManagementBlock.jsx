/**
 * Bloque «Gerencia: apertura y cierre» (Estadísticas → Checklists).
 * Calificación de cada sucursal por día para comparar tiendas.
 * Con más de 31 días se agrupa por semana (promedio de los días con datos).
 */
import { getManagementChecklistReport, weekStart } from '../../../services/reportService'
import BarList from '../../../components/charts/BarList'
import Heatmap from '../../../components/charts/Heatmap'
import { Loader, ErrorState } from '../../../components/ui/Feedback'
import { addDaysISO } from '../../../utils/formatters'
import { complianceTone, fmtPct, shortDate, useReport, useReportLink } from '../reportFilters'
import { ReportSection } from '../reportUi'

const mean = (vals) => {
  const v = vals.filter((x) => x != null)
  return v.length ? Math.round(v.reduce((a, b) => a + b, 0) / v.length) : null
}

export default function ManagementBlock({ filters }) {
  const { data, loading, error, reload } = useReport(getManagementChecklistReport, filters)
  const link = useReportLink()
  const { from, to } = filters

  const byWeek = (data?.days.length ?? 0) > 31
  const cols = !data ? [] : byWeek
    ? [...new Set(data.days.map(weekStart))].map((w) => ({ key: w, label: shortDate(w) }))
    : data.days.map((d) => ({ key: d, label: String(Number(d.slice(8))) }))
  const cellValue = (branch, col) => (byWeek
    ? mean(data.days.filter((d) => weekStart(d) === col).map((d) => branch.days[d]?.score))
    : branch.days[col]?.score ?? null)
  const history = (params) => link('/checklists/history', { dept: data?.gerDeptId, status: 'all', ...params })

  const csvRows = (data?.branches ?? []).flatMap((b) => data.days.filter((d) => b.days[d]).map((d) => ({
    branch: b.name, day: d, opening: b.days[d].opening, closing: b.days[d].closing, score: b.days[d].score,
  })))

  return (
    <ReportSection wide title="Gerencia: apertura y cierre"
      subtitle={`Calificación por sucursal ${byWeek ? 'por semana' : 'por día'} · «Sí» ÷ preguntas programadas (un checklist sin llenar cuenta como no cumplido)`}
      csv={{ name: `gerencia-apertura-cierre_${from}_${to}`, rows: csvRows, columns: [
        { key: 'branch', label: 'Sucursal' }, { key: 'day', label: 'Fecha' },
        { key: 'opening', label: '% Apertura' }, { key: 'closing', label: '% Cierre' }, { key: 'score', label: '% Día' }] }}>
      {error ? <ErrorState error={error} onRetry={reload} />
        : loading && !data ? <Loader text="Calculando…" />
        : !data?.branches.length ? <p className="chart-empty">Sin checklists de Gerencia en este periodo</p>
        : (
          <div className="report-split">
            <BarList max={100} format={fmtPct} items={data.branches.map((b) => ({
              key: b.id, label: b.name, value: b.score, tone: complianceTone(b.score),
              hint: `Apertura ${fmtPct(b.opening)} · Cierre ${fmtPct(b.closing)}`,
              to: history({ from, to }),
            }))} />
            <Heatmap cols={cols} rows={data.branches.map((b) => ({ key: b.id, label: b.name }))}
              cell={(rowKey, colKey) => {
                const b = data.branches.find((x) => x.id === rowKey)
                const v = cellValue(b, colKey)
                if (v == null) return null
                const d = !byWeek && b.days[colKey]
                return {
                  value: v,
                  title: byWeek
                    ? `${b.name} · semana del ${shortDate(colKey)}: ${v}%`
                    : `${b.name} · ${shortDate(colKey)}: ${v}% (apertura ${fmtPct(d.opening)}, cierre ${fmtPct(d.closing)})`,
                  to: byWeek
                    ? history({ from: colKey < from ? from : colKey, to: addDaysISO(colKey, 6) > to ? to : addDaysISO(colKey, 6) })
                    : history({ from: colKey, to: colKey }),
                }
              }} />
          </div>
        )}
    </ReportSection>
  )
}
