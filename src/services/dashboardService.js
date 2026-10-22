/**
 * Servicio del Dashboard.
 *
 * Objetivo: cada usuario ve SOLO los indicadores de los módulos a los que
 * tiene permiso (el prototipo mostraba a Caja datos de inventario y pedidos).
 * Los conteos usan HEAD + count para no descargar filas.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, countOf, countQuery } from '../lib/queryHelpers'
import { P } from '../config/permissions'

/**
 * @param {object} args
 * @param {(p:string)=>boolean} args.can   hasPermission del AuthProvider
 * @param {string|null} args.branchId      sucursal filtrada (null = todas)
 * @param {string} args.employeeId
 * @param {string} args.today              YYYY-MM-DD
 */
export async function getDashboardSummary({ can, branchId, employeeId, today }) {
  const tasks = []
  const add = (key, promise) => tasks.push(promise.then((v) => [key, v]).catch(() => [key, null]))

  if (can(P.VIEW_TASKS)) {
    add('myTasks', countOf(countQuery('tasks').eq('assigned_to', employeeId).in('status', ['pending', 'in_progress'])))
  }
  if (can(P.FILL_CHECKLISTS) || can(P.REVIEW_CHECKLISTS)) {
    // Rondas futuras (0016) no cuentan como pendientes hasta que llega su hora.
    add('checklistsPending', countOf(byBranch(countQuery('checklist_runs'), branchId)
      .eq('scheduled_date', today).in('status', ['pending', 'in_progress', 'reopened'])
      .lte('scheduled_start', new Date().toTimeString().slice(0, 8))))
    add('checklistsOverdue', countOf(byBranch(countQuery('checklist_runs'), branchId).eq('status', 'overdue')
      .gte('scheduled_date', today)))
  }
  if (can(P.REVIEW_CHECKLISTS)) {
    add('checklistsToReview', countOf(byBranch(countQuery('checklist_runs'), branchId).eq('review_status', 'pending_review')))
  }
  if (can(P.VIEW_INVENTORY)) {
    add('lowStock', countOf(byBranch(countQuery('inventory'), branchId).in('status', ['low', 'critical', 'out_of_stock'])))
  }
  if (can(P.APPROVE_ORDERS)) {
    add('ordersToApprove', countOf(byBranch(countQuery('orders'), branchId).in('status', ['requested', 'in_review'])))
  } else if (can(P.CREATE_ORDERS)) {
    add('myOpenOrders', countOf(countQuery('orders').eq('requested_by', employeeId)
      .in('status', ['requested', 'in_review', 'approved', 'sent'])))
  }
  if (can(P.MANAGE_SHELF_TAGS) || can(P.VALIDATE_SHELF_TAGS)) {
    add('tagsPending', countOf(byBranch(countQuery('shelf_tags'), branchId).in('status', ['pending', 'printed', 'placed'])))
  }
  if (can(P.MANAGE_EXPIRATIONS)) {
    add('expiringSoon', countOf(byBranch(supabase.from('v_expirations').select('*', { count: 'exact', head: true }), branchId)
      .in('status', ['active', 'markdown']).lte('days_left', 3)))
  }
  if (can(P.RECEIVE_PRODUCTS)) {
    add('receivingOpen', countOf(byBranch(countQuery('receiving_orders'), branchId).eq('status', 'in_progress')))
  }
  if (can(P.REGISTER_SUPPLIER_VISIT)) {
    add('suppliersInside', countOf(byBranch(countQuery('supplier_visits'), branchId).is('check_out_at', null)))
  }
  if (can(P.REVIEW_EVIDENCE)) {
    add('evidencePending', countOf(byBranch(countQuery('evidence_files'), branchId).eq('status', 'pending')))
  }
  if (can(P.MANAGE_TICKETS)) {
    add('ticketsOpen', countOf(countQuery('support_tickets').in('status', ['open', 'in_progress'])))
  } else if (can(P.CREATE_TICKETS)) {
    add('myTickets', countOf(countQuery('support_tickets').eq('created_by', employeeId)
      .in('status', ['open', 'in_progress', 'waiting_user'])))
  }

  return Object.fromEntries(await Promise.all(tasks))
}

/** Checklists de hoy; de las plantillas con rondas solo la ronda vigente (o la siguiente). */
export async function getTodayRuns({ branchId, today }) {
  const rows = await unwrap(byBranch(supabase.from('v_checklist_runs')
    .select('id, template_id, branch_id, title, department_name, scheduled_start, scheduled_end, status, branch_name, round_no, rounds_total'), branchId)
    .eq('scheduled_date', today).order('scheduled_start').limit(200))
  const now = new Date().toTimeString().slice(0, 8)
  const seen = new Set()
  const pick = rows.filter((r) => {
    if ((r.rounds_total ?? 1) <= 1) return true
    const key = `${r.template_id}:${r.branch_id}`
    if (seen.has(key)) return false
    const rounds = rows.filter((x) => x.template_id === r.template_id && x.branch_id === r.branch_id)
    const current = rounds.find((x) => x.status !== 'completed' && x.status !== 'cancelled' && x.scheduled_end >= now) ?? rounds[rounds.length - 1]
    if (current.id !== r.id) return false
    seen.add(key)
    return true
  })
  return pick.slice(0, 8)
}

export const getMyOpenTasks = (employeeId) =>
  unwrap(supabase.from('v_tasks').select('id, title, due_date, priority, status, is_late')
    .eq('assigned_to', employeeId).in('status', ['pending', 'in_progress'])
    .order('due_date', { nullsFirst: false }).limit(8))

export const getCriticalStock = (branchId) =>
  unwrap(byBranch(supabase.from('v_inventory')
    .select('id, product_name, sku, stock, min_stock, unit, status, branch_name'), branchId)
    .in('status', ['critical', 'out_of_stock']).order('stock').limit(8))
