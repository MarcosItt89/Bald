/**
 * InventoryItemModal — detalle de un producto en la sucursal.
 *
 * Pestaña "Movimiento": registra entrada/salida/ajuste/merma/conteo. El stock
 * lo recalcula el trigger SQL; si la salida deja stock negativo, la BD la
 * rechaza con un mensaje claro.
 * Pestaña "Configuración": mínimo, máximo, ubicación y marca de revisión.
 */
import { useState } from 'react'
import { useToast } from '../../hooks/useToast'
import { createMovement, updateInventorySettings } from '../../services/inventoryService'
import { INVENTORY_STATUS, MOVEMENT_TYPES } from '../../constants/status'
import { formatCurrency, formatDateTime, formatNumber } from '../../utils/formatters'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import Tabs from '../../components/ui/Tabs'
import StatusBadge from '../../components/ui/StatusBadge'

const MANUAL_TYPES = ['in', 'out', 'adjustment_in', 'adjustment_out', 'waste', 'return', 'count']
const REASON_REQUIRED = ['adjustment_in', 'adjustment_out', 'waste', 'count']

export default function InventoryItemModal({ item, canManage, onClose, onSaved }) {
  const toast = useToast()
  const [tab, setTab] = useState(canManage ? 'movement' : 'info')
  const [saving, setSaving] = useState(false)
  const [movement, setMovement] = useState({ movement_type: 'in', quantity: '', reason: '' })
  const [settings, setSettings] = useState({
    min_stock: item.min_stock ?? 0, max_stock: item.max_stock ?? '', location: item.location ?? '',
    review: item.status === 'review',
  })

  const qty = Number(movement.quantity)
  const sign = MOVEMENT_TYPES[movement.movement_type].sign
  const projected = movement.movement_type === 'count' ? qty : Number(item.stock) + sign * (qty || 0)
  const needsReason = REASON_REQUIRED.includes(movement.movement_type)

  const saveMovement = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await createMovement({ ...movement, branch_id: item.branch_id, product_id: item.product_id })
      toast.success('Movimiento registrado')
      onSaved()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const saveSettings = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await updateInventorySettings(item.id, {
        min_stock: Number(settings.min_stock) || 0,
        max_stock: settings.max_stock === '' ? null : Number(settings.max_stock),
        location: settings.location,
        // Si se desmarca "revisión", el trigger recalcula el estado real.
        status: settings.review ? 'review' : 'normal',
      })
      toast.success('Configuración guardada')
      onSaved()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const tabs = [
    ...(canManage ? [{ key: 'movement', label: 'Movimiento' }, { key: 'settings', label: 'Configuración' }] : []),
    { key: 'info', label: 'Información' },
  ]

  return (
    <Modal open onClose={onClose} title={item.product_name} size="md"
      footer={tab === 'movement' ? <>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="movement-form" loading={saving}
          disabled={!qty || qty < 0 || projected < 0 || (needsReason && !movement.reason.trim())}>Registrar</Button>
      </> : tab === 'settings' ? <>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="settings-form" loading={saving}>Guardar</Button>
      </> : <Button variant="ghost" onClick={onClose}>Cerrar</Button>}>

      <div className="detail-strip">
        <div><span>Existencia</span><strong>{formatNumber(item.stock, 3)} {item.unit}</strong></div>
        <div><span>Mínimo</span><strong>{formatNumber(item.min_stock, 3)}</strong></div>
        <div><span>Precio</span><strong>{formatCurrency(item.price)}</strong></div>
        <div><span>Estado</span><StatusBadge statusMap={INVENTORY_STATUS} value={item.status} /></div>
      </div>

      <Tabs tabs={tabs} active={tab} onChange={setTab} />

      {tab === 'movement' && (
        <form id="movement-form" className="form-stack" onSubmit={saveMovement}>
          <div className="form-grid">
            <Select label="Tipo de movimiento" value={movement.movement_type}
              onChange={(e) => setMovement({ ...movement, movement_type: e.target.value })}
              options={MANUAL_TYPES.map((t) => ({ value: t, label: MOVEMENT_TYPES[t].label }))} />
            <Input label={movement.movement_type === 'count' ? 'Cantidad contada' : 'Cantidad'} type="number"
              min="0" step="0.001" value={movement.quantity} required
              onChange={(e) => setMovement({ ...movement, quantity: e.target.value })} />
          </div>
          <Input label="Motivo / referencia" value={movement.reason} required={needsReason}
            placeholder={needsReason ? 'Obligatorio para ajustes, mermas y conteos' : 'Opcional'}
            onChange={(e) => setMovement({ ...movement, reason: e.target.value })} />
          {qty > 0 && (
            <p className={`hint-box ${projected < 0 ? 'hint-danger' : ''}`}>
              Existencia resultante: <strong>{formatNumber(projected, 3)} {item.unit}</strong>
              {projected < 0 && ' — no puede quedar negativa'}
            </p>
          )}
        </form>
      )}

      {tab === 'settings' && (
        <form id="settings-form" className="form-stack" onSubmit={saveSettings}>
          <div className="form-grid">
            <Input label="Stock mínimo" type="number" min="0" step="0.001" value={settings.min_stock}
              onChange={(e) => setSettings({ ...settings, min_stock: e.target.value })} />
            <Input label="Stock máximo" type="number" min="0" step="0.001" value={settings.max_stock}
              onChange={(e) => setSettings({ ...settings, max_stock: e.target.value })} />
          </div>
          <Input label="Ubicación (pasillo / anaquel)" value={settings.location}
            onChange={(e) => setSettings({ ...settings, location: e.target.value })} />
          <label className="checkbox">
            <input type="checkbox" checked={settings.review}
              onChange={(e) => setSettings({ ...settings, review: e.target.checked })} />
            Marcar como "pendiente de revisión" (p. ej. diferencia en conteo)
          </label>
        </form>
      )}

      {tab === 'info' && (
        <dl className="detail-list">
          <dt>SKU</dt><dd className="td-mono">{item.sku}</dd>
          <dt>Códigos de barras</dt><dd className="td-mono">{item.barcodes || '—'}</dd>
          <dt>Departamento</dt><dd>{item.department_name ?? '—'}</dd>
          <dt>Sucursal</dt><dd>{item.branch_name}</dd>
          <dt>Precio anterior</dt><dd>{formatCurrency(item.previous_price)}</dd>
          <dt>Último cambio de precio</dt><dd>{formatDateTime(item.price_updated_at)}</dd>
          <dt>Último movimiento</dt><dd>{formatDateTime(item.last_movement_at)}</dd>
          <dt>Último conteo</dt><dd>{formatDateTime(item.last_counted_at)}</dd>
        </dl>
      )}
    </Modal>
  )
}
