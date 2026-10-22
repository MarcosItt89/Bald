/**
 * InventoryPage — existencias por sucursal (Objetivos §11.2).
 *
 * Funciones:
 *   - Buscar por nombre / SKU / código de barras, filtrar por departamento y estado.
 *   - Estado calculado por la BD (normal, bajo, crítico, sin existencia).
 *   - Con manage_inventory: registrar movimientos (entrada, salida, ajuste,
 *     merma, conteo), ajustar mínimos/ubicación y dar de alta productos.
 *   - Exportar a CSV.
 */
import { useCallback, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Download, Package, Plus } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { P } from '../../config/permissions'
import { getInventory } from '../../services/inventoryService'
import { getDepartments } from '../../services/organizationService'
import { INVENTORY_STATUS, toOptions } from '../../constants/status'
import { formatCurrency, formatNumber } from '../../utils/formatters'
import { downloadCsv } from '../../utils/csv'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import { ErrorState } from '../../components/ui/Feedback'
import InventoryItemModal from './InventoryItemModal'
import NewProductModal from './NewProductModal'

export default function InventoryPage() {
  const { branchFilter, hasPermission } = useAuth()
  const canManage = hasPermission(P.MANAGE_INVENTORY)
  const [search, setSearch] = useState('')
  const [params] = useSearchParams()
  const [status, setStatus] = useState(() => params.get('status') ?? '')
  const [departmentId, setDepartmentId] = useState(() => params.get('dept') ?? '')
  const [selected, setSelected] = useState(null)
  const [creating, setCreating] = useState(false)
  const debounced = useDebouncedValue(search)

  const load = useCallback(
    () => getInventory({ branchId: branchFilter, search: debounced, status, departmentId }),
    [branchFilter, debounced, status, departmentId],
  )
  const { data: rows = [], loading, error, reload } = useAsync(load)
  const { data: departments = [] } = useAsync(getDepartments)

  const columns = [
    { key: 'sku', label: 'SKU', mono: true, sortable: true },
    { key: 'product_name', label: 'Producto', bold: true, sortable: true,
      render: (v, r) => (<>
        {v}
        {r.has_pending_tag && <Badge color="warning" className="ml-1" title="Cenefa pendiente">Cenefa</Badge>}
        <div className="cell-sub td-mono">{r.barcodes?.split(' ')[0]}</div>
      </>) },
    { key: 'department_name', label: 'Departamento', sortable: true },
    ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal', sortable: true }]),
    { key: 'location', label: 'Ubicación' },
    { key: 'stock', label: 'Existencia', align: 'right', sortable: true,
      render: (v, r) => <span className={Number(v) <= Number(r.min_stock) ? 'td-danger' : 'td-bold'}>{formatNumber(v, 3)} {r.unit}</span> },
    { key: 'min_stock', label: 'Mín.', align: 'right', render: (v) => formatNumber(v, 3) },
    { key: 'price', label: 'Precio', align: 'right', sortable: true, render: (v) => formatCurrency(v) },
    { key: 'status', label: 'Estado', sortable: true, render: (v) => <StatusBadge statusMap={INVENTORY_STATUS} value={v} /> },
  ]

  const exportCsv = () => downloadCsv('inventario.csv', rows, [
    { key: 'sku', label: 'SKU' }, { key: 'barcodes', label: 'Códigos' }, { key: 'product_name', label: 'Producto' },
    { key: 'department_name', label: 'Departamento' }, { key: 'branch_name', label: 'Sucursal' },
    { key: 'stock', label: 'Existencia' }, { key: 'min_stock', label: 'Mínimo' }, { key: 'max_stock', label: 'Máximo' },
    { key: 'price', label: 'Precio' }, { label: 'Estado', value: (r) => INVENTORY_STATUS[r.status]?.label },
  ])

  const alerts = rows.filter((r) => ['low', 'critical', 'out_of_stock'].includes(r.status)).length

  return (
    <div className="page">
      <PageHeader
        icon={Package}
        title="Inventario"
        subtitle={loading ? 'Cargando…' : `${rows.length} productos · ${alerts} bajo mínimo`}
        actions={<>
          <Button variant="outline" size="sm" onClick={exportCsv} disabled={!rows.length}><Download size={14} /> CSV</Button>
          {canManage && <Button size="sm" onClick={() => setCreating(true)}><Plus size={14} /> Nuevo producto</Button>}
        </>}
      />

      <div className="filters">
        <SearchInput value={search} onChange={setSearch} placeholder="Buscar por nombre, SKU o código…" />
        <select className="filter-select" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
          <option value="">Todos los departamentos</option>
          {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="filter-select" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">Todos los estados</option>
          <option value="alerts">Bajo mínimo (todos)</option>
          {toOptions(INVENTORY_STATUS).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      </div>

      {error && <ErrorState error={error} onRetry={reload} />}

      <Card flush>
        <Table columns={columns} data={rows} loading={loading} onRowClick={setSelected}
          emptyText={debounced ? `Sin resultados para "${debounced}"` : 'No hay productos en inventario'} />
      </Card>

      {selected && (
        <InventoryItemModal item={selected} canManage={canManage} onClose={() => setSelected(null)}
          onSaved={() => { setSelected(null); reload() }} />
      )}
      {creating && (
        <NewProductModal departments={departments} onClose={() => setCreating(false)}
          onSaved={() => { setCreating(false); reload() }} />
      )}
    </div>
  )
}
