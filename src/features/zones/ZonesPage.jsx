/**
 * ZonesPage — zonas que agrupan sucursales (Norte, Sur...). Permiso manage_branches.
 * Los roles con alcance «zona» (p. ej. Jefe de Escáner) ven las sucursales de sus zonas.
 * La zona de cada sucursal se elige en Sucursales.
 */
import { useState } from 'react'
import { Map as MapIcon, Plus } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getZones, saveZone } from '../../services/organizationService'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import { ErrorState } from '../../components/ui/Feedback'

const EMPTY = { code: '', name: '', is_active: true }

export default function ZonesPage() {
  const toast = useToast()
  const { data: rows = [], loading, error, reload } = useAsync(getZones)
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try { await saveZone({ ...form, code: form.code.trim().toUpperCase() }); toast.success('Zona guardada'); setForm(null); reload() } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  return (
    <div className="page">
      <PageHeader icon={MapIcon} title="Zonas" subtitle={`${rows.length} zonas · agrupan sucursales para los jefes de zona`}
        actions={<Button size="sm" onClick={() => setForm(EMPTY)}><Plus size={14} /> Nueva zona</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} emptyText="Sin zonas" columns={[
          { key: 'name', label: 'Zona', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.code}</div></> },
          { key: 'branches', label: 'Sucursales', render: (v) => (v?.length
            ? v.map((b) => `${b.code} · ${b.name}`).join(', ')
            : <span className="text-muted">Sin sucursales</span>) },
          { key: 'is_active', label: 'Estado', render: (v) => <Badge color={v ? 'success' : 'default'}>{v ? 'Activa' : 'Inactiva'}</Badge> },
        ]} />
      </Card>
      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar zona' : 'Nueva zona'} size="sm"
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="zone-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="zone-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid">
              <Input label="Clave" required maxLength={10} placeholder="NOR" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} />
              <Input label="Nombre" required placeholder="Norte" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </div>
            <label className="checkbox"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} /> Activa</label>
            <p className="text-muted text-sm">Asigna sucursales a esta zona desde Configuración → Sucursales.</p>
          </form>
        )}
      </Modal>
    </div>
  )
}
