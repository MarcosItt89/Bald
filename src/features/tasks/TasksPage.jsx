/**
 * TasksPage — tareas operativas (Objetivos §11.12).
 * - "Mis tareas": el asignado inicia, sube foto (si se requiere) y completa con notas.
 * - "Todas": quien tiene manage_tasks crea, edita, reasigna, cancela y elimina
 *   (eliminar solo mientras está pendiente; la BD lo valida).
 * - Filtros por texto, departamento y prioridad. Clic en la fila abre el detalle
 *   con sus evidencias.
 * - Acepta filtros por URL (desde Estadísticas): ?tab=all&done=1&dept=&prio=&late=1&assignee=&age=
 */
import { useCallback, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ListTodo, Plus, Trash2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getTasks, createTask, updateTask, setTaskStatus, deleteTask } from '../../services/taskService'
import { getAssignableEmployees } from '../../services/employeeService'
import { getDepartments } from '../../services/organizationService'
import { getEvidence } from '../../services/evidenceService'
import { PRIORITY, TASK_AGE_BUCKETS, TASK_STATUS, taskAgeBucket, toOptions } from '../../constants/status'
import { formatDate, formatDateTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import Modal from '../../components/ui/Modal'
import Input, { Textarea } from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'
import FilterChip from '../../components/ui/FilterChip'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import EvidenceGallery from '../../components/domain/EvidenceGallery'

const EMPTY = { title: '', description: '', department_id: '', assigned_to: '', due_date: todayISO(), priority: 'medium', requires_evidence: false }
const OPEN = ['pending', 'in_progress']
const EDITABLE_FIELDS = ['id', 'title', 'description', 'department_id', 'assigned_to', 'due_date', 'priority', 'requires_evidence']

export default function TasksPage() {
  const { branchFilter, workingBranchId, hasPermission, profile } = useAuth()
  const toast = useToast()
  const canManage = hasPermission(P.MANAGE_TASKS)
  const canSeeAll = canManage || hasPermission(P.VIEW_REPORTS)
  const canShelf = hasPermission(P.MANAGE_SHELF_GAPS)
  const [params] = useSearchParams()
  const [tab, setTab] = useState(() => (params.get('tab') === 'all' && canSeeAll ? 'all' : 'mine'))
  const [showDone, setShowDone] = useState(() => params.get('done') === '1')
  const [search, setSearch] = useState('')
  const [deptFilter, setDeptFilter] = useState(() => params.get('dept') ?? '')
  const [prioFilter, setPrioFilter] = useState(() => params.get('prio') ?? '')
  const [lateOnly, setLateOnly] = useState(() => params.get('late') === '1')
  const [assignee, setAssignee] = useState(() => params.get('assignee') ?? '')
  const [age, setAge] = useState(() => params.get('age') ?? '')
  const [form, setForm] = useState(null)          // crear / editar
  const [detail, setDetail] = useState(null)      // ver detalle + evidencias
  const [completing, setCompleting] = useState(null)
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  const load = useCallback(() => getTasks({ branchId: branchFilter }), [branchFilter])
  const { data: all = [], loading, error, reload } = useAsync(load)
  const loadPeople = useCallback(() => (canManage ? getAssignableEmployees({ branchId: workingBranchId }) : Promise.resolve([])), [canManage, workingBranchId])
  const { data: people = [] } = useAsync(loadPeople)
  const { data: departments = [] } = useAsync(getDepartments)

  // «Surtir a piso» (huecos en anaquel) no lleva responsable: la toma cualquiera de Almacén.
  const isMine = useCallback((t) => t.assigned_to === profile.id || (canShelf && t.source_type === 'shelf_gap' && !t.assigned_to), [profile.id, canShelf])

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase()
    return all.filter((t) =>
      (tab === 'all' || isMine(t))
      && (showDone || OPEN.includes(t.status))
      && (!deptFilter || t.department_id === deptFilter)
      && (!prioFilter || t.priority === prioFilter)
      && (!lateOnly || t.is_late)
      && (!assignee || t.assigned_to === assignee)
      && (!age || (OPEN.includes(t.status) && taskAgeBucket(t.created_at) === age))
      && (!q || `${t.title} ${t.description ?? ''} ${t.assigned_to_name ?? ''}`.toLowerCase().includes(q)))
  }, [all, tab, showDone, deptFilter, prioFilter, lateOnly, assignee, age, search, isMine])

  const run = async (fn, msg) => {
    try { await fn(); toast.success(msg); reload(); return true } catch (err) { toast.error(err.message); return false }
  }

  const changeStatus = (task, status) => run(() => setTaskStatus(task.id, status), `Tarea: ${TASK_STATUS[status].label.toLowerCase()}`)

  const confirmComplete = async () => {
    setSaving(true)
    const ok = await run(() => setTaskStatus(completing.id, 'completed', notes), 'Tarea completada')
    setSaving(false)
    if (ok) { setCompleting(null); setNotes(''); setDetail(null) }
  }

  const remove = async (task) => {
    if (!window.confirm(`¿Eliminar la tarea "${task.title}"? Esta acción no se puede deshacer.`)) return
    if (await run(() => deleteTask(task.id), 'Tarea eliminada')) setDetail(null)
  }

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    const payload = Object.fromEntries(Object.entries(form).filter(([k]) => EDITABLE_FIELDS.includes(k)))
    const ok = await run(
      () => (payload.id ? updateTask(payload.id, payload) : createTask({ ...payload, branch_id: workingBranchId })),
      payload.id ? 'Tarea actualizada' : 'Tarea creada')
    setSaving(false)
    if (ok) setForm(null)
  }

  const canAct = (t) => isMine(t) || canManage
  const needsPhoto = (t) => t.requires_evidence && !Number(t.evidence_count)

  const actions = (r) => (
    <div className="row-actions" onClick={(e) => e.stopPropagation()}>
      {r.status === 'pending' && canAct(r) && <Button size="sm" variant="outline" onClick={() => changeStatus(r, 'in_progress')}>Iniciar</Button>}
      {r.requires_evidence && OPEN.includes(r.status) && r.assigned_to === profile.id && (
        <EvidenceUploader entityType="task" entityId={r.id} branchId={r.branch_id} label="Foto" variant="ghost" onUploaded={reload} />
      )}
      {OPEN.includes(r.status) && canAct(r) && (
        <Button size="sm" variant="success" disabled={needsPhoto(r)} title={needsPhoto(r) ? 'Sube la evidencia primero' : undefined}
          onClick={() => { setCompleting(r); setNotes('') }}>Completar</Button>
      )}
      {canManage && OPEN.includes(r.status) && <Button size="sm" variant="ghost" onClick={() => changeStatus(r, 'cancelled')}>Cancelar</Button>}
      {canManage && r.status === 'pending' && (
        <button className="icon-btn icon-btn-danger" title="Eliminar" onClick={() => remove(r)}><Trash2 size={14} /></button>
      )}
    </div>
  )

  return (
    <div className="page">
      <PageHeader icon={ListTodo} title="Tareas" subtitle={`${rows.length} tareas`}
        actions={canManage && <Button size="sm" onClick={() => setForm({ ...EMPTY, department_id: profile.department_id ?? '' })}><Plus size={14} /> Nueva tarea</Button>} />
      <Tabs active={tab} onChange={setTab} tabs={[
        { key: 'mine', label: 'Mis tareas', count: all.filter((t) => isMine(t) && OPEN.includes(t.status)).length },
        ...(canSeeAll ? [{ key: 'all', label: 'Todas' }] : []),
      ]} />
      <div className="filters">
        <SearchInput value={search} onChange={setSearch} placeholder="Buscar tarea o responsable…" />
        <select className="filter-select" value={deptFilter} onChange={(e) => setDeptFilter(e.target.value)}>
          <option value="">Todos los departamentos</option>
          {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="filter-select" value={prioFilter} onChange={(e) => setPrioFilter(e.target.value)}>
          <option value="">Todas las prioridades</option>
          {toOptions(PRIORITY).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        <label className="checkbox"><input type="checkbox" checked={showDone} onChange={(e) => setShowDone(e.target.checked)} /> Incluir completadas y canceladas</label>
        {lateOnly && <FilterChip label="Solo atrasadas" onClear={() => setLateOnly(false)} />}
        {age && <FilterChip label={`Abiertas hace ${TASK_AGE_BUCKETS.find((b) => b.key === age)?.label ?? age}`} onClear={() => setAge('')} />}
        {assignee && <FilterChip label={`Responsable: ${all.find((t) => t.assigned_to === assignee)?.assigned_to_name ?? 'seleccionado'}`} onClear={() => setAssignee('')} />}
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setDetail} emptyText="Sin tareas con estos filtros" columns={[
          { key: 'title', label: 'Tarea', bold: true, sortable: true, render: (v, r) => <>{v}{r.description && <div className="cell-sub">{r.description}</div>}</> },
          { key: 'department_name', label: 'Departamento', sortable: true },
          { key: 'assigned_to_name', label: 'Responsable', sortable: true, render: (v) => v ?? <span className="text-muted">Sin asignar</span> },
          { key: 'due_date', label: 'Límite', sortable: true, render: (v, r) => <>{formatDate(v)}{r.is_late && <Badge color="danger" className="ml-1">Atrasada</Badge>}</> },
          { key: 'priority', label: 'Prioridad', render: (v) => <StatusBadge statusMap={PRIORITY} value={v} /> },
          { key: 'status', label: 'Estado', render: (v, r) => <><StatusBadge statusMap={TASK_STATUS} value={v} />{r.requires_evidence && <Badge color="info" className="ml-1">📷 {r.evidence_count}</Badge>}</> },
          { key: 'actions', label: '', render: (_, r) => actions(r) },
        ]} />
      </Card>

      {detail && <TaskDetailModal task={detail} canManage={canManage} actions={actions(detail)}
        onClose={() => setDetail(null)} onEdit={() => { setForm(detail); setDetail(null) }} />}

      <Modal open={!!completing} onClose={() => setCompleting(null)} title="Completar tarea" size="sm"
        footer={<><Button variant="ghost" onClick={() => setCompleting(null)}>Cancelar</Button>
          <Button variant="success" loading={saving} onClick={confirmComplete}>Completar</Button></>}>
        {completing && <>
          <p className="mb-3"><strong>{completing.title}</strong></p>
          <Textarea label="Notas de cierre (opcional)" value={notes} onChange={(e) => setNotes(e.target.value)}
            placeholder="¿Qué se hizo? ¿Quedó algo pendiente?" rows={3} />
        </>}
      </Modal>

      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar tarea' : 'Nueva tarea'}
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="task-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="task-form" className="form-stack" onSubmit={submit}>
            <Input label="Título" required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
            <Textarea label="Descripción" value={form.description ?? ''} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            <div className="form-grid">
              <Select label="Departamento" value={form.department_id ?? ''} placeholder="General" options={departments.map((d) => ({ value: d.id, label: d.name }))}
                onChange={(e) => setForm({ ...form, department_id: e.target.value })} />
              <Select label="Responsable" value={form.assigned_to ?? ''} placeholder="Sin asignar"
                options={people.map((p) => ({ value: p.id, label: `${p.full_name} · ${p.role_name}` }))}
                onChange={(e) => setForm({ ...form, assigned_to: e.target.value })} />
              <Input label="Fecha límite" type="date" value={form.due_date ?? ''} onChange={(e) => setForm({ ...form, due_date: e.target.value })} />
              <Select label="Prioridad" value={form.priority} options={toOptions(PRIORITY)} onChange={(e) => setForm({ ...form, priority: e.target.value })} />
            </div>
            <label className="checkbox"><input type="checkbox" checked={form.requires_evidence} onChange={(e) => setForm({ ...form, requires_evidence: e.target.checked })} /> Requiere evidencia fotográfica</label>
          </form>
        )}
      </Modal>
    </div>
  )
}

