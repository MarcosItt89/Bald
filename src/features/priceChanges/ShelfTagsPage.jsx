// TODO: Replace with: supabase.from('shelf_tags').select('*, price_changes(*, products(*))').eq('status', 'pending')

export default function ShelfTagsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Cenefas</h1>
        <p className="page-subtitle">Gestión de cenefas pendientes de colocación</p>
      </div>
      <div className="placeholder-section">
        <p>Módulo en construcción — se conectará a shelf_tags en Supabase</p>
      </div>
    </div>
  )
}
