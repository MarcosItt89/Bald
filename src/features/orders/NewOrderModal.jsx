/**
 * NewOrderModal — captura de un pedido interno con varios productos.
 * Se agregan renglones con el buscador de productos; si el mismo producto se
 * agrega dos veces, se suman las cantidades (evita renglones duplicados).
 */
import { useCallback, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { createOrder } from '../../services/orderService'
import { getDepartments } from '../../services/organizationService'
import { PRIORITY, toOptions } from '../../constants/status'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Input, { Textarea } from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import ProductPicker from '../../components/domain/ProductPicker'

export default function NewOrderModal({ onClose, onSaved }) {
  const { profile, workingBranchId } = useAuth()
  const toast = useToast()
  const [form, setForm] = useState({ title: '', department_id: profile.department_id ?? '', priority: 'medium', notes: '' })
  const [items, setItems] = useState([])
  const [product, setProduct] = useState(null)
  const [qty, setQty] = useState('')
  const [saving, setSaving] = useState(false)

  const loadDepts = useCallback(() => getDepartments({ onlyActive: true }), [])
  const { data: departments = [] } = useAsync(loadDepts)

  const addLine = () => {
    const quantity = Number(qty)
    if (!product || !(quantity > 0)) return
    setItems((list) => {
      const existing = list.find((i) => i.product_id === product.id)
      return existing
        ? list.map((i) => (i.product_id === product.id ? { ...i, quantity: i.quantity + quantity } : i))
        : [...list, { product_id: product.id, name: product.name, sku: product.sku, unit: product.unit, quantity }]
    })
    setProduct(null)
    setQty('')
  }

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const order = await createOrder({ ...form, branch_id: workingBranchId, items })
      toast.success(`Pedido ${order.folio} enviado`)
      onSaved()
    } catch (err) {
      toast.error(err.message)
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title="Nuevo pedido interno" size="lg"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="order-form" loading={saving} disabled={!items.length}>Enviar pedido ({items.length})</Button>
      </>}>
      <form id="order-form" className="form-stack" onSubmit={submit}>
        <Input label="Título" required value={form.title} placeholder="Ej. Resurtido pasillo 3"
          onChange={(e) => setForm({ ...form, title: e.target.value })} />
        <div className="form-grid">
          <Select label="Departamento solicitante" value={form.department_id} placeholder="Sin departamento"
            onChange={(e) => setForm({ ...form, department_id: e.target.value })}
            options={departments.map((d) => ({ value: d.id, label: d.name }))} />
          <Select label="Prioridad" value={form.priority} options={toOptions(PRIORITY)}
            onChange={(e) => setForm({ ...form, priority: e.target.value })} />
        </div>

        <div className="line-editor">
          <ProductPicker value={product} onSelect={setProduct} />
          <Input label="Cantidad" type="number" min="0" step="0.001" value={qty} onChange={(e) => setQty(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addLine() } }} />
          <Button variant="outline" onClick={addLine} disabled={!product || !(Number(qty) > 0)}><Plus size={14} /> Agregar</Button>
        </div>

        {items.length > 0 && (
          <table className="table table-compact">
            <thead><tr><th>Producto</th><th>SKU</th><th style={{ textAlign: 'right' }}>Cantidad</th><th /></tr></thead>
            <tbody>
              {items.map((i) => (
                <tr key={i.product_id}>
                  <td className="td-bold">{i.name}</td>
                  <td className="td-mono">{i.sku}</td>
                  <td style={{ textAlign: 'right' }}>{i.quantity} {i.unit}</td>
                  <td><button type="button" className="icon-btn icon-btn-danger" aria-label="Quitar"
                    onClick={() => setItems((l) => l.filter((x) => x.product_id !== i.product_id))}><Trash2 size={14} /></button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        <Textarea label="Notas" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
      </form>
    </Modal>
  )
}
