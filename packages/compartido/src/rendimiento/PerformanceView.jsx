/**
 * PerformanceView — tablero de rendimiento en cascada (migraciones 0025 y 0027).
 * Lo usan la Consola (scope="platform") y la app de tiendas (scope="company");
 * cada app le pasa en «source» de dónde salen los datos.
 *   scope="platform": Plataforma → Rendimiento (superadmin). Empresas y sus
 *                     sucursales; clic en una empresa → sus sucursales (?empresa=).
 *   scope="company":  Análisis → Rendimiento de sucursales. Las sucursales de
 *                     su empresa que quien consulta puede ver (propietario y
 *                     administradores: todas; jefe de zona: sus zonas; gerente: la suya).
 * Totales, ranking por métrica, tendencia diaria y mapa de calor de
 * checklists. Todo sale de funciones SQL que devuelven solo agregados.
 */
import { useCallback, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Activity, Building2, ClipboardCheck, Download, Globe, ListTodo, LifeBuoy, PackageSearch, ScanBarcode, Trash2, Users } from 'lucide-react'
import { useAsync } from '../hooks/useAsync'
import FilterChip from '../components/ui/FilterChip'
import { addDaysISO, daysBetween, formatDate, todayISO } from '../utils/formatters'
import { downloadCsv } from '../utils/csv'
import PageHeader from '../components/ui/PageHeader'
import StatCard from '../components/ui/StatCard'
import Button from '../components/ui/Button'
import Tabs from '../components/ui/Tabs'
import BarList from '../components/charts/BarList'
import LineChart from '../components/charts/LineChart'
import Heatmap from '../components/charts/Heatmap'
import { ErrorState, Loader } from '../components/ui/Feedback'
import { PERIODS, fmtHours, fmtPct, shortDate } from '../reports/reportFormat.js'
import { ReportSection } from '../reports/reportUi'
import { RANKING_METRICS, TREND_METRICS, metricTone, metricValue, moneyShort, platformTotals } from './platformMetrics'

const PLATFORM_PERIODS = PERIODS.filter((p) => p.key !== 'today')
const HEAT_DAYS = 31
const dayOf = (v) => String(v).slice(0, 10) // columnas date: 'YYYY-MM-DD'

/**
 * source: { subtitle, csvName, kpis({from,to}), trend({sel,metric,from,to}), heat({sel,from,to}) }
 * «sel» es la empresa (platform) o la sucursal (company) elegida.
 */

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

