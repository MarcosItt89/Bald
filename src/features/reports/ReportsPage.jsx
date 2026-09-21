import { FileText } from 'lucide-react'

// TODO: Build report queries once all tables exist in Supabase

export default function ReportsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Reportes</h1>
        <p className="page-subtitle">Análisis y exportación de datos</p>
      </div>
      <div className="placeholder-section">
        <FileText size={40} className="placeholder-icon" />
        <p>Módulo en construcción — reportes por sucursal, departamento y período</p>
      </div>
    </div>
  )
}
