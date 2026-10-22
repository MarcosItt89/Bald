/**
 * ReportsPage — Estadísticas operativas (/reports, permiso view_reports).
 *
 * Filtros en la URL: zona y sucursal (mismo alcance que BranchSwitcher: el gerente
 * solo ve la suya; el jefe de zona, las de sus zonas), departamento, periodo y
 * comparación con el periodo anterior. Zona sin sucursal = todas las de la zona.
 * Cada pestaña se muestra solo si el usuario tiene permiso del módulo y carga
 * sus propios datos (reportService: una función por pestaña).
 */
import { useCallback, useMemo } from 'react'
import { BarChart3, Building2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { P } from '../../config/permissions'
import { getDepartments, getMyBranches, getZones } from '../../services/organizationService'
import { formatDate } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Tabs from '../../components/ui/Tabs'
import { PERIODS, useReportFilters } from './reportFilters'
import SummaryTab from './tabs/SummaryTab'
import ChecklistsTab from './tabs/ChecklistsTab'
import TemperaturesTab from './tabs/TemperaturesTab'
import TasksTab from './tabs/TasksTab'
import InventoryTab from './tabs/InventoryTab'
import ReceivingTab from './tabs/ReceivingTab'
import SupportTab from './tabs/SupportTab'

const TABS = [
  { key: 'summary', label: 'Resumen', Component: SummaryTab },
  { key: 'checklists', label: 'Checklists', Component: ChecklistsTab, anyOf: [P.FILL_CHECKLISTS, P.REVIEW_CHECKLISTS] },
  { key: 'temperatures', label: 'Temperaturas', Component: TemperaturesTab, anyOf: [P.FILL_CHECKLISTS, P.REVIEW_CHECKLISTS] },
  { key: 'tasks', label: 'Tareas', Component: TasksTab, anyOf: [P.VIEW_TASKS, P.MANAGE_TASKS] },
  { key: 'inventory', label: 'Inventario', Component: InventoryTab, anyOf: [P.VIEW_INVENTORY] },
  { key: 'receiving', label: 'Recibo y precios', Component: ReceivingTab, anyOf: [P.RECEIVE_PRODUCTS, P.MANAGE_PRICE_CHANGES, P.MANAGE_SHELF_TAGS, P.VALIDATE_SHELF_TAGS] },
  { key: 'support', label: 'Soporte', Component: SupportTab, anyOf: [P.CREATE_TICKETS, P.MANAGE_TICKETS] },
]

export default function ReportsPage() {
  const { hasAny, isCompanyScope, isZoneScope, isMultiBranch, zoneIds, profile } = useAuth()
  const { filters, setFilter } = useReportFilters()
  const zoneKey = zoneIds.join(',')
  const loadBranches = useCallback(
    () => getMyBranches({ isCompanyScope, isZoneScope, zoneIds: zoneKey ? zoneKey.split(',') : [] }),
    [isCompanyScope, isZoneScope, zoneKey],
  )
  const { data: branches = [] } = useAsync(loadBranches)
  const loadZones = useCallback(async () => {
    if (!isMultiBranch) return []
    const all = await getZones({ onlyActive: true })
    return isZoneScope ? all.filter((z) => zoneKey.split(',').includes(z.id)) : all
  }, [isMultiBranch, isZoneScope, zoneKey])
  const { data: zones = [] } = useAsync(loadZones)
  const loadDepartments = useCallback(() => getDepartments({ onlyActive: true }), [])
  const { data: departments = [] } = useAsync(loadDepartments)

  const tabs = TABS.filter((t) => !t.anyOf || hasAny(t.anyOf))
  const current = tabs.find((t) => t.key === filters.tab) ?? tabs[0]
  const deptName = departments.find((d) => d.id === filters.deptId)?.name ?? null

  const { branchId: selectedBranch, zoneId, deptId, from, to, prevFrom, prevTo, compare } = filters
  const zoneBranches = zoneId ? branches.filter((b) => b.zone_id === zoneId) : branches
  const zoneBranchKey = zoneId ? zoneBranches.map((b) => b.id).join(',') : ''
  const query = useMemo(() => ({
    // Zona elegida y «todas»: la consulta se limita a las sucursales de esa zona.
    branchId: selectedBranch ?? (zoneId ? zoneBranchKey.split(',').filter(Boolean) : null),
    deptId, deptName, from, to, prevFrom, prevTo, compare,
  }), [selectedBranch, zoneId, zoneBranchKey, deptId, deptName, from, to, prevFrom, prevTo, compare])

  return (
    <div className="page">
      <PageHeader icon={BarChart3} title="Estadísticas" subtitle="Indicadores operativos por sucursal, departamento y periodo" />

      <div className="report-filters">
        {isMultiBranch && zones.length > 0 && (
          <select className="filter-select" aria-label="Zona" value={zoneId ?? ''} onChange={(e) => setFilter({ zone: e.target.value, branch: 'all' })}>
            <option value="">{isZoneScope ? 'Todas mis zonas' : 'Todas las zonas'}</option>
            {zones.map((z) => <option key={z.id} value={z.id}>Zona {z.name}</option>)}
          </select>
        )}
        {isMultiBranch ? (
          <select className="filter-select" aria-label="Sucursal" value={selectedBranch ?? 'all'} onChange={(e) => setFilter({ branch: e.target.value })}>
            <option value="all">{zoneId ? 'Todas las sucursales de la zona' : isZoneScope ? 'Todas mis sucursales' : 'Todas las sucursales'}</option>
            {zoneBranches.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
          </select>
        ) : (
          <span className="topbar-branch"><Building2 size={14} /> {profile?.branch_name ?? 'Sin sucursal'}</span>
        )}
        <select className="filter-select" aria-label="Departamento" value={deptId ?? ''} onChange={(e) => setFilter({ dept: e.target.value })}>
          <option value="">Todos los departamentos</option>
          {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="filter-select" aria-label="Periodo" value={filters.period}
          onChange={(e) => setFilter(e.target.value === 'custom' ? { p: 'custom', from, to } : { p: e.target.value, from: null, to: null })}>
          {PERIODS.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}
        </select>
        {filters.period === 'custom' && (<>
          <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => e.target.value && setFilter({ from: e.target.value })} /></label>
          <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => e.target.value && setFilter({ to: e.target.value })} /></label>
        </>)}
        <label className="checkbox">
          <input type="checkbox" checked={compare} onChange={(e) => setFilter({ cmp: e.target.checked ? null : '0' })} /> Comparar con periodo anterior
        </label>
      </div>
      <p className="report-period">
        Del {formatDate(from)} al {formatDate(to)}
        {compare && ` · comparado con ${formatDate(prevFrom)} – ${formatDate(prevTo)}`}
      </p>

      <Tabs active={current.key} onChange={(key) => setFilter({ tab: key === 'summary' ? null : key })}
        tabs={tabs.map(({ key, label }) => ({ key, label }))} />
      <current.Component filters={query} />
    </div>
  )
}
