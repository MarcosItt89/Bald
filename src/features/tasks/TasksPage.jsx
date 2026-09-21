import { ClipboardList } from 'lucide-react'
import { MOCK_TASKS } from '../../data/mockData'
import StatusBadge from '../../components/ui/StatusBadge'
import { TASK_PRIORITY, CHECKLIST_STATUS } from '../../utils/statusHelpers'
import { formatDate } from '../../utils/formatters'
import Badge from '../../components/ui/Badge'

// TODO: Replace MOCK_TASKS with: supabase.from('tasks').select('*, employees(name)').eq('branch_id', user.branch_id)

const TASK_STATUS = {
  pending:     { label: 'Pendiente',   color: 'warning' },
  in_progress: { label: 'En progreso', color: 'info'    },
  completed:   { label: 'Completada',  color: 'success' },
}

export default function TasksPage() {
  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Tareas</h1>
          <p className="page-subtitle">{MOCK_TASKS.filter(t => t.status !== 'completed').length} tareas activas</p>
        </div>
      </div>

      <div className="card">
        <div className="card-body p-0">
          <table className="table">
            <thead>
              <tr>
                <th>Tarea</th><th>Departamento</th><th>Responsable</th>
                <th>Fecha límite</th><th>Prioridad</th><th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {MOCK_TASKS.map(t => (
                <tr key={t.id}>
                  <td className="td-bold">
                    <ClipboardList size={14} className="inline-icon" /> {t.title}
                  </td>
                  <td>{t.department}</td>
                  <td>{t.assignee}</td>
                  <td>{formatDate(t.dueDate)}</td>
                  <td><StatusBadge statusMap={TASK_PRIORITY} value={t.priority} /></td>
                  <td><StatusBadge statusMap={TASK_STATUS} value={t.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
