import {
  CheckSquare, Package, ShoppingCart, DollarSign,
  AlertTriangle, ClipboardList, Activity,
} from 'lucide-react'
import { useAuth } from '../../contexts/AuthContext'
import { MOCK_DASHBOARD, MOCK_TASKS, MOCK_CHECKLIST_RUNS } from '../../data/mockData'
import StatusBadge from '../../components/ui/StatusBadge'
import { CHECKLIST_STATUS, TASK_PRIORITY } from '../../utils/statusHelpers'
import { formatDate } from '../../utils/formatters'

// TODO: Replace MOCK_DASHBOARD with a Supabase query filtered by user.branch / user.company_id

const STAT_CARDS = [
  {
    key: 'pendingTasks',
    label: 'Tareas pendientes',
    icon: ClipboardList,
    color: 'stat-blue',
  },
  {
    key: 'pendingChecklists',
    label: 'Checklists del día',
    icon: CheckSquare,
    color: 'stat-orange',
  },
  {
    key: 'lowStockProducts',
    label: 'Productos bajo stock',
    icon: Package,
    color: 'stat-red',
  },
  {
    key: 'pendingOrders',
    label: 'Pedidos pendientes',
    icon: ShoppingCart,
    color: 'stat-purple',
  },
  {
    key: 'pendingPriceChanges',
    label: 'Cambios de precio',
    icon: DollarSign,
    color: 'stat-green',
  },
]

const ACTIVITY_ICONS = {
  checklist: CheckSquare,
  price:     DollarSign,
  order:     ShoppingCart,
  task:      ClipboardList,
  receiving: Package,
}

export default function DashboardPage() {
  const { user } = useAuth()
  const today = new Date().toLocaleDateString('es-MX', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  })

  return (
    <div className="page">
      {/* Encabezado */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Dashboard</h1>
          <p className="page-subtitle">{today} — {user?.branch}</p>
        </div>
      </div>

      {/* Tarjetas de resumen */}
      <div className="stat-grid">
        {STAT_CARDS.map(card => {
          const Icon = card.icon
          const value = MOCK_DASHBOARD[card.key]
          return (
            <div key={card.key} className={`stat-card ${card.color}`}>
              <div className="stat-card-body">
                <div className="stat-card-info">
                  <span className="stat-card-label">{card.label}</span>
                  <span className="stat-card-value">{value}</span>
                </div>
                <div className="stat-card-icon">
                  <Icon size={28} />
                </div>
              </div>
              {value > 0 && (
                <div className="stat-card-alert">
                  <AlertTriangle size={12} />
                  <span>Requiere atención</span>
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Contenido principal */}
      <div className="dashboard-grid">
        {/* Checklists del día */}
        <div className="card">
          <div className="card-header">
            <h3 className="card-title">
              <CheckSquare size={16} /> Checklists del día
            </h3>
          </div>
          <div className="card-body p-0">
            <table className="table">
              <thead>
                <tr>
                  <th>Checklist</th>
                  <th>Departamento</th>
                  <th>Turno</th>
                  <th>Estado</th>
                </tr>
              </thead>
              <tbody>
                {MOCK_CHECKLIST_RUNS.slice(0, 5).map(cl => (
                  <tr key={cl.id}>
                    <td className="td-bold">{cl.title}</td>
                    <td>{cl.department}</td>
                    <td>{cl.schedule}</td>
                    <td>
                      <StatusBadge statusMap={CHECKLIST_STATUS} value={cl.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Tareas pendientes */}
        <div className="card">
          <div className="card-header">
            <h3 className="card-title">
              <ClipboardList size={16} /> Tareas pendientes
            </h3>
          </div>
          <div className="card-body p-0">
            <table className="table">
              <thead>
                <tr>
                  <th>Tarea</th>
                  <th>Responsable</th>
                  <th>Límite</th>
                  <th>Prioridad</th>
                </tr>
              </thead>
              <tbody>
                {MOCK_TASKS.filter(t => t.status !== 'completed').map(task => (
                  <tr key={task.id}>
                    <td className="td-bold">{task.title}</td>
                    <td>{task.assignee}</td>
                    <td>{formatDate(task.dueDate)}</td>
                    <td>
                      <StatusBadge statusMap={TASK_PRIORITY} value={task.priority} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Actividad reciente */}
        <div className="card dashboard-activity">
          <div className="card-header">
            <h3 className="card-title">
              <Activity size={16} /> Actividad reciente
            </h3>
          </div>
          <div className="card-body">
            <ul className="activity-list">
              {MOCK_DASHBOARD.recentActivity.map(item => {
                const Icon = ACTIVITY_ICONS[item.type] ?? Activity
                return (
                  <li key={item.id} className="activity-item">
                    <div className={`activity-icon activity-${item.type}`}>
                      <Icon size={14} />
                    </div>
                    <div className="activity-content">
                      <span className="activity-message">{item.message}</span>
                      <span className="activity-meta">{item.user} · {item.time}</span>
                    </div>
                  </li>
                )
              })}
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
