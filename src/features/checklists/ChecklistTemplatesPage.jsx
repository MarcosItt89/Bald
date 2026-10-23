/**
 * ChecklistTemplatesPage — diseño de plantillas de checklist (preguntas,
 * horario, departamento). Las ejecuciones diarias se generan de aquí.
 * Quitar una pregunta la desactiva (no borra respuestas históricas).
 */
import { useCallback, useState } from 'react'
import { ArrowDown, ArrowUp, ClipboardCheck, Plus, Trash2 } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getTemplates, getTemplateQuestions, saveTemplate, setTemplateActive } from '../../services/checklistService'
import { getDepartments } from '../../services/organizationService'
import { ANSWER_TYPES, FREQUENCIES, SHIFTS } from '../../constants/status'
import { formatTime } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { getCheckpoints } from '../../services/checkpointService'
import { ErrorState } from '../../components/ui/Feedback'

const opts = (map) => Object.entries(map).map(([value, label]) => ({ value, label }))
const EMPTY = {
  title: '', description: '', department_id: '', shift: 'apertura', start_time: '07:00', end_time: '09:00',
  frequency: 'daily', requires_evidence: false, is_active: true, repeat_every_minutes: null, repeat_until: null,
}
const REPEAT_OPTIONS = [
  { value: '', label: 'Una vez al día' }, { value: '30', label: 'Cada 30 min' }, { value: '60', label: 'Cada 1 h' },
  { value: '120', label: 'Cada 2 h' }, { value: '180', label: 'Cada 3 h' }, { value: '240', label: 'Cada 4 h' },
]
const newQuestion = () => ({ text: '', answer_type: 'yes_no', is_required: true, requires_photo: false, is_critical: false, options: [], min_value: null, max_value: null, unit: '', equipment_name: '' })
const numOrNull = (v) => (v === '' || v == null ? null : Number(v))

