/**
 * NewCompanyPage — Plataforma → Nueva empresa (solo superadmins).
 * Da de alta una empresa cliente con provision_company (migración 0024):
 * empresa, semilla base, primera sucursal y propietario con cuenta. Al
 * terminar muestra la tarjeta con los datos de acceso para copiarlos.
 * Desde Prospectos («Dar de alta») llega con el prospecto en location.state:
 * llena nombre y propietario, y al crear la empresa liga el prospecto.
 */
import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { CirclePlus, Copy, RefreshCw } from 'lucide-react'
import { useToast } from '../../hooks/useToast'
import { linkLeadToCompany, provisionCompany } from '../../services/platformService'
import { generateTempPassword } from '../../services/employeeService'
import { normalizeCompanyCode } from '../../config/env'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Input from '../../components/ui/Input'
import Select from '../../components/ui/Select'

const TIMEZONES = [
  ['America/Tijuana', 'Tijuana (Baja California)'],
  ['America/Hermosillo', 'Hermosillo (Sonora)'],
  ['America/Mazatlan', 'Mazatlán (Pacífico)'],
  ['America/Chihuahua', 'Chihuahua'],
  ['America/Monterrey', 'Monterrey'],
  ['America/Mexico_City', 'Ciudad de México (Centro)'],
  ['America/Merida', 'Mérida'],
  ['America/Cancun', 'Cancún (Quintana Roo)'],
].map(([value, label]) => ({ value, label }))

const emptyForm = (lead) => ({
  name: lead?.chain_name ?? '', legalName: '', rfc: '', code: normalizeCompanyCode(lead?.chain_name ?? ''), timezone: 'America/Tijuana',
  branchCode: '001', branchName: '', ownerUsername: '', ownerFullName: lead?.contact_name ?? '',
  ownerPassword: generateTempPassword(), withDemo: false,
})

const cleanUsername = (v) => v.toLowerCase().replace(/[^a-z0-9._-]/g, '')

