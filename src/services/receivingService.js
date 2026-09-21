// TODO: Replace with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

export const getReceivingOrders = async (branchId) => {
  // TODO: return supabase.from('receiving_orders').select('*, suppliers(*), receiving_items(*, products(*)), employees(name)').eq('branch_id', branchId)
  return { data: [], error: null }
}

export const createReceivingOrder = async (payload) => {
  // TODO: return supabase.from('receiving_orders').insert(payload).select().single()
  console.log('createReceivingOrder mock:', payload)
  return { data: null, error: null }
}
