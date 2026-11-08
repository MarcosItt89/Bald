/** Periodos y formato de los indicadores (Estadísticas y Rendimiento). */
export const PERIODS = [
  { key: 'today', label: 'Hoy', days: 1 },
  { key: '7', label: 'Últimos 7 días', days: 7 },
  { key: '30', label: 'Últimos 30 días', days: 30 },
  { key: '90', label: 'Últimos 90 días', days: 90 },
  { key: 'custom', label: 'Personalizado' },
]

export const shortDate = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' })
export const fmtPct = (v) => (v == null ? '—' : `${v}%`)
export const fmtHours = (v) => (v == null ? '—' : `${v} h`)
export const complianceTone = (v) => (v == null ? 'neutral' : v >= 90 ? 'good' : v >= 70 ? 'warn' : 'bad')
