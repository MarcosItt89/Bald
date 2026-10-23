/**
 * AnnouncementsPage — comunicados con acuse de lectura.
 * - Para mí / Anteriores: los comunicados de mi alcance; confirmo con «Leído».
 * - Publicados (publish_announcements / manage_announcements): avance de
 *   lectura y quién falta, por sucursal y persona.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Archive, Check, CheckCheck, Megaphone, Paperclip, Plus, Users } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import {
  archiveAnnouncement, getAnnouncementProgress, getAnnouncements, getAttachmentUrl, markAnnouncementRead, publishAnnouncement,
} from '../../services/announcementService'
import { getDepartments, getMyBranches, getZones } from '../../services/organizationService'
import { addDaysISO, formatDate, formatDateTime, formatRelative, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input, { Textarea } from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import ProgressBar from '../../components/ui/ProgressBar'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'

const SCOPES = { company: 'Toda la empresa', zone: 'Una zona', branch: 'Una sucursal', department: 'Un departamento' }

const scopeLabel = (a) => ({
  company: 'Toda la empresa',
  zone: `Zona ${a.zone_name ?? ''}`,
  branch: a.branch_name,
  department: `${a.department_name ?? ''} · ${a.branch_name ?? 'todas las sucursales'}`,
}[a.scope])

export default function AnnouncementsPage() {
  const { profile, hasPermission, isCompanyScope } = useAuth()
  const toast = useToast()
  const [params] = useSearchParams()
  const focusId = params.get('id')
  const canPublish = hasPermission(P.PUBLISH_ANNOUNCEMENTS)
  const seesAll = hasPermission(P.MANAGE_ANNOUNCEMENTS) && isCompanyScope
  const [chosenTab, setTab] = useState(null)
  const [publishing, setPublishing] = useState(false)
  const [tracking, setTracking] = useState(null)
  const [busy, setBusy] = useState(null)

  const { data: all = [], loading, error, reload } = useAsync(getAnnouncements)

  const lists = useMemo(() => ({
    mine: all.filter((a) => a.is_for_me && a.status === 'active' && !a.is_expired)
      .sort((a, b) => Number(!!a.my_read_at) - Number(!!b.my_read_at)),
    past: all.filter((a) => a.is_for_me && a.status === 'active' && a.is_expired),
    published: all.filter((a) => a.published_by === profile.id || seesAll),
  }), [all, profile.id, seesAll])

  // Desde una notificación (?id=…): abre la pestaña donde está y lo resalta.
  const focusTab = focusId ? ['mine', 'past', 'published'].find((k) => lists[k].some((a) => a.id === focusId)) : null
  const tab = chosenTab ?? focusTab ?? 'mine'
  useEffect(() => {
    if (focusTab) setTimeout(() => document.getElementById(`ann-${focusId}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 200)
  }, [focusId, focusTab])

  const markRead = async (a) => {
    setBusy(a.id)
    try { await markAnnouncementRead(a.id); toast.success('Confirmado como leído'); reload() } catch (err) { toast.error(err.message) } finally { setBusy(null) }
  }
  const archive = async (a) => {
    if (!window.confirm(`¿Archivar «${a.title}»? Ya no lo verán los empleados.`)) return
    try { await archiveAnnouncement(a.id); toast.success('Comunicado archivado'); reload() } catch (err) { toast.error(err.message) }
  }

  const unread = lists.mine.filter((a) => !a.my_read_at).length
  const rows = lists[tab]

  return (
    <div className="page">
      <PageHeader icon={Megaphone} title="Comunicados" subtitle="Avisos oficiales: léelos y confirma con «Leído»"
        actions={canPublish && <Button size="sm" onClick={() => setPublishing(true)}><Plus size={14} /> Publicar</Button>} />
      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'mine', label: 'Para mí', count: unread || undefined },
        { key: 'past', label: 'Anteriores' },
        ...(canPublish || seesAll ? [{ key: 'published', label: seesAll ? 'Todos los publicados' : 'Publicados por mí' }] : []),
      ]} />
      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !all.length ? <Loader /> : !rows.length ? (
        <EmptyState icon={Megaphone} title={tab === 'published' ? 'Aún no publicas comunicados' : 'Sin comunicados'}
          message={tab === 'mine' ? 'Aquí aparecen los avisos vigentes para ti.' : undefined} />
      ) : (
        <div className="ann-list">
          {rows.map((a) => (
            <AnnouncementCard key={a.id} a={a} mode={tab} focused={a.id === focusId} busy={busy === a.id}
              onRead={() => markRead(a)} onTrack={() => setTracking(a)} onArchive={() => archive(a)} />
          ))}
        </div>
      )}
      {publishing && <PublishModal onClose={() => setPublishing(false)} onDone={() => { setPublishing(false); setTab('published'); reload() }} />}
      {tracking && <ProgressModal a={tracking} onClose={() => setTracking(null)} />}
    </div>
  )
}

function AnnouncementCard({ a, mode, focused, busy, onRead, onTrack, onArchive }) {
  const toast = useToast()
  const openAttachment = async () => {
    try { window.open(await getAttachmentUrl(a.attachment_path), '_blank', 'noopener') } catch (err) { toast.error(err.message) }
  }
  const pending = a.audience != null ? a.audience - a.read_count : null
  return (
    <article id={`ann-${a.id}`} className={`card ann-card ${a.is_for_me && !a.my_read_at && mode !== 'published' ? 'ann-unread' : ''} ${focused ? 'ann-focus' : ''}`}>
      <header className="ann-head">
        <h3>{a.title}</h3>
        {mode === 'published'
          ? <Badge color={a.status === 'archived' ? 'default' : a.is_expired ? 'warning' : 'success'}>{a.status === 'archived' ? 'Archivado' : a.is_expired ? 'Vencido' : 'Vigente'}</Badge>
          : a.my_read_at ? <Badge color="success"><CheckCheck size={12} /> Leído</Badge> : <Badge color="warning">Por confirmar</Badge>}
      </header>
      <p className="cell-sub">
        {a.published_by_name ?? 'Operalia'} · {formatRelative(a.published_at)} · {scopeLabel(a)}
        {a.valid_until ? ` · vigente hasta ${formatDate(a.valid_until)}` : ''}
      </p>
      <p className="ann-body">{a.body}</p>
      {a.attachment_path && (
        <button type="button" className="link-btn ann-attach" onClick={openAttachment}><Paperclip size={14} /> {a.attachment_name ?? 'Adjunto'}</button>
      )}
      <footer className="ann-foot">
        {mode === 'published' ? (
          <>
            {a.audience != null && (
              <div className="ann-progress">
                <ProgressBar value={a.read_count} total={a.audience} label={`${a.read_count}/${a.audience} leído`} />
                <span className="cell-sub">{pending ? `Faltan ${pending}` : 'Todos lo leyeron'}</span>
              </div>
            )}
            <div className="row-actions">
              <Button size="sm" variant="outline" onClick={onTrack}><Users size={14} /> Quién falta</Button>
              {a.status === 'active' && <Button size="sm" variant="ghost" onClick={onArchive}><Archive size={14} /> Archivar</Button>}
            </div>
          </>
        ) : a.my_read_at ? (
          <span className="cell-sub"><Check size={12} /> Confirmaste {formatDateTime(a.my_read_at)}</span>
        ) : (
          <Button size="sm" variant="success" loading={busy} onClick={onRead}><Check size={14} /> Marcar como leído</Button>
        )}
      </footer>
    </article>
  )
}

function PublishModal({ onClose, onDone }) {
  const { profile, isCompanyScope, isZoneScope, zoneIds, workingBranchId } = useAuth()
  const toast = useToast()
  const zoneKey = (zoneIds ?? []).join(',')
  const loadBranches = useCallback(() => getMyBranches({ isCompanyScope, isZoneScope, zoneIds: zoneKey ? zoneKey.split(',') : [] }), [isCompanyScope, isZoneScope, zoneKey])
  const { data: myBranches = [] } = useAsync(loadBranches)
  // Roles de una sola sucursal: getMyBranches no devuelve lista, se usa la suya.
  const branches = myBranches.length ? myBranches : profile.branch_id ? [{ id: profile.branch_id, name: profile.branch_name }] : []
  const loadZones = useCallback(() => getZones({ onlyActive: true }), [])
  const { data: zones = [] } = useAsync(loadZones)
  const loadDepts = useCallback(() => getDepartments({ onlyActive: true }), [])
  const { data: departments = [] } = useAsync(loadDepts)
  const [form, setForm] = useState({
    title: '', body: '', scope: 'branch', zone_id: '', branch_id: workingBranchId ?? profile.branch_id ?? '', department_id: '',
    valid_until: addDaysISO(todayISO(), 7),
  })
  const [file, setFile] = useState(null)
  const [saving, setSaving] = useState(false)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const myZones = isCompanyScope ? zones : zones.filter((z) => zoneKey.split(',').includes(z.id))
  const scopes = Object.entries(SCOPES).filter(([k]) => k !== 'company' || isCompanyScope).filter(([k]) => k !== 'zone' || myZones.length)

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await publishAnnouncement({ ...form, file, companyId: profile.company_id })
      toast.success('Comunicado publicado y notificado')
      onDone()
    } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title="Publicar comunicado"
      footer={<><Button variant="ghost" onClick={onClose}>Cancelar</Button><Button type="submit" form="ann-form" loading={saving}><Megaphone size={14} /> Publicar</Button></>}>
      <form id="ann-form" className="form-stack" onSubmit={submit}>
        <Input label="Título" required maxLength={120} placeholder="Ej. Inventario general el domingo" value={form.title} onChange={set('title')} />
        <Textarea label="Mensaje" required rows={5} value={form.body} onChange={set('body')} />
        <div className="form-grid">
          <Select label="Para" value={form.scope} options={scopes.map(([value, label]) => ({ value, label }))} onChange={set('scope')} />
          {form.scope === 'zone' && (
            <Select label="Zona" required value={form.zone_id} placeholder="Elige zona" options={myZones.map((z) => ({ value: z.id, label: z.name }))} onChange={set('zone_id')} />
          )}
          {['branch', 'department'].includes(form.scope) && (
            <Select label="Sucursal" required={form.scope === 'branch' || !isCompanyScope} value={form.branch_id ?? ''}
              placeholder={form.scope === 'department' && isCompanyScope ? 'Todas las sucursales' : 'Elige sucursal'}
              options={branches.map((b) => ({ value: b.id, label: b.name }))} onChange={set('branch_id')} />
          )}
          {form.scope === 'department' && (
            <Select label="Departamento" required value={form.department_id} placeholder="Elige departamento" options={departments.map((d) => ({ value: d.id, label: d.name }))} onChange={set('department_id')} />
          )}
          <Input label="Vigente hasta" type="date" required min={todayISO()} value={form.valid_until} onChange={set('valid_until')} />
        </div>
        <label className="form-group">
          <span className="form-label">Adjunto (opcional)</span>
          <input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" className="form-input" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          <span className="form-hint">Imagen o PDF de hasta 10 MB</span>
        </label>
      </form>
    </Modal>
  )
}

function ProgressModal({ a, onClose }) {
  const load = useCallback(() => getAnnouncementProgress(a.id), [a.id])
  const { data: people = [], loading, error, reload } = useAsync(load)
  const [showRead, setShowRead] = useState(false)
  const byBranch = useMemo(() => {
    const m = new Map()
    for (const p of people) {
      const k = p.branch_name ?? 'Sin sucursal'
      if (!m.has(k)) m.set(k, [])
      m.get(k).push(p)
    }
    return [...m.entries()].map(([name, list]) => ({ name, list, read: list.filter((p) => p.read_at).length }))
      .sort((x, y) => (x.read / x.list.length) - (y.read / y.list.length))
  }, [people])
  const read = people.filter((p) => p.read_at).length

  return (
    <Modal open onClose={onClose} title={a.title} footer={<Button variant="ghost" onClick={onClose}>Cerrar</Button>}>
      {error && <ErrorState error={error} onRetry={reload} />}
      {loading ? <Loader /> : (
        <>
          <p className="cell-sub mb-2">{read} de {people.length} personas confirmaron · {scopeLabel(a)}</p>
          <label className="checkbox mb-2"><input type="checkbox" checked={showRead} onChange={(e) => setShowRead(e.target.checked)} /> Mostrar también quién ya leyó</label>
          <div className="ann-branches">
            {byBranch.map((b) => (
              <section key={b.name} className="ann-branch">
                <div className="ann-branch-head">
                  <strong>{b.name}</strong>
                  <span className={b.read < b.list.length ? 'td-danger' : 'text-muted'}>{b.list.length - b.read ? `faltan ${b.list.length - b.read}` : 'completa'}</span>
                </div>
                <ProgressBar value={b.read} total={b.list.length} label={`${b.read}/${b.list.length}`} />
                <ul className="ann-people">
                  {b.list.filter((p) => showRead || !p.read_at).map((p) => (
                    <li key={p.employee_id} className={p.read_at ? 'ann-person-read' : ''}>
                      <span>{p.full_name}<span className="cell-sub"> · {[p.job_title, p.department_name].filter(Boolean).join(' · ')}</span></span>
                      <span className="cell-sub">{p.read_at ? formatDateTime(p.read_at) : 'Pendiente'}</span>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </div>
        </>
      )}
    </Modal>
  )
}
