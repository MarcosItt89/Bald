/**
 * ShelfGapsPage — huecos en anaquel.
 * El empleado escanea (o busca) un producto que no está en piso. La base cruza
 * con la existencia: si hay, crea la tarea a Almacén «Surtir a piso»; si no,
 * sugiere crear un pedido. Quien gestiona huecos ve los de la sucursal y los
 * marca como surtidos o descartados.
 */
import { useCallback, useState } from 'react'
import { Check, PackageSearch, ScanBarcode, ShoppingCart, Truck, X } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { closeShelfGap, createOrderFromGap, getShelfGaps, reportShelfGap } from '../../services/shelfGapService'
import { searchProducts } from '../../services/inventoryService'
import { ORDER_STATUS, TASK_STATUS } from '../../constants/status'
import { formatNumber, formatRelative } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'
import ProductPicker from '../../components/domain/ProductPicker'
import BarcodeScanner from '../inventory/BarcodeScanner'

const CLOSED = { resolved: ['Surtido', 'success'], dismissed: ['Descartado', 'default'] }

export default function ShelfGapsPage() {
  const { hasPermission, branchFilter, workingBranchId } = useAuth()
  const toast = useToast()
  const canReport = hasPermission(P.REPORT_SHELF_GAPS)
  const canManage = hasPermission(P.MANAGE_SHELF_GAPS)
  const canOrder = hasPermission(P.CREATE_ORDERS)
  const [tab, setTab] = useState('open')
  const [notes, setNotes] = useState('')
  const [busy, setBusy] = useState(false)
  const [scanning, setScanning] = useState(false)
  const [result, setResult] = useState(null)
  const [ordering, setOrdering] = useState(null)   // { gapId, name, unit, qty }

  const load = useCallback(() => getShelfGaps({ branchId: branchFilter, open: tab === 'open' }), [branchFilter, tab])
  const { data: gaps = [], loading, error, reload } = useAsync(load)

  const report = async (product) => {
    if (!product) return
    if (!workingBranchId) { toast.error('Elige una sucursal para reportar'); return }
    setBusy(true)
    try {
      const r = await reportShelfGap({ branchId: workingBranchId, productId: product.id, notes })
      setResult(r)
      setNotes('')
      reload()
    } catch (err) { toast.error(err.message) } finally { setBusy(false) }
  }

  const onScan = async (code) => {
    setScanning(false)
    try {
      const found = (await searchProducts(code, 5)).find((p) => p.sku === code || (p.barcodes ?? '').split(' ').includes(code))
      if (!found) { toast.error(`No hay un producto con el código ${code}`); return }
      report(found)
    } catch (err) { toast.error(err.message) }
  }

  const order = async (e) => {
    e.preventDefault()
    setBusy(true)
    try {
      await createOrderFromGap(ordering.gapId, String(ordering.qty).replace(',', '.'))
      toast.success('Pedido creado')
      if (result?.gap_id === ordering.gapId) setResult({ ...result, order_id: true })
      setOrdering(null)
      reload()
    } catch (err) { toast.error(err.message) } finally { setBusy(false) }
  }

  const close = async (gap, status) => {
    try { await closeShelfGap(gap.id, status); toast.success(status === 'resolved' ? 'Marcado como surtido' : 'Hueco descartado'); reload() } catch (err) { toast.error(err.message) }
  }

  return (
    <div className="page">
      <PageHeader icon={PackageSearch} title="Huecos en anaquel" subtitle="Escanea lo que no está en piso: si hay en bodega se avisa a Almacén" />

      {canReport && (
        <Card title="Reportar hueco" subtitle="Escanea la cenefa o el producto, o búscalo por nombre">
          <div className="sg-report">
            <Button onClick={() => setScanning(true)} loading={busy}><ScanBarcode size={16} /> Escanear producto</Button>
            <ProductPicker label="O búscalo" value={null} onSelect={report} />
            <Input label="Nota (opcional)" placeholder="Ej. pasillo 3, anaquel de abajo" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
          {result && <ReportResult r={result} canOrder={canOrder} onOrder={() => setOrdering({ gapId: result.gap_id, name: result.product_name, unit: result.unit, qty: result.suggested_qty })} onClose={() => setResult(null)} />}
        </Card>
      )}

      <Tabs active={tab} onChange={setTab} tabs={[{ key: 'open', label: 'Abiertos', count: tab === 'open' ? gaps.length : undefined }, { key: 'closed', label: 'Cerrados' }]} />
      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !gaps.length ? <Loader /> : !gaps.length ? (
        <EmptyState icon={PackageSearch} title={tab === 'open' ? 'Sin huecos abiertos' : 'Sin huecos cerrados'}
          message={canManage ? 'Aquí aparecen los productos reportados en la sucursal.' : 'Aquí aparecen los huecos que tú reportaste.'} />
      ) : (
        <Card flush>
          <ul className="sg-list">
            {gaps.map((g) => (
              <li key={g.id} className="sg-item">
                <div className="sg-info">
                  <strong>{g.product_name}</strong>
                  <span className="cell-sub td-mono">{g.sku}{g.department_name ? ` · ${g.department_name}` : ''}{g.location ? ` · ${g.location}` : ''}</span>
                  <span className="sg-badges">
                    {g.has_stock
                      ? <Badge color="info"><Truck size={12} /> Hay en bodega · {formatNumber(g.system_stock, 3)} {g.unit}</Badge>
                      : <Badge color="danger">Sin existencia</Badge>}
                    {g.task_status && <Badge color={TASK_STATUS[g.task_status]?.color ?? 'default'}>Tarea: {TASK_STATUS[g.task_status]?.label ?? g.task_status}</Badge>}
                    {g.order_folio && <Badge color={ORDER_STATUS[g.order_status]?.color ?? 'default'}><ShoppingCart size={12} /> {g.order_folio} · {ORDER_STATUS[g.order_status]?.label}</Badge>}
                    {g.status !== 'open' && <Badge color={CLOSED[g.status][1]}>{CLOSED[g.status][0]}</Badge>}
                    {g.report_count > 1 && <Badge color="warning">×{g.report_count} reportes</Badge>}
                  </span>
                  <span className="cell-sub">
                    {g.reported_by_name ?? 'Sistema'} · {formatRelative(g.last_reported_at)}{g.notes ? ` · «${g.notes}»` : ''}
                    {g.resolved_by_name && g.status !== 'open' ? ` · cerró ${g.resolved_by_name}` : ''}
                  </span>
                </div>
                {g.status === 'open' && (
                  <div className="sg-actions">
                    {!g.has_stock && canOrder && (!g.order_folio || ['rejected', 'cancelled'].includes(g.order_status)) && (
                      <Button size="sm" variant="outline" onClick={() => setOrdering({ gapId: g.id, name: g.product_name, unit: g.unit, qty: 1 })}><ShoppingCart size={14} /> Pedir</Button>
                    )}
                    {canManage && <Button size="sm" variant="success" onClick={() => close(g, 'resolved')}><Check size={14} /> Surtido</Button>}
                    {canManage && <Button size="sm" variant="ghost" onClick={() => close(g, 'dismissed')}>Descartar</Button>}
                  </div>
                )}
              </li>
            ))}
          </ul>
        </Card>
      )}

      {scanning && <BarcodeScanner onClose={() => setScanning(false)} onDetected={onScan} />}

      <Modal open={!!ordering} onClose={() => setOrdering(null)} title="Crear pedido" size="sm"
        footer={<><Button variant="ghost" onClick={() => setOrdering(null)}>Cancelar</Button><Button type="submit" form="sg-order" loading={busy}>Crear pedido</Button></>}>
        {ordering && (
          <form id="sg-order" className="form-stack" onSubmit={order}>
            <p className="text-muted">Pedido interno de <strong>{ordering.name}</strong> con prioridad alta. Lo revisa quien aprueba pedidos.</p>
            <Input label={`Cantidad (${ordering.unit})`} inputMode="decimal" required autoFocus value={ordering.qty}
              onChange={(e) => setOrdering({ ...ordering, qty: e.target.value })} />
          </form>
        )}
      </Modal>
    </div>
  )
}

function ReportResult({ r, canOrder, onOrder, onClose }) {
  const stock = `${formatNumber(r.stock, 3)} ${r.unit}`
  return (
    <div className={`hint-box sg-result ${r.has_stock ? '' : 'hint-warning'}`} role="status">
      <div>
        <strong>{r.product_name}</strong>
        {r.has_stock ? (
          <p>Hay {stock} en sistema. {r.repeat ? 'Ya estaba reportado: se sumó tu reporte a la tarea' : 'Se creó la tarea'} «Surtir a piso» para Almacén.</p>
        ) : (
          <p>Sin existencia en sistema. {r.order_id ? 'Ya tiene un pedido en curso.' : canOrder ? 'Sugerencia: crea un pedido.' : 'Avisa a tu supervisor para pedirlo.'}</p>
        )}
        {!r.has_stock && !r.order_id && canOrder && <Button size="sm" onClick={onOrder}><ShoppingCart size={14} /> Crear pedido</Button>}
      </div>
      <button type="button" className="icon-btn" onClick={onClose} aria-label="Cerrar aviso"><X size={14} /></button>
    </div>
  )
}
