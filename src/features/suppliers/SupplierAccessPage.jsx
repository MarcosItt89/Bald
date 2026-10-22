/**
 * SupplierAccessPage — entrada y salida de proveedores (caseta / Protección).
 *
 * "Dentro de tienda" muestra quién está en la sucursal y cuánto tiempo lleva
 * (útil para detectar proveedores que se quedan demasiado). La salida
 * registra la hora y quién la autorizó.
 */
import { useCallback, useState } from 'react'
import { DoorOpen, LogIn, LogOut } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getSuppliers, getVisits, registerVisit, closeVisit } from '../../services/supplierService'
import { addDaysISO, formatDateTime, formatDuration, formatTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input, { Textarea } from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'

const PURPOSES = [
  { value: 'entrega', label: 'Entrega de mercancía' },
  { value: 'recoleccion', label: 'Recolección / devolución' },
  { value: 'surtido', label: 'Surtido / promotoría' },
  { value: 'servicio', label: 'Servicio / mantenimiento' },
  { value: 'otro', label: 'Otro' },
]

export default function SupplierAccessPage() {
  const { branchFilter, workingBranchId, profile } = useAuth()
  const toast = useToast()
  const [from, setFrom] = useState(addDaysISO(todayISO(), -7))
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({ supplier_id: '', driver_name: '', vehicle_plate: '', purpose: 'entrega', notes: '' })
  const [saving, setSaving] = useState(false)

  // "Dentro" no depende del filtro de fechas: un proveedor que entró hace días sigue adentro.
  const loadInside = useCallback(() => getVisits({ branchId: branchFilter, onlyOpen: true }), [branchFilter])
  const insideQ = useAsync(loadInside)
  const load = useCallback(() => getVisits({ branchId: branchFilter, from }), [branchFilter, from])
  const { data: visits = [], loading, error, reload: reloadHistory } = useAsync(load)
  const reload = () => { insideQ.reload(); reloadHistory() }
  const loadSuppliers = useCallback(() => getSuppliers({ status: 'active' }), [])
  const { data: suppliers = [] } = useAsync(loadSuppliers)

  const inside = insideQ.data ?? []
  const history = visits.filter((v) => v.check_out_at)

  const checkIn = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await registerVisit({ ...form, branch_id: workingBranchId })
      toast.success('Entrada registrada')
      setCreating(false)
      setForm({ supplier_id: '', driver_name: '', vehicle_plate: '', purpose: 'entrega', notes: '' })
      reload()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const checkOut = async (visit) => {
    try {
      await closeVisit(visit.id, profile.id)
      toast.success(`Salida registrada: ${visit.supplier_name}`)
      reload()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="page">
      <PageHeader icon={DoorOpen} title="Accesos de proveedores" subtitle="Registro de entradas y salidas en caseta"
        actions={<Button size="sm" onClick={() => setCreating(true)}><LogIn size={14} /> Registrar entrada</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}

      <Card title={<>Dentro de tienda <Badge color={inside.length ? 'warning' : 'default'}>{inside.length}</Badge></>} flush>
        <Table data={inside} loading={insideQ.loading} emptyText="No hay proveedores dentro" columns={[
          { key: 'supplier_name', label: 'Proveedor', bold: true, render: (v, r) => <>{v}<div className="cell-sub">{r.supplier_code}</div></> },
          { key: 'driver_name', label: 'Chofer' },
          { key: 'vehicle_plate', label: 'Placas', mono: true },
          { key: 'purpose', label: 'Motivo', render: (v) => PURPOSES.find((p) => p.value === v)?.label ?? v },
          { key: 'check_in_at', label: 'Entrada', render: formatTime },
          { key: 'minutes_inside', label: 'Tiempo', render: (v) => (
            <span className={v > 120 ? 'td-danger' : ''}>{formatDuration(v)}</span>
          ) },
          { key: 'actions', label: '', render: (_, r) => (
            <Button size="sm" variant="outline" onClick={() => checkOut(r)}><LogOut size={14} /> Salida</Button>
          ) },
        ]} />
      </Card>

      <div className="section-header mt-3">
        <h3>Historial</h3>
        <label className="filter-date">Desde <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
      </div>
      <Card flush>
        <Table data={history} loading={loading} emptyText="Sin visitas cerradas en el periodo" columns={[
          { key: 'supplier_name', label: 'Proveedor', bold: true, sortable: true },
          ...(branchFilter ? [] : [{ key: 'branch_name', label: 'Sucursal' }]),
          { key: 'driver_name', label: 'Chofer' },
          { key: 'check_in_at', label: 'Entrada', render: formatDateTime, sortable: true },
          { key: 'check_out_at', label: 'Salida', render: formatDateTime },
          { key: 'minutes_inside', label: 'Duración', render: formatDuration },
          { key: 'registered_by_name', label: 'Registró' },
          { key: 'closed_by_name', label: 'Cerró' },
        ]} />
      </Card>

      <Modal open={creating} onClose={() => setCreating(false)} title="Registrar entrada de proveedor"
        footer={<>
          <Button variant="ghost" onClick={() => setCreating(false)}>Cancelar</Button>
          <Button type="submit" form="visit-form" loading={saving}>Registrar entrada</Button>
        </>}>
        <form id="visit-form" className="form-stack" onSubmit={checkIn}>
          <Select label="Proveedor" required value={form.supplier_id} placeholder="Selecciona…"
            onChange={(e) => setForm({ ...form, supplier_id: e.target.value })}
            options={suppliers.map((s) => ({ value: s.id, label: `${s.code} · ${s.name}` }))} />
          <div className="form-grid">
            <Input label="Chofer / visitante" value={form.driver_name} onChange={(e) => setForm({ ...form, driver_name: e.target.value })} />
            <Input label="Placas" value={form.vehicle_plate} onChange={(e) => setForm({ ...form, vehicle_plate: e.target.value.toUpperCase() })} />
          </div>
          <Select label="Motivo" value={form.purpose} options={PURPOSES} onChange={(e) => setForm({ ...form, purpose: e.target.value })} />
          <Textarea label="Notas" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
        </form>
      </Modal>
    </div>
  )
}
