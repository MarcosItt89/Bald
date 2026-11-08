/**
 * SupportPage — Soporte.
 * - create_tickets: "Mis tickets" (y los de su equipo si es jefe/gerente).
 * - manage_tickets: bandeja Sin asignar / Míos / Vencidos / Esperando usuario / Cerrados.
 * - Acepta ?tab= y ?cat= (categoría, desde Estadísticas: muestra todos los tickets de esa categoría).
 */
import { useCallback, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { LifeBuoy, Plus, MapPin } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { P } from '../../config/permissions'
import { getTickets } from '../../services/supportService'
import { PRIORITY, TICKET_CATEGORY, TICKET_STATUS } from '@operalia/compartido/constants/status.js'
import FilterChip from '@operalia/compartido/components/ui/FilterChip.jsx'
import { formatRelative } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Tabs from '@operalia/compartido/components/ui/Tabs.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import StatusBadge from '@operalia/compartido/components/ui/StatusBadge.jsx'
import { ErrorState } from '@operalia/compartido/components/ui/Feedback.jsx'
import { BlocksBadge, DueBadge } from '@operalia/compartido/support/supportUi.jsx'

const AGENT_TABS = [
  { key: 'unassigned', label: 'Sin asignar', filter: () => ({ status: 'active', unassigned: true }) },
  { key: 'assigned', label: 'Míos', filter: (me) => ({ status: 'active', assignedTo: me }) },
  { key: 'overdue', label: 'Vencidos', filter: () => ({ overdue: true }) },
  { key: 'waiting', label: 'Esperando usuario', filter: () => ({ status: 'waiting_user' }) },
  { key: 'done', label: 'Cerrados', filter: () => ({ status: 'done' }) },
]

const USER_TABS = [
  { key: 'mine', label: 'Mis tickets', filter: (me) => ({ status: 'active', createdBy: me }) },
  { key: 'team', label: 'De mi equipo', team: true, filter: (me) => ({ status: 'active', notCreatedBy: me }) },
  { key: 'done', label: 'Cerrados', filter: () => ({ status: 'done' }) },
]

export default function SupportPage() {
  const { hasPermission, profile } = useAuth()
  const navigate = useNavigate()
  const isAgent = hasPermission(P.MANAGE_TICKETS)
  const tabs = isAgent ? AGENT_TABS : USER_TABS.filter((t) => !t.team || profile.role_scope !== 'self')
  const [params] = useSearchParams()
  const [tab, setTab] = useState(() => params.get('tab') ?? tabs[0].key)
  const [category, setCategory] = useState(() => params.get('cat') ?? '')
  const current = tabs.find((t) => t.key === tab) ?? tabs[0]
  const showRequester = isAgent || category || current.key !== 'mine'

  const load = useCallback(() => getTickets(category ? { category } : current.filter(profile.id)), [current, category, profile.id])
  const { data: rows = [], loading, error, reload } = useAsync(load)

  return (
    <div className="page">
      <PageHeader icon={LifeBuoy} title={isAgent ? 'Bandeja de soporte' : 'Soporte'}
        subtitle={isAgent ? 'Atiende y da seguimiento a los reportes' : '¿Algo no funciona? Repórtalo y dale seguimiento aquí'}
        actions={hasPermission(P.CREATE_TICKETS) && <Button size="sm" onClick={() => navigate('/support/new')}><Plus size={14} /> Nuevo ticket</Button>} />
      <Tabs active={category ? null : current.key} onChange={(k) => { setCategory(''); setTab(k) }} tabs={tabs} />
      {category && <div className="filters"><FilterChip label={`Categoría: ${TICKET_CATEGORY[category] ?? category} (todos los estados)`} onClear={() => setCategory('')} /></div>}
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={(r) => navigate(`/support/${r.id}`)} emptyText="Sin tickets aquí" columns={[
          { key: 'subject', label: 'Asunto', bold: true, render: (v, r) => (
            <>
              <span className="mono text-muted">{r.folio}</span> {v}
              <div className="cell-sub">
                {r.topic_name ?? TICKET_CATEGORY[r.category]}
                {r.location && <> · <MapPin size={11} /> {r.location}</>}
              </div>
            </>
          ) },
          ...(showRequester ? [{ key: 'created_by_name', label: 'Solicitante', render: (v, r) => <>{v}<div className="cell-sub">{[r.branch_name, r.department_name].filter(Boolean).join(' · ')}</div></> }] : []),
          ...(isAgent ? [{ key: 'assigned_to_name', label: 'Asignado', render: (v) => v ?? <span className="text-muted">—</span> }] : []),
          { key: 'priority', label: 'Prioridad', render: (v, r) => (
            <div className="badge-stack"><StatusBadge statusMap={PRIORITY} value={v} /><BlocksBadge ticket={r} /><DueBadge ticket={r} /></div>
          ) },
          { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={TICKET_STATUS} value={v} /> },
          { key: 'updated_at', label: 'Actividad', sortable: true, render: formatRelative },
        ]} />
      </Card>
    </div>
  )
}
