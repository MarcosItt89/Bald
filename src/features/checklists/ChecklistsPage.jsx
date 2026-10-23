/**
 * ChecklistsPage — checklists / bitácoras del día (Objetivos §11.6 y §11.7).
 *
 * - Datos reales de Supabase (vista v_checklist_runs). Al abrir la página del
 *   día actual se ejecuta run_daily_maintenance(): genera los checklists de
 *   hoy y marca como vencidos los que pasaron su hora límite.
 * - Pestañas por estado + filtros de departamento, sucursal y fecha.
 *   «Míos»: los checklists del departamento del usuario (p. ej. Gerencia para el gerente).
 * - Plantillas con rondas (0016): una tarjeta por plantilla y sucursal con la
 *   ronda actual («Ronda 3 de 7») y fichas para abrir cualquier otra ronda.
 *   Una ronda futura no se puede iniciar hasta 10 minutos antes de su hora.
 * - "Iniciar" pasa el checklist a En progreso y abre la ejecución.
 * - La flecha ▸ expande la tarjeta y muestra sus ítems con la respuesta.
 * - El estado "vencido" se recalcula cada minuto con la hora local, así un
 *   checklist se ve vencido en cuanto pasa su hora límite, sin recargar.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckSquare, ChevronDown, ChevronRight, Clock, Play, QrCode, RefreshCw, Settings } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getRuns, getRunDetail, runDailyMaintenance, startRun } from '../../services/checklistService'
import { getMyBranches, getDepartments } from '../../services/organizationService'
import { CHECKLIST_REVIEW_STATUS, CHECKLIST_RUN_STATUS, SHIFTS } from '../../constants/status'
import { formatDate, formatTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import Tabs from '../../components/ui/Tabs'
import StatusBadge from '../../components/ui/StatusBadge'
import ProgressBar from '../../components/ui/ProgressBar'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'
import ChecklistRunModal from './ChecklistRunModal'
import CheckpointScanModal from './CheckpointScanModal'

const TABS = [
  { key: 'mine',        label: 'Míos',        statuses: null, mine: true },
  { key: 'all',         label: 'Todos',       statuses: null },
  { key: 'pending',     label: 'Pendientes',  statuses: ['pending', 'reopened'] },
  { key: 'in_progress', label: 'En progreso', statuses: ['in_progress'] },
  { key: 'completed',   label: 'Completados', statuses: ['completed'] },
  { key: 'overdue',     label: 'Vencidos',    statuses: ['overdue'] },
]
const ORDER = { overdue: 0, reopened: 1, in_progress: 2, pending: 3, completed: 4, cancelled: 5 }
const nowHHMM = () => new Date().toTimeString().slice(0, 5)
const EARLY_MIN = 10

/** HH:MM + minutos (sin pasar de 23:59). */
const addMinutes = (hhmm, mins) => {
  const [h, m] = hhmm.split(':').map(Number)
  const t = Math.min(23 * 60 + 59, h * 60 + m + mins)
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`
}

/** ¿Es una ronda que todavía no empieza? (solo aplica al día de hoy). */
const isFuture = (run, today, now) =>
  run.scheduled_date === today && run.scheduled_start.slice(0, 5) > addMinutes(now, EARLY_MIN)

/** Ronda a mostrar: la abierta, si no la vigente, si no la siguiente, si no la última. */
const currentRound = (rounds, today, now) =>
  rounds.find((r) => ['in_progress', 'reopened'].includes(r.status))
  ?? rounds.find((r) => r.status === 'pending' && !isFuture(r, today, now))
  ?? rounds.find((r) => r.status === 'pending')
  ?? rounds[rounds.length - 1]

/** Vencido si sigue abierto y ya pasó su fecha u hora límite (reabiertos no vencen). */
const effectiveStatus = (run, today, now) => {
  if (!['pending', 'in_progress'].includes(run.status)) return run.status
  if (run.scheduled_date < today) return 'overdue'
  if (run.scheduled_date === today && run.scheduled_end.slice(0, 5) < now) return 'overdue'
  return run.status
}

export default function ChecklistsPage() {
  const { branchFilter, isCompanyScope, isZoneScope, isMultiBranch, zoneIds, hasPermission, profile } = useAuth()
  const toast = useToast()
  const canFill = hasPermission(P.FILL_CHECKLISTS)
  const myDept = profile.department_id
  const [tab, setTab] = useState(myDept ? 'mine' : 'all')
  const [date, setDate] = useState(todayISO())
  const [departmentId, setDepartmentId] = useState('')
  const [branchId, setBranchId] = useState(null) // null = usar la sucursal del Topbar
  const [openRunId, setOpenRunId] = useState(null)
  const [starting, setStarting] = useState(null)
  const [scanRun, setScanRun] = useState(null) // checklist que exige escanear su punto QR
  const [now, setNow] = useState(nowHHMM)

  useEffect(() => {
    const id = setInterval(() => setNow(nowHHMM()), 60_000)
    return () => clearInterval(id)
  }, [])

  const effectiveBranch = isMultiBranch ? (branchId ?? branchFilter) : profile.branch_id
  const today = todayISO()

  const load = useCallback(async () => {
    if (date === today) await runDailyMaintenance().catch(() => {}) // no bloquea si falla
    return getRuns({ branchId: effectiveBranch || undefined, date, departmentId: departmentId || undefined })
  }, [effectiveBranch, date, departmentId, today])
  const { data: raw = [], loading, error, reload } = useAsync(load)
  const { data: departments = [] } = useAsync(getDepartments)
  const zoneKey = zoneIds.join(',')
  const loadBranches = useCallback(
    () => getMyBranches({ isCompanyScope, isZoneScope, zoneIds: zoneKey ? zoneKey.split(',') : [] }),
    [isCompanyScope, isZoneScope, zoneKey],
  )
  const { data: branches = [] } = useAsync(loadBranches)

  const runs = useMemo(() => raw
    .map((r) => ({ ...r, status: effectiveStatus(r, today, now) }))
    .sort((a, b) => ORDER[a.status] - ORDER[b.status] || a.scheduled_start.localeCompare(b.scheduled_start)),
  [raw, today, now])

  const visible = useMemo(() => {
    const t = TABS.find((x) => x.key === tab)
    if (t.mine) return runs.filter((r) => r.department_id === myDept)
    return t.statuses ? runs.filter((r) => t.statuses.includes(r.status)) : runs
  }, [runs, tab, myDept])

  // Una tarjeta por corrida; las plantillas con rondas se agrupan por plantilla y sucursal.
  const cards = useMemo(() => {
    const out = []
    const groups = new Map()
    visible.forEach((r) => {
      if ((r.rounds_total ?? 1) <= 1) { out.push({ key: r.id, run: r, rounds: null }); return }
      const key = `${r.template_id}:${r.branch_id}`
      if (!groups.has(key)) {
        const g = { key, visibleRounds: [], rounds: runs.filter((x) => x.template_id === r.template_id && x.branch_id === r.branch_id)
          .sort((a, b) => a.scheduled_start.localeCompare(b.scheduled_start)) }
        groups.set(key, g)
        out.push(g)
      }
      groups.get(key).visibleRounds.push(r)
    })
    groups.forEach((g) => { g.run = currentRound(g.visibleRounds.sort((a, b) => a.scheduled_start.localeCompare(b.scheduled_start)), today, now) })
    return out
  }, [visible, runs, today, now])

  const count = (t) => (t.mine ? runs.filter((r) => r.department_id === myDept && !['completed', 'cancelled'].includes(r.status)).length
    : t.statuses ? runs.filter((r) => t.statuses.includes(r.status)).length : runs.length)
  const done = runs.filter((r) => r.status === 'completed').length
  const valid = runs.filter((r) => r.status !== 'cancelled').length

  const start = async (run) => {
    if (run.checkpoint_required && !run.checkpoint_scanned_at && ['pending', 'reopened'].includes(run.status)) {
      setScanRun(run)
      return
    }
    setStarting(run.id)
    try {
      if (run.status === 'pending' || run.status === 'reopened') await startRun(run.id)
      setOpenRunId(run.id)
      reload()
    } catch (err) {
      toast.error(err.message)
      reload()
    } finally {
      setStarting(null)
    }
  }

  const clearFilters = () => { setDepartmentId(''); setBranchId(null); setDate(today) }
  const hasFilters = departmentId || branchId !== null || date !== today

  return (
    <div className="page">
      <PageHeader icon={CheckSquare} title="Checklists"
        subtitle={`${formatDate(date)} · ${done} de ${valid} completados`}
        actions={<>
          <Button variant="ghost" size="sm" onClick={reload} loading={loading}>{!loading && <RefreshCw size={14} />} Actualizar</Button>
          {hasPermission(P.MANAGE_CHECKLIST_TEMPLATES) && (
            <Link to="/checklists/templates" className="btn btn-outline btn-sm"><Settings size={14} /> Plantillas</Link>
          )}
        </>} />

      {valid > 0 && <div className="mb-3"><ProgressBar value={done} total={valid} semaphore label={`${Math.round((done / valid) * 100)}% de cumplimiento`} /></div>}

      <Tabs active={tab} onChange={setTab} tabs={TABS.filter((t) => !t.mine || myDept).map((t) => ({ key: t.key, label: t.label, count: count(t) }))} />

      <div className="filters">
        <select className="filter-select" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
          <option value="">Todos los departamentos</option>
          {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        {isMultiBranch ? (
          <select className="filter-select" value={effectiveBranch ?? ''} onChange={(e) => setBranchId(e.target.value)}>
            <option value="">Todas las sucursales</option>
            {branches.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        ) : (
          <select className="filter-select" disabled value=""><option value="">{profile.branch_name}</option></select>
        )}
        <input type="date" className="filter-select" value={date} max={today} onChange={(e) => setDate(e.target.value || today)} />
        {hasFilters && <button className="link-btn" onClick={clearFilters}>Limpiar filtros</button>}
      </div>

      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !raw.length && <Loader />}
      {!loading && visible.length === 0 && (
        <EmptyState icon={CheckSquare} title="No hay checklists con estos filtros"
          message={runs.length ? 'Prueba otra pestaña o limpia los filtros.' : 'No hay checklists programados para este día.'} />
      )}

      <div className="cl-section-body">
        {cards.map(({ key, run, rounds }) => (
          <RunCard key={key} run={run} rounds={rounds} future={isFuture(run, today, now)} showBranch={!effectiveBranch} canFill={canFill}
            starting={starting === run.id} onStart={() => start(run)} onOpen={() => setOpenRunId(run.id)}
            onPickRound={(r) => (canFill && ['pending', 'reopened'].includes(r.status) && !isFuture(r, today, now) ? start(r) : setOpenRunId(r.id))}
            isFutureRound={(r) => isFuture(r, today, now)} />
        ))}
      </div>

      {scanRun && <CheckpointScanModal run={scanRun} onClose={() => setScanRun(null)}
        onStarted={(id) => { setScanRun(null); setOpenRunId(id); reload() }} />}
      {openRunId && <ChecklistRunModal runId={openRunId} onClose={() => setOpenRunId(null)} onChanged={reload} />}
    </div>
  )
}

function RunCard({ run, rounds, future, showBranch, canFill, starting, onStart, onOpen, onPickRound, isFutureRound }) {
  const [expanded, setExpanded] = useState(false)
  const canStart = canFill && ['pending', 'reopened', 'in_progress'].includes(run.status) && !future

  return (
    <div className={`cl-run-card cl-run-${run.status}`}>
      <div className="cl-run-header">
        <button className="cl-expand-btn" onClick={() => setExpanded((e) => !e)} aria-label={expanded ? 'Ocultar ítems' : 'Ver ítems'}>
          {expanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        </button>
        <span className="cl-dept-dot" style={{ background: run.department_color ?? '#94a3b8' }} />
        <div className="cl-run-info" onClick={onOpen} role="button" tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && onOpen()}>
          <span className="cl-run-title">{run.title}</span>
          <span className="cl-run-meta">
            {rounds && <strong className="cl-round-label">Ronda {run.round_no} de {run.rounds_total} · </strong>}
            {run.department_name ?? 'General'} · {SHIFTS[run.shift]} · <Clock size={11} /> {formatTime(run.scheduled_start)}–{formatTime(run.scheduled_end)}
            {showBranch && ` · ${run.branch_name}`}
            {run.completed_by_name && ` · completó ${run.completed_by_name} ${formatTime(run.completed_at)}`}
          </span>
        </div>
        <div className="cl-run-right">
          {run.requires_evidence && <Badge color="info">Evidencia requerida</Badge>}
          {run.checkpoint_required && <Badge color={run.checkpoint_scanned_at ? 'success' : 'default'} className="qr-required" title={run.checkpoint_name ? `Punto: ${run.checkpoint_name}` : undefined}><QrCode size={11} /> {run.checkpoint_scanned_at ? 'QR verificado' : 'Requiere QR'}</Badge>}
          {['in_progress', 'reopened'].includes(run.status) && (
            <ProgressBar value={Number(run.answered_questions)} total={Number(run.total_questions)}
              label={`${run.answered_questions}/${run.total_questions}`} width={60} />
          )}
          {run.review_status && <StatusBadge statusMap={CHECKLIST_REVIEW_STATUS} value={run.review_status} />}
          <StatusBadge statusMap={CHECKLIST_RUN_STATUS} value={run.status} />
          {future && run.status === 'pending' ? (
            <Badge color="default" title="Se podrá iniciar 10 minutos antes"><Clock size={11} /> Desde {formatTime(run.scheduled_start)}</Badge>
          ) : canStart ? (
            <Button size="sm" loading={starting} onClick={onStart}>
              {!starting && <Play size={12} />} {run.status === 'in_progress' ? 'Continuar' : 'Iniciar'}
            </Button>
          ) : (
            <Button size="sm" variant="ghost" onClick={onOpen}>Ver</Button>
          )}
        </div>
      </div>
      {rounds && (
        <div className="cl-rounds" role="group" aria-label="Rondas del día">
          {rounds.map((r) => (
            <button key={r.id} type="button" title={`Ronda ${r.round_no}: ${CHECKLIST_RUN_STATUS[r.status]?.label ?? r.status}${isFutureRound(r) ? ' (aún no empieza)' : ''}`}
              className={`cl-round cl-round-${isFutureRound(r) && r.status === 'pending' ? 'future' : r.status} ${r.id === run.id ? 'cl-round-current' : ''}`}
              onClick={() => onPickRound(r)}>
              {formatTime(r.scheduled_start)}
            </button>
          ))}
        </div>
      )}
      {expanded && <RunItems runId={run.id} />}
    </div>
  )
}

/** Ítems del checklist con su respuesta (se cargan al expandir). */
function RunItems({ runId }) {
  const load = useCallback(() => getRunDetail(runId), [runId])
  const { data, loading, error } = useAsync(load)
  if (loading && !data) return <div className="cl-run-body text-muted text-sm">Cargando ítems…</div>
  if (error) return <div className="cl-run-body text-sm td-danger">{error.message}</div>
  const byQuestion = Object.fromEntries(data.answers.map((a) => [a.question_id, a]))
  const label = (v) => ({ yes: 'Sí', no: 'No', na: 'N/A' }[v] ?? v)
  return (
    <div className="cl-run-body">
      <div className="cl-question-list">
        {data.questions.map((q) => {
          const a = byQuestion[q.id]
          const v = a?.answer_value
          const cls = v == null || v === '' ? 'q-pending' : v === 'no' ? 'q-fail' : 'q-ok'
          return (
            <div key={q.id} className={`checklist-question ${cls}`}>
              <span className="q-indicator" />
              <div className="q-body">
                <span className="q-text">{q.text}{q.is_required && <span className="form-required"> *</span>}</span>
                {q.requires_photo && <span className="q-photo-tag">📷 Requiere foto</span>}
                {a?.comment && <span className="q-comment">"{a.comment}"</span>}
              </div>
              <span className="q-answer-label">{v ? label(v) : 'Sin responder'}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
