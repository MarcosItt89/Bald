import { Truck } from 'lucide-react'
import Button from '../../components/ui/Button'

// TODO: Replace with: supabase.from('receiving_orders').select('*, suppliers(*), receiving_items(*)').eq('branch_id', user.branch_id)

export default function ReceivingPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Recibo de mercancía</h1>
          <p className="page-subtitle">Registra entradas de proveedores</p>
        </div>
        <Button variant="primary" size="sm">
          <Truck size={14} /> Nuevo recibo
        </Button>
      </div>
      <div className="placeholder-section">
        <Truck size={40} className="placeholder-icon" />
        <p>Módulo en construcción — se conectará a receiving_orders en Supabase</p>
      </div>
    </div>
  )
}
