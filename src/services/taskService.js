/**
 * Servicio de tareas operativas.
 *
 * - Quien tiene manage_tasks crea, asigna, edita y cancela.
 * - El asignado solo puede cambiar el estado (lo valida tg_task_rules).
 * - Si la tarea requiere evidencia, no se puede completar sin subirla.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, emptyToNull } from '../lib/queryHelpers'

export const getTasks = ({ branchId, status, assignedTo, limit = 300 } = {}) => {
  let q = byBranch(supabase.from('v_tasks').select('*'), branchId)
    .order('due_date', { ascending: true, nullsFirst: false }).limit(limit)
  if (status) q = q.eq('status', status)
  if (assignedTo) q = q.eq('assigned_to', assignedTo)
  return unwrap(q)
}

const VIEW_ONLY = ['department_name', 'branch_name', 'assigned_to_name', 'created_by_name', 'evidence_count', 'is_late']

const cleanTask = (task) => {
  const row = { ...task }
  VIEW_ONLY.forEach((k) => delete row[k])
  return emptyToNull(row)
}

export const createTask = (task) =>
  unwrap(supabase.from('tasks').insert(cleanTask(task)).select().single())

export const updateTask = (id, task) =>
  unwrap(supabase.from('tasks').update(cleanTask(task)).eq('id', id).select().single())

export const setTaskStatus = (id, status, completionNotes) =>
  unwrap(supabase.from('tasks')
    .update({ status, ...(completionNotes !== undefined ? { completion_notes: completionNotes || null } : {}) })
    .eq('id', id).select().single())

export const deleteTask = (id) => unwrap(supabase.from('tasks').delete().eq('id', id))