export default function NewCompanyPage() {
  const navigate = useNavigate()
  const toast = useToast()
  const location = useLocation()
  const [lead, setLead] = useState(() => location.state?.lead ?? null)
  const [form, setForm] = useState(() => emptyForm(lead))
  const [codeEdited, setCodeEdited] = useState(false)
  const [saving, setSaving] = useState(false)
  const [done, setDone] = useState(null)
  const set = (k, fn = (v) => v) => (e) => setForm({ ...form, [k]: fn(e.target.value) })

  const setName = (e) => {
    const name = e.target.value
    setForm({ ...form, name, ...(codeEdited ? {} : { code: normalizeCompanyCode(name) }) })
  }

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await provisionCompany(form)
      setDone({ ...res, name: form.name.trim(), ownerFullName: form.ownerFullName.trim(), password: form.ownerPassword })
      toast.success('Empresa creada')
      if (lead) {
        try { await linkLeadToCompany(lead.id, res.id) } catch { toast.error('La empresa se creó, pero no se pudo ligar el prospecto') }
      }
    } catch (err) { toast.error(err.message) } finally { setSaving(false) }
  }

  const appUrl = window.location.origin
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(`Operalia: ${appUrl}\nEmpresa: ${done.code}\nUsuario: ${done.owner_username}\nContraseña temporal: ${done.password}`)
      toast.success('Copiado')
    } catch { toast.error('No se pudo copiar') }
  }

  const again = () => { setLead(null); setForm(emptyForm()); setCodeEdited(false); setDone(null) }

  if (done) {
    return (
      <div className="page">
        <PageHeader icon={CirclePlus} title="Empresa creada" subtitle={done.name} />
        <Card title="Datos de acceso del propietario">
          <div className="form-stack">
            <p>Comparte estos datos con <strong>{done.ownerFullName}</strong>. Al entrar se le pedirá crear su propia contraseña; esta temporal no se vuelve a mostrar.</p>
            <div className="temp-credentials">
              <span>App</span><code>{appUrl}</code>
              <span>Empresa</span><code>{done.code}</code>
              <span>Usuario</span><code>{done.owner_username}</code>
              <span>Contraseña temporal</span><code>{done.password}</code>
            </div>
            <div className="row-actions">
              <Button variant="outline" onClick={copy}><Copy size={14} /> Copiar</Button>
              <Button variant="ghost" onClick={again}>Dar de alta otra</Button>
              <Button onClick={() => navigate('/plataforma')}>Ver empresas</Button>
            </div>
          </div>
        </Card>
      </div>
    )
  }

  return (
    <div className="page">
      <PageHeader icon={CirclePlus} title="Nueva empresa"
        subtitle={lead
          ? `Desde el prospecto «${lead.chain_name}»${lead.branch_count ? ` (${lead.branch_count} sucursales)` : ''}. Al crearla queda ligado.`
          : 'Crea la empresa con sus departamentos, roles, plantillas y su primera sucursal, y la cuenta del propietario'} />
      <form className="form-stack" onSubmit={submit}>
        <Card title="Empresa">
          <div className="form-stack">
            <div className="form-grid form-grid-top">
              <Input label="Nombre comercial" required value={form.name} onChange={setName} placeholder="Súper La Luna" />
              <Input label="Código de empresa" required minLength={2} maxLength={30} value={form.code}
                onChange={(e) => { setCodeEdited(true); setForm({ ...form, code: normalizeCompanyCode(e.target.value) }) }}
                hint="Lo escriben sus empleados al entrar. Minúsculas, números y guiones; no se cambia después." />
            </div>
            <div className="form-grid form-grid-3 form-grid-top">
              <Input label="Razón social" value={form.legalName} onChange={set('legalName')} />
              <Input label="RFC" value={form.rfc} maxLength={13} onChange={set('rfc', (v) => v.toUpperCase())} />
              <Select label="Zona horaria" value={form.timezone} onChange={set('timezone')} options={TIMEZONES}
                hint="Define el «hoy» de sus checklists" />
            </div>
          </div>
        </Card>

        <Card title="Primera sucursal">
          <div className="form-grid form-grid-top">
            <Input label="Número / clave" required value={form.branchCode} onChange={set('branchCode')} />
            <Input label="Nombre" required value={form.branchName} onChange={set('branchName')} placeholder="Sucursal Centro" />
          </div>
        </Card>

        <Card title="Propietario" subtitle="Rol Administrador, departamento Administración. Es el único que edita roles y permisos.">
          <div className="form-stack">
            <div className="form-grid form-grid-top">
              <Input label="Nombre completo" required value={form.ownerFullName} onChange={set('ownerFullName')} />
              <Input label="Usuario" required minLength={3} maxLength={40} value={form.ownerUsername}
                onChange={set('ownerUsername', cleanUsername)} hint="Minúsculas, números, punto, guion o guion bajo" />
            </div>
            <div className="input-row">
              <Input label="Contraseña temporal" required minLength={8} value={form.ownerPassword}
                onChange={set('ownerPassword')} hint="Mínimo 8 caracteres. Se le pedirá cambiarla al entrar." />
              <Button variant="outline" onClick={() => setForm({ ...form, ownerPassword: generateTempPassword() })}
                title="Generar otra" aria-label="Generar otra"><RefreshCw size={14} /></Button>
            </div>
            <label className="checkbox">
              <input type="checkbox" checked={form.withDemo} onChange={(e) => setForm({ ...form, withDemo: e.target.checked })} />
              Cargar datos de ejemplo (productos, inventario, tareas). Solo para pruebas; requiere la carpeta demo/ instalada.
            </label>
          </div>
        </Card>

        <div className="row-actions">
          <Button variant="ghost" onClick={() => navigate('/plataforma')}>Cancelar</Button>
          <Button type="submit" loading={saving} disabled={form.ownerPassword.length < 8}>Crear empresa</Button>
        </div>
      </form>
    </div>
  )
}
