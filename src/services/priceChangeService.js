// TODO: Replace with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

import { MOCK_PRICE_CHANGES } from '../data/mockData'

export const getPriceChanges = async (branchId) => {
  // TODO: return supabase.from('price_changes').select('*, products(*), shelf_tags(status)').eq('branch_id', branchId)
  return { data: MOCK_PRICE_CHANGES, error: null }
}

export const updateTagStatus = async (tagId, status, evidence) => {
  // TODO: return supabase.from('shelf_tags').update({ status, evidence_url: evidence }).eq('id', tagId)
  console.log('updateTagStatus mock:', { tagId, status, evidence })
  return { data: null, error: null }
}
