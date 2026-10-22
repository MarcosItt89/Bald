import { useNavigate } from 'react-router-dom'
import { getChecklistReport, pct } from '../../../services/reportService'
import { SHIFTS } from '../../../constants/status'
import Table from '../../../components/ui/Table'
import Donut from '../../../components/charts/Donut'
import BarList from '../../../components/charts/BarList'
import Heatmap from '../../../components/charts/Heatmap'
import { complianceTone, fmtPct, useReport, useReportLink } from '../reportFilters'
import { ReportSection, ReportState } from '../reportUi'
import ManagementBlock from './ManagementBlock'

const WEEKDAYS = [[1, 'Lun'], [2, 'Mar'], [3, 'Mié'], [4, 'Jue'], [5, 'Vie'], [6, 'Sáb'], [0, 'Dom']]
  .map(([key, label]) => ({ key: String(key), label }))

const shiftLabel = (s) => SHIFTS[s] ?? s

export default function ChecklistsTab({ filters }) {
  const { data, loading, error, reload } = useReport(getChecklistReport, filters)
  const link = useReportLink()
  const navigate = useNavigate()
  const { from, to, deptId: dept } = filters
  const history = (params) => link('/checklists/history', { from, to, dept, status: 'all', ...params })
  const s = data?.status

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload} empty={data && !data.total}>
      {data && (
        <div className="report-grid">
          <ManagementBlock filters={filters} />

          <ReportSection title="Estado de los checklists" subtitle={`${data.total} programados en el periodo`}
            csv={{ name: `checklists-estado_${from}_${to}`, rows: [
              { label: 'Completados', value: s.completed }, { label: 'Vencidos', value: s.overdue },
              { label: 'Cancelados', value: s.cancelled }, { label: 'Pendientes', value: s.open }],
            columns: [{ key: 'label', label: 'Estado' }, { key: 'value', label: 'Cantidad' }] }}>
            <Donut center={{ value: fmtPct(pct(s.completed, data.total - s.cancelled)), label: 'completados' }} segments={[
              { key: 'completed', label: 'Completados', value: s.completed, tone: 'good', to: history({ status: 'completed' }) },
              { key: 'overdue', label: 'Vencidos', value: s.overdue, tone: 'bad', to: history({ status: 'overdue' }) },
              { key: 'cancelled', label: 'Cancelados', value: s.cancelled, tone: 'neutral', to: history({ status: 'cancelled' }) },
              { key: 'open', label: 'Pendientes', value: s.open, tone: 'primary', to: history({}) },
            ]} />
          </ReportSection>

          <ReportSection title="Cumplimiento por turno"
            csv={{ name: `checklists-turno_${from}_${to}`, rows: data.byShift,
              columns: [{ label: 'Turno', value: (r) => shiftLabel(r.shift) }, { key: 'completed', label: 'Completados' }, { key: 'total', label: 'Programados' }, { key: 'pct', label: '%' }] }}>
            <BarList max={100} format={fmtPct} items={data.byShift.map((x) => ({
              key: x.shift, label: shiftLabel(x.shift), value: x.pct, hint: `${x.completed} de ${x.total}`,
              tone: complianceTone(x.pct), to: history({ shift: x.shift }),
            }))} />
          </ReportSection>

          <ReportSection title="Cumplimiento por hora del día" subtitle="Según la hora de inicio de cada checklist o ronda"
            csv={{ name: `checklists-hora_${from}_${to}`, rows: data.byHour,
              columns: [{ label: 'Hora', value: (r) => `${r.hour}:00` }, { key: 'completed', label: 'Completados' }, { key: 'total', label: 'Programados' }, { key: 'pct', label: '%' }] }}>
            <BarList max={100} format={fmtPct} items={data.byHour.map((h) => ({
              key: h.hour, label: `${h.hour}:00 – ${h.hour}:59`, value: h.pct, hint: `${h.completed} de ${h.total}`,
              tone: complianceTone(h.pct), to: history({}),
            }))} />
          </ReportSection>

          {data.rounds.templates.length > 0 && (
            <ReportSection wide title="Cumplimiento por ronda" subtitle="Checklists que se repiten en el día · plantilla × hora de la ronda"
              csv={{ name: `checklists-rondas_${from}_${to}`,
                rows: data.rounds.templates.flatMap((t) => Object.entries(t.byTime).map(([time, c]) => ({ title: t.title, time, ...c }))),
                columns: [{ key: 'title', label: 'Checklist' }, { key: 'time', label: 'Ronda' }, { key: 'completed', label: 'Completadas' }, { key: 'total', label: 'Programadas' }, { key: 'pct', label: '%' }] }}>
              <Heatmap cols={data.rounds.times.map((t) => ({ key: t, label: t }))}
                rows={data.rounds.templates.map((t) => ({ key: t.id, label: `${t.title} (${fmtPct(t.pct)})` }))}
                cell={(row, col) => {
                  const c = data.rounds.templates.find((t) => t.id === row)?.byTime[col]
                  return c ? { value: c.pct, title: `Ronda de las ${col}: ${c.completed} de ${c.total} (${fmtPct(c.pct)})`, to: history({ template: row }) } : null
                }} />
            </ReportSection>
          )}

          <ReportSection title="Cumplimiento por departamento"
            csv={{ name: `checklists-departamento_${from}_${to}`, rows: data.byDepartment,
              columns: [{ key: 'name', label: 'Departamento' }, { key: 'completed', label: 'Completados' }, { key: 'total', label: 'Programados' }, { key: 'pct', label: '%' }] }}>
            <BarList max={100} format={fmtPct} items={data.byDepartment.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.pct, hint: `${d.completed} de ${d.total}`,
              tone: complianceTone(d.pct), to: history({ dept: d.id }),
            }))} />
          </ReportSection>

          <ReportSection title="Cumplimiento por día de la semana" subtitle="Departamento × día · más oscuro = mejor cumplimiento">
            <Heatmap cols={WEEKDAYS} rows={data.byDepartment.map((d) => ({ key: d.id ?? '', label: d.name }))}
              cell={(row, col) => {
                const v = data.heat[row]?.[col]
                return v == null ? null : { value: v, to: history({ dept: row || undefined }) }
              }} />
          </ReportSection>

          <ReportSection wide title="Preguntas con más respuestas «No»" subtitle="Top 10 del periodo"
            csv={{ name: `checklists-preguntas-no_${from}_${to}`, rows: data.topNo, columns: [{ key: 'text', label: 'Pregunta' }, { key: 'count', label: 'Respuestas No' }] }}>
            <BarList tone="bad" emptyText="Ninguna respuesta «No» en este periodo" items={data.topNo.map((q) => ({
              key: q.id, label: q.text, value: q.count, to: history({ template: q.templateId }),
            }))} />
          </ReportSection>

          <ReportSection wide title="Checklists que se completan tarde con frecuencia"
            subtitle="Al menos 2 veces y en 30 % o más de sus ejecuciones (vencidos o completados después de la hora límite)"
            csv={{ name: `checklists-tarde_${from}_${to}`, rows: data.lateTemplates, columns: [
              { key: 'title', label: 'Checklist' }, { key: 'department', label: 'Departamento' }, { label: 'Turno', value: (r) => shiftLabel(r.shift) },
              { key: 'late', label: 'Tarde' }, { key: 'total', label: 'Ejecuciones' }, { key: 'pct', label: '% tarde' }] }}>
            <Table data={data.lateTemplates} emptyText="Ningún checklist se completa tarde con frecuencia"
              onRowClick={(r) => { const target = history({ template: r.id }); if (target) navigate(target) }}
              columns={[
                { key: 'title', label: 'Checklist', bold: true, render: (v, r) => <>{v}<div className="cell-sub">{r.department} · {shiftLabel(r.shift)}</div></> },
                { key: 'late', label: 'Tarde', align: 'right', render: (v, r) => `${v} de ${r.total}` },
                { key: 'pct', label: '% tarde', align: 'right', sortable: true, render: fmtPct },
              ]} />
          </ReportSection>
        </div>
      )}
    </ReportState>
  )
}
