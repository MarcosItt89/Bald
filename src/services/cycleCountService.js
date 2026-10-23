/**
 * Conteo cíclico (0019): planes, tareas del día y captura a ciegas.
 * La captura usa record_cycle_count, que registra el movimiento 'count' y
 * calcula la diferencia; quien solo cuenta no ve existencia ni diferencias.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, saveRow, emptyToNull } from '../lib/queryHelpers'

export const getCycleTasks = ({ branchId, date }) =>
  unwrap(byBranch(supabase.from('v_cycle_count_tasks').select('*'), branchId)
    .eq('scheduled_date', date).order('plan_name'))

export const getCycleItems = (taskId) =>
  unwrap(supabase.from('v_cycle_count_items').select('*').eq('task_id', taskId).order('position'))

export const recordCycleCount = (itemId, counted) =>
  unwrap(supabase.rpc('record_cycle_count', { p_item_id: itemId, p_counted: Number(counted) }))

export const getCyclePlans = ({ branchId } = {}) =>
  unwrap(byBranch(supabase.from('cycle_count_plans')
    .select('*, branch:branches(name), department:departments(name)'), branchId).order('name'))

export const saveCyclePlan = (plan) => {
  const { branch, department, created_at, updated_at, created_by, ...row } = plan
  return saveRow('cycle_count_plans', emptyToNull({
    ...row,
    items_per_count: Number(row.items_per_count) || 10,
    weekday: row.frequency === 'weekly' ? Number(row.weekday ?? 1) : null,
  }))
}
