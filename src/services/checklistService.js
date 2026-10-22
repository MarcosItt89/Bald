/**
 * Servicio de checklists / bitácoras.
 *
 * Modelo:
 *   checklist_templates → checklist_questions   (el formulario)
 *   checklist_runs      → checklist_answers     (la ejecución de un día)
 *
 * Reglas que valida la BD (tg_checklist_run_rules):
 *   - completar exige todas las preguntas obligatorias y las fotos requeridas
 *   - un vencido solo se reabre con permiso review_checklists
 *   - quien completó no puede revisarse a sí mismo
 *   - "corrección requerida" reabre el checklist
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch } from '../lib/queryHelpers'

export const getRuns = ({ branchId, date, from, to, status, departmentId } = {}) => {
  let q = byBranch(supabase.from('v_checklist_runs').select('*'), branchId)
    .order('scheduled_date', { ascending: false }).order('scheduled_start')
  if (date) q = q.eq('scheduled_date', date)
  if (from) q = q.gte('scheduled_date', from)
  if (to) q = q.lte('scheduled_date', to)
  if (status) q = q.eq('status', status)
  if (departmentId) q = q.eq('department_id', departmentId)
  return unwrap(q)
}

/** Ejecución + preguntas + respuestas + evidencias de cada respuesta. */
export async function getRunDetail(runId) {
  const run = await unwrap(supabase.from('v_checklist_runs').select('*').eq('id', runId).single())
  const [questions, answers] = await Promise.all([
    unwrap(supabase.from('checklist_questions').select('*').eq('template_id', run.template_id).order('position')),
    unwrap(supabase.from('checklist_answers').select('*').eq('run_id', runId)),
  ])
  // Preguntas desactivadas solo se muestran si esta ejecución ya las respondió.
  const answered = new Set(answers.map((a) => a.question_id))
  const visibleQuestions = questions.filter((q) => q.is_active || answered.has(q.id))
  // Evidencias: las de cada respuesta + las generales del checklist ('checklist_run').
  const answerIds = answers.map((a) => a.id)
  const [answerEvidence, runEvidence] = await Promise.all([
    answerIds.length
      ? unwrap(supabase.from('v_evidence').select('*').eq('entity_type', 'checklist_answer').in('entity_id', answerIds))
      : [],
    unwrap(supabase.from('v_evidence').select('*').eq('entity_type', 'checklist_run').eq('entity_id', runId)),
  ])
  return { run, questions: visibleQuestions, answers, evidence: answerEvidence, runEvidence }
}

/** Guarda (o reemplaza) la respuesta de una pregunta. */
export const saveAnswer = (runId, questionId, answerValue, comment) =>
  unwrap(supabase.from('checklist_answers')
    .upsert({ run_id: runId, question_id: questionId, answer_value: answerValue, comment: comment || null },
            { onConflict: 'run_id,question_id' })
    .select().single())

export const startRun = (id) => updateRun(id, { status: 'in_progress' })
export const completeRun = (id) => updateRun(id, { status: 'completed' })
export const reopenRun = (id) => updateRun(id, { status: 'reopened' })
export const cancelRun = (id, reason) => updateRun(id, { status: 'cancelled', review_comment: reason })
export const reviewRun = (id, reviewStatus, comment) =>
  updateRun(id, { review_status: reviewStatus, review_comment: comment || null })

function updateRun(id, patch) {
  return unwrap(supabase.from('checklist_runs').update(patch).eq('id', id).select().single())
}

// ─── Plantillas ──────────────────────────────────────────────────────────────
export const getTemplates = () =>
  unwrap(supabase.from('checklist_templates')
    .select('*, department:departments(name, color), questions:checklist_questions(count)')
    .order('start_time'))

export const getTemplateQuestions = (templateId) =>
  unwrap(supabase.from('checklist_questions').select('*')
    .eq('template_id', templateId).eq('is_active', true).order('position'))

/**
 * Guarda plantilla y preguntas. Las preguntas quitadas en el editor NO se
 * borran: se desactivan (is_active = false) para no perder las respuestas
 * históricas. Las demás se insertan o actualizan con su nueva posición.
 */
export async function saveTemplate({ department, questions: _count, ...template }, questions) {
  const { id, ...fields } = template
  const saved = await unwrap((id
    ? supabase.from('checklist_templates').update(fields).eq('id', id)
    : supabase.from('checklist_templates').insert(fields)).select().single())

  const keepIds = questions.filter((q) => q.id).map((q) => q.id)
  let retire = supabase.from('checklist_questions').update({ is_active: false }).eq('template_id', saved.id)
  if (keepIds.length) retire = retire.not('id', 'in', `(${keepIds.join(',')})`)
  await unwrap(retire)

  const rows = questions.map((q, i) => ({
    ...(q.id ? { id: q.id } : {}),
    template_id: saved.id,
    position: i + 1,
    text: q.text,
    answer_type: q.answer_type,
    options: q.answer_type === 'option' ? q.options : null,
    is_required: q.is_required,
    requires_photo: q.answer_type === 'photo' ? true : q.requires_photo,
    is_active: true,
  }))
  const updates = rows.filter((r) => r.id)
  const inserts = rows.filter((r) => !r.id)
  if (updates.length) await unwrap(supabase.from('checklist_questions').upsert(updates))
  if (inserts.length) await unwrap(supabase.from('checklist_questions').insert(inserts))
  return saved
}

export const setTemplateActive = (id, isActive) =>
  unwrap(supabase.from('checklist_templates').update({ is_active: isActive }).eq('id', id))

/** Genera los checklists de hoy, marca vencidos y aplica precios programados. */
export const runDailyMaintenance = () => unwrap(supabase.rpc('run_daily_maintenance'))
