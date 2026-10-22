/**
 * PermissionsPage — excepciones de permisos por empleado.
 * Por cada permiso: "Rol" (hereda), "Conceder" o "Revocar".
 */
import { useCallback, useState } from 'react'
import { KeyRound } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getEmployees } from '../../services/employeeService'
import { getRoles, getPermissionsCatalog, getEmployeeOverrides, setEmployeeOverride } from '../../services/roleService'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Badge from '../../components/ui/Badge'

export default function PermissionsPage() {
  const toast = useToast()
  const loadEmployees = useCallback(() => getEmployees({ status: 'active' }), [])
  const { data: employees = [] } = useAsync(loadEmployees)
  const { data: roles = [] } = useAsync(getRoles)
  const { data: catalog = [], loading } = useAsync(getPermissionsCatalog)
  const [employeeId, setEmployeeId] = useState('')

  const loadOverrides = useCallback(() => (employeeId ? getEmployeeOverrides(employeeId) : Promise.resolve([])), [employeeId])
  const overrides = useAsync(loadOverrides)

  const employee = employees.find((e) => e.id === employeeId)
  const rolePerms = roles.find((r) => r.id === employee?.role_id)?.permissions ?? []

  const change = async (code, value) => {
    try { await setEmployeeOverride(employeeId, code, value); overrides.reload(); toast.success('Permiso actualizado') } catch (err) { toast.error(err.message) }
  }

  return (
    <div className="page">
      <PageHeader icon={KeyRound} title="Permisos especiales" subtitle="Concede o revoca permisos a un empleado sin cambiar su rol" />
      <div className="filters">
        <select className="filter-select" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
          <option value="">Selecciona un empleado…</option>
          {employees.map((e) => <option key={e.id} value={e.id}>{e.full_name} · {e.role_name}</option>)}
        </select>
      </div>
      <Card flush>
        <Table rowKey="code" data={employeeId ? catalog : []} loading={loading}
          emptyText={employeeId ? 'Sin permisos' : 'Elige un empleado para ver sus permisos'} columns={[
            { key: 'module', label: 'Módulo', sortable: true },
            { key: 'name', label: 'Permiso', bold: true, render: (v, r) => <>{v}<div className="cell-sub td-mono">{r.code}</div></> },
            { key: 'role', label: 'Por rol', render: (_, r) => <Badge color={rolePerms.includes(r.code) ? 'success' : 'default'}>{rolePerms.includes(r.code) ? 'Sí' : 'No'}</Badge> },
            { key: 'override', label: 'Excepción', render: (_, r) => {
              const o = (overrides.data ?? []).find((x) => x.permission_code === r.code)
              const value = o ? (o.is_granted ? 'grant' : 'revoke') : 'inherit'
              return (
                <select className="filter-select" value={value}
                  onChange={(e) => change(r.code, e.target.value === 'inherit' ? null : e.target.value === 'grant')}>
                  <option value="inherit">Usar rol</option>
                  <option value="grant">Conceder</option>
                  <option value="revoke">Revocar</option>
                </select>
              )
            } },
          ]} />
      </Card>
    </div>
  )
}
