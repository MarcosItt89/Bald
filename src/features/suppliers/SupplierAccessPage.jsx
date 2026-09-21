// TODO: Replace with: supabase.from('supplier_visits').select('*, suppliers(*)').eq('branch_id', user.branch_id)

export default function SupplierAccessPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Accesos de proveedores</h1>
        <p className="page-subtitle">Registro de entradas y salidas</p>
      </div>
      <div className="placeholder-section">
        <p>Módulo en construcción — se conectará a supplier_visits en Supabase</p>
      </div>
    </div>
  )
}
