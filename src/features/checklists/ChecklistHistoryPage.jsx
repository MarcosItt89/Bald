/**
 * ChecklistHistoryPage — historial de checklists completados y vencidos.
 * Muestra fecha, quién completó, revisión y permite abrir el detalle
 * (respuestas + evidencias) en el mismo modal de ejecución.
 * Acepta filtros por URL (desde Estadísticas): ?from=&to=&status=all|completed|overdue|cancelled&dept=&shift=&template=
 */
import { useCallback, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Download, History } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { getRuns } from '../../services/checklistService'
import { CHECKLIST_REVIEW_STATUS, CHECKLIST_RUN_STATUS, SHIFTS } from '../../constants/status'
import { addDaysISO, formatDate, formatDateTime, todayISO } from '../../utils/formatters'
import { downloadCsv } from '../../utils/csv'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Badge from '../../components/ui/Badge'
import { ErrorState } from '../../components/ui/Feedback'
import FilterChip from '../../components/ui/FilterChip'
import ChecklistRunModal from './ChecklistRunModal'

export default function ChecklistHistoryPage() {
  const { branchFilter } = useAuth()
  const [params] = useSearchParams()
  const [from, setFrom] = useState(() => params.get('from') ?? addDaysISO(todayISO(), -7))
  const [to, setTo] = useState(() => params.get('to') ?? todayISO())
  const [status, setStatus] = useState(() => (params.get('status') === 'all' ? '' : params.get('status') ?? 'completed'))
  const [departmentId, setDepartmentId] = useState(() => params.get('dept') ?? '')
  const [shift, setShift] = useState(() => params.get('shift') ?? '')
  const [templateId, setTemplateId] = useState(() => params.get('template') ?? '')
  const [openId, setOpenId] = useState(null)

  const load = useCallback(
    () => getRuns({ branchId: branchFilter, from, to, status: status || undefined, departmentId: departmentId || undefined, shift: shift || undefined, templateId: templateId || undefined }),
    [branchFilter, from, to, status, departmentId, shift, templateId],
  )
  const { data: rows = [], loading, error, reload } = useAsync(load)

  const exportCsv = () => downloadCsv(`checklists_${from}_${to}.csv`, rows, [
    { key: 'scheduled_date', label: 'Fecha' }, { key: 'title', label: 'Checklist' },
    { key: 'department_name', label: 'Departamento' }, { key: 'branch_name', label: 'Sucursal' },
    { label: 'Estado', value: (r) => CHECKLIST_RUN_STATUS[r.status]?.label },
    { key: 'completed_by_name', label: 'Completó' }, { key: 'completed_at', label: 'Hora' },
    { label: 'Revisión', value: (r) => CHECKLIST_REVIEW_STATUS[r.review_status]?.label ?? '' },
    { key: 'evidence_count', label: 'Evidencias' },
  ])

  return (
    <div className="page">
      <PageHeader icon={History} title="Historial de checklists" subtitle={`${rows.length} registros`}
        actions={<Button variant="outline" size="sm" onClick={exportCsv} disabled={!rows.length}><Download size={14} /> CSV</Button>} />
      <div className="filters">
        <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} /></label>
        <select className="filter-select" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="completed">Completados</option>
          <option value="overdue">Vencidos</option>
          <option value="cancelled">Cancelados</option>
          <option value="">Todos</option>
        </select>
        {departmentId && <FilterChip label={`Departamento: ${rows[0]?.department_name ?? 'seleccionado'}`} onClear={() => setDepartmentId('')} />}
        {shift && <FilterChip label={`Turno: ${SHIFTS[shift] ?? shift}`} onClear={() => setShift('')} />}
        {templateId && <FilterChip label={`Checklist: ${rows[0]?.title ?? 'seleccionado'}`} onClear={() => setTemplateId('')} />}
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={(r) => setOpenId(r.id)} emptyText="Sin registros en el periodo" columns={[
          { key: 'scheduled_date', label: 'Fecha', sortable: true, render: formatDate },
          { key: 'title', label: 'Checklist', bold: true, sortable: true },
          { key: 'department_name', label: 'Departamento', sortable: true },
          ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
          { key: 'completed_by_name', label: 'Completó', render: (v, r) => (v ? <>{v}<div className="cell-sub">{formatDateTime(r.completed_at)}</div></> : '—') },
          { key: 'evidence_count', label: 'Evidencias', align: 'center', render: (v, r) => (Number(v) > 0
            ? <Badge color="info">📷 {v}</Badge>
            : <span className={r.requires_evidence ? 'td-danger' : 'text-muted'}>{r.requires_evidence ? 'Faltante' : '—'}</span>) },
          { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={CHECKLIST_RUN_STATUS} value={v} /> },
          { key: 'review_status', label: 'Revisión', render: (v) => <StatusBadge statusMap={CHECKLIST_REVIEW_STATUS} value={v} /> },
        ]} />
      </Card>
      {openId && <ChecklistRunModal runId={openId} onClose={() => setOpenId(null)} onChanged={reload} />}
    </div>
  )
}
