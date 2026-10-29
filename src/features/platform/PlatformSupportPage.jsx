/**
 * PlatformSupportPage — Plataforma → Soporte de tiendas (solo superadmins).
 * Bandeja de los tickets de TODAS las empresas, vía platform_list_tickets
 * (las políticas RLS de cada empresa no se abren). Acepta ?empresa=<id>.
 */
import { useCallback, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Headset, MapPin } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { getCompanies, getPlatformTickets } from '../../services/platformService'
import { PRIORITY, TICKET_CATEGORY, TICKET_STATUS } from '../../constants/status'
import { formatRelative } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Tabs from '../../components/ui/Tabs'
import Badge from '../../components/ui/Badge'
import SearchInput from '../../components/ui/SearchInput'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState } from '../../components/ui/Feedback'
import { BlocksBadge, DueBadge } from '../support/supportUi'

const TABS = [
  { key: 'active', label: 'Abiertos' },
  { key: 'overdue', label: 'Vencidos' },
  { key: 'waiting_user', label: 'Esperando usuario' },
  { key: 'done', label: 'Cerrados' },
  { key: '', label: 'Todos' },
]

export default function PlatformSupportPage() {
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const companyId = params.get('empresa') ?? ''
  const [tab, setTab] = useState('active')
  const [search, setSearch] = useState('')
  const debounced = useDebouncedValue(search)
  const { data: companies = [] } = useAsync(getCompanies)

  const load = useCallback(() => getPlatformTickets({ companyId, status: tab, search: debounced }), [companyId, tab, debounced])
  const { data: rows = [], loading, error, reload } = useAsync(load)

  const setCompany = (id) => setParams(id ? { empresa: id } : {}, { replace: true })

  return (
    <div className="page">
      <PageHeader icon={Headset} title="Soporte de tiendas"
        subtitle="Tickets de todas las empresas. Tus respuestas llegan firmadas como «Soporte Operalia»." />
      <Tabs active={tab} onChange={setTab} tabs={TABS} />
      <div className="filters">
        <SearchInput value={search} onChange={setSearch} placeholder="Folio, asunto o descripción…" />
        <select className="filter-select" value={companyId} onChange={(e) => setCompany(e.target.value)} aria-label="Empresa">
          <option value="">Todas las empresas</option>
          {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={(r) => navigate(`/plataforma/soporte/${r.id}`)} emptyText="Sin tickets aquí" columns={[
          { key: 'subject', label: 'Asunto', bold: true, render: (v, r) => (
            <>
              <span className="mono text-muted">{r.folio}</span> {v}
              <div className="cell-sub">{r.topic_name ?? TICKET_CATEGORY[r.category] ?? r.category}</div>
            </>
          ) },
          { key: 'company_name', label: 'Empresa', sortable: true, render: (v, r) => (
            <>{v}<div className="cell-sub">{r.branch_name && <><MapPin size={11} /> {r.branch_name}</>}</div></>
          ) },
          { key: 'created_by_name', label: 'Solicitante', render: (v) => v ?? '—' },
          { key: 'priority', label: 'Prioridad', render: (v, r) => (
            <div className="badge-stack"><StatusBadge statusMap={PRIORITY} value={v} /><BlocksBadge ticket={r} /><DueBadge ticket={r} /></div>
          ) },
          { key: 'status', label: 'Estado', render: (v, r) => (
            <div className="badge-stack">
              <StatusBadge statusMap={TICKET_STATUS} value={v} />
              {r.platform_replied && <Badge color="primary" title="Ya respondió Soporte Operalia">Operalia</Badge>}
            </div>
          ) },
          { key: 'updated_at', label: 'Actividad', sortable: true, render: formatRelative },
        ]} />
      </Card>
    </div>
  )
}
