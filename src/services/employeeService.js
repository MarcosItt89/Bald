/**
 * Servicio de empleados y sus cuentas de acceso.
 *
 * Alta de empleado con cuenta (flujo):
 *   1. Se inserta el empleado (sin user_id) → requiere manage_employees.
 *   2. Si trae contraseña, admin_set_password (SQL) crea la cuenta de Auth ya
 *      confirmada (usuario@<empresa>.operalia.local) y la liga al empleado.
 *      No se usa auth.signUp: el registro público queda desactivado en Supabase.
 *
 * Limitación conocida: restablecer la contraseña de OTRO usuario requiere la
 * service key (Edge Function). Ver docs/guias/configurar-supabase.md.
 */
import { supabase, unwrap, friendlyError } from '../lib/supabaseClient'
import { byBranch, ilikeTerm, emptyToNull } from '../lib/queryHelpers'
import { AUTH_EMAIL_DOMAIN, normalizeCompanyCode } from '../config/env'

export const getEmployees = ({ branchId, status, search } = {}) => {
  let q = byBranch(supabase.from('v_employees').select('*'), branchId).order('full_name')
  if (status) q = q.eq('status', status)
  if (search) {
    const t = ilikeTerm(search)
    q = q.or(`full_name.ilike.${t},username.ilike.${t},employee_code.ilike.${t}`)
  }
  return unwrap(q)
}

/** Empleados activos a los que se les puede asignar algo (tareas, tickets). */
export const getAssignableEmployees = ({ branchId } = {}) =>
  unwrap(byBranch(
    supabase.from('v_employees').select('id, full_name, department_id, department_name, role_name, branch_id')
      .eq('status', 'active'),
    branchId,
  ).order('full_name'))

export const getEmployeeDepartments = (employeeId) =>
  unwrap(supabase.from('employee_departments').select('department_id').eq('employee_id', employeeId))
    .then((rows) => rows.map((r) => r.department_id))

export async function setEmployeeDepartments(employeeId, departmentIds) {
  await unwrap(supabase.from('employee_departments').delete().eq('employee_id', employeeId))
  if (departmentIds.length) {
    await unwrap(supabase.from('employee_departments')
      .insert(departmentIds.map((department_id) => ({ employee_id: employeeId, department_id }))))
  }
}

/** Crea la cuenta de Supabase Auth (confirmada) para un empleado ya registrado. */
export async function createAccount(employeeId, password) {
  try {
    await adminSetPassword(employeeId, password)
  } catch (err) {
    throw new Error(`No se pudo crear la cuenta de acceso: ${err.message}`, { cause: err })
  }
}

export async function createEmployee({ password, extraDepartmentIds = [], ...fields }) {
  const row = emptyToNull({ ...fields, username: fields.username.trim().toLowerCase() })
  const employee = await unwrap(supabase.from('employees').insert(row).select().single())
  if (extraDepartmentIds.length) await setEmployeeDepartments(employee.id, extraDepartmentIds)
  if (password) {
    try {
      await createAccount(employee.id, password)
    } catch (err) {
      err.message = `El empleado se guardó, pero ${err.message.charAt(0).toLowerCase()}${err.message.slice(1)}`
      throw err
    }
  }
  return employee
}

export async function updateEmployee(id, { extraDepartmentIds, ...fields }) {
  // Columnas que vienen de la vista y no existen en la tabla
  const {
    role_code, role_name, role_scope, branch_name, department_name, department_color,
    has_account, user_id, is_owner, created_at, updated_at, ...row
  } = fields
  const saved = await unwrap(supabase.from('employees').update(emptyToNull(row)).eq('id', id).select().single())
  if (extraDepartmentIds) await setEmployeeDepartments(id, extraDepartmentIds)
  return saved
}

/** El usuario conectado cambia su propia contraseña. */
export async function changeOwnPassword(newPassword) {
  const { error } = await supabase.auth.updateUser({ password: newPassword, data: { must_change_password: false } })
  if (error) throw new Error(friendlyError(error))
}

export const adminSetPassword = (employeeId, password) =>
  unwrap(supabase.rpc('admin_set_password', { p_employee_id: employeeId, p_password: password }))

const isRealEmail = (value) => value.includes('@') && !value.toLowerCase().endsWith(AUTH_EMAIL_DOMAIN)

export async function requestPasswordReset(companyCode, identifier) {
  const value = identifier.trim()
  if (isRealEmail(value)) {
    const { error } = await supabase.auth.resetPasswordForEmail(value.toLowerCase(), {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    if (error) throw new Error(friendlyError(error))
    return 'email'
  }
  await unwrap(supabase.rpc('request_password_reset', { p_company_code: normalizeCompanyCode(companyCode), p_username: value }))
  return 'admin'
}

export const generateTempPassword = () => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(10))
  return Array.from(bytes, (b) => chars[b % chars.length]).join('')
}
