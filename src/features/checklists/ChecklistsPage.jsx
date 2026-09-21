import { useState, useMemo } from 'react'
import {
  CheckSquare, Clock, AlertTriangle, ChevronDown, ChevronRight,
  Filter, History, Plus, Eye,
} from 'lucide-react'
import { useAuth } from '../../contexts/AuthContext'
import { MOCK_CHECKLIST_RUNS } from '../../data/mockData'
import { MOCK_BRANCHES } from '../../data/mockData'
import { DEPARTMENTS } from '../../utils/departments'
import { CHECKLIST_RUN_STATUS, CHECKLIST_REVIEW_STATUS } from '../../utils/statusHelpers'
import StatusBadge from '../../components/ui/StatusBadge'
import Badge from '../../components/ui/Badge'
import Button from '../../components/ui/Button'

// TODO: Replace MOCK_CHECKLIST_RUNS with:
//   supabase.from('checklist_runs')
//     .select('*, checklist_assignments(*, checklist_templates(*)), checklist_answers(*)')
//     .eq('branch_id', user.branch_id)
//     .gte('scheduled_date', today)

const TODAY = '2026-06-12'

const FILTER_TABS = [
  { key: 'all',         label: 'Todos'       },
  { key: 'pending',     label: 'Pendientes'  },
  { key: 'in_progress', label: 'En progreso' },
  { key: 'completed',   label: 'Completados' },
  { key: 'overdue',     label: 'Vencidos'    },
]

function ProgressBar({ answered, total }) {
  const pct = total > 0 ? Math.round((answered / total) * 100) : 0
  return (
    <div className="cl-progress-bar">
      <div className="cl-progress-track">
        <div className="cl-progress-fill" style={{ width: `${pct}%` }} />
      </div>
      <span className="cl-progress-label">{answered}/{total} preguntas</span>
    </div>
  )
}

function QuestionList({ questions, readonly = false }) {
  return (
    <div className="cl-question-list">
      {questions.map(q => {
        const stateClass = q.answer === true ? 'q-ok' : q.answer === false ? 'q-fail' : 'q-pending'
        return (
          <div key={q.id} className={`checklist-question ${stateClass}`}>
            <span className="q-indicator" />
            <div className="q-body">
              <span className="q-text">{q.text}</span>
              {q.requiresPhoto && (
                <span className={`q-photo-tag ${q.evidenceUploaded ? 'photo-ok' : 'photo-pending'}`}>
                  {q.evidenceUploaded ? '📷 Evidencia cargada' : '📷 Evidencia requerida'}
                </span>
              )}
              {q.comment && <span className="q-comment">"{q.comment}"</span>}
            </div>
            {readonly && q.answer !== null && (
              <span className="q-answer-label">
                {q.answer === true ? 'Sí' : q.answer === false ? 'No' : '—'}
              </span>
            )}
          </div>
        )
      })}
    </div>
  )
}

