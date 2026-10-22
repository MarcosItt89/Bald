import { useNavigate } from 'react-router-dom'
import { Clock, Siren, Thermometer, TriangleAlert } from 'lucide-react'
import { getTemperatureReport } from '../../../services/reportService'
import { TASK_STATUS } from '../../../constants/status'
import { formatDateTime } from '../../../utils/formatters'
import StatCard from '../../../components/ui/StatCard'
import StatusBadge from '../../../components/ui/StatusBadge'
import Table from '../../../components/ui/Table'
import LineChart from '../../../components/charts/LineChart'
import { fmtHours, fmtPct, shortDate, useReport, useReportLink } from '../reportFilters'
import { ReportSection, ReportState } from '../reportUi'

const range = (e) => `${e.min ?? '−∞'} a ${e.max ?? '∞'} ${e.unit}`

export default function TemperaturesTab({ filters }) {
  const { data, loading, error, reload } = useReport(getTemperatureReport, filters)
  const link = useReportLink()
  const navigate = useNavigate()
  const { from, to, deptId: dept } = filters
  const tasksLink = link('/tasks', { tab: 'all', done: '1' })

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload} empty={data && !data.readings && !data.outOfRange}>
      {data && (<>
        <div className="report-kpis">
          <StatCard label="Lecturas registradas" value={data.readings} icon={Thermometer} tone="blue" hint={`${data.equipments.length} equipos`} />
          <StatCard label="Fuera de rango" value={data.outOfRange} icon={TriangleAlert} tone="orange" hint={`${fmtPct(data.outPct)} de las lecturas`} to={tasksLink} />
          <StatCard label="Sin corregir" value={data.openEvents} icon={Siren} tone="red" hint="Tarea abierta" to={link('/tasks', { tab: 'all' })} />
          <StatCard label="Tiempo hasta corrección" value={fmtHours(data.avgFixHours)} icon={Clock} tone="purple" hint="Promedio" />
        </div>

        <div className="report-grid">
          {data.equipments.map((e) => (
            <ReportSection key={e.name} title={e.name}
              subtitle={`Permitido ${range(e)} · ${e.count} lecturas${e.out ? ` · ${e.out} fuera de rango` : ''}`}
              csv={{ name: `temperatura_${e.name}_${from}_${to}`, rows: e.daily.filter((d) => d.avg != null),
                columns: [{ key: 'day', label: 'Fecha' }, { key: 'avg', label: `Promedio (${e.unit})` }] }}>
              <LineChart band={{ min: e.min, max: e.max }} format={(v) => `${v}${e.unit}`}
                series={[{ key: 'avg', label: 'Promedio del día', slot: 1 }]}
                data={e.daily.map((d) => ({
                  x: d.day, label: shortDate(d.day), values: { avg: d.avg },
                  to: link('/checklists/history', { from: d.day, to: d.day, status: 'all', dept }),
                }))} />
            </ReportSection>
          ))}

          <ReportSection wide title="Lecturas fuera de rango" subtitle="Cada una generó una tarea; se considera corregida cuando la tarea se cierra o la lectura se corrige"
            csv={{ name: `temperaturas-fuera-de-rango_${from}_${to}`, rows: data.events, columns: [
              { key: 'created_at', label: 'Detectada' }, { key: 'title', label: 'Lectura' }, { key: 'branch_name', label: 'Sucursal' },
              { key: 'department_name', label: 'Departamento' }, { label: 'Estado', value: (r) => TASK_STATUS[r.status]?.label },
              { key: 'fixedAt', label: 'Corregida' }, { key: 'hours', label: 'Horas hasta corrección' }] }}>
            <Table data={data.events} emptyText="Ninguna lectura fuera de rango en este periodo"
              onRowClick={tasksLink ? () => navigate(tasksLink) : undefined}
              columns={[
                { key: 'title', label: 'Lectura', bold: true, render: (v, r) => <>{v.replace(/^(Temperatura|Lectura) fuera de rango: /, '')}<div className="cell-sub">{formatDateTime(r.created_at)} · {r.branch_name}{r.department_name ? ` · ${r.department_name}` : ''}</div></> },
                { key: 'status', label: 'Tarea', render: (v) => <StatusBadge statusMap={TASK_STATUS} value={v} /> },
                { key: 'hours', label: 'Corrección', align: 'right', sortable: true, render: (v) => (v == null ? <span className="text-muted">Pendiente</span> : fmtHours(v)) },
              ]} />
          </ReportSection>
        </div>
      </>)}
    </ReportState>
  )
}
