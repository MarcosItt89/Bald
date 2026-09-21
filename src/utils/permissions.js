import { ROLES } from '../data/mockData'

export const hasPermission = (user, permission) => {
  if (!user) return false
  const role = ROLES[user.role]
  if (!role) return false
  return role.permissions.includes(permission)
}

export const hasAnyPermission = (user, permissions = []) =>
  permissions.some(p => hasPermission(user, p))

export const hasAllPermissions = (user, permissions = []) =>
  permissions.every(p => hasPermission(user, p))
