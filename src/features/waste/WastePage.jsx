/**
 * WastePage — captura rápida de mermas (permiso register_waste).
 *
 * Producto (buscador o cámara), cantidad y motivo; la foto es opcional y se
 * liga al movimiento. La base de datos descuenta el inventario y guarda el
 * costo unitario del producto en ese momento (unit_cost).
 * Abajo, las mermas del día con su total en pesos.
 */
import { useCallback, useState } from 'react'
import { CalendarX, CircleHelp, Hand, PackageX, ScanBarcode, ShieldAlert, Thermometer, Trash2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { createMovement, getWaste, searchProducts } from '../../services/inventoryService'
import { WASTE_REASONS } from '../../constants/status'
import { formatCurrency, formatDate, formatNumber, formatTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Input from '../../components/ui/Input'
import { ErrorState } from '../../components/ui/Feedback'
import ProductPicker from '../../components/domain/ProductPicker'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import BarcodeScanner from '../inventory/BarcodeScanner'

const REASON_ICONS = { expired: CalendarX, damaged: PackageX, theft: ShieldAlert, mishandling: Hand, temperature: Thermometer, other: CircleHelp }
const EMPTY = { quantity: '', reason: '', note: '' }

export default function WastePage() {
  const { branchFilter, workingBranchId } = useAuth()
  const toast = useToast()
  const [product, setProduct] = useState(null)
  const [form, setForm] = useState(EMPTY)
  const [saving, setSaving] = useState(false)
  const [scanning, setScanning] = useState(false)
  const [lastId, setLastId] = useState(null)
  const today = todayISO()

  const load = useCallback(() => getWaste({ branchId: branchFilter, from: today }), [branchFilter, today])
  const { data: rows = [], loading, error, reload } = useAsync(load)
  const total = rows.reduce((s, r) => s + Number(r.total_cost ?? 0), 0)

  const onScan = async (code) => {
    setScanning(false)
    try {
      const found = await searchProducts(code, 2)
      if (found.length === 1) setProduct(found[0])
      else toast.error(found.length ? 'Hay varios productos con ese código; búscalo por nombre' : `No se encontró el código ${code}`)
    } catch (err) { toast.error(err.message) }
  }

  const qty = Number(String(form.quantity).replace(',', '.'))
  const valid = product && qty > 0 && form.reason && workingBranchId

  const submit = async (e) => {
    e.preventDefault()
    if (!valid) return
    setSaving(true)
    try {
      const saved = await createMovement({
        branch_id: workingBranchId, product_id: product.id, movement_type: 'waste',
        quantity: qty, waste_reason: form.reason, reason: form.note.trim() || null,
      })
      toast.success(`Merma registrada: ${formatNumber(qty, 3)} ${product.unit} de ${product.name}`)
      setLastId(saved.id)
      setProduct(null)
      setForm(EMPTY)
      reload()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="page page-narrow">
      <PageHeader icon={Trash2} title="Mermas" subtitle={`${formatDate(today)} · ${rows.length} registros · ${formatCurrency(total)}`} />

      <Card title="Registrar merma">
        <form className="form-stack" onSubmit={submit}>
          {!workingBranchId && <p className="hint-box">Elige una sucursal en la barra superior para registrar mermas.</p>}
          <div className="waste-product">
            <ProductPicker value={product} onSelect={setProduct} autoFocus />
            {!product && (
              <Button variant="outline" onClick={() => setScanning(true)} aria-label="Escanear código"><ScanBarcode size={18} /> Escanear</Button>
            )}
          </div>

          <Input label={`Cantidad${product ? ` (${product.unit})` : ''}`} inputMode="decimal" required placeholder="0"
            value={form.quantity} onChange={(e) => setForm({ ...form, quantity: e.target.value })} />

          <div>
            <span className="form-label">Motivo</span>
            <div className="waste-reasons" role="radiogroup" aria-label="Motivo de la merma">
              {Object.entries(WASTE_REASONS).map(([key, r]) => {
                const Icon = REASON_ICONS[key]
                return (
                  <button key={key} type="button" role="radio" aria-checked={form.reason === key}
                    className={`waste-reason ${form.reason === key ? 'waste-reason-active' : ''}`}
                    onClick={() => setForm({ ...form, reason: key })}>
                    <Icon size={20} /><span>{r.label}</span>
                  </button>
                )
              })}
            </div>
          </div>

          <Input label="Nota (opcional)" placeholder="Ej. bolsa rota en recibo, lote 123" value={form.note}
            onChange={(e) => setForm({ ...form, note: e.target.value })} />

          {product && qty > 0 && (
            <p className="text-sm text-muted">Costo estimado: <strong>{formatCurrency(qty * Number(product.cost ?? 0))}</strong> (se toma el costo del producto al guardar)</p>
          )}

          <Button type="submit" className="btn-block" loading={saving} disabled={!valid}>
            {!saving && <Trash2 size={16} />} Registrar merma
          </Button>
        </form>
        {lastId && (
          <div className="waste-photo">
            <span className="text-sm">¿Quieres agregar una foto a la última merma?</span>
            <EvidenceUploader entityType="inventory_movement" entityId={lastId} branchId={workingBranchId}
              label="Agregar foto" onUploaded={() => setLastId(null)} />
          </div>
        )}
      </Card>

      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush title="Mermas de hoy" action={<strong>{formatCurrency(total)}</strong>}>
        <Table data={rows} loading={loading} emptyText="Sin mermas registradas hoy" columns={[
          { key: 'product_name', label: 'Producto', bold: true, render: (v, r) => <>{v}<div className="cell-sub">{formatTime(r.created_at)} · {r.created_by_name}{r.reason ? ` · ${r.reason}` : ''}</div></> },
          { key: 'quantity', label: 'Cantidad', align: 'right', render: (v, r) => `${formatNumber(v, 3)} ${r.unit}` },
          { key: 'waste_reason', label: 'Motivo', render: (v) => <StatusBadge statusMap={WASTE_REASONS} value={v ?? 'other'} /> },
          { key: 'total_cost', label: 'Costo', align: 'right', render: (v) => formatCurrency(v) },
          { key: 'photo', label: 'Foto', render: (_, r) => (
            <EvidenceUploader entityType="inventory_movement" entityId={r.id} branchId={r.branch_id} label="Foto" variant="ghost" onUploaded={reload} />
          ) },
        ]} />
      </Card>

      {scanning && <BarcodeScanner onClose={() => setScanning(false)} onDetected={onScan} />}
    </div>
  )
}
