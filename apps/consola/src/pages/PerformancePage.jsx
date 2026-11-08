/**
 * PerformancePage — Rendimiento de las empresas cliente y sus sucursales
 * (solo agregados, migraciones 0025 y 0027). Clic en una empresa → sus sucursales.
 */
import PerformanceView from '@operalia/compartido/rendimiento/PerformanceView.jsx'
import { getChecklistHeatmap, getPlatformKpis, getPlatformTrend } from '../services/platformService'

const SOURCE = {
  subtitle: 'Cómo van las empresas cliente y sus sucursales (solo agregados)',
  csvName: 'rendimiento-plataforma',
  kpis: getPlatformKpis,
  trend: ({ sel, ...a }) => getPlatformTrend({ companyId: sel, ...a }),
  heat: ({ sel, ...a }) => getChecklistHeatmap({ companyId: sel, ...a }),
}

export default function PerformancePage() {
  return <PerformanceView scope="platform" source={SOURCE} />
}
