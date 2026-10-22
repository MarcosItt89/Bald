/**
 * PriceChangesPage — registro y seguimiento de cambios de precio (§11.10).
 *
 * Al guardar un cambio:
 *   - fecha efectiva hoy o antes → se aplica al momento (precio del producto
 *     actualizado + cenefas pendientes por sucursal si "requiere cenefa")
 *   - fecha futura → queda "Programado" y se aplica ese día automáticamente
 * El precio anterior lo toma la BD (no se puede falsear desde el cliente).
 */
import { useCallback, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { DollarSign, Plus } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getPriceChanges, createPriceChange, cancelPriceChange } from '../../services/priceChangeService'
import { PRICE_CHANGE_STATUS } from '../../constants/status'
import { getZones } from '../../services/organizationService'
import { formatCurrency, formatDate, formatDateTime, todayISO } from '../../utils/formatters'
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
import ProgressBar from '../../components/ui/ProgressBar'
import { ErrorState } from '../../components/ui/Feedback'
import ProductPicker from '../../components/domain/ProductPicker'

export default function PriceChangesPage() {
  const { branchFilter, hasPermission } = useAuth()
  const toast = useToast()
  const canManage = hasPermission(P.MANAGE_PRICE_CHANGES)
  const [params] = useSearchParams()
  const [tab, setTab] = useState(() => params.get('tab') ?? 'all')
  const [creating, setCreating] = useState(false)

  const load = useCallback(() => getPriceChanges({ branchId: branchFilter }), [branchFilter])
  const { data: all = [], loading, error, reload } = useAsync(load)
  const rows = useMemo(() => (tab === 'all' ? all : all.filter((r) => r.status === tab)), [all, tab])

  const cancel = async (row) => {
    if (!window.confirm(`¿Cancelar el cambio programado de ${row.product_name}?`)) return
    try { await cancelPriceChange(row.id); toast.success('Cambio cancelado'); reload() } catch (err) { toast.error(err.message) }
  }

  const columns = [
    { key: 'product_name', label: 'Producto', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.sku}</div></> },
    { key: 'old_price', label: 'Anterior', align: 'right', render: (v) => <span className="td-strikethrough">{formatCurrency(v)}</span> },
    { key: 'new_price', label: 'Nuevo', align: 'right', render: (v, r) => {
      const diff = ((r.new_price - r.old_price) / r.old_price) * 100
      return <><strong>{formatCurrency(v)}</strong><div className={`cell-sub ${diff > 0 ? 'td-danger' : 'td-ok'}`}>{diff > 0 ? '▲' : '▼'} {Math.abs(diff).toFixed(1)}%</div></>
    } },
    { key: 'effective_date', label: 'Efectivo', sortable: true, render: formatDate },
    { key: 'branch_name', label: 'Alcance', render: (v, r) => v ?? (r.zone_name ? <Badge color="info">Zona {r.zone_name}</Badge> : <Badge color="primary">Todas las sucursales</Badge>) },
    { key: 'tags_total', label: 'Cenefas', render: (v, r) => (!r.requires_tag ? <span className="text-muted">No requiere</span>
      : r.status !== 'applied' ? '—'
      : <ProgressBar value={Number(r.tags_validated)} total={Number(v)} label={`${r.tags_validated}/${v}`} width={60} />) },
    { key: 'created_by_name', label: 'Registró', render: (v, r) => <>{v}<div className="cell-sub">{formatDateTime(r.created_at)}</div></> },
    { key: 'status', label: 'Estado', render: (v, r) => (<>
      <StatusBadge statusMap={PRICE_CHANGE_STATUS} value={v} />
      {canManage && v === 'scheduled' && <button className="link-btn ml-1" onClick={(e) => { e.stopPropagation(); cancel(r) }}>Cancelar</button>}
    </>) },
  ]

  return (
    <div className="page">
      <PageHeader icon={DollarSign} title="Cambios de precio" subtitle="Historial de precios y su cenefa correspondiente"
        actions={canManage && <Button size="sm" onClick={() => setCreating(true)}><Plus size={14} /> Nuevo cambio</Button>} />
      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'all', label: 'Todos' },
        { key: 'scheduled', label: 'Programados', count: all.filter((r) => r.status === 'scheduled').length },
        { key: 'applied', label: 'Aplicados' },
        { key: 'cancelled', label: 'Cancelados' },
      ]} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush><Table columns={columns} data={rows} loading={loading} emptyText="Sin cambios de precio" /></Card>

      {creating && <NewPriceChangeModal onClose={() => setCreating(false)} onSaved={() => { setCreating(false); reload() }} />}
    </div>
  )
}

