import { DollarSign, FileWarning, Tags, Timer, Truck } from 'lucide-react'
import { getReceivingReport } from '../../../services/reportService'
import StatCard from '../../../components/ui/StatCard'
import BarList from '../../../components/charts/BarList'
import Donut from '../../../components/charts/Donut'
import { complianceTone, fmtPct, useReport, useReportLink } from '../reportFilters'
import { ReportSection, ReportState } from '../reportUi'

export default function ReceivingTab({ filters }) {
  const { data, loading, error, reload } = useReport(getReceivingReport, filters)
  const link = useReportLink()
  const { from, to } = filters
  const hasReceipts = data?.receipts != null
  const hasTags = data?.tagsCreated != null

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload}
      empty={data && !data.receipts && !data.priceChanges && !data.tagsCreated && !data.tagsPending}>
      {data && (<>
        <div className="report-kpis">
          {hasReceipts && <StatCard label="Recibos cerrados" value={data.receipts} icon={Truck} tone="blue" to={link('/receiving', { tab: 'completed' })} />}
          {hasReceipts && <StatCard label="Recibos con diferencias" value={fmtPct(data.receipts ? Math.round((data.receiptsWithDiff / data.receipts) * 100) : null)}
            icon={FileWarning} tone="orange" hint={`${data.receiptsWithDiff} de ${data.receipts}`} to={link('/receiving', { tab: 'completed', diff: '1' })} />}
          {data.priceChanges != null && <StatCard label="Cambios de precio aplicados" value={data.priceChanges} icon={DollarSign} tone="green" to={link('/price-changes', { tab: 'applied' })} />}
          {hasTags && <StatCard label="Cenefas validadas en ≤ 48 h" value={fmtPct(data.tagsOnTimePct)} icon={Timer} tone="purple"
            hint={`${data.tagsOnTime} de ${data.tagsValidated} validadas`} to={link('/shelf-tags', { tab: 'validated' })} />}
          {hasTags && <StatCard label="Cenefas pendientes" value={data.tagsPending} icon={Tags} tone="red" hint="Sin validar hoy" to={link('/shelf-tags', { tab: 'pending' })} />}
        </div>

        <div className="report-grid">
          {hasReceipts && (
            <ReportSection title="Recibos por proveedor" subtitle="Recibos cerrados en el periodo"
              csv={{ name: `recibos-proveedor_${from}_${to}`, rows: data.bySupplier, columns: [
                { key: 'name', label: 'Proveedor' }, { key: 'count', label: 'Recibos' }, { key: 'withDiff', label: 'Con diferencias' }, { key: 'diffPct', label: '% con diferencias' }] }}>
              <BarList items={data.bySupplier.map((s) => ({
                key: s.id, label: s.name, value: s.count, hint: `${s.withDiff} con diferencias (${fmtPct(s.diffPct)})`,
                tone: s.diffPct >= 30 ? 'warn' : 'primary', to: link('/receiving', { tab: 'completed', supplier: s.id }),
              }))} />
            </ReportSection>
          )}
          {hasTags && data.tagsByStore.length > 0 && (
            <ReportSection wide title="Cenefas por tienda" subtitle="Validadas en ≤ 48 h (del periodo) y pendientes hoy · compara a los encargados de escáner"
              csv={{ name: `cenefas-por-tienda_${from}_${to}`, rows: data.tagsByStore, columns: [
                { key: 'name', label: 'Sucursal' }, { key: 'pending', label: 'Pendientes' }, { key: 'validated', label: 'Validadas' },
                { key: 'onTime', label: 'Validadas en ≤ 48 h' }, { key: 'onTimePct', label: '% en ≤ 48 h' }] }}>
              <BarList max={100} format={fmtPct} items={data.tagsByStore.map((st) => ({
                key: st.id, label: st.name, value: st.onTimePct, tone: complianceTone(st.onTimePct),
                hint: `${st.pending} pendientes · ${st.onTime} de ${st.validated} validadas a tiempo`,
                to: link('/shelf-tags', { tab: st.pending ? 'pending' : 'validated' }),
              }))} />
            </ReportSection>
          )}
          {hasTags && (
            <ReportSection title="Validación de cenefas" subtitle="Cenefas generadas en el periodo"
              csv={{ name: `cenefas_${from}_${to}`, rows: [
                { label: 'Validadas en ≤ 48 h', value: data.tagsOnTime }, { label: 'Validadas después de 48 h', value: data.tagsValidated - data.tagsOnTime },
                { label: 'Sin validar', value: data.tagsCreated - data.tagsValidated }],
              columns: [{ key: 'label', label: 'Estado' }, { key: 'value', label: 'Cenefas' }] }}>
              <Donut center={{ value: fmtPct(data.tagsOnTimePct), label: 'en ≤ 48 h' }} segments={[
                { key: 'ontime', label: 'Validadas en ≤ 48 h', value: data.tagsOnTime, tone: 'good', to: link('/shelf-tags', { tab: 'validated' }) },
                { key: 'late', label: 'Validadas después', value: data.tagsValidated - data.tagsOnTime, tone: 'warn', to: link('/shelf-tags', { tab: 'validated' }) },
                { key: 'pending', label: 'Sin validar', value: data.tagsCreated - data.tagsValidated, tone: 'bad', to: link('/shelf-tags', { tab: 'pending' }) },
              ]} />
            </ReportSection>
          )}
        </div>
      </>)}
    </ReportState>
  )
}
