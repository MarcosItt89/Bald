/**
 * Servicio de reportes operativos (Objetivos §7.8 y §19 "Indicadores de éxito").
 *
 * Descarga columnas mínimas del período y calcula los indicadores en el
 * navegador. Para volúmenes grandes conviene moverlo a vistas o funciones
 * SQL agregadas (ver docs/guias/pendientes-y-mejoras.md).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, dayStart, dayEnd } from '../lib/queryHelpers'

const pct = (part, total) => (total ? Math.round((part / total) * 100) : null)

const groupCount = (rows, key) =>
  rows.reduce((acc, r) => { const k = r[key] ?? 'Sin dato'; acc[k] = (acc[k] ?? 0) + 1; return acc }, {})

export async function getOperationalReport({ branchId, from, to }) {
  // Columnas *_at son timestamptz (se convierten a UTC); scheduled_date es DATE.
  const range = (q, col) => (col.endsWith('_at')
    ? q.gte(col, dayStart(from)).lte(col, dayEnd(to))
    : q.gte(col, from).lte(col, to))

  const [runs, tasks, evidence, inventory, orders, receipts, tags, tickets] = await Promise.all([
    unwrap(range(byBranch(supabase.from('v_checklist_runs')
      .select('status, review_status, department_name, scheduled_date'), branchId), 'scheduled_date')),
    unwrap(range(byBranch(supabase.from('v_tasks')
      .select('status, is_late, department_name, created_at, completed_at, due_date'), branchId), 'created_at')),
    unwrap(range(byBranch(supabase.from('evidence_files').select('status, entity_type'), branchId), 'created_at')),
    unwrap(byBranch(supabase.from('inventory').select('status'), branchId)),
    unwrap(range(byBranch(supabase.from('orders').select('status'), branchId), 'created_at')),
    unwrap(range(byBranch(supabase.from('v_receiving_orders')
      .select('status, has_differences, supplier_name, total_received'), branchId), 'created_at')),
    unwrap(range(byBranch(supabase.from('shelf_tags').select('status, created_at, validated_at'), branchId), 'created_at')),
    unwrap(range(supabase.from('support_tickets').select('status, created_at, first_response_at, category'), 'created_at')),
  ])

  // Checklists: cumplimiento por departamento
  const byDept = {}
  runs.filter((r) => r.status !== 'cancelled').forEach((r) => {
    const d = (byDept[r.department_name ?? 'General'] ??= { total: 0, completed: 0, overdue: 0 })
    d.total += 1
    if (r.status === 'completed') d.completed += 1
    if (r.status === 'overdue') d.overdue += 1
  })
  const checklistByDept = Object.entries(byDept)
    .map(([department, v]) => ({ department, ...v, compliance: pct(v.completed, v.total) }))
    .sort((a, b) => (a.compliance ?? 0) - (b.compliance ?? 0))

  const completedRuns = runs.filter((r) => r.status === 'completed').length
  const validRuns = runs.filter((r) => r.status !== 'cancelled').length

  // Tareas
  const doneTasks = tasks.filter((t) => t.status === 'completed')
  const avgCloseHours = doneTasks.length
    ? Math.round(doneTasks.reduce((s, t) => s + (new Date(t.completed_at) - new Date(t.created_at)), 0)
        / doneTasks.length / 36e5 * 10) / 10
    : null

  // Cenefas validadas en ≤ 48 h
  const validated = tags.filter((t) => t.status === 'validated' && t.validated_at)
  const onTime = validated.filter((t) => new Date(t.validated_at) - new Date(t.created_at) <= 48 * 36e5).length

  // Soporte: tiempo a primera respuesta
  const answered = tickets.filter((t) => t.first_response_at)
  const avgFirstResponseH = answered.length
    ? Math.round(answered.reduce((s, t) => s + (new Date(t.first_response_at) - new Date(t.created_at)), 0)
        / answered.length / 36e5 * 10) / 10
    : null

  const completedReceipts = receipts.filter((r) => r.status === 'completed')

  return {
    kpis: {
      checklistCompliance: pct(completedRuns, validRuns),
      checklistsTotal: validRuns,
      tasksCompleted: doneTasks.length,
      tasksTotal: tasks.filter((t) => t.status !== 'cancelled').length,
      tasksLate: tasks.filter((t) => t.is_late).length,
      avgTaskCloseHours: avgCloseHours,
      evidenceApproved: evidence.filter((e) => e.status === 'approved').length,
      evidenceRejected: evidence.filter((e) => ['rejected', 'correction_required'].includes(e.status)).length,
      evidencePending: evidence.filter((e) => e.status === 'pending').length,
      lowStock: inventory.filter((i) => ['low', 'critical', 'out_of_stock'].includes(i.status)).length,
      inventoryTotal: inventory.length,
      receiptsCompleted: completedReceipts.length,
      receiptsClean: pct(completedReceipts.filter((r) => !r.has_differences).length, completedReceipts.length),
      tagsValidatedOnTime: pct(onTime, validated.length),
      tagsPending: tags.filter((t) => ['pending', 'printed', 'placed'].includes(t.status)).length,
      ticketsOpen: tickets.filter((t) => !['resolved', 'closed'].includes(t.status)).length,
      avgFirstResponseH,
    },
    checklistByDept,
    ordersByStatus: groupCount(orders, 'status'),
    receiptsBySupplier: groupCount(completedReceipts, 'supplier_name'),
    ticketsByCategory: groupCount(tickets, 'category'),
  }
}

export const getAuditLogs = ({ table, limit = 200 } = {}) => {
  let q = supabase.from('v_audit_logs').select('*').order('performed_at', { ascending: false }).limit(limit)
  if (table) q = q.eq('table_name', table)
  return unwrap(q)
}
