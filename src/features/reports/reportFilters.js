/**
 * Filtros de Estadísticas guardados en la URL (?tab=&zone=&branch=&dept=&p=&from=&to=&cmp=)
 * y utilidades para armar enlaces a las páginas de detalle.
 */
import { useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { NAV_GROUPS, canAccess } from '../../config/navigation'
import { addDaysISO, todayISO } from '../../utils/formatters'

export const PERIODS = [
  { key: 'today', label: 'Hoy', days: 1 },
  { key: '7', label: 'Últimos 7 días', days: 7 },
  { key: '30', label: 'Últimos 30 días', days: 30 },
  { key: '90', label: 'Últimos 90 días', days: 90 },
  { key: 'custom', label: 'Personalizado' },
]

const DAY_MS = 864e5
const isoOk = (v) => /^\d{4}-\d{2}-\d{2}$/.test(v ?? '')

export function useReportFilters() {
  const [params, setParams] = useSearchParams()
  const { isMultiBranch, branchFilter, profile } = useAuth()

  const filters = useMemo(() => {
    const today = todayISO()
    const period = PERIODS.some((p) => p.key === params.get('p')) ? params.get('p') : '30'
    let from
    let to
    if (period === 'custom') {
      to = isoOk(params.get('to')) ? params.get('to') : today
      from = isoOk(params.get('from')) ? params.get('from') : addDaysISO(to, -29)
      if (from > to) [from, to] = [to, from]
    } else {
      to = today
      from = addDaysISO(today, -(PERIODS.find((p) => p.key === period).days - 1))
    }
    const days = Math.round((new Date(`${to}T12:00:00`) - new Date(`${from}T12:00:00`)) / DAY_MS) + 1
    const branchParam = params.get('branch')
    const branchId = isMultiBranch
      ? (branchParam == null ? branchFilter : branchParam === 'all' ? null : branchParam)
      : profile?.branch_id ?? null
    return {
      tab: params.get('tab') ?? 'summary',
      period,
      branchId,
      deptId: params.get('dept') || null,
      zoneId: isMultiBranch ? params.get('zone') || null : null,
      from,
      to,
      prevTo: addDaysISO(from, -1),
      prevFrom: addDaysISO(from, -days),
      compare: params.get('cmp') !== '0',
    }
  }, [params, isMultiBranch, branchFilter, profile?.branch_id])

  const setFilter = useCallback((patch) => {
    setParams((prev) => {
      const next = new URLSearchParams(prev)
      Object.entries(patch).forEach(([k, v]) => (v == null || v === '' ? next.delete(k) : next.set(k, v)))
      return next
    }, { replace: true })
  }, [setParams])

  return { filters, setFilter }
}

/** Ejecuta la función del servicio de la pestaña con los filtros actuales. */
export function useReport(fetcher, filters) {
  const { hasPermission } = useAuth()
  const load = useCallback(() => fetcher({ ...filters, can: hasPermission }), [fetcher, filters, hasPermission])
  return useAsync(load)
}

/** path + query string sin valores vacíos. */
export const withQuery = (path, params = {}) => {
  const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null && v !== '')).toString()
  return qs ? `${path}?${qs}` : path
}

const NAV_ITEMS = NAV_GROUPS.flatMap((g) => g.items)

/** ¿El usuario puede abrir esta ruta? (mismo permiso que el menú lateral). */
export const canOpen = (auth, to) => {
  const path = to.split('?')[0]
  const item = NAV_ITEMS
    .filter((i) => path === i.path || path.startsWith(`${i.path}/`))
    .sort((a, b) => b.path.length - a.path.length)[0]
  return !item || canAccess(item, auth)
}

/** link(path, params) → URL filtrada, o undefined si el usuario no tiene acceso a esa página. */
export function useReportLink() {
  const auth = useAuth()
  return useCallback((path, params) => (canOpen(auth, path) ? withQuery(path, params) : undefined), [auth])
}

export const shortDate = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' })
export const fmtPct = (v) => (v == null ? '—' : `${v}%`)
export const fmtHours = (v) => (v == null ? '—' : `${v} h`)
export const complianceTone = (v) => (v == null ? 'neutral' : v >= 90 ? 'good' : v >= 70 ? 'warn' : 'bad')
