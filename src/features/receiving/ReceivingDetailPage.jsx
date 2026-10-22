/**
 * ReceivingDetailPage — captura y cierre de un recibo.
 *
 * Mientras está "En captura":
 *   - Agregar productos: cantidad esperada (factura), recibida, dañada, peso,
 *     lote y caducidad. La diferencia se calcula sola (recibida − esperada).
 *   - Adjuntar evidencias (foto de factura, mercancía, daños).
 *   - Cerrar recibo (permiso close_receiving): la BD genera las entradas de
 *     inventario y los lotes de caducidad; ya no se puede editar.
 */
import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, CheckCircle2, Plus, Trash2, XCircle } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import {
  getReceivingOrder, addItem, deleteItem, closeReceiving, cancelReceiving,
} from '../../services/receivingService'
import { getEvidence } from '../../services/evidenceService'
import { RECEIVING_STATUS } from '../../constants/status'
import { formatDate, formatDateTime, formatNumber } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Input from '../../components/ui/Input'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState, Loader } from '../../components/ui/Feedback'
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
    { key: 'product_name', label: 'Producto', bold: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.sku}</div></> },
    { key: 'expected_qty', label: 'Esperado', align: 'right', render: (v) => formatNumber(v, 3) },
    { key: 'received_qty', label: 'Recibido', align: 'right', render: (v) => <strong>{formatNumber(v, 3)}</strong> },
    { key: 'difference', label: 'Diferencia', align: 'right',
      render: (v) => <span className={Number(v) < 0 ? 'td-danger' : Number(v) > 0 ? 'td-warning' : 'td-ok'}>{Number(v) > 0 ? '+' : ''}{formatNumber(v, 3)}</span> },
    { key: 'damaged_qty', label: 'Dañado', align: 'right', render: (v) => (Number(v) > 0 ? <span className="td-danger">{formatNumber(v, 3)}</span> : '0') },
    { key: 'weight_kg', label: 'Peso (kg)', align: 'right', render: (v) => (v == null ? '—' : formatNumber(v, 3)) },
    { key: 'lot', label: 'Lote' },
    { key: 'expiration_date', label: 'Caducidad', render: formatDate },
    ...(editable ? [{ key: 'actions', label: '', render: (_, r) => (
      <button className="icon-btn icon-btn-danger" title="Quitar" disabled={busy}
        onClick={() => run(() => deleteItem(r.id), 'Producto quitado')}><Trash2 size={14} /></button>
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
    </div>
  )
}
