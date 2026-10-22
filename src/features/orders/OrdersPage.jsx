/**
 * OrdersPage — pedidos internos de mercancía o insumos (Objetivos §11.9).
 *
 * Flujo: Solicitado → En revisión → Aprobado/Rechazado → Enviado → Recibido → Cerrado
 * - Quien tiene create_orders solicita y da seguimiento a sus pedidos.
 * - Quien tiene approve_orders revisa, aprueba/rechaza y marca enviado.
 * Los botones visibles salen de ORDER_TRANSITIONS; la BD revalida cada paso
 * y notifica al solicitante en cada cambio.
 */
import { useCallback, useMemo, useState } from 'react'
import { Plus, ShoppingCart } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { P } from '../../config/permissions'
import { getOrders } from '../../services/orderService'
import { ORDER_STATUS, PRIORITY } from '../../constants/status'
import { formatDateTime, formatNumber } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState } from '../../components/ui/Feedback'
import NewOrderModal from './NewOrderModal'
import OrderDetailModal from './OrderDetailModal'

const GROUPS = {
  open:     ['requested', 'in_review', 'approved', 'sent'],
  received: ['received'],
  closed:   ['closed', 'rejected', 'cancelled'],
}

export default function OrdersPage() {
  const { branchFilter, hasPermission, profile } = useAuth()
  const [tab, setTab] = useState('open')
  const [creating, setCreating] = useState(false)
  const [selected, setSelected] = useState(null)

  const load = useCallback(() => getOrders({ branchId: branchFilter }), [branchFilter])
  const { data: all = [], loading, error, reload } = useAsync(load)

  const rows = useMemo(() => (tab === 'all' ? all : all.filter((o) => GROUPS[tab].includes(o.status))), [all, tab])
  const count = (g) => all.filter((o) => GROUPS[g].includes(o.status)).length

  const columns = [
    { key: 'folio', label: 'Folio', mono: true, sortable: true },
    { key: 'title', label: 'Pedido', bold: true, sortable: true,
      render: (v, r) => <>{v}{r.requested_by === profile.id && <div className="cell-sub">Solicitado por ti</div>}</> },
    { key: 'department_name', label: 'Departamento', sortable: true },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
    { key: 'requested_by_name', label: 'Solicitó' },
    { key: 'created_at', label: 'Fecha', sortable: true, render: formatDateTime },
    { key: 'items_count', label: 'Productos', align: 'right',
      render: (v, r) => `${v} (${formatNumber(r.total_quantity, 2)} u.)` },
    { key: 'priority', label: 'Prioridad', render: (v) => <StatusBadge statusMap={PRIORITY} value={v} /> },
    { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={ORDER_STATUS} value={v} /> },
  ]

  return (
    <div className="page">
      <PageHeader icon={ShoppingCart} title="Pedidos internos" subtitle="Solicitud y surtido de mercancía entre áreas"
        actions={hasPermission(P.CREATE_ORDERS) && <Button size="sm" onClick={() => setCreating(true)}><Plus size={14} /> Nuevo pedido</Button>} />

      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'open', label: 'En curso', count: count('open') },
        { key: 'received', label: 'Recibidos', count: count('received') },
        { key: 'closed', label: 'Cerrados / rechazados' },
        { key: 'all', label: 'Todos' },
      ]} />

      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table columns={columns} data={rows} loading={loading} onRowClick={setSelected} emptyText="Sin pedidos" />
      </Card>

      {creating && <NewOrderModal onClose={() => setCreating(false)} onSaved={() => { setCreating(false); reload() }} />}
      {selected && <OrderDetailModal order={selected} onClose={() => setSelected(null)}
        onChanged={() => { setSelected(null); reload() }} />}
    </div>
  )
}
