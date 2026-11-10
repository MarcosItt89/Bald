/**
 * SuppliersPage — catálogo de proveedores (Objetivos §11.4).
 * Con manage_suppliers se pueden crear, editar, bloquear o desactivar.
 */
import { useCallback, useState } from 'react'
import { Building, Plus } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { useDebouncedValue } from '@operalia/compartido/hooks/useDebouncedValue.js'
import { SUPPLIER_STATUS, toOptions } from '@operalia/compartido/constants/status.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import StatusBadge from '@operalia/compartido/components/ui/StatusBadge.jsx'
import SearchInput from '@operalia/compartido/components/ui/SearchInput.jsx'
import Modal from '@operalia/compartido/components/ui/Modal.jsx'
import Input from '@operalia/compartido/components/ui/Input.jsx'
import Select from '@operalia/compartido/components/ui/Select.jsx'
import { ErrorState } from '@operalia/compartido/components/ui/Feedback.jsx'
import { P } from '../../config/permissions'
import { getSuppliers, saveSupplier } from '../../services/supplierService'

const EMPTY = {
  code: '', name: '', legal_name: '', rfc: '', merchandise_type: '', contact_name: '', phone: '', email: '', status: 'active',
}

export default function SuppliersPage() {
  const { hasPermission } = useAuth()
  const toast = useToast()
  const canManage = hasPermission(P.MANAGE_SUPPLIERS)
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState(null)
  const [saving, setSaving] = useState(false)
  const debounced = useDebouncedValue(search)

  const load = useCallback(() => getSuppliers({ search: debounced }), [debounced])
  const { data: rows = [], loading, error, reload } = useAsync(load)

  const set = (k) => (e) => setEditing({ ...editing, [k]: e.target.value })

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await saveSupplier({ ...editing, code: editing.code.trim().toUpperCase() })
      toast.success('Proveedor guardado')
      setEditing(null)
      reload()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const columns = [
    { key: 'code', label: 'Código', mono: true, sortable: true },
    { key: 'name', label: 'Proveedor', bold: true, sortable: true, render: (v, r) => <>{v}<div className="cell-sub">{r.legal_name}</div></> },
    { key: 'merchandise_type', label: 'Tipo de mercancía', sortable: true },
    { key: 'contact_name', label: 'Contacto' },
    { key: 'phone', label: 'Teléfono' },
    { key: 'email', label: 'Correo' },
    { key: 'status', label: 'Estado', render: (v) => <StatusBadge statusMap={SUPPLIER_STATUS} value={v} /> },
  ]

  return (
    <div className="page">
      <PageHeader icon={Building} title="Proveedores" subtitle={`${rows.length} proveedores`}
        actions={canManage && <Button size="sm" onClick={() => setEditing(EMPTY)}><Plus size={14} /> Nuevo proveedor</Button>} />

      <div className="filters">
        <SearchInput value={search} onChange={setSearch} placeholder="Nombre, código o tipo…" />
      </div>
      {error && <ErrorState error={error} onRetry={reload} />}
      <Card flush>
        <Table columns={columns} data={rows} loading={loading} onRowClick={canManage ? setEditing : undefined} />
      </Card>

      <Modal open={!!editing} onClose={() => setEditing(null)} title={editing?.id ? 'Editar proveedor' : 'Nuevo proveedor'} size="lg"
        footer={<>
          <Button variant="ghost" onClick={() => setEditing(null)}>Cancelar</Button>
          <Button type="submit" form="supplier-form" loading={saving}>Guardar</Button>
        </>}>
        {editing && (
          <form id="supplier-form" className="form-stack" onSubmit={submit}>
            <div className="form-grid">
              <Input label="Código de proveedor" value={editing.code} onChange={set('code')} required />
              <Select label="Estado" value={editing.status} onChange={set('status')} options={toOptions(SUPPLIER_STATUS)} />
            </div>
            <Input label="Nombre comercial" value={editing.name} onChange={set('name')} required />
            <div className="form-grid">
              <Input label="Razón social" value={editing.legal_name ?? ''} onChange={set('legal_name')} />
              <Input label="RFC" value={editing.rfc ?? ''} onChange={set('rfc')} />
            </div>
            <Input label="Tipo de mercancía" value={editing.merchandise_type ?? ''} onChange={set('merchandise_type')} />
            <div className="form-grid form-grid-3">
              <Input label="Contacto" value={editing.contact_name ?? ''} onChange={set('contact_name')} />
              <Input label="Teléfono" type="tel" value={editing.phone ?? ''} onChange={set('phone')} />
              <Input label="Correo" type="email" value={editing.email ?? ''} onChange={set('email')} />
            </div>
          </form>
        )}
      </Modal>
    </div>
  )
}
