import { Camera, ClipboardCheck, Clock, ListTodo, Package, Truck } from 'lucide-react'
import { getSummaryReport } from '../../../services/reportService'
import { TASK_AGE_BUCKETS } from '../../../constants/status'
import StatCard from '../../../components/ui/StatCard'
import LineChart from '../../../components/charts/LineChart'
import BarList from '../../../components/charts/BarList'
import { complianceTone, fmtHours, fmtPct, shortDate, useReport, useReportLink } from '../reportFilters'
import { Delta, ReportSection, ReportState } from '../reportUi'

const AGE_TONE = { lt1: 'primary', '1-3': 'primary', '4-7': 'warn', gt7: 'bad' }

export default function SummaryTab({ filters }) {
  const { data, loading, error, reload } = useReport(getSummaryReport, filters)
  const link = useReportLink()
  const { from, to, deptId: dept } = filters
  const k = data?.kpis ?? {}

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload} empty={data && !Object.keys(k).length}>
      <div className="report-kpis">
        {k.checklists && <StatCard label="Checklists completados" value={fmtPct(k.checklists.cur)} icon={ClipboardCheck} tone="blue"
          hint={<Delta d={k.checklists} unit=" pts" />} to={link('/checklists/history', { status: 'completed', from, to, dept })} />}
        {k.tasksOnTime && <StatCard label="Tareas cerradas a tiempo" value={fmtPct(k.tasksOnTime.cur)} icon={ListTodo} tone="green"
          hint={<Delta d={k.tasksOnTime} unit=" pts" />} to={link('/tasks', { tab: 'all', done: '1', dept })} />}
        {k.taskHours && <StatCard label="Cierre promedio de tarea" value={fmtHours(k.taskHours.cur)} icon={Clock} tone="purple"
          hint={<Delta d={k.taskHours} better="down" unit=" h" />} to={link('/tasks', { tab: 'all', done: '1', dept })} />}
        {k.evidenceRejected && <StatCard label="Evidencias rechazadas" value={fmtPct(k.evidenceRejected.cur)} icon={Camera} tone="orange"
          hint={<Delta d={k.evidenceRejected} better="down" unit=" pts" />} to={link('/evidence', { tab: 'rejected', from, to })} />}
        {k.lowStock && <StatCard label="Productos bajo mínimo" value={k.lowStock.cur} icon={Package} tone="red"
          hint="Existencia actual" to={link('/inventory', { status: 'alerts', dept })} />}
        {k.receiptsClean && <StatCard label="Recibos sin diferencia" value={fmtPct(k.receiptsClean.cur)} icon={Truck} tone="slate"
          hint={<Delta d={k.receiptsClean} unit=" pts" />} to={link('/receiving', { tab: 'completed', diff: '0' })} />}
      </div>

      <div className="report-grid">
        {data?.dailyChecklists && (
          <ReportSection wide title="Cumplimiento diario de checklists" subtitle="% completados de los programados cada día"
            csv={{ name: `checklists-diario_${from}_${to}`, rows: data.dailyChecklists, columns: [{ key: 'day', label: 'Fecha' }, { key: 'pct', label: '% completados' }] }}>
            <LineChart yMax={100} format={(v) => `${v}%`} series={[{ key: 'pct', label: 'Cumplimiento', slot: 1 }]}
              data={data.dailyChecklists.map((d) => ({
                x: d.day, label: shortDate(d.day), values: { pct: d.pct },
                to: link('/checklists/history', { from: d.day, to: d.day, status: 'all', dept }),
              }))} />
          </ReportSection>
        )}
        {data?.checklistsByDept && (
          <ReportSection title="Cumplimiento por departamento"
            csv={{ name: `checklists-departamento_${from}_${to}`, rows: data.checklistsByDept, columns: [
              { key: 'name', label: 'Departamento' }, { key: 'completed', label: 'Completados' }, { key: 'total', label: 'Programados' }, { key: 'pct', label: '%' }] }}>
            <BarList max={100} format={fmtPct} items={data.checklistsByDept.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.pct, hint: `${d.completed} de ${d.total}`, tone: complianceTone(d.pct),
              to: link('/checklists/history', { dept: d.id, from, to, status: 'all' }),
            }))} />
          </ReportSection>
        )}
        {data?.openTasksByAge && (
          <ReportSection title="Tareas abiertas por antigüedad" subtitle="Pendientes y en progreso hoy"
            csv={{ name: 'tareas-antiguedad', rows: TASK_AGE_BUCKETS.map((b) => ({ label: b.label, count: data.openTasksByAge[b.key]?.length ?? 0 })),
              columns: [{ key: 'label', label: 'Antigüedad' }, { key: 'count', label: 'Tareas' }] }}>
            <BarList items={TASK_AGE_BUCKETS.map((b) => ({
              key: b.key, label: b.label, value: data.openTasksByAge[b.key]?.length ?? 0, tone: AGE_TONE[b.key],
              to: link('/tasks', { tab: 'all', age: b.key, dept }),
            }))} />
          </ReportSection>
        )}
      </div>
    </ReportState>
  )
}
