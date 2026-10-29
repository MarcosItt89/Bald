/**
 * PlatformCompaniesPage — Plataforma → Empresas (solo superadmins).
 * Lista las empresas cliente con sucursales, empleados activos, último
 * inicio de sesión, salud de la cuenta y avance de arranque (0025); suspende
 * o reactiva cada una (con confirmación). Suspendida: sus empleados pierden
 * el acceso, sin borrar datos. Clic en una fila: detalle de salud y arranque.
 */
import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Globe, Plus, Ban, CirclePlay, Headset, CircleCheck, Circle } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getCompanies, getCompanyHealth, setCompanyStatus } from '../../services/platformService'
import { ACCOUNT_HEALTH, COMPANY_STATUS } from '../../constants/status'
import { formatDate, formatRelative } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Table from '../../components/ui/Table'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import ProgressBar from '../../components/ui/ProgressBar'
import Modal from '../../components/ui/Modal'
import { ErrorState } from '../../components/ui/Feedback'

export default function PlatformCompaniesPage() {
  const navigate = useNavigate()
  const toast = useToast()
  const { data: companies = [], loading, error, reload } = useAsync(getCompanies)
  const { data: health = [], error: healthError, reload: reloadHealth } = useAsync(getCompanyHealth)
  const rows = useMemo(() => {
    const byId = new Map(health.map((h) => [h.company_id, h]))
    return companies.map((c) => ({ ...c, health: byId.get(c.id) ?? null }))
  }, [companies, health])
  const [busy, setBusy] = useState(null)
  const [detail, setDetail] = useState(null)
  const suspended = rows.filter((c) => c.status === 'suspended').length

  const changeStatus = async (c, status) => {
    const question = status === 'suspended'
      ? `¿Suspender «${c.name}»? Sus ${c.active_employees} empleados dejarán de poder entrar. Los datos no se borran.`
      : `¿Reactivar «${c.name}»? Sus empleados podrán volver a entrar.`
    if (!window.confirm(question)) return
    setBusy(c.id)
    try {
      await setCompanyStatus(c.id, status)
      toast.success(status === 'suspended' ? 'Empresa suspendida' : 'Empresa reactivada')
      reload()
      reloadHealth()
    } catch (err) { toast.error(err.message) } finally { setBusy(null) }
  }

  return (
    <div className="page">
      <PageHeader icon={Globe} title="Empresas"
        subtitle={`${rows.length} empresas cliente${suspended ? ` · ${suspended} suspendida${suspended > 1 ? 's' : ''}` : ''}`}
        actions={<Button size="sm" onClick={() => navigate('/plataforma/nueva')}><Plus size={14} /> Nueva empresa</Button>} />
      {error && <ErrorState error={error} onRetry={reload} />}
      {healthError && <ErrorState error={healthError} onRetry={reloadHealth} />}
      <Card flush>
        <Table data={rows} loading={loading} onRowClick={setDetail} emptyText="Aún no hay empresas" columns={[
          { key: 'name', label: 'Empresa', bold: true, sortable: true, render: (v, r) => (
            <>{v}<div className="cell-sub"><span className="mono">{r.code}</span> · {r.owner_name ? `${r.owner_name} (@${r.owner_username})` : 'sin propietario'}</div></>
          ) },
          { key: 'status', label: 'Estado', render: (v, r) => <><StatusBadge statusMap={COMPANY_STATUS} value={v} /><div className="cell-sub">Plan {r.plan}</div></> },
          { key: 'health', label: 'Salud', sortable: true, sortValue: (r) => ({ green: 0, yellow: 1, red: 2 })[r.health?.health] ?? 3,
            render: (h) => (h ? (
              <span title={h.reasons.join(' · ') || 'Uso, checklists y tickets en orden'}>
                <StatusBadge statusMap={ACCOUNT_HEALTH} value={h.health} />
                <div className="cell-sub">{h.reasons[0] ?? 'Todo en orden'}{h.reasons.length > 1 && ` y ${h.reasons.length - 1} más`}</div>
              </span>
            ) : '—') },
          { key: 'onboarding', label: 'Arranque', sortable: true, sortValue: (r) => r.health?.onboarding_pct,
            render: (_, r) => (r.health ? <ProgressBar percent={r.health.onboarding_pct} semaphore width={64} /> : '—') },
          { key: 'branches', label: 'Tamaño', align: 'right', sortable: true,
            render: (v, r) => <>{v} suc.<div className="cell-sub">{r.active_employees} empleados</div></> },
          { key: 'last_sign_in_at', label: 'Último acceso', sortable: true,
            render: (v, r) => <>{v ? formatRelative(v) : <span className="text-muted">Nunca</span>}<div className="cell-sub">Alta {formatDate(r.created_at)}</div></> },
          { key: 'actions', label: '', render: (_, r) => (
            <div className="row-actions" onClick={(e) => e.stopPropagation()}>
              <Button size="sm" variant="ghost" title="Tickets de esta empresa" aria-label="Tickets de esta empresa"
                onClick={() => navigate(`/plataforma/soporte?empresa=${r.id}`)}><Headset size={14} /></Button>
              {r.status === 'active'
                ? <Button size="sm" variant="outline" loading={busy === r.id} onClick={() => changeStatus(r, 'suspended')}><Ban size={14} /> Suspender</Button>
                : <Button size="sm" variant="success" loading={busy === r.id} onClick={() => changeStatus(r, 'active')}><CirclePlay size={14} /> Reactivar</Button>}
            </div>
          ) },
        ]} />
      </Card>

      <Modal open={!!detail} onClose={() => setDetail(null)} title={detail?.name} size="sm"
        footer={<>
          <Button variant="ghost" onClick={() => navigate(`/plataforma/soporte?empresa=${detail.id}`)}><Headset size={14} /> Tickets</Button>
          <Button onClick={() => setDetail(null)}>Cerrar</Button>
        </>}>
        {detail?.health && <HealthDetail h={detail.health} />}
      </Modal>
    </div>
  )
}

/** Salud de la cuenta con sus tres criterios y los pasos del arranque. */
function HealthDetail({ h }) {
  return (
    <div className="form-stack">
      <div>
        <span className="form-label">Salud de la cuenta (últimos 7 días)</span>
        <p><StatusBadge statusMap={ACCOUNT_HEALTH} value={h.health} /></p>
        <dl className="ticket-facts">
          <dt>Uso</dt><dd>{h.accounts ? `${h.usage_pct ?? 0}% · ${h.users_7d} de ${h.accounts} con cuenta entraron` : 'Nadie tiene cuenta'}</dd>
          <dt>Checklists a tiempo</dt><dd>{h.checklist_on_time_pct == null ? 'Sin checklists' : `${h.checklist_on_time_pct}% de ${h.runs_7d}`}</dd>
          <dt>Tickets abiertos</dt><dd>{h.tickets_open} en {h.branches} sucursales</dd>
        </dl>
        <p className="text-muted text-sm">Verde: uso de 60% o más, checklists a tiempo de 60% o más y hasta 1 ticket abierto por sucursal. Rojo: uso menor a 30%, checklists menor a 45% o más de 2 tickets por sucursal.</p>
      </div>
      <div>
        <span className="form-label">Avance de arranque · {h.onboarding_pct}%</span>
        <ProgressBar percent={h.onboarding_pct} semaphore />
        <ul className="onboarding-steps">
          {h.onboarding.map((step) => (
            <li key={step.key} className={step.done ? 'onboarding-done' : ''}>
              {step.done ? <CircleCheck size={16} /> : <Circle size={16} />}
              <span><strong>{step.label}</strong><small>{step.detail}</small></span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
