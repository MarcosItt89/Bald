/**
 * Funciones puras de formato (moneda, fechas, números, iniciales).
 * Todas en español de México. No dependen de React ni de Supabase.
 */

export const formatCurrency = (amount) =>
  amount == null || amount === ''
    ? '—'
    : new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(Number(amount))

export const formatNumber = (n, decimals = 0) =>
  n == null ? '—' : new Intl.NumberFormat('es-MX', { maximumFractionDigits: decimals }).format(Number(n))

/**
 * Convierte 'YYYY-MM-DD' o un ISO completo a Date.
 * Las fechas "solo día" se interpretan en hora local (evita que 2026-06-12
 * se muestre como 11 de junio por el desfase UTC).
 */
export const parseDate = (value) => {
  if (!value) return null
  if (value instanceof Date) return value
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return new Date(`${value}T00:00:00`)
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? null : d
}

export const formatDate = (value) => {
  const d = parseDate(value)
  return d ? d.toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'
}

export const formatDateTime = (value) => {
  const d = parseDate(value)
  return d
    ? d.toLocaleString('es-MX', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : '—'
}

export const formatTime = (value) => {
  if (!value) return '—'
  if (/^\d{2}:\d{2}/.test(value)) return value.slice(0, 5) // columnas TIME de Postgres
  const d = parseDate(value)
  return d ? d.toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' }) : '—'
}

/** "hace 5 min", "hace 2 h", "ayer"... */
export const formatRelative = (value) => {
  const d = parseDate(value)
  if (!d) return '—'
  const diff = (Date.now() - d.getTime()) / 1000
  if (diff < 60) return 'hace un momento'
  if (diff < 3600) return `hace ${Math.floor(diff / 60)} min`
  if (diff < 86400) return `hace ${Math.floor(diff / 3600)} h`
  if (diff < 172800) return 'ayer'
  return formatDate(d)
}

/** Minutos → "1 h 25 min". */
export const formatDuration = (minutes) => {
  if (minutes == null) return '—'
  const m = Math.round(minutes)
  if (m < 60) return `${m} min`
  return `${Math.floor(m / 60)} h ${m % 60} min`
}

export const getInitials = (name = '') =>
  name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase() || 'U'

/** Fecha local de hoy en formato YYYY-MM-DD (para inputs type=date). */
export const todayISO = () => {
  const d = new Date()
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}

export const addDaysISO = (iso, days) => {
  const d = parseDate(iso) ?? new Date()
  d.setDate(d.getDate() + days)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
}
