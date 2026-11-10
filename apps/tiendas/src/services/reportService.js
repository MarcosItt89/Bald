/**
 * Servicio de Estadísticas (/reports) — una función por pestaña.
 *
 * Los cálculos los hace la base (migración 0033, funciones report_*): sin el
 * tope de 1000 filas por consulta y con el RLS de quien consulta. Cada función
 * devuelve el mismo JSON que usan las pestañas. Filtros comunes:
 *   { branchId, deptId, from, to, prevFrom, prevTo, compare }
 * branchId: null = todas las sucursales visibles; un id; o un arreglo (zona).
 */
import { supabase, unwrap } from '@operalia/compartido/lib/supabaseClient.js'
import { addDaysISO } from '@operalia/compartido/utils/formatters.js'

// ─── utilidades que usan las pestañas ───────────────────────────────────────
export const pct = (part, total) => (total ? Math.round((part / total) * 100) : null)

/** Lunes de la semana de una fecha YYYY-MM-DD. */
export const weekStart = (iso) => { const d = new Date(`${iso}T12:00:00`); return addDaysISO(iso, -((d.getDay() + 6) % 7)) }

// ─── llamada común ──────────────────────────────────────────────────────────
const branches = (branchId) => (branchId == null ? null : [branchId].flat())
const period = ({ from, to }) => ({ p_from: from, p_to: to })
const comparison = ({ prevFrom, prevTo, compare }) => ({ p_prev_from: prevFrom ?? null, p_prev_to: prevTo ?? null, p_compare: Boolean(compare) })
const report = (fn, args) => unwrap(supabase.rpc(fn, args))

// ─── pestañas ───────────────────────────────────────────────────────────────
export const getSummaryReport = (f) => report('report_summary',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f), ...comparison(f) })

export const getChecklistReport = (f) => report('report_checklists',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f) })

/** Gerencia: calificación de apertura y cierre por sucursal y día. */
export const getManagementChecklistReport = (f) => report('report_management',
  { p_branches: branches(f.branchId), ...period(f) })

export const getTaskReport = (f) => report('report_tasks',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f) })

export const getInventoryReport = (f) => report('report_inventory',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f), ...comparison(f) })

export const getTemperatureReport = (f) => report('report_temperatures',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f) })

export const getReceivingReport = (f) => report('report_receiving',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f) })

export const getSupportReport = (f) => report('report_support',
  { p_branches: branches(f.branchId), p_dept: f.deptId ?? null, ...period(f) })

// ─── RENDIMIENTO DE SUCURSALES (0027) ───────────────────────────────────────
// Mismas métricas que la Consola → Rendimiento, pero solo de las sucursales
// que quien consulta puede ver (company: todas; zone: sus zonas; branch: la suya).

/** Una fila por sucursal y una de total (branch_id null). */
export const getBranchKpis = ({ from, to }) =>
  unwrap(supabase.rpc('branch_kpis', { p_from: from, p_to: to }))

/** Serie diaria [{ day, value, base }]; branchId null = todas mis sucursales. */
export const getBranchTrend = ({ branchId, metric, from, to }) =>
  unwrap(supabase.rpc('branch_trend', { p_branch_id: branchId || null, p_metric: metric, p_from: from, p_to: to }))

/** % de checklists completados por sucursal y día. */
export const getBranchHeatmap = ({ from, to }) =>
  unwrap(supabase.rpc('branch_checklist_heatmap', { p_from: from, p_to: to }))