export default function ChecklistTemplatesPage() {
  const toast = useToast()
  const { data: rows = [], loading, error, reload } = useAsync(getTemplates)
  const { data: departments = [] } = useAsync(getDepartments)
  const { data: checkpoints = [] } = useAsync(getCheckpoints)
  // Un punto por nombre: la plantilla guarda uno «modelo» y cada sucursal usa el suyo con el mismo nombre.
  const pointOptions = [...new Map(checkpoints.filter((c) => c.is_active).map((c) => [c.name, c])).values()]
    .map((c) => ({ value: c.id, label: c.name }))
  const modelName = (id) => checkpoints.find((c) => c.id === id)?.name
  const [editing, setEditing] = useState(null)
  const [questions, setQuestions] = useState([])
  const [saving, setSaving] = useState(false)

  const open = useCallback(async (tpl) => {
    if (!tpl) { setEditing(EMPTY); setQuestions([newQuestion()]); return }
    try {
      setQuestions(await getTemplateQuestions(tpl.id))
      setEditing({ ...tpl, start_time: tpl.start_time.slice(0, 5), end_time: tpl.end_time.slice(0, 5) })
    } catch (err) { toast.error(err.message) }
  }, [toast])

  const setQ = (i, patch) => setQuestions((list) => list.map((q, j) => (j === i ? { ...q, ...patch } : q)))
  const move = (i, d) => setQuestions((list) => {
    const next = [...list]; const j = i + d
    if (j < 0 || j >= next.length) return list
    ;[next[i], next[j]] = [next[j], next[i]]
    return next
  })

  const submit = async (e) => {
    e.preventDefault()
    const valid = questions.filter((q) => q.text.trim())
    if (!valid.length) { toast.error('Agrega al menos una pregunta'); return }
    if (editing.checkpoint_required && !editing.checkpoint_id) { toast.error('Elige el punto QR que hay que escanear'); return }
    setSaving(true)
    try {
      await saveTemplate({ ...editing, department_id: editing.department_id || null }, valid)
      toast.success('Plantilla guardada')
      setEditing(null)
      reload()
    } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  const toggle = async (tpl) => {
    try { await setTemplateActive(tpl.id, !tpl.is_active); reload() } catch (err) { toast.error(err.message) }
  }

  return (
    <div className="page">
      <PageHeader icon={ClipboardCheck} title="Plantillas de checklist" subtitle="Las ejecuciones de cada día se generan a partir de estas plantillas"
        actions={<Button size="sm" onClick={() => open(null)}><Plus size={14} /> Nueva plantilla</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={open} columns={[
          { key: 'title', label: 'Plantilla', bold: true, sortable: true },
          { key: 'department', label: 'Departamento', render: (v) => v?.name ?? 'General' },
          { key: 'shift', label: 'Turno', render: (v) => SHIFTS[v] },
          { key: 'start_time', label: 'Horario', render: (v, r) => `${formatTime(v)}–${formatTime(r.end_time)}` },
          { key: 'frequency', label: 'Frecuencia', render: (v, r) => (r.repeat_every_minutes
            ? `${FREQUENCIES[v]} · cada ${r.repeat_every_minutes >= 60 ? `${r.repeat_every_minutes / 60} h` : `${r.repeat_every_minutes} min`}`
            : FREQUENCIES[v]) },
          { key: 'questions', label: 'Preguntas', render: (v) => v?.[0]?.count ?? 0 },
          { key: 'is_active', label: 'Estado', render: (v, r) => (
            <button className="link-btn" onClick={(e) => { e.stopPropagation(); toggle(r) }}>
              <Badge color={v ? 'success' : 'default'}>{v ? 'Activa' : 'Inactiva'}</Badge>
            </button>
          ) },
        ]} />
      </Card>

      <Modal open={!!editing} onClose={() => setEditing(null)} title={editing?.id ? 'Editar plantilla' : 'Nueva plantilla'} size="xl"
        footer={<><Button variant="ghost" onClick={() => setEditing(null)}>Cancelar</Button>
          <Button type="submit" form="tpl-form" loading={saving}>Guardar</Button></>}>
        {editing && (
          <form id="tpl-form" className="form-stack" onSubmit={submit}>
            <Input label="Título" required value={editing.title} onChange={(e) => setEditing({ ...editing, title: e.target.value })} />
            <div className="form-grid form-grid-3">
              <Select label="Departamento" value={editing.department_id ?? ''} placeholder="General"
                options={departments.map((d) => ({ value: d.id, label: d.name }))}
                onChange={(e) => setEditing({ ...editing, department_id: e.target.value })} />
              <Select label="Turno" value={editing.shift} options={opts(SHIFTS)} onChange={(e) => setEditing({ ...editing, shift: e.target.value })} />
              <Select label="Frecuencia" value={editing.frequency} options={opts(FREQUENCIES)} onChange={(e) => setEditing({ ...editing, frequency: e.target.value })} />
              <Input label="Hora inicio" type="time" value={editing.start_time} onChange={(e) => setEditing({ ...editing, start_time: e.target.value })} />
              <Input label="Hora límite" type="time" value={editing.end_time} onChange={(e) => setEditing({ ...editing, end_time: e.target.value })}
                hint={editing.repeat_every_minutes ? 'De la primera ronda; cada ronda dura lo mismo' : undefined} />
              <Select label="Repetir" value={editing.repeat_every_minutes ? String(editing.repeat_every_minutes) : ''} options={REPEAT_OPTIONS}
                onChange={(e) => setEditing({ ...editing, repeat_every_minutes: e.target.value ? Number(e.target.value) : null, repeat_until: e.target.value ? editing.repeat_until : null })} />
              {editing.repeat_every_minutes && (
                <Input label="Hasta (último inicio)" type="time" value={editing.repeat_until?.slice(0, 5) ?? ''}
                  onChange={(e) => setEditing({ ...editing, repeat_until: e.target.value || null })}
                  hint="Vacío = hasta el cierre de la sucursal" />
              )}
              <label className="checkbox"><input type="checkbox" checked={editing.requires_evidence}
                onChange={(e) => setEditing({ ...editing, requires_evidence: e.target.checked })} /> Requiere evidencia</label>
              <label className="checkbox" title="Para iniciar hay que escanear el QR del punto en la sucursal"><input type="checkbox" checked={!!editing.checkpoint_required}
                disabled={!pointOptions.length && !editing.checkpoint_required}
                onChange={(e) => setEditing({ ...editing, checkpoint_required: e.target.checked, checkpoint_id: e.target.checked ? editing.checkpoint_id : null })} /> Requiere escanear QR</label>
              {editing.checkpoint_required && (
                <Select label="Punto QR" required value={pointOptions.find((o) => o.label === modelName(editing.checkpoint_id))?.value ?? editing.checkpoint_id ?? ''}
                  placeholder="Selecciona…" options={pointOptions} onChange={(e) => setEditing({ ...editing, checkpoint_id: e.target.value || null })}
                  hint={pointOptions.length ? 'Cada sucursal usa su punto con este mismo nombre' : 'Primero crea puntos en Puntos QR'} />
              )}
            </div>
            <h4>Preguntas</h4>
            {questions.map((q, i) => (
              <div key={q.id ?? `new-${i}`} className="question-editor">
                <span className="text-muted">{i + 1}.</span>
                <input className="form-input" placeholder="Texto de la pregunta" value={q.text} onChange={(e) => setQ(i, { text: e.target.value })} />
                <select className="form-select" value={q.answer_type} onChange={(e) => setQ(i, { answer_type: e.target.value })}>
                  {opts(ANSWER_TYPES).map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
                {q.answer_type === 'option' && (
                  <input className="form-input" placeholder="Opciones separadas por coma" value={(q.options ?? []).join(', ')}
                    onChange={(e) => setQ(i, { options: e.target.value.split(',').map((s) => s.trim()).filter(Boolean) })} />
                )}
                {q.answer_type === 'number' && (
                  <div className="range-editor">
                    <input className="form-input" placeholder="Equipo (ej. Cámara de carnes)" value={q.equipment_name ?? ''} onChange={(e) => setQ(i, { equipment_name: e.target.value })} />
                    <input className="form-input" type="number" step="any" placeholder="Mín." value={q.min_value ?? ''} onChange={(e) => setQ(i, { min_value: numOrNull(e.target.value) })} />
                    <input className="form-input" type="number" step="any" placeholder="Máx." value={q.max_value ?? ''} onChange={(e) => setQ(i, { max_value: numOrNull(e.target.value) })} />
                    <input className="form-input" placeholder="Unidad (°C)" value={q.unit ?? ''} onChange={(e) => setQ(i, { unit: e.target.value })} />
                  </div>
                )}
                <label className="checkbox"><input type="checkbox" checked={q.is_required} onChange={(e) => setQ(i, { is_required: e.target.checked })} /> Oblig.</label>
                {q.answer_type === 'yes_no' && (
                  <label className="checkbox" title="Un «No» crea una tarea urgente y avisa al gerente"><input type="checkbox" checked={!!q.is_critical} onChange={(e) => setQ(i, { is_critical: e.target.checked })} /> Crítica</label>
                )}
                <label className="checkbox"><input type="checkbox" checked={q.requires_photo || q.answer_type === 'photo'}
                  disabled={q.answer_type === 'photo'} onChange={(e) => setQ(i, { requires_photo: e.target.checked })} /> Foto</label>
                <button type="button" className="icon-btn" onClick={() => move(i, -1)} aria-label="Subir"><ArrowUp size={14} /></button>
                <button type="button" className="icon-btn" onClick={() => move(i, 1)} aria-label="Bajar"><ArrowDown size={14} /></button>
                <button type="button" className="icon-btn icon-btn-danger" aria-label="Quitar"
                  onClick={() => setQuestions((l) => l.filter((_, j) => j !== i))}><Trash2 size={14} /></button>
              </div>
            ))}
            <div><Button variant="outline" size="sm" onClick={() => setQuestions((l) => [...l, newQuestion()])}><Plus size={14} /> Pregunta</Button></div>
          </form>
        )}
      </Modal>
    </div>
  )
}
