// TODO: Replace with: supabase.from('receiving_orders').select('*, receiving_items(count)').eq('status', 'completed')

export default function ReceivingSummaryPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Resumen de recibo</h1>
      </div>
      <div className="placeholder-section">
        <p>Módulo en construcción — resúmenes de recibo por fecha y proveedor</p>
      </div>
    </div>
  )
}
