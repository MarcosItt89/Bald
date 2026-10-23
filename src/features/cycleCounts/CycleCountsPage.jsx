/**
 * CycleCountsPage — conteo cíclico de inventario.
 * - Hoy: tareas de conteo del día; se cuenta producto por producto (a ciegas:
 *   quien cuenta no ve la existencia del sistema). Se puede escanear para
 *   ubicar el producto en la lista.
 * - Planes (manage_cycle_counts): qué contar, cada cuándo y cuántos productos.
 */
import { useCallback, useState } from 'react'
import { Check, ClipboardList, Plus, ScanBarcode } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getCycleItems, getCyclePlans, getCycleTasks, recordCycleCount, saveCyclePlan } from '../../services/cycleCountService'
import { getDepartments } from '../../services/organizationService'
import { FREQUENCIES } from '../../constants/status'
import { formatCurrency, formatDate, formatNumber, formatTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import ProgressBar from '../../components/ui/ProgressBar'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'
import BarcodeScanner from '../inventory/BarcodeScanner'

const REASON = { differences: 'Tuvo diferencias', rotation: 'Alta rotación', oldest: 'Sin contar hace tiempo' }
const WEEKDAYS = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado']
const STATUS = { pending: ['Pendiente', 'warning'], in_progress: ['En conteo', 'info'], completed: ['Completado', 'success'], cancelled: ['Cancelado', 'default'] }

export default function CycleCountsPage() {
  const { hasPermission } = useAuth()
  const canManage = hasPermission(P.MANAGE_CYCLE_COUNTS)
  const [tab, setTab] = useState('today')
  return (
    <div className="page">
      <PageHeader icon={ClipboardList} title="Conteo cíclico" subtitle="Cuenta pocos productos cada día para mantener el inventario exacto" />
      {canManage && <Tabs active={tab} onChange={setTab} tabs={[{ key: 'today', label: 'Hoy' }, { key: 'plans', label: 'Planes' }]} />}
      {tab === 'today' ? <TodayTasks /> : <Plans />}
    </div>
  )
}

function TodayTasks() {
  const { branchFilter, hasPermission } = useAuth()
  const today = todayISO()
  const load = useCallback(() => getCycleTasks({ branchId: branchFilter, date: today }), [branchFilter, today])
  const { data: tasks = [], loading, error, reload } = useAsync(load)
  const [openId, setOpenId] = useState(null)

  if (error) return <ErrorState error={error} onRetry={reload} />
  if (loading && !tasks.length) return <Loader />
  if (!tasks.length) return <EmptyState icon={ClipboardList} title="Sin conteos para hoy" message="Los conteos se generan cada día según los planes de la sucursal." />

  const open = tasks.find((t) => t.id === openId)
  return (
    <>
      <div className="cc-tasks">
        {tasks.map((t) => (
          <button key={t.id} type="button" className={`cc-task ${t.id === openId ? 'cc-task-open' : ''}`} onClick={() => setOpenId(t.id === openId ? null : t.id)}>
            <span className="cc-task-title">{t.plan_name}</span>
            <span className="cell-sub">{t.branch_name}{t.department_name ? ` · ${t.department_name}` : ''}{t.category ? ` · ${t.category}` : ''}</span>
            <ProgressBar value={t.items_counted} total={t.items_total} label={`${t.items_counted}/${t.items_total}`} />
            <span className="cc-task-foot">
              <Badge color={STATUS[t.status][1]}>{STATUS[t.status][0]}</Badge>
              {t.status === 'completed' && hasPermission(P.MANAGE_CYCLE_COUNTS) && (
                <span className={t.items_with_diff ? 'td-danger' : 'text-muted'}>{t.items_with_diff} con diferencia · {formatCurrency(t.diff_value)}</span>
              )}
            </span>
          </button>
        ))}
      </div>
      {open && <TaskItems key={open.id} task={open} onChanged={reload} />}
    </>
  )
}

function TaskItems({ task, onChanged }) {
  const toast = useToast()
  const { hasPermission } = useAuth()
  const canCount = hasPermission(P.PERFORM_CYCLE_COUNTS) && !['completed', 'cancelled'].includes(task.status)
  const seesDiff = hasPermission(P.MANAGE_CYCLE_COUNTS) || hasPermission(P.MANAGE_INVENTORY)
  const load = useCallback(() => getCycleItems(task.id), [task.id])
  const { data: items = [], loading, error, reload } = useAsync(load)
  const [drafts, setDrafts] = useState({})
  const [saving, setSaving] = useState(null)
  const [scanning, setScanning] = useState(false)
  const [highlight, setHighlight] = useState(null)

  const save = async (item) => {
    const raw = String(drafts[item.id] ?? '').replace(',', '.')
    if (raw === '' || Number.isNaN(Number(raw))) { toast.error('Escribe la cantidad contada'); return }
    setSaving(item.id)
    try {
      const r = await recordCycleCount(item.id, raw)
      toast.success(seesDiff && r.difference ? `Diferencia: ${formatNumber(r.difference, 3)} (${formatCurrency(r.difference_value)})` : 'Conteo guardado')
      setDrafts((d) => ({ ...d, [item.id]: undefined }))
      reload()
      onChanged()
    } catch (err) { toast.error(err.message) } finally { setSaving(null) }
  }

  const onScan = (code) => {
    setScanning(false)
    const found = items.find((i) => i.sku === code || (i.barcodes ?? '').split(' ').includes(code))
    if (!found) { toast.error(`El código ${code} no está en este conteo`); return }
    setHighlight(found.id)
    document.getElementById(`cc-${found.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
    document.getElementById(`cc-input-${found.id}`)?.focus()
  }

  return (
    <Card title={task.plan_name} subtitle={`${formatDate(task.scheduled_date)} · cuenta lo que hay físicamente en anaquel y bodega`}
      action={canCount && <Button size="sm" variant="outline" onClick={() => setScanning(true)}><ScanBarcode size={14} /> Escanear</Button>}>
      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !items.length ? <Loader /> : (
        <ul className="cc-items">
          {items.map((it) => (
            <li key={it.id} id={`cc-${it.id}`} className={`cc-item ${it.counted_at ? 'cc-item-done' : ''} ${highlight === it.id ? 'cc-item-hit' : ''}`}>
              <div className="cc-item-info">
                <strong>{it.product_name}</strong>
                <span className="cell-sub td-mono">{it.sku} · {REASON[it.priority_reason]}</span>
                {it.counted_at && (
                  <span className="cell-sub">
                    <Check size={12} /> {formatNumber(it.counted_qty, 3)} {it.unit} · {it.counted_by_name} {formatTime(it.counted_at)}
                    {seesDiff && it.difference != null && (
                      <span className={Number(it.difference) ? 'td-danger' : 'text-muted'}> · sistema {formatNumber(it.expected_qty, 3)} · dif. {formatNumber(it.difference, 3)} ({formatCurrency(it.difference_value)})</span>
                    )}
                  </span>
                )}
              </div>
              {canCount && (
                <div className="cc-item-input">
                  <input id={`cc-input-${it.id}`} className="form-input" inputMode="decimal" placeholder={it.counted_at ? 'Recontar' : 'Cantidad'}
                    aria-label={`Cantidad contada de ${it.product_name}`} value={drafts[it.id] ?? ''}
                    onChange={(e) => setDrafts((d) => ({ ...d, [it.id]: e.target.value }))}
                    onKeyDown={(e) => { if (e.key === 'Enter') save(it) }} />
                  <span className="cc-unit">{it.unit}</span>
                  <Button size="sm" loading={saving === it.id} disabled={drafts[it.id] == null || drafts[it.id] === ''} onClick={() => save(it)}>Guardar</Button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      {scanning && <BarcodeScanner onClose={() => setScanning(false)} onDetected={onScan} />}
    </Card>
  )
}

function Plans() {
  const { branchFilter, workingBranchId, profile } = useAuth()
  const toast = useToast()
  const load = useCallback(() => getCyclePlans({ branchId: branchFilter }), [branchFilter])
  const { data: rows = [], loading, error, reload } = useAsync(load)
  const { data: departments = [] } = useAsync(getDepartments)
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try { await saveCyclePlan({ ...form, company_id: profile.company_id }); toast.success('Plan guardado'); setForm(null); reload() } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  return (
    <>
      <div className="page-actions mb-3">
        <Button size="sm" disabled={!workingBranchId} onClick={() => setForm({ name: '', branch_id: workingBranchId, department_id: '', category: '', frequency: 'daily', weekday: 1, items_per_count: 10, is_active: true })}>
          <Plus size={14} /> Nuevo plan
        </Button>
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setForm} emptyText="Sin planes de conteo" columns={[
          { key: 'name', label: 'Plan', bold: true, render: (v, r) => <>{v}<div className="cell-sub">{r.branch?.name}</div></> },
          { key: 'department', label: 'Qué se cuenta', render: (v, r) => [v?.name, r.category].filter(Boolean).join(' · ') || 'Toda la sucursal' },
          { key: 'frequency', label: 'Frecuencia', render: (v, r) => (v === 'weekly' ? `Cada ${WEEKDAYS[r.weekday]?.toLowerCase()}` : FREQUENCIES[v]) },
          { key: 'items_per_count', label: 'Productos', align: 'right' },
          { key: 'is_active', label: 'Estado', render: (v) => <Badge color={v ? 'success' : 'default'}>{v ? 'Activo' : 'Pausado'}</Badge> },
        ]} />
      </Card>
      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Editar plan' : 'Nuevo plan de conteo'}
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="cc-plan" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="cc-plan" className="form-stack" onSubmit={submit}>
            <Input label="Nombre" required placeholder="Ej. Conteo diario de Abarrotes" value={form.name} onChange={set('name')} />
            <div className="form-grid">
              <Select label="Departamento" value={form.department_id ?? ''} placeholder="Todos" options={departments.map((d) => ({ value: d.id, label: d.name }))} onChange={set('department_id')} />
              <Input label="Categoría (opcional)" placeholder="Ej. Lácteos" value={form.category ?? ''} onChange={set('category')} />
              <Select label="Frecuencia" value={form.frequency} options={Object.entries(FREQUENCIES).map(([value, label]) => ({ value, label }))} onChange={set('frequency')} />
              {form.frequency === 'weekly' && (
                <Select label="Día" value={String(form.weekday ?? 1)} options={WEEKDAYS.map((label, value) => ({ value: String(value), label }))} onChange={set('weekday')} />
              )}
              <Input label="Productos por conteo" type="number" min="1" max="100" required value={form.items_per_count} onChange={set('items_per_count')}
                hint="Primero los que tuvieron diferencias, luego los de más rotación" />
            </div>
            <label className="checkbox"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} /> Activo</label>
          </form>
        )}
      </Modal>
    </>
  )
}
