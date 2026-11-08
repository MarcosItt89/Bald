/** BranchesPage — alta y edición de sucursales (permiso manage_branches). */
import { useState } from 'react'
import { Building2, Plus } from 'lucide-react'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { getBranches, getZones, saveBranch } from '../../services/organizationService'
import { ACTIVE_STATUS, BRANCH_TYPES } from '@operalia/compartido/constants/status.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import StatusBadge from '@operalia/compartido/components/ui/StatusBadge.jsx'
import Modal from '@operalia/compartido/components/ui/Modal.jsx'
import Input from '@operalia/compartido/components/ui/Input.jsx'
import Select from '@operalia/compartido/components/ui/Select.jsx'
import { ErrorState } from '@operalia/compartido/components/ui/Feedback.jsx'

const EMPTY = { code: '', name: '', branch_type: 'tienda', address: '', city: '', phone: '', status: 'active' }

export default function BranchesPage() {
  const toast = useToast()
  const { data: rows = [], loading, error, reload } = useAsync(getBranches)
  const { data: zones = [] } = useAsync(getZones)
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try { await saveBranch(form); toast.success('Sucursal guardada'); setForm(null); reload() } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  return (
    <div className="page">
      <PageHeader icon={Building2} title="Sucursales" subtitle={`${rows.length} sucursales`}
        actions={<Button size="sm" onClick={() => setForm(EMPTY)}><Plus size={14} /> Nueva sucursal</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} columns={[
          { key: 'code', label: 'No.', mono: true, sortable: true },
          { key: 'name', label: 'Nombre', bold: true, sortable: true },
          { key: 'branch_type', label: 'Tipo', render: (v) => BRANCH_TYPES[v] ?? v },
          { key: 'address', label: 'Dirección' },
          { key: 'city', label: 'Ciudad' },
          { key: 'zone', label: 'Zona', render: (v) => v?.name ?? <span className="text-muted">—</span> },
          { key: 'manager', label: 'Gerente', render: (v) => v?.full_name ?? '—' },
          { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={ACTIVE_STATUS} value={v} /> },
        ]} />
      </Card>
      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar sucursal' : 'Nueva sucursal'}
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="branch-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="branch-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid">
              <Input label="Número / clave" required value={form.code} onChange={set('code')} />
              <Select label="Tipo" value={form.branch_type} onChange={set('branch_type')} options={Object.entries(BRANCH_TYPES).map(([value, label]) => ({ value, label }))} />
            </div>
            <Input label="Nombre" required value={form.name} onChange={set('name')} />
            <Input label="Dirección" value={form.address ?? ''} onChange={set('address')} />
            <div className="form-grid form-grid-3">
              <Input label="Ciudad" value={form.city ?? ''} onChange={set('city')} />
              <Input label="Teléfono" value={form.phone ?? ''} onChange={set('phone')} />
              <Select label="Estado" value={form.status} onChange={set('status')} options={[{ value: 'active', label: 'Activa' }, { value: 'inactive', label: 'Inactiva' }]} />
            </div>
            <Select label="Zona" value={form.zone_id ?? ''} placeholder="Sin zona" onChange={set('zone_id')}
              options={zones.filter((z) => z.is_active || z.id === form.zone_id).map((z) => ({ value: z.id, label: `${z.code} · ${z.name}` }))}
              hint="Los jefes de zona (p. ej. Jefe de Escáner) ven las sucursales de sus zonas." />
          </form>
        )}
      </Modal>
    </div>
  )
}
