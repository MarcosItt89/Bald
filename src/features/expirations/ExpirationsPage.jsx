/**
 * ExpirationsPage — control de lotes con fecha de caducidad.
 *
 * Semáforo por días restantes (vencido / ≤ 3 / ≤ 7 / ok). Acciones:
 *   - Rebajar: el lote sigue en anaquel con precio de liquidación.
 *   - Retirar como merma: descuenta la cantidad del inventario (movimiento 'waste').
 *   - Agotado: se vendió todo antes de vencer.
 * Los lotes también llegan solos al cerrar un recibo con fecha de caducidad.
 */
import { useCallback, useMemo, useState } from 'react'
import { CalendarClock, Plus } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getExpirations, createExpiration, updateExpirationStatus, withdrawAsWaste } from '../../services/expirationService'
import { EXPIRATION_STATUS, expirationUrgency } from '../../constants/status'
import { formatDate, formatNumber } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import StatCard from '../../components/ui/StatCard'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import { ErrorState } from '../../components/ui/Feedback'
import ProductPicker from '../../components/domain/ProductPicker'

const OPEN = ['active', 'markdown', 'expired']

export default function ExpirationsPage() {
  const { branchFilter, workingBranchId } = useAuth()
  const toast = useToast()
  const [tab, setTab] = useState('open')
  const [creating, setCreating] = useState(false)
  const [product, setProduct] = useState(null)
  const [form, setForm] = useState({ lot: '', quantity: '', expiration_date: '' })
  const [saving, setSaving] = useState(false)

  const load = useCallback(() => getExpirations({ branchId: branchFilter }), [branchFilter])
  const { data: all = [], loading, error, reload } = useAsync(load)

  const rows = useMemo(() => {
    if (tab === 'open') return all.filter((r) => OPEN.includes(r.status))
    if (tab === 'soon') return all.filter((r) => OPEN.includes(r.status) && r.days_left <= 7)
    return all.filter((r) => !OPEN.includes(r.status))
  }, [all, tab])

  const open = all.filter((r) => OPEN.includes(r.status))
  const stats = {
    expired: open.filter((r) => r.days_left < 0).length,
    three: open.filter((r) => r.days_left >= 0 && r.days_left <= 3).length,
    seven: open.filter((r) => r.days_left > 3 && r.days_left <= 7).length,
  }

  const act = async (fn, msg) => {
    try { await fn(); toast.success(msg); reload() } catch (err) { toast.error(err.message) }
  }

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await createExpiration({ ...form, product_id: product.id, branch_id: workingBranchId })
      toast.success('Lote registrado')
      setCreating(false); setProduct(null); setForm({ lot: '', quantity: '', expiration_date: '' })
      reload()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const columns = [
    { key: 'days_left', label: 'Vence en', sortable: true, render: (v) => { const u = expirationUrgency(v); return <Badge color={u.color}>{u.label}</Badge> } },
    { key: 'product_name', label: 'Producto', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.sku}</div></> },
    { key: 'department_name', label: 'Departamento' },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
    { key: 'lot', label: 'Lote', mono: true },
    { key: 'quantity', label: 'Cantidad', align: 'right', render: (v, r) => `${formatNumber(v, 3)} ${r.unit}` },
    { key: 'expiration_date', label: 'Caducidad', sortable: true, render: formatDate },
    { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={EXPIRATION_STATUS} value={v} /> },
    { key: 'actions', label: '', render: (_, r) => OPEN.includes(r.status) && (
      <div className="row-actions">
        {r.status === 'active' && r.days_left >= 0 && (
          <Button size="sm" variant="outline" onClick={() => act(() => updateExpirationStatus(r.id, 'markdown', 'Rebaja por próxima caducidad'), 'Lote marcado como rebajado')}>Rebajar</Button>
        )}
        <Button size="sm" variant="danger" onClick={() => {
          if (window.confirm(`¿Retirar ${formatNumber(r.quantity, 3)} ${r.unit} de ${r.product_name} como merma? Se descontará del inventario.`)) {
            act(() => withdrawAsWaste(r, 'Retirado por caducidad'), 'Lote retirado y merma registrada')
          }
        }}>Retirar</Button>
        {r.days_left >= 0 && (
          <Button size="sm" variant="ghost" onClick={() => act(() => updateExpirationStatus(r.id, 'sold_out'), 'Lote agotado')}>Agotado</Button>
        )}
      </div>
    ) },
  ]

  return (
    <div className="page">
      <PageHeader icon={CalendarClock} title="Caducidades" subtitle="Lotes próximos a vencer y retiro de producto"
        actions={<Button size="sm" onClick={() => setCreating(true)}><Plus size={14} /> Registrar lote</Button>} />

      <div className="stat-grid">
        <StatCard label="Vencidos en anaquel" value={stats.expired} tone="red" alert={stats.expired ? 'Retirar de inmediato' : undefined} />
        <StatCard label="Vencen en ≤ 3 días" value={stats.three} tone="orange" />
        <StatCard label="Vencen en 4 a 7 días" value={stats.seven} tone="blue" />
      </div>

      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'open', label: 'En anaquel', count: open.length },
        { key: 'soon', label: 'Próximos 7 días', count: stats.expired + stats.three + stats.seven },
        { key: 'closed', label: 'Retirados / agotados' },
      ]} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table columns={columns} data={rows} loading={loading} emptyText="Sin lotes"
          rowClassName={(r) => (OPEN.includes(r.status) && r.days_left < 0 ? 'tr-danger' : '')} />
      </Card>

      <Modal open={creating} onClose={() => setCreating(false)} title="Registrar lote con caducidad"
        footer={<>
          <Button variant="ghost" onClick={() => setCreating(false)}>Cancelar</Button>
          <Button type="submit" form="exp-form" loading={saving} disabled={!product}>Guardar</Button>
        </>}>
        <form id="exp-form" className="form-stack" onSubmit={submit}>
          <ProductPicker value={product} onSelect={setProduct} autoFocus />
          <div className="form-grid form-grid-3">
            <Input label="Lote" value={form.lot} onChange={(e) => setForm({ ...form, lot: e.target.value })} />
            <Input label="Cantidad" type="number" min="0" step="0.001" required value={form.quantity}
              onChange={(e) => setForm({ ...form, quantity: e.target.value })} />
            <Input label="Fecha de caducidad" type="date" required value={form.expiration_date}
              onChange={(e) => setForm({ ...form, expiration_date: e.target.value })} />
          </div>
        </form>
      </Modal>
    </div>
  )
}
