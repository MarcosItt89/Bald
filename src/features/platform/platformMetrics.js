/**
 * Métricas de Plataforma → Rendimiento.
 *
 * RANKING_METRICS leen las filas de platform_company_kpis (migración 0025);
 * TREND_METRICS son las que acepta platform_company_trend. Las definiciones
 * son las de Estadísticas (ver el encabezado de la migración).
 *   better: 'up' (más es mejor) | 'down'
 */
import { formatCurrency } from '../../utils/formatters'
import { complianceTone, fmtHours, fmtPct } from '../reports/reportFilters'

const pctOf = (part, total) => (total ? Math.round((part / total) * 100) : null)
const money = (v) => (v == null ? '—' : formatCurrency(v))
/** Pesos sin centavos, para tarjetas y ejes. */
export const moneyShort = (v) => (v == null ? '—' : `$${Math.round(v).toLocaleString('es-MX')}`)
const count = (v) => (v == null ? '—' : String(v))

export const RANKING_METRICS = [
  { key: 'checklist_on_time_pct', label: 'Checklists a tiempo', better: 'up', format: fmtPct, pct: true,
    hint: (r) => `${r.runs_on_time} de ${r.runs_total}` },
  { key: 'checklist_pct', label: 'Checklists completados', better: 'up', format: fmtPct, pct: true,
    hint: (r) => `${r.runs_completed} de ${r.runs_total}` },
  { key: 'tasks_late', label: 'Tareas vencidas', better: 'down', format: count, hint: () => 'abiertas hoy' },
  { key: 'waste_value', label: 'Merma ($)', better: 'down', format: money, hint: (r) => `${r.waste_count} registros` },
  { key: 'count_accuracy_pct', label: 'Exactitud del conteo cíclico', better: 'up', format: fmtPct, pct: true,
    hint: (r) => `${r.counts_exact} de ${r.counts_total} sin diferencia` },
  { key: 'gaps_open', label: 'Huecos en anaquel abiertos', better: 'down', format: count, hint: () => 'hoy' },
  { key: 'gap_hours', label: 'Atención de huecos', better: 'down', format: fmtHours, hint: (r) => `${r.gaps_resolved} resueltos` },
  { key: 'tickets_open', label: 'Tickets abiertos', better: 'down', format: count, hint: (r) => `${r.tickets_overdue} vencidos` },
  { key: 'sla_pct', label: 'Tickets dentro de SLA', better: 'up', format: fmtPct, pct: true, hint: (r) => `${r.sla_met} de ${r.sla_total}` },
  { key: 'usage_pct', label: 'Usuarios que entraron (7 días)', better: 'up', format: fmtPct, pct: true,
    hint: (r) => `${r.users_7d} de ${r.employees_active} empleados` },
]

export const TREND_METRICS = [
  { key: 'checklist_on_time_pct', label: 'Checklists a tiempo', format: fmtPct, yMax: 100 },
  { key: 'checklist_pct', label: 'Checklists completados', format: fmtPct, yMax: 100 },
  { key: 'tasks_on_time_pct', label: 'Tareas cerradas a tiempo', format: fmtPct, yMax: 100 },
  { key: 'waste_value', label: 'Merma ($)', format: moneyShort },
  { key: 'waste_count', label: 'Registros de merma', format: count },
  { key: 'count_accuracy_pct', label: 'Exactitud del conteo cíclico', format: fmtPct, yMax: 100 },
  { key: 'gaps_reported', label: 'Huecos reportados', format: count },
  { key: 'gap_hours', label: 'Horas de atención de huecos', format: fmtHours },
  { key: 'tickets_created', label: 'Tickets creados', format: count },
]

/** Valor de una métrica en una fila de platform_company_kpis (usage_pct se calcula aquí). */
export const metricValue = (row, key) => {
  if (key === 'usage_pct') return pctOf(row.users_7d, row.employees_active)
  const v = row[key]
  return v == null ? null : Number(v)
}

/** Color de la barra: semáforo para porcentajes «más es mejor»; neutro para conteos. */
export const metricTone = (metric, value) => (metric.pct && metric.better === 'up' ? complianceTone(value) : 'primary')

/** Suma las filas de empresa para la plataforma completa (porcentajes = Σ numerador ÷ Σ denominador). */
export function platformTotals(companyRows) {
  const sum = (k) => companyRows.reduce((s, r) => s + Number(r[k] ?? 0), 0)
  const resolved = sum('gaps_resolved')
  return {
    companies: companyRows.length,
    activeCompanies: companyRows.filter((r) => r.company_status === 'active').length,
    employees: sum('employees_active'),
    users7d: sum('users_7d'),
    usagePct: pctOf(sum('users_7d'), sum('employees_active')),
    onTimePct: pctOf(sum('runs_on_time'), sum('runs_total')),
    checklistPct: pctOf(sum('runs_completed'), sum('runs_total')),
    tasksLate: sum('tasks_late'),
    wasteValue: Math.round(sum('waste_value') * 100) / 100,
    wasteCount: sum('waste_count'),
    accuracyPct: pctOf(sum('counts_exact'), sum('counts_total')),
    gapsOpen: sum('gaps_open'),
    gapHours: resolved
      ? Math.round((companyRows.reduce((s, r) => s + Number(r.gap_hours ?? 0) * Number(r.gaps_resolved ?? 0), 0) / resolved) * 10) / 10
      : null,
    ticketsOpen: sum('tickets_open'),
    slaPct: pctOf(sum('sla_met'), sum('sla_total')),
  }
}
