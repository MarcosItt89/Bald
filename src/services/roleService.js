/**
 * Servicio de roles y permisos.
 *
 * - roles + role_permissions: paquete de permisos por puesto.
 * - employee_permissions: excepciones por empleado (conceder / revocar).
 * Escritura protegida por RLS con el permiso manage_roles.
 */
import { supabase, unwrap } from '../lib/supabaseClient'

export const getPermissionsCatalog = () =>
  unwrap(supabase.from('permissions').select('*').order('module').order('code'))

export const getRoles = () =>
  unwrap(supabase.from('roles').select('*, role_permissions(permission_code)').order('name'))
    .then((roles) => roles.map((r) => ({
      ...r,
      permissions: r.role_permissions.map((rp) => rp.permission_code),
    })))

export const createRole = ({ code, name, scope, description }) =>
  unwrap(supabase.from('roles').insert({ code, name, scope, description }).select().single())

export async function setRolePermission(roleId, permissionCode, enabled) {
  if (enabled) {
    await unwrap(supabase.from('role_permissions').upsert({ role_id: roleId, permission_code: permissionCode }))
  } else {
    await unwrap(supabase.from('role_permissions').delete()
      .eq('role_id', roleId).eq('permission_code', permissionCode))
  }
}

export const getEmployeeOverrides = (employeeId) =>
  unwrap(supabase.from('employee_permissions').select('*').eq('employee_id', employeeId))

/** value: true = conceder, false = revocar, null = quitar excepción (usar lo del rol). */
export async function setEmployeeOverride(employeeId, permissionCode, value) {
  if (value === null) {
    await unwrap(supabase.from('employee_permissions').delete()
      .eq('employee_id', employeeId).eq('permission_code', permissionCode))
  } else {
    await unwrap(supabase.from('employee_permissions')
      .upsert({ employee_id: employeeId, permission_code: permissionCode, is_granted: value }))
  }
}
