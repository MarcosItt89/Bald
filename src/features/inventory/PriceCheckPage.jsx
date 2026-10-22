/**
 * PriceCheckPage — consulta rápida de precios (Objetivos §11.3).
 *
 * Pensada para caja y piso de venta:
 *   - Busca por nombre, SKU o código de barras (compatible con lector USB).
 *   - Botón de cámara: usa BarcodeDetector del navegador si está disponible
 *     (Chrome Android); si no, se escribe el código.
 *   - Muestra precio actual, precio anterior, fecha de cambio y si hay
 *     cenefa pendiente.
 *   - "Reportar diferencia": crea una tarea para Escáner (RPC SQL).
 */
import { useCallback, useState } from 'react'
import { AlertTriangle, ScanLine, Tag } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { lookupPrice, reportPriceDifference } from '../../services/inventoryService'
import { INVENTORY_STATUS } from '../../constants/status'
import { formatCurrency, formatDate, formatNumber } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import SearchInput from '../../components/ui/SearchInput'
import StatusBadge from '../../components/ui/StatusBadge'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'
import Modal from '../../components/ui/Modal'
import Input, { Textarea } from '../../components/ui/Input'
import { EmptyState } from '../../components/ui/Feedback'
import BarcodeScanner from './BarcodeScanner'

export default function PriceCheckPage() {
  const { workingBranchId, hasPermission } = useAuth()
  const toast = useToast()
  const [query, setQuery] = useState('')
  const [scanning, setScanning] = useState(false)
  const [reporting, setReporting] = useState(null)
  const [report, setReport] = useState({ observed: '', comment: '' })
  const [sending, setSending] = useState(false)
  const debounced = useDebouncedValue(query, 250)

  const load = useCallback(
    () => (debounced.trim().length >= 2 ? lookupPrice({ branchId: workingBranchId, search: debounced }) : Promise.resolve([])),
    [debounced, workingBranchId],
  )
  const { data: results = [], loading } = useAsync(load)

  const sendReport = async () => {
    setSending(true)
    try {
      await reportPriceDifference({
        productId: reporting.product_id, branchId: reporting.branch_id,
        observedPrice: report.observed, comment: report.comment,
      })
      toast.success('Reporte enviado al departamento de Escáner')
      setReporting(null)
      setReport({ observed: '', comment: '' })
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="page page-narrow">
      <PageHeader icon={Tag} title="Consulta de precios" subtitle="Escanea o escribe el nombre, SKU o código de barras" />

      <div className="price-search">
        <SearchInput large value={query} onChange={setQuery} autoFocus
          placeholder="Ej. arroz, ABR-001 o 7501055300001" />
        {hasPermission(P.SCAN_PRODUCTS) && (
          <Button variant="outline" onClick={() => setScanning(true)} title="Escanear con cámara">
            <ScanLine size={18} />
          </Button>
        )}
      </div>

      {loading && debounced.length >= 2 && <p className="text-muted mt-2">Buscando…</p>}

      <div className="price-results">
        {results.map((p) => (
          <div key={p.id} className="price-card">
            <div className="price-card-header">
              <div>
                <span className="price-product-name">{p.product_name}</span>
                <span className="price-product-sku">{p.sku} · {p.barcodes?.split(' ')[0]}</span>
              </div>
              <StatusBadge statusMap={INVENTORY_STATUS} value={p.status} />
            </div>
            <div className="price-card-body">
              <span className="price-amount">{formatCurrency(p.price)}</span>
              {p.previous_price != null && Number(p.previous_price) !== Number(p.price) && (
                <span className="price-previous">Antes {formatCurrency(p.previous_price)}</span>
              )}
            </div>
            <div className="price-card-meta">
              <span>Existencia: <strong>{formatNumber(p.stock, 3)} {p.unit}</strong></span>
              {p.location && <span>Ubicación: {p.location}</span>}
              {p.price_updated_at && <span>Cambio: {formatDate(p.price_updated_at)}</span>}
              {p.has_pending_tag && <Badge color="warning">Cenefa pendiente</Badge>}
            </div>
            {hasPermission(P.REPORT_PRICE_DIFFERENCE) && (
              <Button variant="ghost" size="sm" onClick={() => setReporting(p)}>
                <AlertTriangle size={14} /> El precio en anaquel es diferente
              </Button>
            )}
          </div>
        ))}
      </div>

      {!loading && debounced.length >= 2 && results.length === 0 && (
        <EmptyState title={`Sin resultados para "${debounced}"`} message="Verifica el código o busca por nombre." />
      )}

      {scanning && (
        <BarcodeScanner onClose={() => setScanning(false)}
          onDetected={(code) => { setQuery(code); setScanning(false) }} />
      )}

      <Modal open={!!reporting} onClose={() => setReporting(null)} title="Reportar diferencia de precio" size="sm"
        footer={<>
          <Button variant="ghost" onClick={() => setReporting(null)}>Cancelar</Button>
          <Button onClick={sendReport} loading={sending}>Enviar reporte</Button>
        </>}>
        {reporting && (
          <div className="form-stack">
            <p><strong>{reporting.product_name}</strong> — precio en sistema {formatCurrency(reporting.price)}</p>
            <Input label="Precio que marca el anaquel" type="number" min="0" step="0.01" value={report.observed}
              onChange={(e) => setReport({ ...report, observed: e.target.value })} />
            <Textarea label="Comentario" value={report.comment} placeholder="Pasillo, cenefa dañada, etc."
              onChange={(e) => setReport({ ...report, comment: e.target.value })} />
          </div>
        )}
      </Modal>
    </div>
  )
}
