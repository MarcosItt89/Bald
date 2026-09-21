import { AlertCircle } from 'lucide-react'

// TODO: Replace with: supabase.from('expirations').select('*, products(*)').eq('branch_id', user.branch_id).order('expiration_date')

export default function ExpirationsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Caducidades</h1>
          <p className="page-subtitle">Registro y alertas de productos próximos a vencer</p>
        </div>
      </div>
      <div className="placeholder-section">
        <AlertCircle size={40} className="placeholder-icon" />
        <p>Módulo en construcción — se conectará a expirations en Supabase</p>
      </div>
    </div>
  )
}
