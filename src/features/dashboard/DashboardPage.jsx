/**
 * DashboardPage — panel inicial personalizado por rol.
 *
 * Objetivo (Objetivos §11.1): mostrar a cada quien lo que necesita atender
 * HOY. Las tarjetas se generan solo para módulos permitidos: la cajera ve
 * sus tareas y checklists; el gerente ve pedidos por aprobar, stock crítico,
 * evidencias por revisar, etc. Cada tarjeta enlaza a su módulo.
 */
import { useCallback } from 'react'
import { Link } from 'react-router-dom'
import {
  ListTodo, CheckSquare, AlertTriangle, ClipboardCheck, Package, ShoppingCart, Tags,
  CalendarClock, Truck, DoorOpen, Camera, LifeBuoy, Megaphone,
} from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { P } from '../../config/permissions'
import {
  getDashboardSummary, getTodayRuns, getMyOpenTasks, getCriticalStock,
} from '../../services/dashboardService'
import { getUnreadAnnouncements } from '../../services/announcementService'
import { CHECKLIST_RUN_STATUS, INVENTORY_STATUS, PRIORITY } from '../../constants/status'
import { formatDate, formatNumber, formatTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import StatCard from '../../components/ui/StatCard'
import Card from '../../components/ui/Card'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState } from '../../components/ui/Feedback'
import Badge from '../../components/ui/Badge'

/** Definición de tarjetas: clave del resumen → presentación. */
const CARDS = [
  { key: 'myTasks',            label: 'Mis tareas abiertas',     icon: ListTodo,       tone: 'blue',   to: '/tasks' },
  { key: 'checklistsPending',  label: 'Checklists de hoy',       icon: CheckSquare,    tone: 'orange', to: '/checklists' },
  { key: 'checklistsOverdue',  label: 'Checklists vencidos hoy', icon: AlertTriangle,  tone: 'red',    to: '/checklists', alert: 'Requieren reapertura' },
  { key: 'checklistsToReview', label: 'Checklists por revisar',  icon: ClipboardCheck, tone: 'purple', to: '/checklists' },
  { key: 'lowStock',           label: 'Productos bajo mínimo',   icon: Package,        tone: 'red',    to: '/inventory' },
  { key: 'ordersToApprove',    label: 'Pedidos por aprobar',     icon: ShoppingCart,   tone: 'purple', to: '/orders' },
  { key: 'myOpenOrders',       label: 'Mis pedidos en curso',    icon: ShoppingCart,   tone: 'purple', to: '/orders' },
  { key: 'tagsPending',        label: 'Cenefas pendientes',      icon: Tags,           tone: 'orange', to: '/shelf-tags' },
  { key: 'expiringSoon',       label: 'Lotes que vencen ≤ 3 días', icon: CalendarClock, tone: 'red',   to: '/expirations' },
  { key: 'receivingOpen',      label: 'Recibos abiertos',        icon: Truck,          tone: 'green',  to: '/receiving' },
  { key: 'suppliersInside',    label: 'Proveedores en tienda',   icon: DoorOpen,       tone: 'slate',  to: '/supplier-access' },
  { key: 'evidencePending',    label: 'Evidencias por revisar',  icon: Camera,         tone: 'blue',   to: '/evidence' },
  { key: 'ticketsOpen',        label: 'Tickets abiertos',        icon: LifeBuoy,       tone: 'slate',  to: '/support' },
  { key: 'myTickets',          label: 'Mis tickets de ayuda',    icon: LifeBuoy,       tone: 'slate',  to: '/support' },
]

