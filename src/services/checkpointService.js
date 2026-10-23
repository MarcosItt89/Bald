/**
 * Puntos de control con QR (0018).
 *
 * Un punto es un lugar o equipo de una sucursal («Área de carritos»,
 * «Cámara de carnes») con un código único impreso en QR. Las plantillas que
 * lo exigen solo se inician escaneando el QR del punto de la misma sucursal.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, saveRow, emptyToNull } from '../lib/queryHelpers'

export const getCheckpoints = ({ branchId, onlyActive = false } = {}) => {
  let q = byBranch(supabase.from('checkpoints')
    .select('*, branch:branches(code, name), department:departments(name)'), branchId).order('name')
  if (onlyActive) q = q.eq('is_active', true)
  return unwrap(q)
}

export const saveCheckpoint = (checkpoint) => {
  const { branch, department, code, created_at, updated_at, ...row } = checkpoint
  return saveRow('checkpoints', emptyToNull(row))
}

/** Valida el código escaneado contra la corrida y la inicia. */
export const startRunWithCheckpoint = (runId, code) =>
  unwrap(supabase.rpc('start_checklist_with_checkpoint', { p_run_id: runId, p_code: code }))
