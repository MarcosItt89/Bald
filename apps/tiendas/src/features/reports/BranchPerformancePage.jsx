/**
 * BranchPerformancePage — Análisis → Rendimiento de sucursales (permiso view_reports).
 * El mismo tablero de la Consola (Rendimiento), limitado a las sucursales de
 * la empresa que quien consulta puede ver (migración 0027).
 */
import PerformanceView from '@operalia/compartido/rendimiento/PerformanceView.jsx'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { getBranchHeatmap, getBranchKpis, getBranchTrend } from '../../services/reportService'

const SOURCE = {
  subtitle: 'Cómo van las sucursales de tu empresa que te tocan',
  csvName: 'rendimiento-sucursales',
  kpis: getBranchKpis,
  trend: ({ sel, ...a }) => getBranchTrend({ branchId: sel, ...a }),
  heat: getBranchHeatmap,
}

export default function BranchPerformancePage() {
  const { profile } = useAuth()
  return <PerformanceView scope="company" source={SOURCE} companyName={profile?.company_name ?? ''} />
}
