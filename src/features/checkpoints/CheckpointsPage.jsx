/**
 * CheckpointsPage — puntos de control con QR (permiso manage_checkpoints).
 * Cada sucursal registra sus puntos con el mismo nombre que usan las
 * plantillas (p. ej. «Área de carritos») e imprime sus QR para pegarlos.
 */
import { useCallback, useState } from 'react'
import { Plus, Printer, QrCode } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getCheckpoints, saveCheckpoint } from '../../services/checkpointService'
import { getDepartments } from '../../services/organizationService'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'
import { printCheckpoints, qrSvg } from './printCheckpoints'

export default function CheckpointsPage() {
  const { branchFilter, workingBranchId, profile } = useAuth()
  const toast = useToast()
  const load = useCallback(() => getCheckpoints({ branchId: branchFilter }), [branchFilter])
  const { data: rows = [], loading, error, reload } = useAsync(load)
  const { data: departments = [] } = useAsync(getDepartments)
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await saveCheckpoint({ ...form, name: form.name.trim(), company_id: profile.company_id })
      toast.success('Punto guardado')
      setForm(null)
      reload()
    } catch (err) {
      toast.error(err.message.includes('duplicate') ? 'Ya existe un punto con ese nombre en la sucursal' : err.message)
    } finally { setSaving(false) }
  }

  const active = rows.filter((r) => r.is_active)

  return (
    <div className="page">
      <PageHeader icon={QrCode} title="Puntos QR" subtitle={`${rows.length} puntos · las plantillas que lo exigen se inician escaneando el QR del punto`}
        actions={<>
          <Button size="sm" variant="outline" disabled={!active.length} onClick={() => printCheckpoints(active)}><Printer size={14} /> Imprimir QR</Button>
          <Button size="sm" disabled={!workingBranchId} onClick={() => setForm({ name: '', department_id: '', branch_id: workingBranchId, is_active: true })}><Plus size={14} /> Nuevo punto</Button>
        </>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} emptyText="Sin puntos en esta sucursal" columns={[
          { key: 'name', label: 'Punto', bold: true, sortable: true, render: (v, r) => (
            <span className="qr-row"><span className="qr-thumb" aria-hidden="true" dangerouslySetInnerHTML={{ __html: qrSvg(r.code) }} />
              <span>{v}<span className="cell-sub td-mono">{r.code}</span></span></span>
          ) },
          { key: 'branch', label: 'Sucursal', render: (v) => v?.name },
          { key: 'department', label: 'Departamento', render: (v) => v?.name ?? '—' },
          { key: 'is_active', label: 'Estado', render: (v) => <Badge color={v ? 'success' : 'default'}>{v ? 'Activo' : 'Inactivo'}</Badge> },
          { key: 'print', label: '', render: (_, r) => (
            <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); printCheckpoints([r]) }}><Printer size={14} /> Imprimir</Button>
          ) },
        ]} />
      </Card>

      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar punto' : 'Nuevo punto'} size="sm"
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="cp-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="cp-form" className="form-stack" onSubmit={submit}>
            <Input label="Nombre del punto" required placeholder="Ej. Área de carritos, Cámara de carnes" value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              hint="Usa el mismo nombre en todas las sucursales: así una plantilla sirve para todas." />
            <Select label="Departamento" value={form.department_id ?? ''} placeholder="General"
              options={departments.map((d) => ({ value: d.id, label: d.name }))} onChange={(e) => setForm({ ...form, department_id: e.target.value })} />
            <label className="checkbox"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} /> Activo</label>
            {form.code && (
              <div className="qr-preview">
                <span dangerouslySetInnerHTML={{ __html: qrSvg(form.code) }} />
                <span className="td-mono">{form.code}</span>
              </div>
            )}
          </form>
        )}
      </Modal>
    </div>
  )
}
