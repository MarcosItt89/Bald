import { Package } from 'lucide-react'
import { MOCK_PRODUCTS } from '../../data/mockData'
import StatusBadge from '../../components/ui/StatusBadge'
import { PRODUCT_STATUS } from '../../utils/statusHelpers'
import { formatCurrency } from '../../utils/formatters'

// TODO: Replace MOCK_PRODUCTS with: supabase.from('inventory').select('*, products(*)').eq('branch_id', user.branch_id)

export default function InventoryPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Inventario</h1>
          <p className="page-subtitle">{MOCK_PRODUCTS.length} productos</p>
        </div>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>SKU</th><th>Código</th><th>Producto</th><th>Departamento</th>
                <th>Existencia</th><th>Stock mín.</th><th>Precio</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_PRODUCTS.map(p => (
                <tr key={p.id}>
                  <td className="td-mono">{p.sku}</td>
                  <td className="td-mono">{p.barcode}</td>
                  <td className="td-bold"><Package size={14} className="inline-icon" /> {p.name}</td>
                  <td>{p.department}</td>
                  <td className={p.stock <= p.minStock ? 'td-danger' : ''}>{p.stock}</td>
                  <td>{p.minStock}</td>
                  <td>{formatCurrency(p.price)}</td>
                  <td><StatusBadge statusMap={PRODUCT_STATUS} value={p.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
