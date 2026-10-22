/**
 * NewProductModal — alta de producto en el catálogo + inventario inicial
 * en la sucursal de trabajo.
 */
import { useState } from 'react'
import { useAuth } from '../../hooks/useAuth'
import { useToast } from '../../hooks/useToast'
import { createProduct } from '../../services/inventoryService'
import { UNITS } from '../../constants/status'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'

const EMPTY = {
  sku: '', name: '', category: '', department_id: '', unit: 'pz', cost: '', price: '',
  barcode: '', min_stock: '', initial_stock: '', controls_expiration: false, is_weighable: false,
}

export default function NewProductModal({ departments, onClose, onSaved }) {
  const { workingBranchId } = useAuth()
  const toast = useToast()
  const [form, setForm] = useState(EMPTY)
  const [saving, setSaving] = useState(false)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await createProduct({
        ...form,
        sku: form.sku.trim().toUpperCase(),
        cost: Number(form.cost) || 0,
        price: Number(form.price) || 0,
        branch_id: workingBranchId,
      })
      toast.success('Producto creado')
      onSaved()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open onClose={onClose} title="Nuevo producto" size="lg"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="product-form" loading={saving}>Crear producto</Button>
      </>}>
      <form id="product-form" className="form-stack" onSubmit={submit}>
        <div className="form-grid">
          <Input label="SKU" value={form.sku} onChange={set('sku')} required placeholder="ABR-010" />
          <Input label="Código de barras" value={form.barcode} onChange={set('barcode')} placeholder="Escanea o escribe" />
        </div>
        <Input label="Nombre" value={form.name} onChange={set('name')} required />
        <div className="form-grid">
          <Select label="Departamento" value={form.department_id} onChange={set('department_id')} placeholder="Sin departamento"
            options={departments.map((d) => ({ value: d.id, label: d.name }))} />
          <Input label="Categoría" value={form.category} onChange={set('category')} />
        </div>
        <div className="form-grid form-grid-3">
          <Select label="Unidad" value={form.unit} onChange={set('unit')}
            options={Object.entries(UNITS).map(([value, label]) => ({ value, label }))} />
          <Input label="Costo" type="number" min="0" step="0.01" value={form.cost} onChange={set('cost')} />
          <Input label="Precio de venta" type="number" min="0" step="0.01" value={form.price} onChange={set('price')} required />
        </div>
        <div className="form-grid">
          <Input label="Stock mínimo" type="number" min="0" step="0.001" value={form.min_stock} onChange={set('min_stock')} />
          <Input label="Existencia inicial" type="number" min="0" step="0.001" value={form.initial_stock}
            onChange={set('initial_stock')} hint="Se registra como movimiento de entrada" />
        </div>
        <div className="form-inline">
          <label className="checkbox"><input type="checkbox" checked={form.controls_expiration} onChange={set('controls_expiration')} /> Controla caducidad</label>
          <label className="checkbox"><input type="checkbox" checked={form.is_weighable} onChange={set('is_weighable')} /> Se vende por peso</label>
        </div>
        {Number(form.price) > 0 && Number(form.cost) > Number(form.price) && (
          <p className="hint-box hint-danger">El costo es mayor que el precio de venta.</p>
        )}
      </form>
    </Modal>
  )
}
