/**
 * Servicio de Estadísticas (/reports) — una función por pestaña.
 *
 * Cada pestaña descarga SOLO las columnas que necesita del periodo y calcula
 * los indicadores en el navegador. Filtros comunes:
 *   { branchId, deptId, deptName, from, to, prevFrom, prevTo, compare, can }
 *
 * TODO: mover estos cálculos a funciones SQL (rpc) que devuelvan los agregados.
 * Hoy Supabase limita cada consulta a 1000 filas (max-rows), así que en
 * periodos largos con mucho movimiento los totales pueden quedar cortos.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, countOf, countQuery, dayStart, dayEnd } from '../lib/queryHelpers'
import { addDaysISO } from '../utils/formatters'
import { P } from '../config/permissions'
import { taskAgeBucket } from '../constants/status'

// ─── utilidades de cálculo ──────────────────────────────────────────────────
export const pct = (part, total) => (total ? Math.round((part / total) * 100) : null)
const avg = (nums) => (nums.length ? Math.round((nums.reduce((s, n) => s + n, 0) / nums.length) * 10) / 10 : null)
const hoursBetween = (a, b) => (new Date(b) - new Date(a)) / 36e5
const pad = (n) => String(n).padStart(2, '0')

/** Fecha local YYYY-MM-DD de un timestamptz. */
export const localDay = (ts) => { const d = new Date(ts); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` }

/** Lunes de la semana de una fecha YYYY-MM-DD. */
export const weekStart = (iso) => { const d = new Date(`${iso}T12:00:00`); return addDaysISO(iso, -((d.getDay() + 6) % 7)) }

export const daysBetween = (from, to) => {
  const out = []
  for (let d = from; d <= to && out.length < 400; d = addDaysISO(d, 1)) out.push(d)
  return out
}

export const weeksBetween = (from, to) => {
  const out = []
  for (let w = weekStart(from); w <= to && out.length < 60; w = addDaysISO(w, 7)) out.push(w)
  return out
}

const groupBy = (rows, keyFn) => rows.reduce((acc, r) => { const k = keyFn(r); (acc[k] ??= []).push(r); return acc }, {})

const inRange = (q, col, from, to) => (col.endsWith('_at')
  ? q.gte(col, dayStart(from)).lte(col, dayEnd(to))
  : q.gte(col, from).lte(col, to))

const byDept = (q, deptId, col = 'department_id') => (deptId ? q.eq(col, deptId) : q)

/** Variación entre periodos: { cur, prev, diff } (diff en puntos o unidades). */
const delta = (cur, prev) => ({ cur, prev, diff: cur != null && prev != null ? Math.round((cur - prev) * 10) / 10 : null })

const LOW_STOCK = ['low', 'critical', 'out_of_stock']
const TICKET_ACTIVE = ['open', 'in_progress', 'waiting_user']
const TAG_PENDING = ['pending', 'printed', 'placed']

const runCompliance = (runs) => {
  const valid = runs.filter((r) => r.status !== 'cancelled')
  return { total: valid.length, completed: valid.filter((r) => r.status === 'completed').length, pct: pct(valid.filter((r) => r.status === 'completed').length, valid.length) }
}

const taskOnTime = (t) => !t.due_date || localDay(t.completed_at) <= t.due_date

// ─── RESUMEN ────────────────────────────────────────────────────────────────
export async function getSummaryReport({ can, branchId, deptId, from, to, prevFrom, prevTo, compare }) {
  const start = compare ? prevFrom : from
  const isCur = (day) => day >= from && day <= to
  const isPrev = (day) => compare && day >= prevFrom && day <= prevTo
  const jobs = {}

  if (can(P.FILL_CHECKLISTS) || can(P.REVIEW_CHECKLISTS)) {
    jobs.runs = unwrap(byDept(inRange(byBranch(supabase.from('v_checklist_runs')
      .select('status, scheduled_date, department_id, department_name'), branchId), 'scheduled_date', start, to), deptId))
  }
  if (can(P.VIEW_TASKS) || can(P.MANAGE_TASKS)) {
    jobs.doneTasks = unwrap(byDept(inRange(byBranch(supabase.from('tasks')
      .select('created_at, completed_at, due_date'), branchId), 'completed_at', start, to), deptId).eq('status', 'completed'))
    jobs.openTasks = unwrap(byDept(byBranch(supabase.from('tasks').select('created_at'), branchId), deptId)
      .in('status', ['pending', 'in_progress']))
  }
  if (can(P.REVIEW_EVIDENCE) || can(P.UPLOAD_EVIDENCE)) {
    jobs.evidence = unwrap(inRange(byBranch(supabase.from('evidence_files').select('status, created_at'), branchId), 'created_at', start, to))
  }
  if (can(P.VIEW_INVENTORY)) {
    jobs.lowStock = countOf(byDept(byBranch(countQuery('v_inventory'), branchId), deptId).in('status', LOW_STOCK))
  }
  if (can(P.RECEIVE_PRODUCTS)) {
    jobs.receipts = unwrap(inRange(byBranch(supabase.from('receiving_orders').select('has_differences, completed_at'), branchId), 'completed_at', start, to)
      .eq('status', 'completed'))
  }

  const keys = Object.keys(jobs)
  const values = await Promise.all(keys.map((k) => jobs[k]))
  const d = Object.fromEntries(keys.map((k, i) => [k, values[i]]))
  const out = { kpis: {} }

  if (d.runs) {
    const cur = d.runs.filter((r) => isCur(r.scheduled_date))
    out.kpis.checklists = delta(runCompliance(cur).pct, compare ? runCompliance(d.runs.filter((r) => isPrev(r.scheduled_date))).pct : null)
    const byDay = groupBy(cur, (r) => r.scheduled_date)
    out.dailyChecklists = daysBetween(from, to).map((day) => ({ day, pct: byDay[day] ? runCompliance(byDay[day]).pct : null }))
    out.checklistsByDept = Object.entries(groupBy(cur, (r) => r.department_id ?? ''))
      .map(([id, rows]) => ({ id: id || null, name: rows[0].department_name ?? 'General', ...runCompliance(rows) }))
      .filter((x) => x.total)
      .sort((a, b) => (a.pct ?? 0) - (b.pct ?? 0))
  }
  if (d.doneTasks) {
    const stats = (rows) => ({ onTime: pct(rows.filter(taskOnTime).length, rows.length), hours: avg(rows.map((t) => hoursBetween(t.created_at, t.completed_at))) })
    const cur = stats(d.doneTasks.filter((t) => isCur(localDay(t.completed_at))))
    const prev = compare ? stats(d.doneTasks.filter((t) => isPrev(localDay(t.completed_at)))) : {}
    out.kpis.tasksOnTime = delta(cur.onTime, prev.onTime ?? null)
    out.kpis.taskHours = delta(cur.hours, prev.hours ?? null)
    const buckets = groupBy(d.openTasks, (t) => taskAgeBucket(t.created_at))
    out.openTasksByAge = buckets
  }
  if (d.evidence) {
    const rejected = (rows) => pct(rows.filter((e) => ['rejected', 'correction_required'].includes(e.status)).length, rows.length)
    out.kpis.evidenceRejected = delta(
      rejected(d.evidence.filter((e) => isCur(localDay(e.created_at)))),
      compare ? rejected(d.evidence.filter((e) => isPrev(localDay(e.created_at)))) : null)
  }
  if (d.lowStock != null) out.kpis.lowStock = delta(d.lowStock, null)
  if (d.receipts) {
    const clean = (rows) => pct(rows.filter((r) => !r.has_differences).length, rows.length)
    out.kpis.receiptsClean = delta(
      clean(d.receipts.filter((r) => isCur(localDay(r.completed_at)))),
      compare ? clean(d.receipts.filter((r) => isPrev(localDay(r.completed_at)))) : null)
  }
  return out
}

// ─── CHECKLISTS ─────────────────────────────────────────────────────────────
export async function getChecklistReport({ branchId, deptId, from, to }) {
  let answers = supabase.from('checklist_answers')
    .select('question_id, checklist_questions!inner(text, template_id), checklist_runs!inner(scheduled_date, branch_id, department_id)')
    .eq('answer_value', 'no')
    .gte('checklist_runs.scheduled_date', from).lte('checklist_runs.scheduled_date', to)
  answers = byBranch(answers, branchId, 'checklist_runs.branch_id')
  if (deptId) answers = answers.eq('checklist_runs.department_id', deptId)

  const [runs, noAnswers] = await Promise.all([
    unwrap(byDept(inRange(byBranch(supabase.from('v_checklist_runs')
      .select('template_id, title, shift, status, department_id, department_name, scheduled_date, scheduled_start, scheduled_end, completed_at, rounds_total'), branchId),
    'scheduled_date', from, to), deptId)),
    unwrap(answers).catch(() => []),
  ])

  const status = {
    completed: runs.filter((r) => r.status === 'completed').length,
    overdue: runs.filter((r) => r.status === 'overdue').length,
    cancelled: runs.filter((r) => r.status === 'cancelled').length,
    open: runs.filter((r) => ['pending', 'in_progress', 'reopened'].includes(r.status)).length,
  }

  const valid = runs.filter((r) => r.status !== 'cancelled')
  const byShift = Object.entries(groupBy(valid, (r) => r.shift)).map(([shift, rows]) => ({ shift, ...runCompliance(rows) }))
  const deptGroups = groupBy(valid, (r) => r.department_id ?? '')
  const byDepartment = Object.entries(deptGroups)
    .map(([id, rows]) => ({ id: id || null, name: rows[0].department_name ?? 'General', ...runCompliance(rows) }))
    .sort((a, b) => (a.pct ?? 0) - (b.pct ?? 0))
  const heat = Object.fromEntries(Object.entries(deptGroups).map(([id, rows]) => [id,
    Object.fromEntries(Object.entries(groupBy(rows, (r) => new Date(`${r.scheduled_date}T12:00:00`).getDay()))
      .map(([wd, list]) => [wd, runCompliance(list).pct]))]))

  const topNo = Object.values(groupBy(noAnswers, (a) => a.question_id))
    .map((list) => ({ id: list[0].question_id, text: list[0].checklist_questions.text, templateId: list[0].checklist_questions.template_id, count: list.length }))
    .sort((a, b) => b.count - a.count).slice(0, 10)

  const isLate = (r) => r.status === 'overdue'
    || (r.status === 'completed' && r.completed_at && new Date(r.completed_at) > new Date(`${r.scheduled_date}T${r.scheduled_end}`))
  const lateTemplates = Object.values(groupBy(valid, (r) => r.template_id))
    .map((rows) => {
      const late = rows.filter(isLate).length
      return { id: rows[0].template_id, title: rows[0].title, department: rows[0].department_name ?? 'General', shift: rows[0].shift, total: rows.length, late, pct: pct(late, rows.length) }
    })
    .filter((t) => t.late >= 2 && t.pct >= 30)
    .sort((a, b) => b.pct - a.pct || b.late - a.late)

  // Hora del día (todas las corridas) y rondas de las plantillas que se repiten (0016).
  const byHour = Object.entries(groupBy(valid, (r) => r.scheduled_start.slice(0, 2)))
    .map(([hour, rows]) => ({ hour, ...runCompliance(rows) }))
    .sort((a, b) => a.hour.localeCompare(b.hour))
  const repeated = valid.filter((r) => (r.rounds_total ?? 1) > 1)
  const rounds = {
    times: [...new Set(repeated.map((r) => r.scheduled_start.slice(0, 5)))].sort(),
    templates: Object.values(groupBy(repeated, (r) => r.template_id)).map((rows) => ({
      id: rows[0].template_id, title: rows[0].title, department: rows[0].department_name ?? 'General', ...runCompliance(rows),
      byTime: Object.fromEntries(Object.entries(groupBy(rows, (r) => r.scheduled_start.slice(0, 5))).map(([t, l]) => [t, runCompliance(l)])),
    })),
  }

  return { total: runs.length, status, byShift, byDepartment, heat, topNo, lateTemplates, byHour, rounds }
}

/** Descarga todas las páginas de una consulta (de 1000 en 1000). makeQuery() debe crear la consulta de nuevo cada vez. */
async function fetchAll(makeQuery, pageSize = 1000, maxRows = 20000) {
  const rows = []
  for (let from = 0; from < maxRows; from += pageSize) {
    const page = await unwrap(makeQuery().range(from, from + pageSize - 1))
    rows.push(...page)
    if (page.length < pageSize) break
  }
  return rows
}

/**
 * Gerencia: calificación de apertura y cierre por sucursal y día.
 * Calificación = respuestas «Sí» ÷ preguntas sí/no programadas (sin contar «N/A»).
 * Un checklist sin llenar cuenta sus preguntas como no cumplidas.
 */
export async function getManagementChecklistReport({ branchId, from, to }) {
  const ger = await unwrap(supabase.from('departments').select('id').eq('code', 'GER').maybeSingle())
  if (!ger) return { gerDeptId: null, branches: [], days: [] }

  const [runs, answers] = await Promise.all([
    fetchAll(() => byBranch(supabase.from('v_checklist_runs')
      .select('id, template_id, branch_id, branch_name, scheduled_date, shift, status'), branchId)
      .eq('department_id', ger.id).neq('status', 'cancelled')
      .gte('scheduled_date', from).lte('scheduled_date', to).order('id')),
    fetchAll(() => {
      let q = supabase.from('checklist_answers')
        .select('run_id, answer_value, checklist_questions!inner(answer_type), checklist_runs!inner(scheduled_date, branch_id, department_id)')
        .eq('checklist_questions.answer_type', 'yes_no').in('answer_value', ['yes', 'no', 'na'])
        .eq('checklist_runs.department_id', ger.id)
        .gte('checklist_runs.scheduled_date', from).lte('checklist_runs.scheduled_date', to)
        .order('id')
      q = byBranch(q, branchId, 'checklist_runs.branch_id')
      return q
    }),
  ])
  if (!runs.length) return { gerDeptId: ger.id, branches: [], days: [] }

  const templateIds = [...new Set(runs.map((r) => r.template_id))]
  const questions = await unwrap(supabase.from('checklist_questions').select('template_id')
    .in('template_id', templateIds).eq('answer_type', 'yes_no').eq('is_active', true))
  const perTemplate = groupBy(questions, (q) => q.template_id)
  const byRun = groupBy(answers, (a) => a.run_id)

  // Por ejecución: preguntas válidas (sin N/A) y respuestas «Sí».
  const scored = runs.map((r) => {
    const list = byRun[r.id] ?? []
    const na = list.filter((a) => a.answer_value === 'na').length
    return { ...r, total: Math.max(0, (perTemplate[r.template_id]?.length ?? 0) - na), yes: list.filter((a) => a.answer_value === 'yes').length }
  })
  const score = (list) => pct(list.reduce((n, r) => n + r.yes, 0), list.reduce((n, r) => n + r.total, 0))

  const branches = Object.values(groupBy(scored, (r) => r.branch_id)).map((list) => ({
    id: list[0].branch_id,
    name: list[0].branch_name,
    score: score(list),
    opening: score(list.filter((r) => r.shift === 'apertura')),
    closing: score(list.filter((r) => r.shift === 'cierre')),
    days: Object.fromEntries(Object.entries(groupBy(list, (r) => r.scheduled_date)).map(([day, l]) => [day, {
      score: score(l), opening: score(l.filter((r) => r.shift === 'apertura')), closing: score(l.filter((r) => r.shift === 'cierre')),
    }])),
  })).sort((a, b) => (b.score ?? -1) - (a.score ?? -1))

  return { gerDeptId: ger.id, branches, days: daysBetween(from, to) }
}

// ─── TAREAS ─────────────────────────────────────────────────────────────────
export async function getTaskReport({ branchId, deptId, from, to }) {
  const s = dayStart(from)
  const e = dayEnd(to)
  const [rows, openLate] = await Promise.all([
    unwrap(byDept(byBranch(supabase.from('v_tasks')
      .select('status, created_at, completed_at, due_date, department_id, department_name, assigned_to, assigned_to_name'), branchId), deptId)
      .or(`and(created_at.gte.${s},created_at.lte.${e}),and(completed_at.gte.${s},completed_at.lte.${e})`)),
    countOf(byDept(byBranch(countQuery('v_tasks'), branchId), deptId).eq('is_late', true)),
  ])

  const inPeriod = (ts) => ts && localDay(ts) >= from && localDay(ts) <= to
  const created = rows.filter((t) => inPeriod(t.created_at))
  const done = rows.filter((t) => t.status === 'completed' && inPeriod(t.completed_at))

  const createdW = groupBy(created, (t) => weekStart(localDay(t.created_at)))
  const doneW = groupBy(done, (t) => weekStart(localDay(t.completed_at)))
  const weekly = weeksBetween(from, to).map((w) => ({ week: w, created: createdW[w]?.length ?? 0, closed: doneW[w]?.length ?? 0 }))

  const closeStats = (list, keyFn, nameFn) => Object.values(groupBy(list, keyFn))
    .map((l) => ({ id: keyFn(l[0]) || null, name: nameFn(l[0]), count: l.length, hours: avg(l.map((t) => hoursBetween(t.created_at, t.completed_at))), onTime: pct(l.filter(taskOnTime).length, l.length) }))
    .sort((a, b) => (b.hours ?? 0) - (a.hours ?? 0))

  return {
    createdCount: created.length,
    weekly,
    onTime: done.filter(taskOnTime).length,
    lateClosed: done.filter((t) => !taskOnTime(t)).length,
    openLate,
    byDepartment: closeStats(done, (t) => t.department_id ?? '', (t) => t.department_name ?? 'General'),
    byAssignee: closeStats(done, (t) => t.assigned_to ?? '', (t) => t.assigned_to_name ?? 'Sin asignar'),
  }
}

// ─── INVENTARIO ─────────────────────────────────────────────────────────────
export async function getInventoryReport({ branchId, deptId, deptName, from, to, prevFrom, prevTo, compare }) {
  let moves = inRange(byBranch(supabase.from('inventory_movements')
    .select('movement_type, quantity, products!inner(cost, department_id)'), branchId), 'created_at', from, to)
  if (deptId) moves = moves.eq('products.department_id', deptId)
  let exps = inRange(byBranch(supabase.from('v_expirations').select('expiration_date, quantity, status'), branchId), 'expiration_date', from, to)
  if (deptName) exps = exps.eq('department_name', deptName)

  const wasteStart = compare ? prevFrom : from
  const wasteQuery = () => {
    let q = inRange(byBranch(supabase.from('inventory_movements')
      .select('quantity, unit_cost, waste_reason, created_at, product_id, products!inner(name, sku, unit, cost, department_id, departments(name))'), branchId),
    'created_at', wasteStart, to).eq('movement_type', 'waste').order('id')
    if (deptId) q = q.eq('products.department_id', deptId)
    return q
  }

  const cycleQuery = () => {
    let q = supabase.from('cycle_count_items')
      .select('difference, difference_value, counted_at, products!inner(department_id, departments(name)), cycle_count_tasks!inner(branch_id)')
      .not('counted_at', 'is', null)
      .gte('counted_at', dayStart(wasteStart)).lte('counted_at', dayEnd(to)).order('id')
    q = byBranch(q, branchId, 'cycle_count_tasks.branch_id')
    if (deptId) q = q.eq('products.department_id', deptId)
    return q
  }

  const [alerts, movements, expirations, wasteRows, cycleRows] = await Promise.all([
    unwrap(byDept(byBranch(supabase.from('v_inventory').select('status, department_id, department_name'), branchId), deptId).in('status', LOW_STOCK)),
    unwrap(moves),
    unwrap(exps),
    fetchAll(wasteQuery),
    fetchAll(cycleQuery).catch(() => []),
  ])

  const alertsByDept = Object.values(groupBy(alerts, (a) => a.department_id ?? ''))
    .map((l) => ({ id: l[0].department_id, name: l[0].department_name ?? 'Sin departamento', total: l.length, out: l.filter((a) => a.status === 'out_of_stock').length }))
    .sort((a, b) => b.total - a.total)

  const byType = Object.entries(groupBy(movements, (m) => m.movement_type))
    .map(([type, l]) => ({ type, count: l.length, quantity: l.reduce((s, m) => s + Number(m.quantity), 0) }))
    .sort((a, b) => b.count - a.count)

  const costOf = (m) => Number(m.quantity) * Number(m.unit_cost ?? m.products?.cost ?? 0)
  const sum = (list, fn) => Math.round(list.reduce((t, m) => t + fn(m), 0) * 100) / 100
  const waste = wasteRows.filter((m) => { const d = localDay(m.created_at); return d >= from && d <= to })
  const wastePrev = compare ? wasteRows.filter((m) => { const d = localDay(m.created_at); return d >= prevFrom && d <= prevTo }) : []
  const reasonOf = (m) => m.waste_reason ?? 'other'
  const prevByReason = groupBy(wastePrev, reasonOf)
  const expW = groupBy(expirations, (x) => weekStart(x.expiration_date))

  return {
    lowStock: alerts.length,
    outOfStock: alerts.filter((a) => a.status === 'out_of_stock').length,
    alertsByDept,
    byType,
    wasteCount: waste.length,
    wasteQty: delta(sum(waste, (m) => Number(m.quantity)), compare ? sum(wastePrev, (m) => Number(m.quantity)) : null),
    wasteCost: delta(sum(waste, costOf), compare ? sum(wastePrev, costOf) : null),
    wasteByReason: Object.entries(groupBy(waste, reasonOf))
      .map(([reason, l]) => ({ reason, cost: sum(l, costOf), count: l.length, prevCost: compare ? sum(prevByReason[reason] ?? [], costOf) : null }))
      .sort((a, b) => b.cost - a.cost),
    wasteByDept: Object.values(groupBy(waste, (m) => m.products?.department_id ?? ''))
      .map((l) => ({ id: l[0].products?.department_id ?? null, name: l[0].products?.departments?.name ?? 'Sin departamento', cost: sum(l, costOf), count: l.length }))
      .sort((a, b) => b.cost - a.cost),
    wasteTopProducts: Object.values(groupBy(waste, (m) => m.product_id))
      .map((l) => ({ id: l[0].product_id, name: l[0].products?.name, sku: l[0].products?.sku, unit: l[0].products?.unit, qty: sum(l, (m) => Number(m.quantity)), cost: sum(l, costOf) }))
      .sort((a, b) => b.cost - a.cost).slice(0, 10),
    expirationsWeekly: weeksBetween(from, to).map((w) => ({ week: w, count: expW[w]?.length ?? 0, quantity: (expW[w] ?? []).reduce((s, x) => s + Number(x.quantity), 0) })),
    expirationsTotal: expirations.length,
    // Exactitud = % de productos contados (conteo cíclico) sin diferencia.
    ...(() => {
      const inP = (r, a, b) => { const d = localDay(r.counted_at); return d >= a && d <= b }
      const cur = cycleRows.filter((r) => inP(r, from, to))
      const prev = compare ? cycleRows.filter((r) => inP(r, prevFrom, prevTo)) : []
      const exact = (l) => pct(l.filter((r) => Number(r.difference) === 0).length, l.length)
      return {
        countsTotal: cur.length,
        countAccuracy: delta(exact(cur), compare ? exact(prev) : null),
        countDiffValue: Math.round(cur.reduce((s, r) => s + Number(r.difference_value ?? 0), 0) * 100) / 100,
        accuracyByDept: Object.values(groupBy(cur, (r) => r.products?.department_id ?? ''))
          .map((l) => ({ id: l[0].products?.department_id ?? null, name: l[0].products?.departments?.name ?? 'Sin departamento', total: l.length, exact: l.filter((r) => Number(r.difference) === 0).length, pct: exact(l), value: Math.round(l.reduce((s, r) => s + Number(r.difference_value ?? 0), 0) * 100) / 100 }))
          .sort((a, b) => (a.pct ?? 0) - (b.pct ?? 0)),
      }
    })(),
  }
}

// ─── TEMPERATURAS ───────────────────────────────────────────────────────────
/**
 * Lecturas de preguntas numéricas con equipo (checklist_questions.equipment_name).
 * Los eventos fuera de rango salen de las tareas automáticas: así se conservan
 * aunque la lectura se haya corregido después, y su cierre da el tiempo de corrección.
 */
export async function getTemperatureReport({ branchId, deptId, from, to }) {
  const [readings, events] = await Promise.all([
    fetchAll(() => {
      let q = supabase.from('checklist_answers')
        .select('id, answer_value, out_of_range, checklist_questions!inner(equipment_name, min_value, max_value, unit), checklist_runs!inner(scheduled_date, branch_id, department_id)')
        .not('checklist_questions.equipment_name', 'is', null)
        .gte('checklist_runs.scheduled_date', from).lte('checklist_runs.scheduled_date', to)
        .order('id')
      q = byBranch(q, branchId, 'checklist_runs.branch_id')
      if (deptId) q = q.eq('checklist_runs.department_id', deptId)
      return q
    }),
    unwrap(inRange(byDept(byBranch(supabase.from('v_tasks')
      .select('id, title, status, created_at, completed_at, updated_at, branch_name, department_name'), branchId), deptId), 'created_at', from, to)
      .eq('source_type', 'checklist_answer').ilike('title', '%fuera de rango:%')
      .order('created_at', { ascending: false }).limit(200)),
  ])

  const days = daysBetween(from, to)
  const equipments = Object.values(groupBy(readings, (a) => a.checklist_questions.equipment_name)).map((list) => {
    const q = list[0].checklist_questions
    const byDay = groupBy(list, (a) => a.checklist_runs.scheduled_date)
    return {
      name: q.equipment_name, unit: q.unit ?? '', min: q.min_value == null ? null : Number(q.min_value), max: q.max_value == null ? null : Number(q.max_value),
      count: list.length, out: list.filter((a) => a.out_of_range).length,
      daily: days.map((day) => ({ day, avg: byDay[day] ? avg(byDay[day].map((a) => Number(a.answer_value))) : null })),
    }
  }).sort((a, b) => b.out - a.out || a.name.localeCompare(b.name))

  const fixedAt = (t) => (t.status === 'completed' ? t.completed_at : t.status === 'cancelled' ? t.updated_at : null)
  const list = events.map((t) => ({ ...t, fixedAt: fixedAt(t), hours: fixedAt(t) ? Math.round(hoursBetween(t.created_at, fixedAt(t)) * 10) / 10 : null }))

  return {
    readings: readings.length,
    outOfRange: list.length,
    outPct: pct(readings.filter((a) => a.out_of_range).length, readings.length),
    openEvents: list.filter((e) => !e.fixedAt).length,
    avgFixHours: avg(list.filter((e) => e.hours != null).map((e) => e.hours)),
    equipments,
    events: list,
  }
}

// ─── RECIBO Y PRECIOS ───────────────────────────────────────────────────────
export async function getReceivingReport({ can, branchId, deptId, from, to }) {
  const jobs = {}
  if (can(P.RECEIVE_PRODUCTS) || can(P.VIEW_REPORTS)) {
    jobs.receipts = unwrap(inRange(byBranch(supabase.from('v_receiving_orders')
      .select('supplier_id, supplier_name, has_differences'), branchId), 'completed_at', from, to).eq('status', 'completed'))
  }
  if (can(P.MANAGE_PRICE_CHANGES) || can(P.VIEW_REPORTS)) {
    let q = inRange(supabase.from('price_changes').select('id, products!inner(department_id)', { count: 'exact', head: true }), 'applied_at', from, to)
      .eq('status', 'applied')
    if (branchId) q = q.or(`branch_id.is.null,branch_id.in.(${[branchId].flat().join(',') || '00000000-0000-0000-0000-000000000000'})`)
    if (deptId) q = q.eq('products.department_id', deptId)
    jobs.priceChanges = countOf(q)
  }
  if (can(P.MANAGE_SHELF_TAGS) || can(P.VALIDATE_SHELF_TAGS)) {
    let tags = inRange(byBranch(supabase.from('shelf_tags').select('branch_id, status, created_at, validated_at, branches(name), products!inner(department_id)'), branchId), 'created_at', from, to)
    let pending = byBranch(supabase.from('shelf_tags').select('branch_id, branches(name), products!inner(department_id)'), branchId).in('status', TAG_PENDING)
    if (deptId) { tags = tags.eq('products.department_id', deptId); pending = pending.eq('products.department_id', deptId) }
    jobs.tags = unwrap(tags)
    jobs.tagsPending = unwrap(pending)
  }

  const keys = Object.keys(jobs)
  const values = await Promise.all(keys.map((k) => jobs[k]))
  const d = Object.fromEntries(keys.map((k, i) => [k, values[i]]))
  const out = {}

  if (d.receipts) {
    out.receipts = d.receipts.length
    out.receiptsWithDiff = d.receipts.filter((r) => r.has_differences).length
    out.bySupplier = Object.values(groupBy(d.receipts, (r) => r.supplier_id))
      .map((l) => ({ id: l[0].supplier_id, name: l[0].supplier_name, count: l.length, withDiff: l.filter((r) => r.has_differences).length }))
      .map((x) => ({ ...x, diffPct: pct(x.withDiff, x.count) }))
      .sort((a, b) => b.count - a.count)
  }
  if (d.priceChanges != null) out.priceChanges = d.priceChanges
  if (d.tags) {
    const validated = d.tags.filter((t) => t.status === 'validated' && t.validated_at)
    out.tagsCreated = d.tags.length
    out.tagsValidated = validated.length
    out.tagsOnTime = validated.filter((t) => hoursBetween(t.created_at, t.validated_at) <= 48).length
    out.tagsOnTimePct = pct(out.tagsOnTime, validated.length)
    out.tagsPending = d.tagsPending.length
    // Por tienda: para que el jefe de zona compare a sus encargados de escáner.
    const stores = {}
    const store = (t) => (stores[t.branch_id] ??= { id: t.branch_id, name: t.branches?.name ?? 'Sucursal', pending: 0, validated: 0, onTime: 0 })
    d.tagsPending.forEach((t) => { store(t).pending += 1 })
    validated.forEach((t) => { const s = store(t); s.validated += 1; if (hoursBetween(t.created_at, t.validated_at) <= 48) s.onTime += 1 })
    out.tagsByStore = Object.values(stores).map((s) => ({ ...s, onTimePct: pct(s.onTime, s.validated) }))
      .sort((a, b) => (b.onTimePct ?? -1) - (a.onTimePct ?? -1) || a.pending - b.pending)
  }
  return out
}

// ─── SOPORTE ────────────────────────────────────────────────────────────────
export async function getSupportReport({ branchId, deptId, from, to }) {
  const [tickets, open] = await Promise.all([
    unwrap(byDept(inRange(byBranch(supabase.from('support_tickets')
      .select('status, category, created_at, first_response_at, resolved_at, closed_at, due_at'), branchId), 'created_at', from, to), deptId)),
    countOf(byDept(byBranch(countQuery('support_tickets'), branchId), deptId).in('status', TICKET_ACTIVE)),
  ])

  const now = Date.now()
  const slaOf = (t) => {
    if (!t.due_at) return null
    const end = t.resolved_at ?? t.closed_at
    return end ? new Date(end) <= new Date(t.due_at) : now <= new Date(t.due_at)
  }
  const withSla = tickets.filter((t) => t.due_at)
  const met = withSla.filter((t) => slaOf(t)).length

  return {
    created: tickets.length,
    open,
    overdueNow: tickets.filter((t) => t.due_at && !t.resolved_at && !t.closed_at && now > new Date(t.due_at)).length,
    firstResponseH: avg(tickets.filter((t) => t.first_response_at).map((t) => hoursBetween(t.created_at, t.first_response_at))),
    slaPct: pct(met, withSla.length),
    slaMet: met,
    slaMissed: withSla.length - met,
    byCategory: Object.entries(groupBy(tickets, (t) => t.category))
      .map(([category, l]) => {
        const s = l.filter((t) => t.due_at)
        return { category, count: l.length, open: l.filter((t) => TICKET_ACTIVE.includes(t.status)).length, slaPct: pct(s.filter((t) => slaOf(t)).length, s.length) }
      })
      .sort((a, b) => b.count - a.count),
  }
}

export const getAuditLogs = ({ table, limit = 200 } = {}) => {
  let q = supabase.from('v_audit_logs').select('*').order('performed_at', { ascending: false }).limit(limit)
  if (table) q = q.eq('table_name', table)
  return unwrap(q)
}
