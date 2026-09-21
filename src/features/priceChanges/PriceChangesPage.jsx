import { DollarSign } from 'lucide-react'
import { MOCK_PRICE_CHANGES } from '../../data/mockData'
import StatusBadge from '../../components/ui/StatusBadge'
import { TAG_STATUS } from '../../utils/statusHelpers'
import { formatCurrency, formatDate } from '../../utils/formatters'
import Badge from '../../components/ui/Badge'

// TODO: Replace MOCK_PRICE_CHANGES with: supabase.from('price_changes').select('*, products(*), shelf_tags(status)').eq('branch_id', user.branch_id)

export default function PriceChangesPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Cambios de precio</h1>
          <p className="page-subtitle">{MOCK_PRICE_CHANGES.length} cambios registrados</p>
        </div>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>SKU</th><th>Producto</th><th>Precio anterior</th>
                <th>Precio nuevo</th><th>Fecha efectiva</th>
                <th>Cenefa</th><th>Estado cenefa</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_PRICE_CHANGES.map(pc => (
                <tr key={pc.id}>
                  <td className="td-mono">{pc.sku}</td>
                  <td className="td-bold"><DollarSign size={14} className="inline-icon" /> {pc.product}</td>
                  <td className="td-strikethrough">{formatCurrency(pc.oldPrice)}</td>
                  <td className="td-bold">{formatCurrency(pc.newPrice)}</td>
                  <td>{formatDate(pc.effectiveDate)}</td>
                  <td>
                    <Badge color={pc.needsTag ? 'warning' : 'default'}>
                      {pc.needsTag ? 'Requiere' : 'No requiere'}
                    </Badge>
                  </td>
                  <td>
                    {pc.needsTag
                      ? <StatusBadge statusMap={TAG_STATUS} value={pc.tagStatus} />
                      : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
