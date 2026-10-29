/**
 * PerformancePage — Plataforma → Rendimiento (solo superadmins).
 * Cómo van las empresas cliente y sus sucursales: totales de la plataforma,
 * ranking por métrica, tendencia diaria y mapa de calor de checklists.
 * Todo sale de funciones de la migración 0025, que devuelven solo agregados.
 */
import { useCallback, useMemo, useState } from 'react'
import { Activity, ClipboardCheck, Download, Globe, ListTodo, LifeBuoy, PackageSearch, ScanBarcode, Trash2, Users } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { getChecklistHeatmap, getPlatformKpis, getPlatformTrend } from '../../services/platformService'
import { daysBetween } from '../../services/reportService'
import { addDaysISO, formatDate, todayISO } from '../../utils/formatters'
import { downloadCsv } from '../../utils/csv'
import PageHeader from '../../components/ui/PageHeader'
import StatCard from '../../components/ui/StatCard'
import Button from '../../components/ui/Button'
import Tabs from '../../components/ui/Tabs'
import BarList from '../../components/charts/BarList'
import LineChart from '../../components/charts/LineChart'
import Heatmap from '../../components/charts/Heatmap'
import { ErrorState, Loader } from '../../components/ui/Feedback'
import { PERIODS, fmtHours, fmtPct, shortDate } from '../reports/reportFilters'
import { ReportSection } from '../reports/reportUi'
import { RANKING_METRICS, TREND_METRICS, metricTone, metricValue, moneyShort, platformTotals } from './platformMetrics'

const PLATFORM_PERIODS = PERIODS.filter((p) => p.key !== 'today')
const HEAT_DAYS = 31
const dayOf = (v) => String(v).slice(0, 10) // columnas date: 'YYYY-MM-DD'

const CSV_COLUMNS = [
  { key: 'company_name', label: 'Empresa' },
  { key: 'company_code', label: 'Código' },
  { label: 'Sucursal', value: (r) => (r.branch_id ? `${r.branch_code} · ${r.branch_name}` : 'Total empresa') },
  { key: 'runs_total', label: 'Checklists programados' },
  { key: 'runs_completed', label: 'Checklists completados' },
  { key: 'runs_on_time', label: 'Checklists a tiempo' },
  { key: 'checklist_pct', label: '% completados' },
  { key: 'checklist_on_time_pct', label: '% a tiempo' },
  { key: 'tasks_late', label: 'Tareas vencidas (hoy)' },
  { key: 'waste_count', label: 'Mermas (registros)' },
  { key: 'waste_qty', label: 'Mermas (cantidad)' },
  { key: 'waste_value', label: 'Mermas ($)' },
  { key: 'counts_total', label: 'Productos contados' },
  { key: 'count_accuracy_pct', label: '% exactitud conteo' },
  { key: 'gaps_open', label: 'Huecos abiertos (hoy)' },
  { key: 'gaps_resolved', label: 'Huecos resueltos' },
  { key: 'gap_hours', label: 'Horas de atención de huecos' },
  { key: 'tickets_open', label: 'Tickets abiertos (hoy)' },
  { key: 'tickets_overdue', label: 'Tickets vencidos (hoy)' },
  { key: 'sla_pct', label: '% tickets dentro de SLA' },
  { key: 'employees_active', label: 'Empleados activos' },
  { key: 'users_7d', label: 'Entraron en 7 días' },
]

