import { Layers, Plus } from 'lucide-react'
import { MOCK_DEPARTMENTS } from '../../data/mockData'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_DEPARTMENTS with: supabase.from('departments').select('*').eq('branch_id', user.branch_id)

export default function DepartmentsPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Departamentos</h1>
          <p className="page-subtitle">{MOCK_DEPARTMENTS.length} departamentos</p>
        </div>
        <Button variant="primary" size="sm">
          <Plus size={14} /> Nuevo departamento
        </Button>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Departamento</th><th>Sucursal</th><th>Supervisor</th><th>Empleados</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_DEPARTMENTS.map(d => (
                <tr key={d.id}>
                  <td className="td-bold"><Layers size={14} className="inline-icon" /> {d.name}</td>
                  <td>{d.branch}</td>
                  <td>{d.supervisor}</td>
                  <td>{d.employees}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
