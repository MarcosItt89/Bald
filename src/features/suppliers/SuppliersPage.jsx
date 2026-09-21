import { Users, Plus } from 'lucide-react'
import { MOCK_SUPPLIERS } from '../../data/mockData'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_SUPPLIERS with: supabase.from('suppliers').select('*').eq('company_id', user.company_id)

export default function SuppliersPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Proveedores</h1>
          <p className="page-subtitle">{MOCK_SUPPLIERS.length} proveedores</p>
        </div>
        <Button variant="primary" size="sm">
          <Plus size={14} /> Nuevo proveedor
        </Button>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Código</th><th>Proveedor</th><th>Tipo</th>
                <th>Contacto</th><th>Teléfono</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_SUPPLIERS.map(s => (
                <tr key={s.id}>
                  <td className="td-mono">{s.code}</td>
                  <td className="td-bold"><Users size={14} className="inline-icon" /> {s.name}</td>
                  <td>{s.type}</td>
                  <td>{s.contact}</td>
                  <td>{s.phone}</td>
                  <td>
                    <Badge color={s.status === 'active' ? 'success' : 'default'}>
                      {s.status === 'active' ? 'Activo' : 'Inactivo'}
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
