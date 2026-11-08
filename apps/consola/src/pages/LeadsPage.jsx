/**
 * LeadsPage — Plataforma → Prospectos (solo superadmins, tabla platform_leads).
 * Cadenas interesadas: contacto, sucursales, giro, estado y notas. Un
 * prospecto «ganado» sin empresa tiene el botón «Dar de alta», que abre
 * Nueva empresa con sus datos llenos; al crearla queda ligado.
 */
import { useCallback, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Handshake, Plus, Rocket, Trash2 } from 'lucide-react'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { deleteLead, getCompanies, getLeads, saveLead } from '../services/platformService'
import { LEAD_STATUS, toOptions } from '@operalia/compartido/constants/status.js'
import { formatRelative } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Tabs from '@operalia/compartido/components/ui/Tabs.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import Modal from '@operalia/compartido/components/ui/Modal.jsx'
import Input, { Textarea } from '@operalia/compartido/components/ui/Input.jsx'
import Select from '@operalia/compartido/components/ui/Select.jsx'
import StatusBadge from '@operalia/compartido/components/ui/StatusBadge.jsx'
import { ErrorState } from '@operalia/compartido/components/ui/Feedback.jsx'
import { usePlatformPath } from '../paths'

const EMPTY = { chain_name: '', contact_name: '', contact_email: '', contact_phone: '', branch_count: '', business_type: '', status: 'new', notes: '' }
const OPEN = ['new', 'demo', 'negotiation']

const TABS = [
  { key: 'open', label: 'En proceso', match: (l) => OPEN.includes(l.status) },
  { key: 'won', label: 'Ganados', match: (l) => l.status === 'won' },
  { key: 'lost', label: 'Perdidos', match: (l) => l.status === 'lost' },
  { key: 'all', label: 'Todos', match: () => true },
]

export default function LeadsPage() {
  const navigate = useNavigate()
  const path = usePlatformPath()
  const toast = useToast()
  const { data: leads = [], loading, error, reload } = useAsync(getLeads)
  const { data: companies = [] } = useAsync(getCompanies)
  const companyById = useMemo(() => new Map(companies.map((c) => [c.id, c])), [companies])
  const [tab, setTab] = useState('open')
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const current = TABS.find((t) => t.key === tab)
  const rows = leads.filter(current.match)
  const tabs = TABS.map((t) => ({ key: t.key, label: t.label, count: t.key === 'all' ? 0 : leads.filter(t.match).length }))

  const provision = useCallback((lead) => navigate(path('nueva'), { state: { lead } }), [navigate, path])

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const branchCount = form.branch_count === '' || form.branch_count == null ? null : Number(form.branch_count)
      await saveLead({ ...form, branch_count: branchCount })
      toast.success('Prospecto guardado')
      setForm(null)
      reload()
    } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  const remove = async () => {
    if (!window.confirm(`¿Eliminar el prospecto «${form.chain_name}»?`)) return
    try { await deleteLead(form.id); toast.success('Prospecto eliminado'); setForm(null); reload() } catch (err) { toast.error(err.message) }
  }

  return (
    <div className="page">
      <PageHeader icon={Handshake} title="Prospectos" subtitle="Cadenas interesadas en Operalia y su avance"
        actions={<Button size="sm" onClick={() => setForm(EMPTY)}><Plus size={14} /> Nuevo prospecto</Button>} />
      <Tabs active={tab} onChange={setTab} tabs={tabs} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} emptyText="Sin prospectos aquí" columns={[
          { key: 'chain_name', label: 'Cadena', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub">{r.business_type ?? '—'}</div></> },
          { key: 'contact_name', label: 'Contacto', render: (v, r) => <>{v ?? '—'}<div className="cell-sub">{[r.contact_email, r.contact_phone].filter(Boolean).join(' · ')}</div></> },
          { key: 'branch_count', label: 'Sucursales', align: 'right', sortable: true, render: (v) => v ?? '—' },
          { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={LEAD_STATUS} value={v} /> },
          { key: 'company_id', label: 'Empresa', render: (v, r) => {
            if (v) return <span className="mono">{companyById.get(v)?.code ?? 'dada de alta'}</span>
            if (r.status !== 'won') return <span className="text-muted">—</span>
            return <Button size="sm" onClick={(e) => { e.stopPropagation(); provision(r) }}><Rocket size={14} /> Dar de alta</Button>
          } },
          { key: 'updated_at', label: 'Actividad', sortable: true, render: formatRelative },
        ]} />
      </Card>

      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar prospecto' : 'Nuevo prospecto'}
        footer={<>
          {form?.id && <Button variant="ghost" onClick={remove}><Trash2 size={14} /> Eliminar</Button>}
          <Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button>
          <Button type="submit" form="lead-form" loading={saving}>Guardar</Button>
        </>}>
        {form && (
          <form id="lead-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid form-grid-top">
              <Input label="Nombre de la cadena" required value={form.chain_name} onChange={set('chain_name')} />
              <Input label="Giro" value={form.business_type ?? ''} onChange={set('business_type')} placeholder="Supermercado, farmacia…" />
            </div>
            <div className="form-grid form-grid-3 form-grid-top">
              <Input label="Contacto" value={form.contact_name ?? ''} onChange={set('contact_name')} />
              <Input label="Correo" type="email" value={form.contact_email ?? ''} onChange={set('contact_email')} />
              <Input label="Teléfono" value={form.contact_phone ?? ''} onChange={set('contact_phone')} />
            </div>
            <div className="form-grid form-grid-top">
              <Input label="Número de sucursales" type="number" min={0} value={form.branch_count ?? ''} onChange={set('branch_count')}
                hint="Al darla de alta, el avance de arranque cuenta contra este número" />
              <Select label="Estado" value={form.status} onChange={set('status')} options={toOptions(LEAD_STATUS)} />
            </div>
            <Textarea label="Notas" rows={4} value={form.notes ?? ''} onChange={set('notes')} />
            {form.id && form.status === 'won' && !form.company_id && (
              <Button variant="success" onClick={() => provision(form)}><Rocket size={14} /> Dar de alta</Button>
            )}
          </form>
        )}
      </Modal>
    </div>
  )
}
