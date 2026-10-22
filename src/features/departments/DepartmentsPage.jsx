/** DepartmentsPage — catálogo de departamentos de la empresa (manage_branches). */
import { useState } from 'react'
import { Layers, Plus } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getDepartments, saveDepartment } from '../../services/organizationService'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import { ErrorState } from '../../components/ui/Feedback'

const EMPTY = { code: '', name: '', description: '', color: '#64748b', is_active: true }

export default function DepartmentsPage() {
  const toast = useToast()
  const { data: rows = [], loading, error, reload } = useAsync(getDepartments)
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try { await saveDepartment({ ...form, code: form.code.toUpperCase() }); toast.success('Departamento guardado'); setForm(null); reload() } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  return (
    <div className="page">
      <PageHeader icon={Layers} title="Departamentos" subtitle={`${rows.length} departamentos`}
        actions={<Button size="sm" onClick={() => setForm(EMPTY)}><Plus size={14} /> Nuevo departamento</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} columns={[
          { key: 'color', label: '', width: 24, render: (v) => <span className="cl-dept-dot" style={{ background: v }} /> },
          { key: 'code', label: 'Clave', mono: true, sortable: true },
          { key: 'name', label: 'Departamento', bold: true, sortable: true },
          { key: 'description', label: 'Descripción' },
          { key: 'is_active', label: 'Estado', render: (v) => <Badge color={v ? 'success' : 'default'}>{v ? 'Activo' : 'Inactivo'}</Badge> },
        ]} />
      </Card>
      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar departamento' : 'Nuevo departamento'} size="sm"
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="dept-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="dept-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid">
              <Input label="Clave" required value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} />
              <Input label="Color" type="color" value={form.color} onChange={(e) => setForm({ ...form, color: e.target.value })} />
            </div>
            <Input label="Nombre" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            <Input label="Descripción" value={form.description ?? ''} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            <label className="checkbox"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} /> Activo</label>
          </form>
        )}
      </Modal>
    </div>
  )
}
