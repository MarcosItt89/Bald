import { CalendarClock, PackageX, Trash2, TriangleAlert } from 'lucide-react'
import { getInventoryReport } from '../../../services/reportService'
import { MOVEMENT_TYPES, WASTE_REASONS } from '../../../constants/status'
import { formatCurrency, formatNumber } from '../../../utils/formatters'
import StatCard from '../../../components/ui/StatCard'
import BarList from '../../../components/charts/BarList'
import LineChart from '../../../components/charts/LineChart'
import Donut from '../../../components/charts/Donut'
import { shortDate, useReport, useReportLink } from '../reportFilters'
import { Delta, ReportSection, ReportState } from '../reportUi'

// El color sigue al motivo (orden fijo), no a su posición en el ranking.
const REASON_SLOT = { expired: 's1', damaged: 's2', theft: 's3', mishandling: 's4', temperature: 's5', other: 's6' }
const money = (v) => formatCurrency(v)

export default function InventoryTab({ filters }) {
  const { data, loading, error, reload } = useReport(getInventoryReport, filters)
  const link = useReportLink()
  const { from, to, deptId: dept } = filters
  const waste = link('/inventory/movements', { type: 'waste', from, to })

  return (
    <ReportState data={data} loading={loading} error={error} reload={reload}
      empty={data && !data.lowStock && !data.byType.length && !data.expirationsTotal && !data.wasteCount}>
      {data && (<>
        <div className="report-kpis">
          <StatCard label="Bajo mínimo" value={data.lowStock} icon={TriangleAlert} tone="orange" hint="Existencia actual" to={link('/inventory', { status: 'alerts', dept })} />
          <StatCard label="Agotados" value={data.outOfStock} icon={PackageX} tone="red" hint="Existencia actual" to={link('/inventory', { status: 'out_of_stock', dept })} />
          <StatCard label="Merma (cantidad)" value={formatNumber(data.wasteQty.cur, 2)} icon={Trash2} tone="slate"
            hint={<Delta d={data.wasteQty} better="down" />} to={waste} />
          <StatCard label="Merma (a costo)" value={formatCurrency(data.wasteCost.cur)} icon={Trash2} tone="red"
            hint={data.wasteCost.prev != null ? <Delta d={data.wasteCost} better="down" format={money} /> : `${data.wasteCount} registros`} to={waste} />
          <StatCard label="Caducidades en el periodo" value={data.expirationsTotal} icon={CalendarClock} tone="purple" to={link('/expirations', { tab: 'open' })} />
        </div>

        <div className="report-grid">
          <ReportSection title="Merma por motivo" subtitle={`${formatCurrency(data.wasteCost.cur)} en el periodo${data.wasteCost.prev != null ? ` · anterior ${formatCurrency(data.wasteCost.prev)}` : ''}`}
            csv={{ name: `merma-motivo_${from}_${to}`, rows: data.wasteByReason, columns: [
              { label: 'Motivo', value: (r) => WASTE_REASONS[r.reason]?.label ?? r.reason }, { key: 'count', label: 'Registros' },
              { key: 'cost', label: 'Costo' }, { key: 'prevCost', label: 'Costo periodo anterior' }] }}>
            <Donut format={money} emptyText="Sin mermas en este periodo"
              center={{ value: formatCurrency(data.wasteCost.cur), label: 'merma' }}
              segments={data.wasteByReason.map((r) => ({
                key: r.reason, label: WASTE_REASONS[r.reason]?.label ?? r.reason, value: r.cost, tone: REASON_SLOT[r.reason] ?? 's6',
                hint: r.prevCost != null ? `anterior ${formatCurrency(r.prevCost)}` : undefined,
                to: link('/inventory/movements', { type: 'waste', from, to }),
              }))} />
          </ReportSection>

          <ReportSection title="Merma por departamento"
            csv={{ name: `merma-departamento_${from}_${to}`, rows: data.wasteByDept, columns: [{ key: 'name', label: 'Departamento' }, { key: 'count', label: 'Registros' }, { key: 'cost', label: 'Costo' }] }}>
            <BarList tone="bad" format={money} emptyText="Sin mermas en este periodo" items={data.wasteByDept.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.cost, hint: `${d.count} registros`, to: waste,
            }))} />
          </ReportSection>

          <ReportSection wide title="Top 10 productos con más merma (en pesos)"
            csv={{ name: `merma-productos_${from}_${to}`, rows: data.wasteTopProducts, columns: [
              { key: 'sku', label: 'SKU' }, { key: 'name', label: 'Producto' }, { key: 'qty', label: 'Cantidad' }, { key: 'cost', label: 'Costo' }] }}>
            <BarList tone="bad" format={money} emptyText="Sin mermas en este periodo" items={data.wasteTopProducts.map((p) => ({
              key: p.id, label: p.name, value: p.cost, hint: `${p.sku} · ${formatNumber(p.qty, 2)} ${p.unit ?? ''}`,
              to: link('/inventory/movements', { type: 'waste', from, to }),
            }))} />
          </ReportSection>

          <ReportSection title="Bajo mínimo y agotados por departamento"
            csv={{ name: 'inventario-bajo-minimo', rows: data.alertsByDept, columns: [{ key: 'name', label: 'Departamento' }, { key: 'total', label: 'Bajo mínimo' }, { key: 'out', label: 'Agotados' }] }}>
            <BarList tone="warn" emptyText="Ningún producto bajo mínimo" items={data.alertsByDept.map((d) => ({
              key: d.id ?? 'none', label: d.name, value: d.total, hint: `${d.out} agotados`,
              to: link('/inventory', { status: 'alerts', dept: d.id }),
            }))} />
          </ReportSection>

          <ReportSection title="Movimientos por tipo"
            csv={{ name: `inventario-movimientos_${from}_${to}`, rows: data.byType, columns: [
              { label: 'Tipo', value: (r) => MOVEMENT_TYPES[r.type]?.label ?? r.type }, { key: 'count', label: 'Movimientos' }, { key: 'quantity', label: 'Cantidad' }] }}>
            <BarList items={data.byType.map((m) => ({
              key: m.type, label: MOVEMENT_TYPES[m.type]?.label ?? m.type, value: m.count, hint: `${formatNumber(m.quantity, 2)} unidades`,
              tone: m.type === 'waste' ? 'bad' : 'primary', to: link('/inventory/movements', { type: m.type, from, to }),
            }))} />
          </ReportSection>

          <ReportSection wide title="Caducidades por semana" subtitle="Lotes con fecha de caducidad dentro del periodo"
            csv={{ name: `caducidades-semana_${from}_${to}`, rows: data.expirationsWeekly, columns: [{ key: 'week', label: 'Semana (lunes)' }, { key: 'count', label: 'Lotes' }, { key: 'quantity', label: 'Cantidad' }] }}>
            <LineChart series={[{ key: 'count', label: 'Lotes', slot: 1 }]}
              data={data.expirationsWeekly.map((w) => ({
                x: w.week, label: shortDate(w.week), values: { count: w.count }, to: link('/expirations', { tab: 'open' }),
              }))} />
          </ReportSection>
        </div>
      </>)}
    </ReportState>
  )
}
