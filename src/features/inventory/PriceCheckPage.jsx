import { useState } from 'react'
import { Search, Barcode } from 'lucide-react'
import { MOCK_PRODUCTS } from '../../data/mockData'
import { formatCurrency } from '../../utils/formatters'
import StatusBadge from '../../components/ui/StatusBadge'
import { PRODUCT_STATUS } from '../../utils/statusHelpers'

// TODO: Replace search with: supabase.from('products').select('*').ilike('name', `%${query}%`).limit(10)

export default function PriceCheckPage() {
  const [query, setQuery] = useState('')
  const results = query.trim().length > 1
    ? MOCK_PRODUCTS.filter(p =>
        p.name.toLowerCase().includes(query.toLowerCase()) ||
        p.sku.includes(query) ||
        p.barcode.includes(query)
      )
    : []

  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Consulta de precios</h1>
      </div>

      <div className="card">
        <div className="card-body">
          <div className="search-bar">
            <Search size={18} className="search-icon" />
            <input
              type="text"
              className="search-input"
              placeholder="Buscar por nombre, SKU o código de barras…"
              value={query}
              onChange={e => setQuery(e.target.value)}
              autoFocus
            />
            <Barcode size={18} className="search-icon-right" />
          </div>
        </div>
      </div>

      {results.length > 0 && (
        <div className="price-results">
          {results.map(p => (
            <div key={p.id} className="price-card">
              <div className="price-card-header">
                <div>
                  <span className="price-product-name">{p.name}</span>
                  <span className="price-product-sku">{p.sku} · {p.barcode}</span>
                </div>
                <StatusBadge statusMap={PRODUCT_STATUS} value={p.status} />
              </div>
              <div className="price-card-body">
                <span className="price-amount">{formatCurrency(p.price)}</span>
                <span className="price-dept">{p.department}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      {query.length > 1 && results.length === 0 && (
        <div className="empty-state">
          <Search size={40} />
          <p>Sin resultados para "{query}"</p>
        </div>
      )}
    </div>
  )
}