export default function PerformancePage() {
  const [period, setPeriod] = useState('30')
  const [range, setRange] = useState(() => ({ from: addDaysISO(todayISO(), -29), to: todayISO() }))
  const { from, to } = useMemo(() => {
    if (period === 'custom') return range
    const days = PERIODS.find((p) => p.key === period).days
    return { from: addDaysISO(todayISO(), -(days - 1)), to: todayISO() }
  }, [period, range])

  const loadKpis = useCallback(() => getPlatformKpis({ from, to }), [from, to])
  const { data: rows, loading, error, reload } = useAsync(loadKpis)
  const companies = useMemo(() => (rows ?? []).filter((r) => !r.branch_id), [rows])
  const branches = useMemo(() => (rows ?? []).filter((r) => r.branch_id), [rows])
  const totals = useMemo(() => platformTotals(companies), [companies])

  const [rankKey, setRankKey] = useState(RANKING_METRICS[0].key)
  const [rankLevel, setRankLevel] = useState('company')
  const rankMetric = RANKING_METRICS.find((m) => m.key === rankKey)
  const ranking = useMemo(() => {
    const list = (rankLevel === 'company' ? companies : branches)
      .map((r) => ({ r, value: metricValue(r, rankKey) }))
      .sort((a, b) => (a.value == null) - (b.value == null)
        || (rankMetric.better === 'up' ? b.value - a.value : a.value - b.value))
    return list.map(({ r, value }) => ({
      key: r.branch_id ?? r.company_id,
      label: r.branch_id ? r.branch_name : r.company_name,
      hint: [r.branch_id && r.company_name, rankMetric.hint(r)].filter(Boolean).join(' · '),
      value,
      tone: metricTone(rankMetric, value),
    }))
  }, [companies, branches, rankLevel, rankKey, rankMetric])

  const [companyId, setCompanyId] = useState('')
  const [trendKey, setTrendKey] = useState(TREND_METRICS[0].key)
  const trendMetric = TREND_METRICS.find((m) => m.key === trendKey)
  const loadTrend = useCallback(() => getPlatformTrend({ companyId, metric: trendKey, from, to }), [companyId, trendKey, from, to])
  const trend = useAsync(loadTrend)

  const heatFrom = from > addDaysISO(to, -(HEAT_DAYS - 1)) ? from : addDaysISO(to, -(HEAT_DAYS - 1))
  const loadHeat = useCallback(() => getChecklistHeatmap({ companyId, from: heatFrom, to }), [companyId, heatFrom, to])
  const heat = useAsync(loadHeat)
  const heatRows = useMemo(() => {
    const seen = new Map()
    ;(heat.data ?? []).forEach((c) => {
      if (!seen.has(c.branch_id)) seen.set(c.branch_id, { key: c.branch_id, label: companyId ? c.branch_name : `${c.company_name} · ${c.branch_name}` })
    })
    return [...seen.values()]
  }, [heat.data, companyId])
  const heatCells = useMemo(() => new Map((heat.data ?? []).map((c) => [`${c.branch_id}|${dayOf(c.day)}`, c])), [heat.data])
  const heatCols = daysBetween(heatFrom, to).map((d) => ({ key: d, label: String(Number(d.slice(8))) }))

  const companyName = companies.find((c) => c.company_id === companyId)?.company_name ?? 'Toda la plataforma'

  const exportAll = () => downloadCsv(`rendimiento-plataforma_${from}_${to}.csv`, rows ?? [], CSV_COLUMNS)

  return (
    <div className="page">
      <PageHeader icon={Activity} title="Rendimiento"
        subtitle="Cómo van las empresas cliente y sus sucursales (solo agregados)"
        actions={<Button size="sm" variant="outline" disabled={!rows?.length} onClick={exportAll}><Download size={14} /> Exportar CSV</Button>} />

      <div className="filters">
        <select className="filter-select" aria-label="Periodo" value={period}
          onChange={(e) => { if (e.target.value === 'custom') setRange({ from, to }); setPeriod(e.target.value) }}>
          {PLATFORM_PERIODS.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}
        </select>
        {period === 'custom' && (<>
          <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => e.target.value && setRange({ ...range, from: e.target.value })} /></label>
          <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => e.target.value && setRange({ ...range, to: e.target.value })} /></label>
        </>)}
      </div>
      <p className="report-period">Del {formatDate(from)} al {formatDate(to)}. Checklists: solo los que ya terminaron su horario. Tareas vencidas, huecos y tickets abiertos y accesos de 7 días son de hoy.</p>

      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !rows ? <Loader text="Calculando rendimiento…" /> : rows && (<>
        <div className="report-kpis">
          <StatCard label="Empresas activas" value={totals.activeCompanies} icon={Globe} tone="blue" hint={`${totals.companies} en total · ${branches.length} sucursales`} />
          <StatCard label="Usuarios que entraron" value={fmtPct(totals.usagePct)} icon={Users} tone="purple" hint={`${totals.users7d} de ${totals.employees} en 7 días`} />
          <StatCard label="Checklists a tiempo" value={fmtPct(totals.onTimePct)} icon={ClipboardCheck} tone="green" hint={`${fmtPct(totals.checklistPct)} completados`} />
          <StatCard label="Tareas vencidas" value={totals.tasksLate} icon={ListTodo} tone="orange" hint="Abiertas con fecha pasada" />
          <StatCard label="Merma" value={moneyShort(totals.wasteValue)} icon={Trash2} tone="red" hint={`${totals.wasteCount} registros`} />
          <StatCard label="Exactitud del conteo" value={fmtPct(totals.accuracyPct)} icon={ScanBarcode} tone="slate" hint="Productos sin diferencia" />
          <StatCard label="Huecos abiertos" value={totals.gapsOpen} icon={PackageSearch} tone="orange" hint={`Atención promedio ${fmtHours(totals.gapHours)}`} />
          <StatCard label="Tickets abiertos" value={totals.ticketsOpen} icon={LifeBuoy} tone="blue" hint={`${fmtPct(totals.slaPct)} dentro de SLA`} />
        </div>

        <div className="report-grid">
          <ReportSection title="Ranking" subtitle={`${rankMetric.label} · ${rankMetric.better === 'up' ? 'mejor arriba' : 'menos es mejor: mejor arriba'}`}
            csv={{ name: `ranking-${rankKey}_${from}_${to}`, rows: ranking, columns: [
              { key: 'label', label: rankLevel === 'company' ? 'Empresa' : 'Sucursal' }, { key: 'hint', label: 'Detalle' }, { key: 'value', label: rankMetric.label }] }}>
            <div className="form-stack">
              <Tabs active={rankLevel} onChange={setRankLevel} tabs={[{ key: 'company', label: 'Empresas' }, { key: 'branch', label: 'Sucursales' }]} />
              <select className="filter-select" aria-label="Métrica del ranking" value={rankKey} onChange={(e) => setRankKey(e.target.value)}>
                {RANKING_METRICS.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
              </select>
              <BarList items={ranking} format={rankMetric.format} max={rankMetric.pct ? 100 : undefined} />
            </div>
          </ReportSection>

          <ReportSection title="Tendencia" subtitle={`${trendMetric.label} · ${companyName}`}
            csv={{ name: `tendencia-${trendKey}_${from}_${to}`, rows: trend.data ?? [], columns: [
              { key: 'day', label: 'Fecha' }, { key: 'value', label: trendMetric.label }, { key: 'base', label: 'Registros' }] }}>
            <div className="form-stack">
              <div className="filters">
                <select className="filter-select" aria-label="Tienda" value={companyId} onChange={(e) => setCompanyId(e.target.value)}>
                  <option value="">Toda la plataforma</option>
                  {companies.map((c) => <option key={c.company_id} value={c.company_id}>{c.company_name}</option>)}
                </select>
                <select className="filter-select" aria-label="Métrica" value={trendKey} onChange={(e) => setTrendKey(e.target.value)}>
                  {TREND_METRICS.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
                </select>
              </div>
              {trend.error ? <ErrorState error={trend.error} onRetry={trend.reload} /> : (
                <LineChart yMax={trendMetric.yMax} format={trendMetric.format}
                  series={[{ key: 'v', label: trendMetric.label, slot: 1 }]}
                  data={(trend.data ?? []).map((d) => ({ x: dayOf(d.day), label: shortDate(dayOf(d.day)), values: { v: d.value == null ? null : Number(d.value) } }))} />
              )}
            </div>
          </ReportSection>

          <ReportSection wide title="Cumplimiento de checklists por sucursal y día"
            subtitle={`% completados · ${companyName} · ${heatFrom === from ? 'todo el periodo' : `últimos ${HEAT_DAYS} días`} (cambia la tienda en Tendencia)`}
            csv={{ name: `checklists-sucursal-dia_${heatFrom}_${to}`, rows: heat.data ?? [], columns: [
              { key: 'company_name', label: 'Empresa' }, { key: 'branch_name', label: 'Sucursal' }, { key: 'day', label: 'Fecha' },
              { key: 'runs_total', label: 'Programados' }, { key: 'pct', label: '% completados' }] }}>
            {heat.error ? <ErrorState error={heat.error} onRetry={heat.reload} /> : (
              <Heatmap rows={heatRows} cols={heatCols} cell={(b, d) => {
                const c = heatCells.get(`${b}|${d}`)
                return c ? { value: c.pct, title: `${c.branch_name} · ${shortDate(d)}: ${c.pct}% de ${c.runs_total}` } : null
              }} />
            )}
          </ReportSection>
        </div>
      </>)}
    </div>
  )
}
