// TODO: Replace with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

import { MOCK_CHECKLIST_RUNS } from '../data/mockData'

export const getChecklistRuns = async (branchId, date) => {
  // TODO: return supabase.from('checklist_runs')
  //   .select('*, checklist_assignments(*, checklist_templates(*)), checklist_answers(*)')
  //   .eq('branch_id', branchId)
  //   .eq('scheduled_date', date)
  return { data: MOCK_CHECKLIST_RUNS, error: null }
}

export const startChecklistRun = async (runId, employeeId) => {
  // TODO: return supabase.from('checklist_runs').update({ status: 'in_progress', started_at: new Date(), started_by: employeeId }).eq('id', runId)
  console.log('startChecklistRun mock:', { runId, employeeId })
  return { data: null, error: null }
}

export const saveAnswer = async (runId, questionId, answer, comment, employeeId) => {
  // TODO: return supabase.from('checklist_answers').upsert({ run_id: runId, question_id: questionId, answer, comment, answered_by: employeeId })
  console.log('saveAnswer mock:', { runId, questionId, answer, comment, employeeId })
  return { data: null, error: null }
}

export const completeChecklistRun = async (runId, employeeId) => {
  // TODO: Validate all required questions answered, then:
  // return supabase.from('checklist_runs').update({ status: 'completed', completed_at: new Date(), completed_by: employeeId }).eq('id', runId)
  console.log('completeChecklistRun mock:', { runId, employeeId })
  return { data: null, error: null }
}

export const reviewChecklistRun = async (runId, reviewStatus, comment, reviewerId) => {
  // TODO: return supabase.from('checklist_reviews').insert({ run_id: runId, status: reviewStatus, comment, reviewer_id: reviewerId })
  console.log('reviewChecklistRun mock:', { runId, reviewStatus, comment, reviewerId })
  return { data: null, error: null }
}
