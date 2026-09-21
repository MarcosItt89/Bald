import { Key } from 'lucide-react'
import { PERMISSIONS } from '../../data/mockData'

// TODO: Replace PERMISSIONS with: supabase.from('permissions').select('*')

export default function PermissionsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Permisos</h1>
        <p className="page-subtitle">{PERMISSIONS.length} permisos del sistema</p>
      </div>

      <div className="card">
        <div className="card-body">
          <div className="permission-tags-lg">
            {PERMISSIONS.map(p => (
              <span key={p} className="permission-tag-lg">
                <Key size={12} /> {p}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
