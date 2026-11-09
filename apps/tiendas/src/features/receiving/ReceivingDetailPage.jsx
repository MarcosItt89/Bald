/**
 * ReceivingDetailPage — captura y cierre de un recibo.
 *
 * Mientras está "En captura":
 *   - Agregar productos: cantidad esperada (factura), recibida, dañada, peso,
 *     lote y caducidad. La diferencia se calcula sola (recibida − esperada).
 *   - Contar una partida ya cargada (las que vienen de la factura XML llegan
 *     con lo esperado y recibido = 0): recibido, dañado, peso, lote y caducidad.
 *   - Adjuntar evidencias (foto de factura, mercancía, daños; el XML de la factura).
 *   - Cerrar recibo (permiso close_receiving): la BD genera las entradas de
 *     inventario y los lotes de caducidad; ya no se puede editar.
 */
import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, CheckCircle2, ClipboardCheck, Plus, Trash2, XCircle } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { P } from '../../config/permissions'
import {
  getReceivingOrder, addItem, updateItem, deleteItem, closeReceiving, cancelReceiving,
} from '../../services/receivingService'
import { getEvidence } from '../../services/evidenceService'
import { RECEIVING_STATUS } from '@operalia/compartido/constants/status.js'
import { formatCurrency, formatDate, formatDateTime, formatNumber } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import Input from '@operalia/compartido/components/ui/Input.jsx'
import Modal from '@operalia/compartido/components/ui/Modal.jsx'
import StatusBadge from '@operalia/compartido/components/ui/StatusBadge.jsx'
import { ErrorState, Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import ProductPicker from '../../components/domain/ProductPicker'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import EvidenceGallery from '../../components/domain/EvidenceGallery'

const EMPTY_ITEM = { expected_qty: '', received_qty: '', damaged_qty: '', weight_kg: '', lot: '', expiration_date: '' }

export default function ReceivingDetailPage() {
  const { id } = useParams()
  const { hasPermission } = useAuth()
  const toast = useToast()
  const [product, setProduct] = useState(null)
  const [item, setItem] = useState(EMPTY_ITEM)
  const [busy, setBusy] = useState(false)
  const [counting, setCounting] = useState(null) // partida que se está contando

  const load = useCallback(() => getReceivingOrder(id), [id])
  const { data, loading, error, reload } = useAsync(load)
  const loadEvidence = useCallback(() => getEvidence({ entityType: 'receiving_order', entityId: id }), [id])
  const evidence = useAsync(loadEvidence)

  if (loading && !data) return <Loader />
  if (error) return <ErrorState error={error} onRetry={reload} />
  const { order, items } = data
  const editable = order.status === 'in_progress' && hasPermission(P.RECEIVE_PRODUCTS)

  const run = async (fn, okMsg) => {
    setBusy(true)
    try { await fn(); if (okMsg) toast.success(okMsg); reload() } catch (err) { toast.error(err.message) } finally { setBusy(false) }
  }

  const submitItem = (e) => {
    e.preventDefault()
    run(async () => {
      await addItem({ ...item, receiving_order_id: order.id, product_id: product.id })
      setProduct(null)
      setItem(EMPTY_ITEM)
    }, 'Producto agregado')
  }

  const close = () => {
    const withDiff = items.filter((i) => Number(i.difference) !== 0 || Number(i.damaged_qty) > 0).length
    const msg = withDiff
      ? `Hay ${withDiff} producto(s) con diferencias o daño. ¿Cerrar el recibo de todos modos? Se afectará el inventario.`
      : '¿Cerrar el recibo? Se sumará la mercancía al inventario y ya no podrá editarse.'
    if (window.confirm(msg)) run(() => closeReceiving(order.id), `Recibo ${order.folio} cerrado`)
  }

  const cancel = () => {
    const reason = window.prompt('Motivo de cancelación:')
    if (reason) run(() => cancelReceiving(order.id, reason), 'Recibo cancelado')
  }

  const totals = items.reduce((t, i) => ({
    expected: t.expected + Number(i.expected_qty), received: t.received + Number(i.received_qty),
    damaged: t.damaged + Number(i.damaged_qty),
  }), { expected: 0, received: 0, damaged: 0 })

  const columns = [
    { key: 'product_name', label: 'Producto', bold: true, render: (v, r) => (<>
      {v}<div className="cell-sub td-mono">{r.sku}</div>
      {r.supplier_code && <div className="cell-sub" title={r.supplier_description ?? ''}>Proveedor: <span className="td-mono">{r.supplier_code}</span>{r.supplier_unit ? ` · ${r.supplier_unit}` : ''}</div>}
    </>) },
    { key: 'expected_qty', label: 'Esperado', align: 'right', render: (v) => formatNumber(v, 3) },
    { key: 'received_qty', label: 'Recibido', align: 'right', render: (v) => <strong>{formatNumber(v, 3)}</strong> },
    { key: 'difference', label: 'Diferencia', align: 'right',
      render: (v) => <span className={Number(v) < 0 ? 'td-danger' : Number(v) > 0 ? 'td-warning' : 'td-ok'}>{Number(v) > 0 ? '+' : ''}{formatNumber(v, 3)}</span> },
    { key: 'damaged_qty', label: 'Dañado', align: 'right', render: (v) => (Number(v) > 0 ? <span className="td-danger">{formatNumber(v, 3)}</span> : '0') },
    { key: 'weight_kg', label: 'Peso (kg)', align: 'right', render: (v) => (v == null ? '—' : formatNumber(v, 3)) },
    ...(items.some((i) => i.unit_cost != null) ? [{ key: 'unit_cost', label: 'Costo factura', align: 'right',
      render: (v) => (v == null ? '—' : formatCurrency(v)) }] : []),
    { key: 'lot', label: 'Lote' },
    { key: 'expiration_date', label: 'Caducidad', render: formatDate },
    ...(editable ? [{ key: 'actions', label: '', render: (_, r) => (
      <div className="row-actions">
        <Button size="sm" variant={Number(r.received_qty) === 0 ? 'primary' : 'ghost'} disabled={busy}
          onClick={() => setCounting(r)}><ClipboardCheck size={14} /> Contar</Button>
        <button className="icon-btn icon-btn-danger" title="Quitar" disabled={busy}
          onClick={() => run(() => deleteItem(r.id), 'Producto quitado')}><Trash2 size={14} /></button>
      </div>
    ) }] : []),
  ]

  return (
    <div className="page">
      <Link to="/receiving" className="back-link"><ArrowLeft size={14} /> Recibos</Link>
      <PageHeader
        title={`Recibo ${order.folio}`}
        subtitle={`${order.supplier_name} · ${order.branch_name} · capturó ${order.received_by_name ?? '—'}`}
        actions={<>
          <StatusBadge statusMap={RECEIVING_STATUS} value={order.status} />
          {editable && <Button variant="ghost" size="sm" onClick={cancel} disabled={busy}><XCircle size={14} /> Cancelar</Button>}
          {editable && hasPermission(P.CLOSE_RECEIVING) && (
            <Button variant="success" size="sm" onClick={close} loading={busy} disabled={!items.length}>
              <CheckCircle2 size={14} /> Cerrar recibo
            </Button>
          )}
        </>}
      />

      <div className="detail-strip">
        <div><span>Factura / remisión</span><strong>{order.invoice_number || '—'}</strong></div>
        {order.cfdi_uuid && (
          <div><span>Factura CFDI</span><strong className="td-mono cfdi-uuid" title={order.cfdi_uuid}>{order.cfdi_uuid}</strong>
            <small>{order.invoice_date ? formatDateTime(order.invoice_date) : ''}{order.invoice_total != null ? ` · ${formatCurrency(order.invoice_total)}` : ''}</small></div>
        )}
        <div><span>Inicio</span><strong>{formatDateTime(order.created_at)}</strong></div>
        <div><span>Productos</span><strong>{items.length}</strong></div>
        <div><span>Esperado</span><strong>{formatNumber(totals.expected, 3)}</strong></div>
        <div><span>Recibido</span><strong>{formatNumber(totals.received, 3)}</strong></div>
        <div><span>Dañado</span><strong className={totals.damaged ? 'td-danger' : ''}>{formatNumber(totals.damaged, 3)}</strong></div>
        {order.completed_at && <div><span>Cerrado</span><strong>{formatDateTime(order.completed_at)} · {order.completed_by_name}</strong></div>}
      </div>
      {order.notes && <p className="hint-box">{order.notes}</p>}

      {editable && (
        <Card title="Agregar producto">
          <form className="form-stack" onSubmit={submitItem}>
            <ProductPicker value={product} onSelect={setProduct} autoFocus />
            <div className="form-grid form-grid-4">
              <Input label="Esperado (factura)" type="number" min="0" step="0.001" value={item.expected_qty}
                onChange={(e) => setItem({ ...item, expected_qty: e.target.value })} />
              <Input label="Recibido" type="number" min="0" step="0.001" required value={item.received_qty}
                onChange={(e) => setItem({ ...item, received_qty: e.target.value })} />
              <Input label="Dañado" type="number" min="0" step="0.001" value={item.damaged_qty}
                onChange={(e) => setItem({ ...item, damaged_qty: e.target.value })} />
              <Input label="Peso (kg)" type="number" min="0" step="0.001" value={item.weight_kg}
                onChange={(e) => setItem({ ...item, weight_kg: e.target.value })} />
            </div>
            <div className="form-grid">
              <Input label="Lote" value={item.lot} onChange={(e) => setItem({ ...item, lot: e.target.value })} />
              <Input label="Caducidad" type="date" value={item.expiration_date}
                onChange={(e) => setItem({ ...item, expiration_date: e.target.value })}
                hint="Si la capturas, el lote aparecerá en Caducidades al cerrar" />
            </div>
            {Number(item.damaged_qty) > Number(item.received_qty) && (
              <p className="hint-box hint-danger">Lo dañado no puede ser mayor que lo recibido.</p>
            )}
            <div>
              <Button type="submit" size="sm" loading={busy}
                disabled={!product || item.received_qty === '' || Number(item.damaged_qty) > Number(item.received_qty)}>
                <Plus size={14} /> Agregar
              </Button>
            </div>
          </form>
        </Card>
      )}

      <Card title="Productos del recibo" flush className="mt-3">
        <Table columns={columns} data={items} emptyText="Aún no hay productos capturados"
          rowClassName={(r) => (Number(r.difference) !== 0 || Number(r.damaged_qty) > 0 ? 'tr-warning' : '')} />
      </Card>

      <Card title="Evidencias" className="mt-3"
        action={editable && <EvidenceUploader entityType="receiving_order" entityId={order.id} branchId={order.branch_id}
          onUploaded={evidence.reload} label="Foto de factura / mercancía" />}>
        <EvidenceGallery items={evidence.data ?? []} showStatus />
      </Card>
      {counting && (
        <CountItemModal item={counting} onClose={() => setCounting(null)} busy={busy}
          onSave={(values) => run(async () => { await updateItem(counting.id, values); setCounting(null) }, 'Partida contada')} />
      )}
    </div>
  )
}

/** Contar una partida ya cargada: lo recibido (y dañado, peso, lote, caducidad). */
function CountItemModal({ item, onClose, onSave, busy }) {
  const [form, setForm] = useState({
    received_qty: Number(item.received_qty) ? String(item.received_qty) : '',
    damaged_qty: Number(item.damaged_qty) ? String(item.damaged_qty) : '',
    weight_kg: item.weight_kg ?? '', lot: item.lot ?? '', expiration_date: item.expiration_date ?? '',
  })
  const tooMuchDamage = Number(form.damaged_qty) > Number(form.received_qty)
  const submit = (e) => {
    e.preventDefault()
    // expected_qty va siempre: el servicio pone 0 si falta.
    onSave({ ...form, expected_qty: item.expected_qty })
  }
  return (
    <Modal open onClose={onClose} title={`Contar · ${item.product_name}`} size="sm"
      footer={<><Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="count-item" loading={busy} disabled={form.received_qty === '' || tooMuchDamage}>Guardar</Button></>}>
      <form id="count-item" className="form-stack" onSubmit={submit}>
        <p className="text-sm">Esperado (factura): <strong>{formatNumber(item.expected_qty, 3)}</strong>
          {item.supplier_description && <span className="text-muted"> · {item.supplier_description}</span>}</p>
        <div className="form-grid">
          <Input label="Recibido" type="number" min="0" step="0.001" required autoFocus value={form.received_qty}
            onChange={(e) => setForm({ ...form, received_qty: e.target.value })} />
          <Input label="Dañado" type="number" min="0" step="0.001" value={form.damaged_qty}
            onChange={(e) => setForm({ ...form, damaged_qty: e.target.value })} />
          <Input label="Peso (kg)" type="number" min="0" step="0.001" value={form.weight_kg}
            onChange={(e) => setForm({ ...form, weight_kg: e.target.value })} />
          <Input label="Lote" value={form.lot} onChange={(e) => setForm({ ...form, lot: e.target.value })} />
        </div>
        <Input label="Caducidad" type="date" value={form.expiration_date}
          onChange={(e) => setForm({ ...form, expiration_date: e.target.value })}
          hint="Si la capturas, el lote aparecerá en Caducidades al cerrar" />
        {tooMuchDamage && <p className="hint-box hint-danger">Lo dañado no puede ser mayor que lo recibido.</p>}
      </form>
    </Modal>
  )
}
