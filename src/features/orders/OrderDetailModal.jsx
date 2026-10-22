/**
 * OrderDetailModal — detalle del pedido y botones de cambio de estado.
 * Solo se muestran las transiciones válidas para el usuario actual
 * (aprobador o solicitante). Rechazar exige comentario.
 */
import { useCallback, useState } from 'react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getOrderItems, changeOrderStatus } from '../../services/orderService'
import { ORDER_STATUS, ORDER_TRANSITIONS, PRIORITY } from '../../constants/status'
import { formatDateTime, formatNumber } from '../../utils/formatters'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { Textarea } from '../../components/ui/Input'
import StatusBadge from '../../components/ui/StatusBadge'

export default function OrderDetailModal({ order, onClose, onChanged }) {
  const { hasPermission, profile } = useAuth()
  const toast = useToast()
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(null)

  const load = useCallback(() => getOrderItems(order.id), [order.id])
  const { data: items = [], loading } = useAsync(load)

  const isApprover = hasPermission(P.APPROVE_ORDERS)
  const isRequester = order.requested_by === profile.id
  const actions = (ORDER_TRANSITIONS[order.status] ?? []).filter((t) =>
    t.who === 'approver' ? isApprover : isApprover || isRequester)

  const apply = async (t) => {
    if (t.needsComment && !comment.trim()) {
      toast.error('Escribe el motivo en el comentario')
      return
    }
    setBusy(t.to)
    try {
      await changeOrderStatus(order.id, t.to, comment)
      toast.success(`Pedido ${ORDER_STATUS[t.to].label.toLowerCase()}`)
      onChanged()
    } catch (err) {
      toast.error(err.message)
      setBusy(null)
    }
  }

  return (
    <Modal open onClose={onClose} title={`${order.folio} · ${order.title}`} size="lg"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cerrar</Button>
        {actions.map((t) => (
          <Button key={t.to} loading={busy === t.to} disabled={!!busy}
            variant={t.to === 'rejected' || t.to === 'cancelled' ? 'danger' : t.to === 'approved' ? 'success' : 'primary'}
            onClick={() => apply(t)}>{t.label}</Button>
        ))}
      </>}>
      <div className="detail-strip">
        <div><span>Estado</span><StatusBadge statusMap={ORDER_STATUS} value={order.status} /></div>
        <div><span>Prioridad</span><StatusBadge statusMap={PRIORITY} value={order.priority} /></div>
        <div><span>Solicitó</span><strong>{order.requested_by_name}</strong></div>
        <div><span>Fecha</span><strong>{formatDateTime(order.created_at)}</strong></div>
        {order.approved_by_name && <div><span>Revisó</span><strong>{order.approved_by_name} · {formatDateTime(order.approved_at)}</strong></div>}
      </div>
      {order.notes && <p className="hint-box">{order.notes}</p>}
      {order.status_comment && <p className="hint-box">Comentario: {order.status_comment}</p>}

      <table className="table table-compact">
        <thead><tr><th>Producto</th><th>SKU</th><th style={{ textAlign: 'right' }}>Cantidad</th></tr></thead>
        <tbody>
          {loading && <tr><td colSpan={3} className="table-empty">Cargando…</td></tr>}
          {items.map((i) => (
            <tr key={i.id}>
              <td className="td-bold">{i.product_name}</td>
              <td className="td-mono">{i.sku}</td>
              <td style={{ textAlign: 'right' }}>{formatNumber(i.quantity, 3)} {i.unit}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {actions.length > 0 && (
        <Textarea label="Comentario (obligatorio para rechazar)" value={comment} className="mt-2"
          onChange={(e) => setComment(e.target.value)} />
      )}
    </Modal>
  )
}
