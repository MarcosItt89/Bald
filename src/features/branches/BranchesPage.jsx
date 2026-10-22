/** BranchesPage — alta y edición de sucursales (permiso manage_branches). */
import { useState } from 'react'
import { Building2, Plus } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getBranches, saveBranch } from '../../services/organizationService'
import { ACTIVE_STATUS, BRANCH_TYPES } from '../../constants/status'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'

const EMPTY = { code: '', name: '', branch_type: 'tienda', address: '', city: '', phone: '', status: 'active' }

export default function BranchesPage() {
  const toast = useToast()
  const { data: rows = [], loading, error, reload } = useAsync(getBranches)
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
          </form>
        )}
      </Modal>
    </div>
  )
}
