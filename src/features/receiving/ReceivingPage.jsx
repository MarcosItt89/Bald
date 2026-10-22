/**
 * ReceivingPage — lista de recibos de mercancía (Objetivos §11.5).
 *
 * "Nuevo recibo" crea el encabezado (proveedor, factura/remisión y, si el
 * proveedor ya registró entrada en caseta, se liga su visita) y abre el
 * detalle para capturar productos.
 */
import { useCallback, useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Plus, Truck } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getReceivingOrders, createReceivingOrder } from '../../services/receivingService'
import { getSuppliers, getVisits } from '../../services/supplierService'
import { RECEIVING_STATUS } from '../../constants/status'
import { formatDateTime, formatNumber } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import Input, { Textarea } from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'
import FilterChip from '../../components/ui/FilterChip'

export default function ReceivingPage() {
  const { branchFilter } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [tab, setTab] = useState(() => params.get('tab') ?? 'in_progress')
  const [supplierId, setSupplierId] = useState(() => params.get('supplier') ?? '')
  const [diff, setDiff] = useState(() => params.get('diff') ?? '')
  const [creating, setCreating] = useState(false)

  const load = useCallback(
    () => getReceivingOrders({ branchId: branchFilter, status: tab === 'all' ? undefined : tab }),
    [branchFilter, tab],
  )
  const { data: all = [], loading, error, reload } = useAsync(load)
  const rows = useMemo(() => all.filter((r) => (!supplierId || r.supplier_id === supplierId)
    && (diff === '' || r.has_differences === (diff === '1'))), [all, supplierId, diff])

  const columns = [
    { key: 'folio', label: 'Folio', mono: true, sortable: true },
    { key: 'supplier_name', label: 'Proveedor', bold: true, sortable: true,
      render: (v, r) => <>{v}<div className="cell-sub">{r.supplier_code}</div></> },
    { key: 'invoice_number', label: 'Factura / remisión' },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
    { key: 'created_at', label: 'Inicio', sortable: true, render: formatDateTime },
    { key: 'items_count', label: 'Productos', align: 'right' },
    { key: 'total_received', label: 'Recibido', align: 'right', render: (v, r) => (r.status === 'completed' ? formatNumber(v, 3) : '—') },
    { key: 'received_by_name', label: 'Capturó' },
    { key: 'status', label: 'Estado', render: (v, r) => (<>
      <StatusBadge statusMap={RECEIVING_STATUS} value={v} />
      {r.has_differences && <Badge color="danger" className="ml-1">Con diferencias</Badge>}
    </>) },
  ]

  return (
    <div className="page">
      <PageHeader icon={Truck} title="Recibo de mercancía" subtitle="Entrada de producto de proveedores"
        actions={<Button size="sm" onClick={() => setCreating(true)}><Plus size={14} /> Nuevo recibo</Button>} />

      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'in_progress', label: 'En captura' },
        { key: 'completed', label: 'Cerrados' },
        { key: 'cancelled', label: 'Cancelados' },
        { key: 'all', label: 'Todos' },
      ]} />
      {(supplierId || diff) && (
        <div className="filters">
          {supplierId && <FilterChip label={`Proveedor: ${all.find((r) => r.supplier_id === supplierId)?.supplier_name ?? 'seleccionado'}`} onClear={() => setSupplierId('')} />}
          {diff && <FilterChip label={diff === '1' ? 'Con diferencias' : 'Sin diferencias'} onClear={() => setDiff('')} />}
        </div>
      )}

      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table columns={columns} data={rows} loading={loading} onRowClick={(r) => navigate(`/receiving/${r.id}`)}
          emptyText={tab === 'in_progress' ? 'No hay recibos en captura' : 'Sin recibos'} />
      </Card>

      {creating && <NewReceivingModal onClose={() => setCreating(false)}
        onCreated={(order) => navigate(`/receiving/${order.id}`)} />}
    </div>
  )
}

function NewReceivingModal({ onClose, onCreated }) {
  const { workingBranchId } = useAuth()
  const toast = useToast()
  const [form, setForm] = useState({ supplier_id: '', visit_id: '', invoice_number: '', notes: '' })
  const [saving, setSaving] = useState(false)

  const loadSuppliers = useCallback(() => getSuppliers({ status: 'active' }), [])
  const { data: suppliers = [] } = useAsync(loadSuppliers)
  const loadVisits = useCallback(
    () => getVisits({ branchId: workingBranchId, onlyOpen: true }),
    [workingBranchId],
  )
  const { data: visits = [] } = useAsync(loadVisits)
  const supplierVisits = visits.filter((v) => v.supplier_id === form.supplier_id)

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const order = await createReceivingOrder({ ...form, branch_id: workingBranchId })
      toast.success(`Recibo ${order.folio} creado`)
      onCreated(order)
    } catch (err) {
      toast.error(err.message)
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title="Nuevo recibo"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="receiving-form" loading={saving}>Crear y capturar productos</Button>
      </>}>
      <form id="receiving-form" className="form-stack" onSubmit={submit}>
        <Select label="Proveedor" required value={form.supplier_id} placeholder="Selecciona…"
          onChange={(e) => setForm({ ...form, supplier_id: e.target.value, visit_id: '' })}
          options={suppliers.map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }))} />
        {supplierVisits.length > 0 && (
          <Select label="Visita registrada en caseta" value={form.visit_id} placeholder="No ligar"
            onChange={(e) => setForm({ ...form, visit_id: e.target.value })}
            options={supplierVisits.map((v) => ({ value: v.id, label: `Entrada ${formatDateTime(v.check_in_at)} · ${v.driver_name ?? 'sin chofer'}` }))} />
        )}
        <Input label="Factura o remisión" value={form.invoice_number}
          onChange={(e) => setForm({ ...form, invoice_number: e.target.value })} />
        <Textarea label="Notas" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
      </form>
    </Modal>
  )
}
