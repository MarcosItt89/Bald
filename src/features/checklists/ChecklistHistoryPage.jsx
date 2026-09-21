// TODO: Replace with: supabase.from('checklist_answers').select('*, checklists(*), employees(*)').order('created_at', { ascending: false })

export default function ChecklistHistoryPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Historial de checklists</h1>
      </div>
      <div className="placeholder-section">
        <p>Módulo en construcción — historial de checklists completados</p>
      </div>
    </div>
  )
}
