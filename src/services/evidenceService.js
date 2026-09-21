// TODO: Replace with real Supabase queries + Supabase Storage
// import { supabase } from '../lib/supabaseClient'

export const uploadEvidence = async (file, path) => {
  // TODO: const { data } = await supabase.storage.from('evidence').upload(path, file)
  // TODO: return supabase.from('evidence_files').insert({ url: data.path, ... })
  console.log('uploadEvidence mock:', { file, path })
  return { data: null, error: null }
}

export const getEvidence = async (filter) => {
  // TODO: return supabase.from('evidence_files').select('*, employees(name)').match(filter)
  return { data: [], error: null }
}
