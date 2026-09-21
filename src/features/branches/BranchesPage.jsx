import { Building2, Plus } from 'lucide-react'
import { MOCK_BRANCHES } from '../../data/mockData'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_BRANCHES with: supabase.from('branches').select('*').eq('company_id', user.company_id)

export default function BranchesPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Sucursales</h1>
          <p className="page-subtitle">{MOCK_BRANCHES.length} sucursales registradas</p>
        </div>
        <Button variant="primary" size="sm">
          <Plus size={14} /> Nueva sucursal
        </Button>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Nombre</th><th>Dirección</th><th>Ciudad</th>
                <th>Gerente</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_BRANCHES.map(b => (
                <tr key={b.id}>
                  <td className="td-bold">
                    <Building2 size={14} className="inline-icon" /> {b.name}
                  </td>
                  <td>{b.address}</td>
                  <td>{b.city}</td>
                  <td>{b.manager}</td>
                  <td>
                    <Badge color={b.status === 'active' ? 'success' : 'default'}>
                      {b.status === 'active' ? 'Activa' : 'Inactiva'}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
