import { UserCheck, Plus } from 'lucide-react'
import { MOCK_USERS, ROLES } from '../../data/mockData'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_USERS with: supabase.from('employees').select('*, roles(label)').eq('branch_id', user.branch_id)

export default function EmployeesPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Empleados</h1>
          <p className="page-subtitle">{MOCK_USERS.length} empleados registrados</p>
        </div>
        <Button variant="primary" size="sm">
          <Plus size={14} /> Nuevo empleado
        </Button>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Nombre</th><th>Correo</th><th>Sucursal</th>
                <th>Departamento</th><th>Rol</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_USERS.map(u => (
                <tr key={u.id}>
                  <td className="td-bold"><UserCheck size={14} className="inline-icon" /> {u.name}</td>
                  <td>{u.email}</td>
                  <td>{u.branch}</td>
                  <td>{u.department}</td>
                  <td><Badge color="info">{ROLES[u.role]?.label ?? u.role}</Badge></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
