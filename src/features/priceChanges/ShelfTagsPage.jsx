/**
 * ShelfTagsPage — control de cenefas (etiquetas de precio en anaquel, §11.11).
 *
 * Flujo: Pendiente → Impresa → Colocada → Validada   (o Rechazada → reimprimir)
 *   - Selección múltiple para imprimir en lote (abre vista imprimible).
 *   - "Colocada" puede llevar foto como evidencia.
 *   - "Validar" requiere validate_shelf_tags (supervisor/gerente).
 */
import { useCallback, useMemo, useState } from 'react'
import { Check, Printer, RotateCcw, Tags, X } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getShelfTags, updateTagStatus, updateTagsStatus } from '../../services/priceChangeService'
import { TAG_STATUS } from '../../constants/status'
import { formatCurrency, formatDate, formatDateTime } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState } from '../../components/ui/Feedback'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import { printShelfTags } from './printShelfTags'

export default function ShelfTagsPage() {
  const { branchFilter, hasPermission } = useAuth()
  const toast = useToast()
  const canManage = hasPermission(P.MANAGE_SHELF_TAGS)
  const canValidate = hasPermission(P.VALIDATE_SHELF_TAGS)
  const [tab, setTab] = useState('pending')
  const [selectedIds, setSelectedIds] = useState(new Set())
  const [busy, setBusy] = useState(false)

  const load = useCallback(() => getShelfTags({ branchId: branchFilter }), [branchFilter])
  const { data: all = [], loading, error, reload } = useAsync(load)
  const rows = useMemo(() => all.filter((t) => t.status === tab), [all, tab])
  const count = (s) => all.filter((t) => t.status === s).length

  const changeTab = (t) => { setTab(t); setSelectedIds(new Set()) }

  const toggle = (id) => setSelectedIds((prev) => {
    const next = new Set(prev)
    if (next.has(id)) next.delete(id); else next.add(id)
    return next
  })

  const act = async (fn, msg) => {
    setBusy(true)
    try { await fn(); toast.success(msg); setSelectedIds(new Set()); reload() } catch (err) { toast.error(err.message) } finally { setBusy(false) }
  }

  const selectedRows = rows.filter((r) => selectedIds.has(r.id))

  const printSelected = () => {
    printShelfTags(selectedRows.length ? selectedRows : rows)
    if (tab === 'pending' && canManage && window.confirm('¿Marcar estas cenefas como impresas?')) {
      act(() => updateTagsStatus((selectedRows.length ? selectedRows : rows).map((r) => r.id), 'printed'), 'Cenefas marcadas como impresas')
    }
  }

  const reject = (row) => {
    const reason = window.prompt('Motivo del rechazo (precio incorrecto, cenefa dañada, etc.):')
    if (reason) act(() => updateTagStatus(row.id, 'rejected', reason), 'Cenefa rechazada')
  }

  const columns = [
    ...(tab === 'pending' || tab === 'printed' ? [{
      key: 'select', label: '', width: 32,
      render: (_, r) => <input type="checkbox" checked={selectedIds.has(r.id)} onChange={() => toggle(r.id)} onClick={(e) => e.stopPropagation()} />,
    }] : []),
    { key: 'product_name', label: 'Producto', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.sku}</div></> },
    { key: 'department_name', label: 'Departamento', sortable: true },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
    { key: 'new_price', label: 'Precio cenefa', align: 'right', render: (v, r) => (<>
      <strong>{formatCurrency(v ?? r.current_price)}</strong>
      {r.old_price && <div className="cell-sub td-strikethrough">{formatCurrency(r.old_price)}</div>}
    </>) },
    { key: 'effective_date', label: 'Efectivo', render: formatDate },
    { key: 'created_at', label: 'Generada', sortable: true, render: formatDateTime },
    { key: 'status', label: 'Estado', render: (v, r) => (<>
      <StatusBadge statusMap={TAG_STATUS} value={v} />
      {r.rejection_reason && v === 'rejected' && <div className="cell-sub">{r.rejection_reason}</div>}
      {v === 'validated' && <div className="cell-sub">{r.validated_by_name}</div>}
    </>) },
    { key: 'actions', label: 'Acciones', render: (_, r) => (
      <div className="row-actions">
        {canManage && r.status === 'printed' && (<>
          <EvidenceUploader entityType="shelf_tag" entityId={r.id} branchId={r.branch_id} label="Foto" variant="ghost" />
          <Button size="sm" variant="outline" disabled={busy} onClick={() => act(() => updateTagStatus(r.id, 'placed'), 'Cenefa colocada')}>
            <Check size={14} /> Colocada
          </Button>
        </>)}
        {canValidate && r.status === 'placed' && (
          <Button size="sm" variant="success" disabled={busy} onClick={() => act(() => updateTagStatus(r.id, 'validated'), 'Cenefa validada')}>
            <Check size={14} /> Validar
          </Button>
        )}
        {(canManage || canValidate) && ['pending', 'printed', 'placed'].includes(r.status) && (
          <button className="icon-btn icon-btn-danger" title="Rechazar" onClick={() => reject(r)}><X size={14} /></button>
        )}
        {canManage && r.status === 'rejected' && (
          <Button size="sm" variant="ghost" disabled={busy} onClick={() => act(() => updateTagStatus(r.id, 'pending'), 'Cenefa enviada a reimpresión')}>
            <RotateCcw size={14} /> Reimprimir
          </Button>
        )}
      </div>
    ) },
  ]

  return (
    <div className="page">
      <PageHeader icon={Tags} title="Cenefas" subtitle="Impresión, colocación y validación de etiquetas de precio"
        actions={(tab === 'pending' || tab === 'printed') && rows.length > 0 && (
          <Button size="sm" variant="outline" onClick={printSelected}>
            <Printer size={14} /> Imprimir {selectedRows.length ? `(${selectedRows.length})` : 'todas'}
          </Button>
        )} />
      <Tabs active={tab} onChange={changeTab} tabs={[
        { key: 'pending', label: 'Pendientes', count: count('pending') },
        { key: 'printed', label: 'Impresas', count: count('printed') },
        { key: 'placed', label: 'Colocadas', count: count('placed') },
        { key: 'validated', label: 'Validadas' },
        { key: 'rejected', label: 'Rechazadas', count: count('rejected') },
      ]} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush><Table columns={columns} data={rows} loading={loading} emptyText="Sin cenefas en este estado" /></Card>
    </div>
  )
}
