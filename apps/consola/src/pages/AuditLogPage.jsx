/**
 * AuditLogPage — Bitácora de la plataforma (solo superadmins; migración 0032).
 * Altas, suspensiones y reactivaciones de empresas, cambios de marca hechos
 * por un superadmin y respuestas de «Soporte Operalia», de todas las empresas.
 * Filtros por empresa y tipo de evento en la URL (?empresa=&evento=).
 */
import { useCallback, useMemo } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Ban, CirclePlay, CirclePlus, Download, Headset, Palette, ScrollText } from 'lucide-react'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { downloadCsv } from '@operalia/compartido/utils/csv.js'
import { formatDateTime, formatRelative } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Badge from '@operalia/compartido/components/ui/Badge.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import { ErrorState } from '@operalia/compartido/components/ui/Feedback.jsx'
import { getAuditLog, getCompanies } from '../services/platformService'

const EVENTS = {
  alta:         { label: 'Alta de empresa', color: 'success', icon: CirclePlus },
  suspension:   { label: 'Suspensión',      color: 'danger',  icon: Ban },
  reactivacion: { label: 'Reactivación',    color: 'info',    icon: CirclePlay },
  marca:        { label: 'Marca',           color: 'primary', icon: Palette },
  soporte:      { label: 'Respuesta de soporte', color: 'default', icon: Headset },
}

export default function AuditLogPage() {
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const companyId = params.get('empresa') ?? ''
  const event = params.get('evento') ?? ''
  const setFilter = (patch) => {
    const next = new URLSearchParams(params)
    Object.entries(patch).forEach(([k, v]) => (v ? next.set(k, v) : next.delete(k)))
    setParams(next, { replace: true })
  }

  const companies = useAsync(getCompanies)
  const load = useCallback(() => getAuditLog({ companyId, event }), [companyId, event])
  const { data, loading, error, reload } = useAsync(load)
  // Un ticket puede tener varias respuestas: la llave es el renglón, no ref_id.
  const rows = useMemo(() => (data ?? []).map((r, i) => ({ ...r, key: `${i}-${r.ref_id}` })), [data])

  // Clic en un renglón: el ticket, la marca o el rendimiento de esa empresa.
  const open = (r) => navigate(r.event === 'soporte' ? `/soporte/${r.ref_id}`
    : r.event === 'marca' ? `/marca?empresa=${r.company_id}` : `/rendimiento?empresa=${r.company_id}`)
  const exportCsv = () => downloadCsv('bitacora-plataforma.csv', rows, [
    { label: 'Fecha', value: (r) => formatDateTime(r.at) }, { label: 'Evento', value: (r) => EVENTS[r.event]?.label ?? r.event },
    { key: 'company_name', label: 'Empresa' }, { key: 'company_code', label: 'Código' },
    { key: 'actor_name', label: 'Quién' }, { key: 'detail', label: 'Detalle' },
  ])

  return (
    <div className="page">
      <PageHeader icon={ScrollText} title="Bitácora" subtitle="Altas, suspensiones, marca y respuestas de soporte de todas las empresas"
        actions={<Button size="sm" variant="outline" disabled={!rows.length} onClick={exportCsv}><Download size={14} /> CSV</Button>} />

      <div className="filters">
        <select className="filter-select" aria-label="Empresa" value={companyId} onChange={(e) => setFilter({ empresa: e.target.value })}>
          <option value="">Todas las empresas</option>
          {(companies.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select className="filter-select" aria-label="Evento" value={event} onChange={(e) => setFilter({ evento: e.target.value })}>
          <option value="">Todos los eventos</option>
          {Object.entries(EVENTS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select>
      </div>

      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} rowKey="key" onRowClick={open} emptyText="Sin eventos con estos filtros" columns={[
          { key: 'at', label: 'Cuándo', sortable: true, render: (v) => <>{formatRelative(v)}<div className="cell-sub">{formatDateTime(v)}</div></> },
          { key: 'event', label: 'Evento', render: (v) => {
            const e = EVENTS[v] ?? { label: v, color: 'default', icon: ScrollText }
            return <Badge color={e.color}><e.icon size={11} /> {e.label}</Badge>
          } },
          { key: 'company_name', label: 'Empresa', bold: true, sortable: true,
            render: (v, r) => <>{v ?? '—'}<div className="cell-sub mono">{r.company_code}</div></> },
          { key: 'detail', label: 'Detalle', render: (v) => v ?? '—' },
          { key: 'actor_name', label: 'Quién', render: (v) => v ?? '—' },
        ]} />
      </Card>
    </div>
  )
}