export default function PerformanceView({ scope = 'platform', source: cfg, companyName = '' }) {
  const isPlatform = scope === 'platform'
  const [params, setParams] = useSearchParams()
  const [period, setPeriod] = useState('30')
  const [range, setRange] = useState(() => ({ from: addDaysISO(todayISO(), -29), to: todayISO() }))
  const { from, to } = useMemo(() => {
    if (period === 'custom') return range
    const days = PERIODS.find((p) => p.key === period).days
    return { from: addDaysISO(todayISO(), -(days - 1)), to: todayISO() }
  }, [period, range])

  const loadKpis = useCallback(() => cfg.kpis({ from, to }), [cfg, from, to])
  const { data: rows, loading, error, reload } = useAsync(loadKpis)
  const companies = useMemo(() => (rows ?? []).filter((r) => !r.branch_id), [rows])
  const branches = useMemo(() => (rows ?? []).filter((r) => r.branch_id), [rows])

  // Selección en cascada: en plataforma, una empresa (?empresa=); en una empresa, una sucursal (?sucursal=).
  const selKey = isPlatform ? 'empresa' : 'sucursal'
  const sel = params.get(selKey) ?? ''
  const setSel = (id) => setParams(id ? { [selKey]: id } : {}, { replace: true })
  const selName = isPlatform
    ? companies.find((c) => c.company_id === sel)?.company_name
    : branches.find((b) => b.branch_id === sel)?.branch_name
  const allLabel = isPlatform ? 'Toda la plataforma' : 'Todas mis sucursales'
  const scopeName = selName ?? allLabel

  // Totales: plataforma completa, la empresa elegida, todas mis sucursales o la sucursal elegida.
  const totals = useMemo(() => platformTotals(
    isPlatform ? (sel ? companies.filter((c) => c.company_id === sel) : companies)
      : (sel ? branches.filter((b) => b.branch_id === sel) : companies)), [isPlatform, sel, companies, branches])

  const [rankKey, setRankKey] = useState(RANKING_METRICS[0].key)
  const [rankTab, setRankTab] = useState('company')
  const rankLevel = isPlatform && !sel ? rankTab : 'branch'
  const rankMetric = RANKING_METRICS.find((m) => m.key === rankKey)
  const ranking = useMemo(() => {
    const list = (rankLevel === 'company' ? companies : branches.filter((b) => !isPlatform || !sel || b.company_id === sel))
      .map((r) => ({ r, value: metricValue(r, rankKey) }))
      .sort((a, b) => (a.value == null) - (b.value == null)
        || (rankMetric.better === 'up' ? b.value - a.value : a.value - b.value))
    return list.map(({ r, value }) => ({
      key: r.branch_id ?? r.company_id,
      label: r.branch_id ? r.branch_name : r.company_name,
      hint: [isPlatform && !sel && r.branch_id && r.company_name, rankMetric.hint(r)].filter(Boolean).join(' · '),
      value,
      tone: metricTone(rankMetric, value),
      // Cascada: clic en una empresa → sus sucursales.
      to: isPlatform && !r.branch_id ? `?empresa=${r.company_id}` : undefined,
    }))
  }, [companies, branches, rankLevel, rankKey, rankMetric, isPlatform, sel])

  const [trendKey, setTrendKey] = useState(TREND_METRICS[0].key)
  const trendMetric = TREND_METRICS.find((m) => m.key === trendKey)
  const loadTrend = useCallback(() => cfg.trend({ sel, metric: trendKey, from, to }), [cfg, sel, trendKey, from, to])
  const trend = useAsync(loadTrend)

  const heatFrom = from > addDaysISO(to, -(HEAT_DAYS - 1)) ? from : addDaysISO(to, -(HEAT_DAYS - 1))
  const loadHeat = useCallback(() => cfg.heat({ sel, from: heatFrom, to }), [cfg, sel, heatFrom, to])
  const heat = useAsync(loadHeat)
  const heatData = useMemo(() => (heat.data ?? []).filter((c) => isPlatform || !sel || c.branch_id === sel), [heat.data, isPlatform, sel])
  const heatRows = useMemo(() => {
    const seen = new Map()
    heatData.forEach((c) => {
      if (!seen.has(c.branch_id)) seen.set(c.branch_id, { key: c.branch_id, label: !isPlatform || sel ? c.branch_name : `${c.company_name} · ${c.branch_name}` })
    })
    return [...seen.values()]
  }, [heatData, isPlatform, sel])
  const heatCells = useMemo(() => new Map(heatData.map((c) => [`${c.branch_id}|${dayOf(c.day)}`, c])), [heatData])
  const heatCols = daysBetween(heatFrom, to).map((d) => ({ key: d, label: String(Number(d.slice(8))) }))

  const exportAll = () => downloadCsv(`${cfg.csvName}_${from}_${to}.csv`, rows ?? [], CSV_COLUMNS)

  return (
    <div className="page">
      <PageHeader icon={Activity} title={isPlatform ? 'Rendimiento' : 'Rendimiento de sucursales'}
        subtitle={isPlatform ? cfg.subtitle : `${cfg.subtitle} · ${companyName}`}
        actions={<Button size="sm" variant="outline" disabled={!rows?.length} onClick={exportAll}><Download size={14} /> Exportar CSV</Button>} />

      <div className="filters">
        <select className="filter-select" aria-label="Periodo" value={period}
          onChange={(e) => { if (e.target.value === 'custom') setRange({ from, to }); setPeriod(e.target.value) }}>
          {PLATFORM_PERIODS.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}
        </select>
        <select className="filter-select" aria-label={isPlatform ? 'Tienda' : 'Sucursal'} value={sel} onChange={(e) => setSel(e.target.value)}>
          <option value="">{allLabel}</option>
          {(isPlatform ? companies : branches).map((r) => (
            <option key={r.branch_id ?? r.company_id} value={r.branch_id ?? r.company_id}>{r.branch_id ? r.branch_name : r.company_name}</option>
          ))}
        </select>
        {sel && <FilterChip label={scopeName} onClear={() => setSel('')} />}
        {period === 'custom' && (<>
          <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => e.target.value && setRange({ ...range, from: e.target.value })} /></label>
          <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => e.target.value && setRange({ ...range, to: e.target.value })} /></label>
        </>)}
      </div>
      <p className="report-period">Del {formatDate(from)} al {formatDate(to)}. Checklists: solo los que ya terminaron su horario. Tareas vencidas, huecos y tickets abiertos y accesos de 7 días son de hoy.</p>

      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !rows ? <Loader text="Calculando rendimiento…" /> : rows && (<>
        <div className="report-kpis">
          {isPlatform && !sel
            ? <StatCard label="Empresas activas" value={totals.activeCompanies} icon={Globe} tone="blue" hint={`${totals.companies} en total · ${branches.length} sucursales`} />
            : <StatCard label={isPlatform ? 'Sucursales de la empresa' : 'Sucursales'} icon={Building2} tone="blue"
                value={isPlatform ? branches.filter((b) => b.company_id === sel).length : (sel ? 1 : branches.length)} hint={scopeName} />}
          <StatCard label="Usuarios que entraron" value={fmtPct(totals.usagePct)} icon={Users} tone="purple" hint={`${totals.users7d} de ${totals.employees} en 7 días`} />
          <StatCard label="Checklists a tiempo" value={fmtPct(totals.onTimePct)} icon={ClipboardCheck} tone="green" hint={`${fmtPct(totals.checklistPct)} completados`} />
          <StatCard label="Tareas vencidas" value={totals.tasksLate} icon={ListTodo} tone="orange" hint="Abiertas con fecha pasada" />
          <StatCard label="Merma" value={moneyShort(totals.wasteValue)} icon={Trash2} tone="red" hint={`${totals.wasteCount} registros`} />
          <StatCard label="Exactitud del conteo" value={fmtPct(totals.accuracyPct)} icon={ScanBarcode} tone="slate" hint="Productos sin diferencia" />
          <StatCard label="Huecos abiertos" value={totals.gapsOpen} icon={PackageSearch} tone="orange" hint={`Atención promedio ${fmtHours(totals.gapHours)}`} />
          <StatCard label="Tickets abiertos" value={totals.ticketsOpen} icon={LifeBuoy} tone="blue" hint={`${fmtPct(totals.slaPct)} dentro de SLA`} />
        </div>

        <div className="report-grid">
          <ReportSection title={rankLevel === 'company' ? 'Ranking de empresas' : `Ranking de sucursales${isPlatform && sel ? ` · ${scopeName}` : ''}`}
            subtitle={`${rankMetric.label} · ${rankMetric.better === 'up' ? 'mejor arriba' : 'menos es mejor: mejor arriba'}${rankLevel === 'company' ? ' · clic en una empresa para ver sus sucursales' : ''}`}
            csv={{ name: `ranking-${rankKey}_${from}_${to}`, rows: ranking, columns: [
              { key: 'label', label: rankLevel === 'company' ? 'Empresa' : 'Sucursal' }, { key: 'hint', label: 'Detalle' }, { key: 'value', label: rankMetric.label }] }}>
            <div className="form-stack">
              {isPlatform && !sel && <Tabs active={rankTab} onChange={setRankTab} tabs={[{ key: 'company', label: 'Empresas' }, { key: 'branch', label: 'Sucursales' }]} />}
              <select className="filter-select" aria-label="Métrica del ranking" value={rankKey} onChange={(e) => setRankKey(e.target.value)}>
                {RANKING_METRICS.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
              </select>
              <BarList items={ranking} format={rankMetric.format} max={rankMetric.pct ? 100 : undefined} />
            </div>
          </ReportSection>

          <ReportSection title="Tendencia" subtitle={`${trendMetric.label} · ${scopeName}`}
            csv={{ name: `tendencia-${trendKey}_${from}_${to}`, rows: trend.data ?? [], columns: [
              { key: 'day', label: 'Fecha' }, { key: 'value', label: trendMetric.label }, { key: 'base', label: 'Registros' }] }}>
            <div className="form-stack">
              <select className="filter-select" aria-label="Métrica" value={trendKey} onChange={(e) => setTrendKey(e.target.value)}>
                {TREND_METRICS.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
              </select>
              {trend.error ? <ErrorState error={trend.error} onRetry={trend.reload} /> : (
                <LineChart yMax={trendMetric.yMax} format={trendMetric.format}
                  series={[{ key: 'v', label: trendMetric.label, slot: 1 }]}
                  data={(trend.data ?? []).map((d) => ({ x: dayOf(d.day), label: shortDate(dayOf(d.day)), values: { v: d.value == null ? null : Number(d.value) } }))} />
              )}
            </div>
          </ReportSection>

          <ReportSection wide title="Cumplimiento de checklists por sucursal y día"
            subtitle={`% completados · ${scopeName} · ${heatFrom === from ? 'todo el periodo' : `últimos ${HEAT_DAYS} días`}`}
            csv={{ name: `checklists-sucursal-dia_${heatFrom}_${to}`, rows: heatData, columns: [
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
