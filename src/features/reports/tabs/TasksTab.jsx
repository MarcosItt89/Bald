import { getTaskReport, pct } from '../../../services/reportService'
import LineChart from '../../../components/charts/LineChart'
import Donut from '../../../components/charts/Donut'
import BarList from '../../../components/charts/BarList'
import { fmtHours, fmtPct, shortDate, useReport, useReportLink } from '../reportFilters'
import { ReportSection, ReportState } from '../reportUi'

const CLOSE_COLUMNS = (label) => [
  { key: 'name', label }, { key: 'count', label: 'Cerradas' }, { key: 'hours', label: 'Horas promedio' }, { key: 'onTime', label: '% a tiempo' },
]

export default function TasksTab({ filters }) {
  const { data, loading, error, reload } = useReport(getTaskReport, filters)
  const link = useReportLink()
  const { from, to, deptId: dept } = filters
  const closed = data ? data.onTime + data.lateClosed : 0

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload} empty={data && !data.createdCount && !closed && !data.openLate}>
      {data && (
        <div className="report-grid">
          <ReportSection wide title="Creadas vs. cerradas por semana"
            csv={{ name: `tareas-semana_${from}_${to}`, rows: data.weekly, columns: [{ key: 'week', label: 'Semana (lunes)' }, { key: 'created', label: 'Creadas' }, { key: 'closed', label: 'Cerradas' }] }}>
            <LineChart format={(v) => v}
              series={[{ key: 'created', label: 'Creadas', slot: 1 }, { key: 'closed', label: 'Cerradas', slot: 2 }]}
              data={data.weekly.map((w) => ({
                x: w.week, label: shortDate(w.week), values: { created: w.created, closed: w.closed },
                to: link('/tasks', { tab: 'all', done: '1', dept }),
              }))} />
          </ReportSection>

          <ReportSection title="A tiempo vs. atrasadas" subtitle="Cerradas en el periodo y abiertas que ya vencieron"
            csv={{ name: `tareas-a-tiempo_${from}_${to}`, rows: [
              { label: 'Cerradas a tiempo', value: data.onTime }, { label: 'Cerradas con atraso', value: data.lateClosed }, { label: 'Abiertas atrasadas (hoy)', value: data.openLate }],
            columns: [{ key: 'label', label: 'Tipo' }, { key: 'value', label: 'Tareas' }] }}>
            <Donut center={{ value: fmtPct(pct(data.onTime, closed)), label: 'a tiempo' }} segments={[
              { key: 'ontime', label: 'Cerradas a tiempo', value: data.onTime, tone: 'good', to: link('/tasks', { tab: 'all', done: '1', dept }) },
              { key: 'late', label: 'Cerradas con atraso', value: data.lateClosed, tone: 'warn', to: link('/tasks', { tab: 'all', done: '1', dept }) },
              { key: 'open', label: 'Abiertas atrasadas', value: data.openLate, tone: 'bad', to: link('/tasks', { tab: 'all', late: '1', dept }) },
            ]} />
          </ReportSection>

          <ReportSection title="Tiempo promedio de cierre por departamento"
            csv={{ name: `tareas-cierre-departamento_${from}_${to}`, rows: data.byDepartment, columns: CLOSE_COLUMNS('Departamento') }}>
            <BarList format={fmtHours} items={data.byDepartment.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.hours, hint: `${d.count} cerradas · ${fmtPct(d.onTime)} a tiempo`,
              to: link('/tasks', { tab: 'all', done: '1', dept: d.id ?? dept }),
            }))} />
          </ReportSection>

          <ReportSection wide title="Tiempo promedio de cierre por responsable"
            csv={{ name: `tareas-cierre-responsable_${from}_${to}`, rows: data.byAssignee, columns: CLOSE_COLUMNS('Responsable') }}>
            <BarList format={fmtHours} items={data.byAssignee.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.hours, hint: `${d.count} cerradas · ${fmtPct(d.onTime)} a tiempo`,
              to: link('/tasks', { tab: 'all', done: '1', dept, assignee: d.id }),
            }))} />
          </ReportSection>
        </div>
      )}
    </ReportState>
  )
}
