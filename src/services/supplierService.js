// TODO: Replace with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

import { MOCK_SUPPLIERS } from '../data/mockData'

export const getSuppliers = async (companyId) => {
  // TODO: return supabase.from('suppliers').select('*').eq('company_id', companyId)
  return { data: MOCK_SUPPLIERS, error: null }
}

export const registerSupplierVisit = async (supplierId, branchId, type, employeeId) => {
  // TODO: return supabase.from('supplier_visits').insert({ supplier_id: supplierId, branch_id: branchId, type, registered_by: employeeId })
  console.log('registerSupplierVisit mock:', { supplierId, branchId, type, employeeId })
  return { data: null, error: null }
}
