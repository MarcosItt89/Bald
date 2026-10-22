/**
 * StockMovementsPage — bitácora de movimientos de inventario (kardex).
 *
 * Cada fila muestra existencia antes/después, quién lo registró y la
 * referencia (p. ej. "Recibo REC-000012"). Es de solo lectura: los
 * movimientos son inmutables para garantizar trazabilidad.
 */
import { useCallback, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ArrowLeftRight, Download } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { getMovements } from '../../services/inventoryService'
import { MOVEMENT_TYPES, toOptions } from '../../constants/status'
import { addDaysISO, formatDateTime, formatNumber, todayISO } from '../../utils/formatters'
import { downloadCsv } from '../../utils/csv'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import { ErrorState } from '../../components/ui/Feedback'

export default function StockMovementsPage() {
  const { branchFilter } = useAuth()
  const [params] = useSearchParams()
  const [type, setType] = useState(() => params.get('type') ?? '')
  const [from, setFrom] = useState(() => params.get('from') ?? addDaysISO(todayISO(), -7))
  const [to, setTo] = useState(() => params.get('to') ?? todayISO())
  const [search, setSearch] = useState('')
  const debounced = useDebouncedValue(search)

  const load = useCallback(
    () => getMovements({ branchId: branchFilter, type, from, to, search: debounced }),
    [branchFilter, type, from, to, debounced],
  )
  const { data: rows = [], loading, error, reload } = useAsync(load)

  const columns = [
    { key: 'created_at', label: 'Fecha', sortable: true, render: formatDateTime },
    { key: 'product_name', label: 'Producto', bold: true, sortable: true,
      render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.sku}</div></> },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
    { key: 'movement_type', label: 'Tipo', render: (v) => <StatusBadge statusMap={MOVEMENT_TYPES} value={v} /> },
    { key: 'quantity', label: 'Cantidad', align: 'right',
      render: (v, r) => {
        const sign = MOVEMENT_TYPES[r.movement_type]?.sign
        return <span className={sign < 0 ? 'td-danger' : 'td-bold'}>{sign > 0 ? '+' : sign < 0 ? '−' : '='}{formatNumber(v, 3)}</span>
      } },
    { key: 'stock_before', label: 'Antes', align: 'right', render: (v) => formatNumber(v, 3) },
    { key: 'stock_after', label: 'Después', align: 'right', render: (v) => <strong>{formatNumber(v, 3)}</strong> },
    { key: 'reason', label: 'Motivo / referencia' },
    { key: 'created_by_name', label: 'Registró' },
  ]

  const exportCsv = () => downloadCsv(`movimientos_${from}_${to}.csv`, rows, [
    { key: 'created_at', label: 'Fecha' }, { key: 'sku', label: 'SKU' }, { key: 'product_name', label: 'Producto' },
    { key: 'branch_name', label: 'Sucursal' }, { label: 'Tipo', value: (r) => MOVEMENT_TYPES[r.movement_type]?.label },
    { key: 'quantity', label: 'Cantidad' }, { key: 'stock_before', label: 'Antes' }, { key: 'stock_after', label: 'Después' },
    { key: 'reason', label: 'Motivo' }, { key: 'created_by_name', label: 'Registró' },
  ])

  return (
    <div className="page">
      <PageHeader icon={ArrowLeftRight} title="Movimientos de inventario"
        subtitle="Entradas, salidas, ajustes, mermas y recibos"
        actions={<Button variant="outline" size="sm" onClick={exportCsv} disabled={!rows.length}><Download size={14} /> CSV</Button>} />

      <div className="filters">
        <SearchInput value={search} onChange={setSearch} placeholder="Producto o SKU…" />
        <select className="filter-select" value={type} onChange={(e) => setType(e.target.value)}>
          <option value="">Todos los tipos</option>
          {toOptions(MOVEMENT_TYPES).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} /></label>
      </div>

      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table columns={columns} data={rows} loading={loading} emptyText="Sin movimientos en el periodo" />
      </Card>
    </div>
  )
}
