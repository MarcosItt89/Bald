/**
 * BranchPerformancePage — Análisis → Rendimiento de sucursales (permiso view_reports).
 * El mismo tablero de Plataforma → Rendimiento, limitado a las sucursales de
 * la empresa que quien consulta puede ver (migración 0027).
 */
import PerformancePage from '../platform/PerformancePage'

export default function BranchPerformancePage() {
  return <PerformancePage scope="company" />
}
