import { ShoppingCart } from 'lucide-react'
import { MOCK_ORDERS } from '../../data/mockData'
import StatusBadge from '../../components/ui/StatusBadge'
import { ORDER_STATUS } from '../../utils/statusHelpers'
import { formatDate } from '../../utils/formatters'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_ORDERS with: supabase.from('orders').select('*, order_items(count), employees(name)').eq('branch_id', user.branch_id)

export default function OrdersPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Pedidos internos</h1>
          <p className="page-subtitle">{MOCK_ORDERS.length} pedidos registrados</p>
        </div>
        <Button variant="primary" size="sm">
          <ShoppingCart size={14} /> Nuevo pedido
        </Button>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Pedido</th><th>Departamento</th><th>Solicitado por</th>
                <th>Fecha</th><th>Artículos</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_ORDERS.map(o => (
                <tr key={o.id}>
                  <td className="td-bold">{o.title}</td>
                  <td>{o.department}</td>
                  <td>{o.requestedBy}</td>
                  <td>{formatDate(o.date)}</td>
                  <td>{o.items}</td>
                  <td><StatusBadge statusMap={ORDER_STATUS} value={o.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