export default function DashboardPage() {
  const { profile, hasPermission, hasAny, branchFilter } = useAuth()
  const today = todayISO()

  const loadSummary = useCallback(
    () => getDashboardSummary({ can: hasPermission, branchId: branchFilter, employeeId: profile.id, today }),
    [hasPermission, branchFilter, profile.id, today],
  )
  const summary = useAsync(loadSummary)

  const canChecklists = hasAny([P.FILL_CHECKLISTS, P.REVIEW_CHECKLISTS])
  const loadRuns = useCallback(
    () => (canChecklists ? getTodayRuns({ branchId: branchFilter, today }) : Promise.resolve([])),
    [canChecklists, branchFilter, today],
  )
  const runs = useAsync(loadRuns)

  const loadTasks = useCallback(() => getMyOpenTasks(profile.id), [profile.id])
  const tasks = useAsync(loadTasks)

  const canInventory = hasPermission(P.VIEW_INVENTORY)
  const loadStock = useCallback(
    () => (canInventory ? getCriticalStock(branchFilter) : Promise.resolve([])),
    [canInventory, branchFilter],
  )
  const stock = useAsync(loadStock)

  const announcements = useAsync(getUnreadAnnouncements)
  const unread = announcements.data ?? []

  const longDate = new Date().toLocaleDateString('es-MX', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
  const visibleCards = CARDS.filter((c) => summary.data && summary.data[c.key] != null)

  return (
    <div className="page">
      <PageHeader
        title={`Hola, ${profile.full_name.split(' ')[0]}`}
        subtitle={`${longDate} · ${profile.role_name}${profile.branch_name ? ` · ${profile.branch_name}` : ''}`}
      />

      {unread.length > 0 && (
        <Link to={unread.length === 1 ? `/announcements?id=${unread[0].id}` : '/announcements'} className="hint-box hint-warning ann-banner">
          <Megaphone size={18} />
          <span><strong>{unread.length === 1 ? 'Tienes un comunicado por confirmar' : `Tienes ${unread.length} comunicados por confirmar`}</strong>
            <span className="ann-banner-title">«{unread[0].title}»{unread.length > 1 ? ' y otros' : ''}</span></span>
        </Link>
      )}

      {summary.error && <ErrorState error={summary.error} onRetry={summary.reload} />}

      <div className="stat-grid">
        {summary.loading && !summary.data
          ? Array.from({ length: 4 }).map((_, i) => <div key={i} className="stat-card skeleton" />)
          : visibleCards.map((c) => (
            <StatCard key={c.key} label={c.label} value={formatNumber(summary.data[c.key])} icon={c.icon}
              tone={c.tone} to={c.to} alert={summary.data[c.key] > 0 ? c.alert : undefined} />
          ))}
      </div>

      <div className="dashboard-grid">
        {canChecklists && (
          <Card title={<><CheckSquare size={16} /> Checklists de hoy</>} flush
            action={<Link to="/checklists" className="link-btn">Ver todos</Link>}>
            {runs.data?.length === 0 && <p className="card-empty">No hay checklists programados hoy.</p>}
            <ul className="list">
              {runs.data?.map((r) => (
                <li key={r.id} className="list-item">
                  <div>
                    <span className="td-bold">{r.title}{r.rounds_total > 1 && <span className="text-muted"> · ronda {r.round_no} de {r.rounds_total}</span>}</span>
                    <span className="list-meta">{r.department_name} · {formatTime(r.scheduled_start)}–{formatTime(r.scheduled_end)}</span>
                  </div>
                  <StatusBadge statusMap={CHECKLIST_RUN_STATUS} value={r.status} />
                </li>
              ))}
            </ul>
          </Card>
        )}

        <Card title={<><ListTodo size={16} /> Mis tareas</>} flush
          action={<Link to="/tasks" className="link-btn">Ver todas</Link>}>
          {tasks.data?.length === 0 && <p className="card-empty">No tienes tareas pendientes. 🎉</p>}
          <ul className="list">
            {tasks.data?.map((t) => (
              <li key={t.id} className="list-item">
                <div>
                  <span className="td-bold">{t.title}</span>
                  <span className="list-meta">
                    {t.due_date ? `Límite ${formatDate(t.due_date)}` : 'Sin fecha límite'}
                    {t.is_late && <Badge color="danger" className="ml-1">Atrasada</Badge>}
                  </span>
                </div>
                <StatusBadge statusMap={PRIORITY} value={t.priority} />
              </li>
            ))}
          </ul>
        </Card>

        {canInventory && (
          <Card title={<><Package size={16} /> Stock crítico</>} flush
            action={<Link to="/inventory" className="link-btn">Ir a inventario</Link>}>
            {stock.data?.length === 0 && <p className="card-empty">Sin productos en nivel crítico.</p>}
            <ul className="list">
              {stock.data?.map((s) => (
                <li key={s.id} className="list-item">
                  <div>
                    <span className="td-bold">{s.product_name}</span>
                    <span className="list-meta">{s.sku} · mín. {formatNumber(s.min_stock, 2)} {s.unit}{branchFilter ? '' : ` · ${s.branch_name}`}</span>
                  </div>
                  <div className="list-right">
                    <strong className="td-danger">{formatNumber(s.stock, 2)}</strong>
                    <StatusBadge statusMap={INVENTORY_STATUS} value={s.status} />
                  </div>
                </li>
              ))}
            </ul>
          </Card>
        )}
      </div>
    </div>
  )
}