/** Detalle de la tarea con sus fotos de evidencia. */
function TaskDetailModal({ task, canManage, actions, onClose, onEdit }) {
  const load = useCallback(() => getEvidence({ entityType: 'task', entityId: task.id }), [task.id])
  const { data: evidence = [], loading } = useAsync(load)
  return (
    <Modal open onClose={onClose} title={task.title} size="lg"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cerrar</Button>
        {canManage && OPEN.includes(task.status) && <Button variant="outline" onClick={onEdit}>Editar</Button>}
      </>}>
      <div className="detail-strip">
        <div><span>Estado</span><StatusBadge statusMap={TASK_STATUS} value={task.status} /></div>
        <div><span>Prioridad</span><StatusBadge statusMap={PRIORITY} value={task.priority} /></div>
        <div><span>Responsable</span><strong>{task.assigned_to_name ?? 'Sin asignar'}</strong></div>
        <div><span>Límite</span><strong>{formatDate(task.due_date)}</strong></div>
        <div><span>Creó</span><strong>{task.created_by_name ?? '—'}</strong></div>
        {task.completed_at && <div><span>Completada</span><strong>{formatDateTime(task.completed_at)}</strong></div>}
      </div>
      {task.description && <p className="mb-3">{task.description}</p>}
      {task.completion_notes && <p className="hint-box">Notas de cierre: {task.completion_notes}</p>}
      <h4 className="mb-3">Evidencias {task.requires_evidence && <Badge color="info">Requerida</Badge>}</h4>
      {loading ? <p className="text-muted text-sm">Cargando…</p> : <EvidenceGallery items={evidence} showStatus emptyText="Sin evidencias" />}
      <div className="mt-3">{actions}</div>
    </Modal>
  )
}
