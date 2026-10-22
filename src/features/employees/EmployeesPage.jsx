/**
 * EmployeesPage — alta, edición y baja de empleados (manage_employees).
 * Al crear con contraseña se genera la cuenta de acceso (usuario@dominio).
 * Requiere "Confirm email" desactivado en Supabase Auth.
 */
import { useCallback, useState } from 'react'
import { Plus, Users } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { getEmployees, createEmployee, updateEmployee } from '../../services/employeeService'
import { getBranches, getDepartments } from '../../services/organizationService'
import { getRoles } from '../../services/roleService'
import { ACTIVE_STATUS, toOptions } from '../../constants/status'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'
import { ErrorState } from '../../components/ui/Feedback'

export default function EmployeesPage() {
  const { branchFilter, workingBranchId, isCompanyScope } = useAuth()
  const toast = useToast()
  const [search, setSearch] = useState('')
  const [form, setForm] = useState(null)
  const [saving, setSaving] = useState(false)
  const debounced = useDebouncedValue(search)

  const load = useCallback(() => getEmployees({ branchId: branchFilter, search: debounced }), [branchFilter, debounced])
  const { data: rows = [], loading, error, reload } = useAsync(load)
  const { data: roles = [] } = useAsync(getRoles)
  const { data: branches = [] } = useAsync(getBranches)
  const { data: departments = [] } = useAsync(getDepartments)
  // Un gerente no puede asignar roles de alcance empresa (la BD también lo impide).
  const roleOptions = roles.filter((r) => isCompanyScope || r.scope !== 'company').map((r) => ({ value: r.id, label: r.name }))
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      if (form.id) await updateEmployee(form.id, form)
      else await createEmployee(form)
      toast.success('Empleado guardado')
      setForm(null)
      reload()
    } catch (err) { toast.error(err.message); reload() } finally { setSaving(false) }
  }

  return (
    <div className="page">
      <PageHeader icon={Users} title="Empleados" subtitle={`${rows.length} empleados`}
        actions={<Button size="sm" onClick={() => setForm({ username: '', password: '', full_name: '', employee_code: '', position: '', phone: '', role_id: '', branch_id: workingBranchId ?? '', department_id: '', status: 'active' })}>
          <Plus size={14} /> Nuevo empleado</Button>} />
      <div className="filters"><SearchInput value={search} onChange={setSearch} placeholder="Nombre, usuario o código…" /></div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={(r) => setForm(r)} columns={[
          { key: 'employee_code', label: 'Código', mono: true, sortable: true },
          { key: 'full_name', label: 'Nombre', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub">@{r.username} · {r.position}</div></> },
          { key: 'branch_name', label: 'Sucursal', sortable: true },
          { key: 'department_name', label: 'Departamento', sortable: true },
          { key: 'role_name', label: 'Rol', render: (v) => <Badge color="info">{v}</Badge> },
          { key: 'has_account', label: 'Acceso', render: (v) => <Badge color={v ? 'success' : 'default'}>{v ? 'Con cuenta' : 'Sin cuenta'}</Badge> },
          { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={ACTIVE_STATUS} value={v} /> },
        ]} />
      </Card>

      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? `Editar · ${form.full_name}` : 'Nuevo empleado'} size="lg"
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Cancelar</Button><Button type="submit" form="emp-form" loading={saving}>Guardar</Button></>}>
        {form && (
          <form id="emp-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid">
              <Input label="Nombre completo" required value={form.full_name} onChange={set('full_name')} />
              <Input label="Usuario" required disabled={!!form.id} value={form.username} onChange={set('username')} hint="Con esto inicia sesión" />
              {!form.id && <Input label="Contraseña inicial" type="password" minLength={8} value={form.password} onChange={set('password')} hint="Vacío = sin cuenta por ahora" />}
              <Input label="Código de empleado" value={form.employee_code ?? ''} onChange={set('employee_code')} />
              <Input label="Puesto" value={form.position ?? ''} onChange={set('position')} />
              <Input label="Teléfono" value={form.phone ?? ''} onChange={set('phone')} />
              <Select label="Rol" required value={form.role_id} placeholder="Selecciona…" options={roleOptions} onChange={set('role_id')} />
              <Select label="Sucursal" value={form.branch_id ?? ''} placeholder="Sin sucursal" disabled={!isCompanyScope}
                options={branches.map((b) => ({ value: b.id, label: b.name }))} onChange={set('branch_id')} />
              <Select label="Departamento" value={form.department_id ?? ''} placeholder="Sin departamento"
                options={departments.map((d) => ({ value: d.id, label: d.name }))} onChange={set('department_id')} />
              {form.id && <Select label="Estado" value={form.status} options={toOptions(ACTIVE_STATUS)} onChange={set('status')} />}
            </div>
          </form>
        )}
      </Modal>
    </div>
  )
}
