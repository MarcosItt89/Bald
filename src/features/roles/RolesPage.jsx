import { Shield } from 'lucide-react'
import { ROLES } from '../../data/mockData'
import Badge from '../../components/ui/Badge'

// TODO: Replace ROLES with: supabase.from('roles').select('*, role_permissions(permissions(*))')

export default function RolesPage() {
  const roles = Object.values(ROLES)
  return (
    <div className="page">
      <div className="page-header">
        <h1 className="page-title">Roles</h1>
        <p className="page-subtitle">{roles.length} roles configurados</p>
      </div>

      <div className="roles-grid">
        {roles.map(role => (
          <div key={role.id} className="card role-card">
            <div className="card-header">
              <h3 className="card-title"><Shield size={16} /> {role.label}</h3>
              <Badge color="info">{role.permissions.length} permisos</Badge>
            </div>
            <div className="card-body">
              <div className="permission-tags">
                {role.permissions.map(p => (
                  <span key={p} className="permission-tag">{p}</span>
                ))}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
