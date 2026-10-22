/**
 * ProductPicker — buscador de productos con lista desplegable.
 *
 * Objetivo: elegir un producto por nombre, SKU o código de barras en recibos,
 * pedidos, cambios de precio y caducidades. Funciona con lector USB: si el
 * código escaneado coincide con un solo producto, se selecciona al dar Enter.
 *
 *   <ProductPicker value={product} onSelect={setProduct} />
 */
import { useCallback, useState } from 'react'
import { Package, X } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { searchProducts } from '../../services/inventoryService'
import { formatCurrency } from '../../utils/formatters'
import SearchInput from '../ui/SearchInput'

export default function ProductPicker({ value, onSelect, label = 'Producto', autoFocus = false }) {
  const [query, setQuery] = useState('')
  const debounced = useDebouncedValue(query, 250)

  const load = useCallback(
    () => (debounced.trim().length >= 2 ? searchProducts(debounced) : Promise.resolve([])),
    [debounced],
  )
  const { data: results = [], loading } = useAsync(load)

  const choose = (product) => {
    onSelect(product)
    setQuery('')
  }

  if (value) {
    return (
      <div className="form-group">
        <span className="form-label">{label}</span>
        <div className="picker-selected">
          <Package size={14} />
          <span className="td-bold">{value.name}</span>
          <span className="td-mono text-muted">{value.sku}</span>
          <button type="button" className="picker-clear" onClick={() => onSelect(null)} aria-label="Quitar producto">
            <X size={14} />
          </button>
        </div>
      </div>
    )
  }

  const showList = debounced.trim().length >= 2
  return (
    <div className="form-group picker">
      <span className="form-label">{label}</span>
      <SearchInput
        value={query}
        onChange={setQuery}
        autoFocus={autoFocus}
        placeholder="Nombre, SKU o código de barras…"
        onEnter={() => { if (results.length === 1) choose(results[0]) }}
      />
      {showList && (
        <div className="picker-list">
          {loading && <div className="picker-item text-muted">Buscando…</div>}
          {!loading && results.length === 0 && <div className="picker-item text-muted">Sin coincidencias</div>}
          {results.map((p) => (
            <button type="button" key={p.id} className="picker-item" onClick={() => choose(p)}>
              <span className="td-bold">{p.name}</span>
              <span className="td-mono text-muted">{p.sku}</span>
              <span className="picker-price">{formatCurrency(p.price)}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