function RunCard({ run, expanded, onToggle }) {
  const isCompleted = run.status === 'completed'
  const isOverdue   = run.status === 'overdue'
  const isPending   = run.status === 'pending'
  const isProgress  = run.status === 'in_progress'

  return (
    <div className={`cl-run-card ${isOverdue ? 'cl-run-overdue' : ''} ${isCompleted ? 'cl-run-completed' : ''}`}>
      {/* Header */}
      <div className="cl-run-header" onClick={onToggle} role="button" tabIndex={0}
        onKeyDown={e => e.key === 'Enter' && onToggle()}>
        <div className="cl-run-header-left">
          <button className="cl-expand-btn">
            {expanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
          </button>
          <div className="cl-run-info">
            <span className="cl-run-title">{run.title}</span>
            <div className="cl-run-meta">
              <span>{run.department}</span>
              <span>·</span>
              <span>{run.schedule}</span>
              <span>·</span>
              <Clock size={12} />
              <span>{run.scheduledStart}–{run.scheduledEnd}</span>
              {run.requiresEvidence && (
                <Badge color="info" className="cl-evidence-badge">Evidencia requerida</Badge>
              )}
            </div>
          </div>
        </div>

        <div className="cl-run-header-right">
          {isProgress && (
            <ProgressBar answered={run.answeredQuestions} total={run.totalQuestions} />
          )}
          {isCompleted && run.reviewStatus && (
            <StatusBadge statusMap={CHECKLIST_REVIEW_STATUS} value={run.reviewStatus} />
          )}
          <StatusBadge statusMap={CHECKLIST_RUN_STATUS} value={run.status} />
          {(isPending || isProgress) && (
            <Button variant="primary" size="sm" onClick={e => e.stopPropagation()}>
              {isPending ? 'Iniciar' : 'Continuar'}
            </Button>
          )}
          {isCompleted && (
            <Button variant="ghost" size="sm" onClick={e => e.stopPropagation()}>
              <Eye size={14} /> Ver
            </Button>
          )}
        </div>
      </div>

      {/* Body expandido */}
      {expanded && (
        <div className="cl-run-body">
          {isOverdue && (
            <div className="cl-overdue-alert">
              <AlertTriangle size={16} />
              <span>Este checklist venció sin completarse. Se requiere permiso para reabrirlo.</span>
            </div>
          )}
          {isCompleted && (
            <div className="cl-completed-meta">
              <span><strong>Completado por:</strong> {run.completedBy}</span>
              {run.startedAt && (
                <span><strong>Inicio:</strong> {new Date(run.startedAt).toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' })}</span>
              )}
              {run.completedAt && (
                <span><strong>Fin:</strong> {new Date(run.completedAt).toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' })}</span>
              )}
            </div>
          )}
          <QuestionList questions={run.questions} readonly={isCompleted} />
        </div>
      )}
    </div>
  )
}

function Section({ title, icon: Icon, runs, emptyText, defaultExpanded = true, collapsible = false }) {
  const [open, setOpen] = useState(defaultExpanded)
  const [expandedRuns, setExpandedRuns] = useState({})

  const toggleRun = (id) =>
    setExpandedRuns(prev => ({ ...prev, [id]: !prev[id] }))

  if (runs.length === 0) return null

  return (
    <div className="cl-section">
      <div className="cl-section-header" onClick={collapsible ? () => setOpen(p => !p) : undefined}
        style={{ cursor: collapsible ? 'pointer' : 'default' }}>
        <div className="cl-section-title">
          <Icon size={16} />
          <span>{title}</span>
          <Badge color="default">{runs.length}</Badge>
        </div>
        {collapsible && (open ? <ChevronDown size={16} /> : <ChevronRight size={16} />)}
      </div>

      {open && (
        <div className="cl-section-body">
          {runs.length === 0
            ? <p className="cl-empty">{emptyText}</p>
            : runs.map(run => (
              <RunCard
                key={run.id}
                run={run}
                expanded={!!expandedRuns[run.id]}
                onToggle={() => toggleRun(run.id)}
              />
            ))
          }
        </div>
      )}
    </div>
  )
}

export default function ChecklistsPage() {
  const { user, hasPermission } = useAuth()

  const [activeTab,    setActiveTab]    = useState('all')
  const [deptFilter,   setDeptFilter]   = useState('')
  const [branchFilter, setBranchFilter] = useState('')
  const [dateFilter,   setDateFilter]   = useState('')

  const canManageTemplates = hasPermission('manage_checklist_templates')

  // Filtrado
  const filtered = useMemo(() => {
    return MOCK_CHECKLIST_RUNS.filter(run => {
      if (activeTab !== 'all' && run.status !== activeTab) return false
      if (deptFilter && run.departmentId !== deptFilter) return false
      if (branchFilter && run.branchId !== branchFilter) return false
      if (dateFilter && run.scheduledDate !== dateFilter) return false
      return true
    })
  }, [activeTab, deptFilter, branchFilter, dateFilter])

  const pending    = filtered.filter(r => r.status === 'pending')
  const inProgress = filtered.filter(r => r.status === 'in_progress')
  const completed  = filtered.filter(r => r.status === 'completed')
  const overdue    = filtered.filter(r => r.status === 'overdue')

  const hasFilters = deptFilter || branchFilter || dateFilter

  return (
    <div className="page">
      {/* Encabezado */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Checklists</h1>
          <p className="page-subtitle">
            {dateFilter || TODAY} — {MOCK_CHECKLIST_RUNS.filter(r => r.status === 'pending' || r.status === 'overdue').length} sin completar
          </p>
        </div>
        {canManageTemplates && (
          <Button variant="primary" size="sm">
            <Plus size={14} /> Nuevo checklist
          </Button>
        )}
      </div>

      {/* Pestañas de estado */}
      <div className="cl-tabs">
        {FILTER_TABS.map(tab => {
          const count = tab.key === 'all'
            ? MOCK_CHECKLIST_RUNS.length
            : MOCK_CHECKLIST_RUNS.filter(r => r.status === tab.key).length
          return (
            <button
              key={tab.key}
              className={`cl-tab ${activeTab === tab.key ? 'cl-tab-active' : ''}`}
              onClick={() => setActiveTab(tab.key)}
            >
              {tab.label}
              {count > 0 && <span className="cl-tab-count">{count}</span>}
            </button>
          )
        })}
      </div>

      {/* Filtros secundarios */}
      <div className="cl-filters">
        <Filter size={14} className="cl-filter-icon" />
        <select
          className="cl-filter-select"
          value={deptFilter}
          onChange={e => setDeptFilter(e.target.value)}
        >
          <option value="">Todos los departamentos</option>
          {DEPARTMENTS.map(d => (
            <option key={d.id} value={d.id}>{d.label}</option>
          ))}
        </select>

        <select
          className="cl-filter-select"
          value={branchFilter}
          onChange={e => setBranchFilter(e.target.value)}
        >
          <option value="">Todas las sucursales</option>
          {MOCK_BRANCHES.map(b => (
            <option key={b.id} value={b.id}>{b.name}</option>
          ))}
        </select>

        <input
          type="date"
          className="cl-filter-date"
          value={dateFilter}
          onChange={e => setDateFilter(e.target.value)}
        />

        {hasFilters && (
          <button className="cl-clear-filters" onClick={() => {
            setDeptFilter(''); setBranchFilter(''); setDateFilter('')
          }}>
            Limpiar filtros
          </button>
        )}
      </div>

      {/* Secciones */}
      <div className="cl-sections">
        {activeTab === 'all' || activeTab === 'overdue' ? (
          <Section
            title="Vencidos"
            icon={AlertTriangle}
            runs={overdue}
            emptyText="Sin checklists vencidos"
            defaultExpanded
          />
        ) : null}

        {activeTab === 'all' || activeTab === 'pending' ? (
          <Section
            title="Pendientes"
            icon={Clock}
            runs={pending}
            emptyText="Sin checklists pendientes"
            defaultExpanded
          />
        ) : null}

        {activeTab === 'all' || activeTab === 'in_progress' ? (
          <Section
            title="En progreso"
            icon={CheckSquare}
            runs={inProgress}
            emptyText="Sin checklists en progreso"
            defaultExpanded
          />
        ) : null}

        {activeTab === 'all' || activeTab === 'completed' ? (
          <Section
            title="Historial — Completados"
            icon={History}
            runs={completed}
            emptyText="Sin checklists completados hoy"
            defaultExpanded={activeTab === 'completed'}
            collapsible={activeTab === 'all'}
          />
        ) : null}

        {filtered.length === 0 && (
          <div className="cl-empty-state">
            <CheckSquare size={40} />
            <p>No hay checklists que coincidan con los filtros seleccionados.</p>
          </div>
        )}
      </div>
    </div>
  )
}
