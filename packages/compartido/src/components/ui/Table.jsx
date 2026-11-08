/**
 * Table — tabla de datos genérica con ordenamiento por columna.
 *
 *   <Table
 *     columns={[
 *       { key: 'sku', label: 'SKU', mono: true, sortable: true },
 *       { key: 'price', label: 'Precio', render: (v) => formatCurrency(v), align: 'right' },
 *     ]}
 *     data={rows} loading={loading} onRowClick={(row) => ...}
 *   />
 *
 * El ordenamiento es local (en memoria) y alterna asc → desc al hacer clic.
 */
import { useMemo, useState } from 'react'
import { ArrowDown, ArrowUp } from 'lucide-react'

export default function Table({
  columns = [], data = [], loading = false, emptyText = 'Sin resultados',
  onRowClick, rowClassName, rowKey = 'id',
}) {
  const [sort, setSort] = useState({ key: null, dir: 'asc' })

  const rows = useMemo(() => {
    if (!sort.key) return data
    const col = columns.find((c) => c.key === sort.key)
    const get = col?.sortValue ?? ((r) => r[sort.key])
    return [...data].sort((a, b) => {
      const va = get(a); const vb = get(b)
      if (va == null) return 1
      if (vb == null) return -1
      const cmp = typeof va === 'number' && typeof vb === 'number'
        ? va - vb
        : String(va).localeCompare(String(vb), 'es', { numeric: true })
      return sort.dir === 'asc' ? cmp : -cmp
    })
  }, [data, sort, columns])

  const toggleSort = (key) =>
    setSort((s) => ({ key, dir: s.key === key && s.dir === 'asc' ? 'desc' : 'asc' }))

  return (
    <div className="table-wrapper">
      <table className="table table-responsive">
        <thead>
          <tr>
            {columns.map((col) => (
              <th key={col.key} style={{ width: col.width, textAlign: col.align }}
                className={col.sortable ? 'th-sortable' : ''}
                onClick={col.sortable ? () => toggleSort(col.key) : undefined}>
                {col.label}
                {sort.key === col.key && (sort.dir === 'asc' ? <ArrowUp size={11} /> : <ArrowDown size={11} />)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {loading && data.length === 0 ? (
            <tr><td colSpan={columns.length} className="table-empty"><span className="spinner-sm spinner-dark" /> Cargando…</td></tr>
          ) : rows.length === 0 ? (
            <tr><td colSpan={columns.length} className="table-empty">{emptyText}</td></tr>
          ) : (
            rows.map((row, i) => (
              <tr key={row[rowKey] ?? i}
                className={`${onRowClick ? 'tr-clickable' : ''} ${rowClassName?.(row) ?? ''}`.trim()}
                onClick={onRowClick ? () => onRowClick(row) : undefined}>
                {columns.map((col) => (
                  <td key={col.key} style={{ textAlign: col.align }} data-label={typeof col.label === 'string' ? col.label : ''}
                    className={`${col.mono ? 'td-mono' : ''} ${col.bold ? 'td-bold' : ''}`.trim() || undefined}>
                    {col.render ? col.render(row[col.key], row) : (row[col.key] ?? '—')}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  )
}
