// TODO: Replace with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

import { MOCK_USERS, ROLES } from '../data/mockData'

export const getEmployees = async (branchId) => {
  // TODO: return supabase.from('employees').select('*, roles(label, permissions(name))').eq('branch_id', branchId)
  return { data: MOCK_USERS, error: null }
}

export const getEmployeePermissions = async (employeeId) => {
  // TODO: return supabase.from('employee_permissions').select('permission').eq('employee_id', employeeId)
  const user = MOCK_USERS.find(u => u.id === employeeId)
  if (!user) return { data: [], error: null }
  return { data: ROLES[user.role]?.permissions ?? [], error: null }
}