function NewPriceChangeModal({ onClose, onSaved }) {
  const { isCompanyScope, isZoneScope, zoneIds, workingBranchId, profile } = useAuth()
  const toast = useToast()
  const [product, setProduct] = useState(null)
  // Alcance: toda la empresa (admin), una zona (admin o jefe de zona) o la sucursal de trabajo.
  const [form, setForm] = useState({
    new_price: '', effective_date: todayISO(), scope: isCompanyScope ? 'all' : 'branch', zone_id: '', requires_tag: true, reason: '',
  })
  const loadZones = useCallback(async () => {
    if (!isCompanyScope && !isZoneScope) return []
    const all = await getZones({ onlyActive: true })
    return isZoneScope ? all.filter((z) => zoneIds.includes(z.id)) : all
  }, [isCompanyScope, isZoneScope, zoneIds])
  const { data: zones = [] } = useAsync(loadZones)
  const scopeOptions = [
    ...(isCompanyScope ? [{ value: 'all', label: 'Todas las sucursales' }] : []),
    ...(zones.length ? [{ value: 'zone', label: 'Una zona (oferta por zona)' }] : []),
    { value: 'branch', label: `Solo ${profile.branch_name ?? 'la sucursal seleccionada'}` },
  ]
  const [saving, setSaving] = useState(false)

  const newPrice = Number(form.new_price)
  const diff = product && newPrice > 0 ? ((newPrice - product.price) / product.price) * 100 : null

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const saved = await createPriceChange({
        product_id: product.id,
        branch_id: form.scope === 'branch' ? workingBranchId : null,
        zone_id: form.scope === 'zone' ? form.zone_id : null,
        new_price: newPrice,
        effective_date: form.effective_date,
        reason: form.reason,
        requires_tag: form.requires_tag,
      })
      toast.success(saved.effective_date > todayISO()
        ? 'Cambio programado' : `Precio aplicado${form.requires_tag ? ' y cenefas generadas' : ''}`)
      onSaved()
    } catch (err) {
      toast.error(err.message)
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title="Nuevo cambio de precio"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="price-form" loading={saving}
          disabled={!product || !(newPrice > 0) || newPrice === Number(product?.price) || (form.scope === 'zone' && !form.zone_id)}>Guardar cambio</Button>
      </>}>
      <form id="price-form" className="form-stack" onSubmit={submit}>
        <ProductPicker value={product} onSelect={setProduct} autoFocus />
        {product && <p className="hint-box">Precio actual: <strong>{formatCurrency(product.price)}</strong></p>}
        <div className="form-grid">
          <Input label="Precio nuevo" type="number" min="0.01" step="0.01" required value={form.new_price}
            onChange={(e) => setForm({ ...form, new_price: e.target.value })}
            hint={diff != null ? `${diff > 0 ? 'Aumento' : 'Reducción'} de ${Math.abs(diff).toFixed(1)}%` : undefined} />
          <Input label="Fecha efectiva" type="date" required min={todayISO()} value={form.effective_date}
            onChange={(e) => setForm({ ...form, effective_date: e.target.value })} />
        </div>
        {diff != null && Math.abs(diff) >= 30 && (
          <p className="hint-box hint-danger">Cambio mayor al 30 %. Verifica que el precio sea correcto.</p>
        )}
        <Textarea label="Motivo" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
        <div className="form-inline">
          <label className="checkbox"><input type="checkbox" checked={form.requires_tag}
            onChange={(e) => setForm({ ...form, requires_tag: e.target.checked })} /> Requiere cenefa nueva</label>
        </div>
        <div className="form-grid">
          <Select label="Aplicar en" value={form.scope} options={scopeOptions} onChange={(e) => setForm({ ...form, scope: e.target.value })} />
          {form.scope === 'zone' && (
            <Select label="Zona" required value={form.zone_id} placeholder="Selecciona…"
              options={zones.map((z) => ({ value: z.id, label: `${z.name} (${z.branches?.length ?? 0} suc.)` }))}
              onChange={(e) => setForm({ ...form, zone_id: e.target.value })} />
          )}
        </div>
        <p className="text-muted text-sm">
          {form.scope === 'all' ? 'Cambia el precio base del producto en todas las sucursales.'
            : form.scope === 'zone' ? 'El precio y las cenefas se aplican a cada sucursal activa de la zona; el resto conserva su precio.'
            : 'Solo esta sucursal tendrá el precio nuevo.'}
        </p>
      </form>
    </Modal>
  )
}
