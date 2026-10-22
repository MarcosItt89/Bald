import { Inbox, ShieldCheck, Siren, Timer } from 'lucide-react'
import { getSupportReport } from '../../../services/reportService'
import { TICKET_CATEGORY } from '../../../constants/status'
import { useAuth } from '../../../hooks/useAuth'
import { P } from '../../../config/permissions'
import StatCard from '../../../components/ui/StatCard'
import BarList from '../../../components/charts/BarList'
import Donut from '../../../components/charts/Donut'
import { fmtHours, fmtPct, useReport, useReportLink } from '../reportFilters'
import { ReportSection, ReportState } from '../reportUi'

export default function SupportTab({ filters }) {
  const { data, loading, error, reload } = useReport(getSupportReport, filters)
  const link = useReportLink()
  const { hasPermission } = useAuth()
  const isAgent = hasPermission(P.MANAGE_TICKETS)
  const { from, to } = filters

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload} empty={data && !data.created && !data.open}>
      {data && (<>
        <div className="report-kpis">
          <StatCard label="Tickets abiertos" value={data.open} icon={Inbox} tone="blue" hint="Hoy" to={link('/support')} />
          <StatCard label="Primera respuesta" value={fmtHours(data.firstResponseH)} icon={Timer} tone="purple" hint="Promedio del periodo" />
          <StatCard label="Cumplimiento de SLA" value={fmtPct(data.slaPct)} icon={ShieldCheck} tone="green" hint={`${data.slaMet} de ${data.slaMet + data.slaMissed}`} />
          <StatCard label="Vencidos sin resolver" value={data.overdueNow} icon={Siren} tone="red"
            to={isAgent ? link('/support', { tab: 'overdue' }) : link('/support')} />
        </div>

        <div className="report-grid">
          <ReportSection title="Cumplimiento de SLA" subtitle={`${data.created} tickets levantados en el periodo`}
            csv={{ name: `soporte-sla_${from}_${to}`, rows: [{ label: 'En tiempo', value: data.slaMet }, { label: 'Fuera de tiempo', value: data.slaMissed }],
              columns: [{ key: 'label', label: 'SLA' }, { key: 'value', label: 'Tickets' }] }}>
            <Donut emptyText="Ningún ticket con tiempo de atención en el periodo" center={{ value: fmtPct(data.slaPct), label: 'en tiempo' }} segments={[
              { key: 'met', label: 'En tiempo', value: data.slaMet, tone: 'good', to: link('/support', { tab: 'done' }) },
              { key: 'missed', label: 'Fuera de tiempo', value: data.slaMissed, tone: 'bad', to: isAgent ? link('/support', { tab: 'overdue' }) : link('/support') },
            ]} />
          </ReportSection>

          <ReportSection title="Tickets por categoría"
            csv={{ name: `soporte-categoria_${from}_${to}`, rows: data.byCategory, columns: [
              { label: 'Categoría', value: (r) => TICKET_CATEGORY[r.category] ?? r.category }, { key: 'count', label: 'Tickets' },
              { key: 'open', label: 'Abiertos' }, { key: 'slaPct', label: '% SLA' }] }}>
            <BarList items={data.byCategory.map((c) => ({
              key: c.category, label: TICKET_CATEGORY[c.category] ?? c.category, value: c.count,
              hint: `${c.open} abiertos · SLA ${fmtPct(c.slaPct)}`, to: link('/support', { cat: c.category }),
            }))} />
          </ReportSection>
        </div>
      </>)}
    </ReportState>
  )
}
