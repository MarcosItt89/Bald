/**
 * RolesPage — matriz de permisos por rol.
 * Con manage_roles se activan/desactivan permisos con un clic (se guarda al momento).
 */
import { useMemo, useState } from 'react'
import { Shield } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P, ROLE_SCOPES } from '../../config/permissions'
import { getRoles, getPermissionsCatalog, setRolePermission } from '../../services/roleService'
import PageHeader from '../../components/ui/PageHeader'
import Badge from '../../components/ui/Badge'
import { ErrorState, Loader } from '../../components/ui/Feedback'

export default function RolesPage() {
  const { hasPermission } = useAuth()
  const toast = useToast()
  const canEdit = hasPermission(P.MANAGE_ROLES)
  const roles = useAsync(getRoles)
  const catalog = useAsync(getPermissionsCatalog)
  const [roleId, setRoleId] = useState(null)

  const role = roles.data?.find((r) => r.id === roleId) ?? roles.data?.[0]
  const byModule = useMemo(() => (catalog.data ?? []).reduce((acc, p) => {
    (acc[p.module] ??= []).push(p); return acc
  }, {}), [catalog.data])

  if (roles.error) return <ErrorState error={roles.error} onRetry={roles.reload} />
  if (!roles.data || !catalog.data) return <Loader />
  if (!role) return <p className="text-muted">No hay roles configurados.</p>

  const toggle = async (code) => {
    const enabled = !role.permissions.includes(code)
    roles.mutate((list) => list.map((r) => (r.id === role.id
      ? { ...r, permissions: enabled ? [...r.permissions, code] : r.permissions.filter((p) => p !== code) } : r)))
    try { await setRolePermission(role.id, code, enabled) } catch (err) { toast.error(err.message); roles.reload() }
  }

  return (
    <div className="page">
      <PageHeader icon={Shield} title="Roles y permisos" subtitle={canEdit ? 'Haz clic en un permiso para activarlo o desactivarlo' : 'Solo lectura'} />
      <div className="roles-layout">
        <div className="roles-list">
          {roles.data.map((r) => (
            <button key={r.id} className={`roles-item ${r.id === role.id ? 'roles-item-active' : ''}`} onClick={() => setRoleId(r.id)}>
              <strong>{r.name}</strong>
              <span>{ROLE_SCOPES[r.scope]?.label} · {r.permissions.length} permisos</span>
            </button>
          ))}
        </div>
        <div className="card card-body">
          <h3>{role.name} <Badge color="info">{ROLE_SCOPES[role.scope]?.label}</Badge></h3>
          <p className="text-muted text-sm">{ROLE_SCOPES[role.scope]?.help}</p>
          {Object.entries(byModule).map(([module, perms]) => (
            <div key={module} className="perm-module">
              <h4>{module}</h4>
              {perms.map((p) => (
                <label key={p.code} className="checkbox" title={p.description}>
                  <input type="checkbox" disabled={!canEdit} checked={role.permissions.includes(p.code)} onChange={() => toggle(p.code)} />
                  {p.name} <span className="text-muted td-mono">{p.code}</span>
                </label>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
