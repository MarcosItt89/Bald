/**
 * ReceivingSummaryPage — resumen de mercancía recibida (Reporte 1, módulo 6).
 *
 * Recibos cerrados en un rango de fechas: por proveedor, cuántos productos,
 * cuánto se recibió y cuáles tuvieron diferencias. Exportable a CSV.
 */
import { useCallback, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Download, FileSpreadsheet } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { getReceivingOrders } from '../../services/receivingService'
import { addDaysISO, formatDateTime, formatNumber, todayISO } from '../../utils/formatters'
import { downloadCsv } from '../../utils/csv'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatCard from '../../components/ui/StatCard'
import { ErrorState } from '../../components/ui/Feedback'

export default function ReceivingSummaryPage() {
  const { branchFilter } = useAuth()
  const navigate = useNavigate()
  const [from, setFrom] = useState(addDaysISO(todayISO(), -30))
  const [to, setTo] = useState(todayISO())

  const load = useCallback(
    () => getReceivingOrders({ branchId: branchFilter, status: 'completed', from, to, limit: 1000 }),
    [branchFilter, from, to],
  )
  const { data: rows = [], loading, error, reload } = useAsync(load)

  const bySupplier = useMemo(() => {
    const map = {}
    rows.forEach((r) => {
      const s = (map[r.supplier_name] ??= { supplier: r.supplier_name, receipts: 0, items: 0, received: 0, withDiff: 0 })
      s.receipts += 1
      s.items += Number(r.items_count)
      s.received += Number(r.total_received)
      if (r.has_differences) s.withDiff += 1
    })
    return Object.values(map).sort((a, b) => b.receipts - a.receipts)
  }, [rows])

  const withDiff = rows.filter((r) => r.has_differences).length

  const exportCsv = () => downloadCsv(`recibos_${from}_${to}.csv`, rows, [
    { key: 'folio', label: 'Folio' }, { key: 'supplier_name', label: 'Proveedor' }, { key: 'invoice_number', label: 'Factura' },
    { key: 'branch_name', label: 'Sucursal' }, { key: 'completed_at', label: 'Cerrado' }, { key: 'items_count', label: 'Productos' },
    { key: 'total_expected', label: 'Esperado' }, { key: 'total_received', label: 'Recibido' }, { key: 'total_damaged', label: 'Dañado' },
    { label: 'Con diferencias', value: (r) => (r.has_differences ? 'Sí' : 'No') }, { key: 'completed_by_name', label: 'Cerró' },
  ])

  return (
    <div className="page">
      <PageHeader icon={FileSpreadsheet} title="Resumen de recibos" subtitle="Mercancía recibida por periodo y proveedor"
        actions={<Button variant="outline" size="sm" onClick={exportCsv} disabled={!rows.length}><Download size={14} /> CSV</Button>} />

      <div className="filters">
        <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} /></label>
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}

      <div className="stat-grid">
        <StatCard label="Recibos cerrados" value={rows.length} tone="green" />
        <StatCard label="Con diferencias" value={withDiff} tone={withDiff ? 'red' : 'green'} />
        <StatCard label="Sin diferencias" value={rows.length ? `${Math.round(((rows.length - withDiff) / rows.length) * 100)}%` : '—'} tone="blue" />
        <StatCard label="Proveedores" value={bySupplier.length} tone="slate" />
      </div>

      <div className="dashboard-grid">
        <Card title="Por proveedor" flush>
          <Table rowKey="supplier" data={bySupplier} loading={loading} columns={[
            { key: 'supplier', label: 'Proveedor', bold: true, sortable: true },
            { key: 'receipts', label: 'Recibos', align: 'right', sortable: true },
            { key: 'items', label: 'Renglones', align: 'right' },
            { key: 'received', label: 'Unidades', align: 'right', render: (v) => formatNumber(v, 2) },
            { key: 'withDiff', label: 'Con dif.', align: 'right', render: (v) => (v ? <span className="td-danger">{v}</span> : 0) },
          ]} />
        </Card>
        <Card title="Recibos del periodo" flush>
          <Table data={rows} loading={loading} onRowClick={(r) => navigate(`/receiving/${r.id}`)} columns={[
            { key: 'folio', label: 'Folio', mono: true },
            { key: 'supplier_name', label: 'Proveedor' },
            { key: 'completed_at', label: 'Cerrado', render: formatDateTime, sortable: true },
            { key: 'has_differences', label: '', render: (v) => (v ? <Badge color="danger">Diferencias</Badge> : <Badge color="success">OK</Badge>) },
          ]} />
        </Card>
      </div>
    </div>
  )
}
