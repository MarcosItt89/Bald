// TODO: Replace with: supabase.from('inventory_movements').select('*, products(*), employees(*)').eq('branch_id', user.branch_id)

export default function StockMovementsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Movimientos de inventario</h1>
        <p className="page-subtitle">Entradas, salidas y ajustes</p>
      </div>
      <div className="placeholder-section">
        <p>Módulo en construcción — se conectará a inventory_movements en Supabase</p>
      </div>
    </div>
  )
}
