import { Camera } from 'lucide-react'

// TODO: Replace with: supabase.from('evidence_files').select('*').eq('branch_id', user.branch_id).eq('status', 'pending')

export default function EvidencePage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Evidencias</h1>
          <p className="page-subtitle">Subir y revisar evidencias fotográficas</p>
        </div>
      </div>
      <div className="placeholder-section">
        <Camera size={40} className="placeholder-icon" />
        <p>Módulo en construcción — se conectará a evidence_files en Supabase</p>
      </div>
    </div>
  )
}
