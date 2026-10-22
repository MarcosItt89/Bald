/**
 * EvidencePage — galería y revisión de evidencias (Objetivos §11.8).
 *
 * - Filtros: estado (pestañas), tipo de origen (checklist, tarea, recibo,
 *   cenefa...) y rango de fechas.
 * - Subir evidencia general (upload_evidence).
 * - Revisar (review_evidence): aprobar, rechazar o pedir corrección con
 *   comentario. La BD impide revisar la propia evidencia y notifica al autor.
 * - El autor puede borrar su evidencia mientras siga pendiente.
 */
import { useCallback, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Camera, Trash2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getEvidence, getSignedUrl, reviewEvidence, deleteEvidence } from '../../services/evidenceService'
import { EVIDENCE_ENTITIES, EVIDENCE_STATUS } from '../../constants/status'
import { addDaysISO, formatDateTime, todayISO } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Tabs from '../../components/ui/Tabs'
import Button from '../../components/ui/Button'
import Badge from '../../components/ui/Badge'
import StatusBadge from '../../components/ui/StatusBadge'
import Modal from '../../components/ui/Modal'
import { Textarea } from '../../components/ui/Input'
import { EmptyState, ErrorState, Loader } from '../../components/ui/Feedback'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import { EvidenceThumb } from '../../components/domain/EvidenceGallery'

const TABS = [
  { key: 'pending',  label: 'Por revisar', statuses: ['pending'] },
  { key: 'rejected', label: 'Rechazadas / corrección', statuses: ['rejected', 'correction_required'] },
  { key: 'approved', label: 'Aprobadas', statuses: ['approved'] },
  { key: 'all',      label: 'Todas', statuses: undefined },
]

export default function EvidencePage() {
  const { branchFilter, hasPermission } = useAuth()
  const [params] = useSearchParams()
  const [tab, setTab] = useState(() => (TABS.some((t) => t.key === params.get('tab')) ? params.get('tab') : 'pending'))
  const [entityType, setEntityType] = useState('')
  const [from, setFrom] = useState(() => params.get('from') ?? addDaysISO(todayISO(), -14))
  const [to, setTo] = useState(() => params.get('to') ?? todayISO())
  const [selected, setSelected] = useState(null)

  const load = useCallback(() => getEvidence({
    branchId: branchFilter, statuses: TABS.find((t) => t.key === tab).statuses,
    entityType: entityType || undefined, from, to, limit: 200,
  }), [branchFilter, tab, entityType, from, to])
  const { data: rows = [], loading, error, reload } = useAsync(load)

  return (
    <div className="page">
      <PageHeader icon={Camera} title="Evidencias" subtitle={`${rows.length} evidencias en el periodo`}
        actions={hasPermission(P.UPLOAD_EVIDENCE) && (
          <EvidenceUploader entityType="other" label="Subir evidencia" variant="primary" onUploaded={reload} />
        )} />
      <Tabs active={tab} onChange={setTab} tabs={TABS.map(({ key, label }) => ({ key, label }))} />
      <div className="filters">
        <select className="filter-select" value={entityType} onChange={(e) => setEntityType(e.target.value)}>
          <option value="">Todos los orígenes</option>
          {Object.entries(EVIDENCE_ENTITIES).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
        <label className="filter-date">Del <input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="filter-date">al <input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} /></label>
      </div>

      {error && <ErrorState error={error} onRetry={reload} />}
      {loading && !rows.length && <Loader />}
      {!loading && !rows.length && <EmptyState icon={Camera} title="Sin evidencias" message="No hay evidencias con estos filtros." />}

      <div className="evidence-grid">
        {rows.map((ev) => (
          <div key={ev.id} className="evidence-card" role="button" tabIndex={0}
            onClick={() => setSelected(ev)} onKeyDown={(e) => e.key === 'Enter' && setSelected(ev)}>
            <EvidenceThumb evidence={ev} size={160} onSelect={() => setSelected(ev)} />
            <div className="evidence-card-body">
              <div className="evidence-card-row">
                <Badge color="default">{EVIDENCE_ENTITIES[ev.entity_type] ?? ev.entity_type}</Badge>
                <StatusBadge statusMap={EVIDENCE_STATUS} value={ev.status} />
              </div>
              <span className="text-sm td-bold">{ev.uploaded_by_name ?? '—'}</span>
              <span className="text-sm text-muted">{formatDateTime(ev.created_at)}{branchFilter ? '' : ` · ${ev.branch_name ?? ''}`}</span>
              {ev.description && <span className="text-sm">{ev.description}</span>}
            </div>
          </div>
        ))}
      </div>

      {selected && <ReviewModal evidence={selected} onClose={() => setSelected(null)}
        onChanged={() => { setSelected(null); reload() }} />}
    </div>
  )
}

function ReviewModal({ evidence, onClose, onChanged }) {
  const { hasPermission, profile } = useAuth()
  const toast = useToast()
  const [comment, setComment] = useState(evidence.review_comment ?? '')
  const [busy, setBusy] = useState(null)
  const load = useCallback(() => getSignedUrl(evidence.storage_path), [evidence.storage_path])
  const { data: url, error } = useAsync(load)

  const isOwn = evidence.uploaded_by === profile.id
  const canReview = hasPermission(P.REVIEW_EVIDENCE) && !isOwn
  const isPdf = evidence.mime_type === 'application/pdf'

  const act = async (key, fn, msg) => {
    setBusy(key)
    try { await fn(); toast.success(msg); onChanged() } catch (err) { toast.error(err.message); setBusy(null) }
  }
  const review = (status, msg) => {
    if (status !== 'approved' && !comment.trim()) { toast.error('Escribe un comentario para el autor'); return }
    act(status, () => reviewEvidence(evidence.id, status, comment), msg)
  }

  return (
    <Modal open onClose={onClose} title="Evidencia" size="lg"
      footer={<>
        {isOwn && evidence.status === 'pending' && (
          <Button variant="ghost" loading={busy === 'delete'}
            onClick={() => window.confirm('¿Eliminar esta evidencia?') && act('delete', () => deleteEvidence(evidence), 'Evidencia eliminada')}>
            <Trash2 size={14} /> Eliminar
          </Button>
        )}
        <Button variant="ghost" onClick={onClose}>Cerrar</Button>
        {canReview && <>
          <Button variant="outline" loading={busy === 'correction_required'} onClick={() => review('correction_required', 'Se pidió corrección')}>Pedir corrección</Button>
          <Button variant="danger" loading={busy === 'rejected'} onClick={() => review('rejected', 'Evidencia rechazada')}>Rechazar</Button>
          <Button variant="success" loading={busy === 'approved'} onClick={() => review('approved', 'Evidencia aprobada')}>Aprobar</Button>
        </>}
      </>}>
      <div className="evidence-preview">
        {error ? <p className="hint-box hint-danger">{error.message}</p>
          : !url ? <Loader />
          : isPdf ? <a className="btn btn-outline" href={url} target="_blank" rel="noreferrer">Abrir PDF</a>
          : <a href={url} target="_blank" rel="noreferrer"><img src={url} alt={evidence.file_name ?? 'Evidencia'} /></a>}
      </div>
      <div className="detail-strip mt-3">
        <div><span>Estado</span><StatusBadge statusMap={EVIDENCE_STATUS} value={evidence.status} /></div>
        <div><span>Origen</span><strong>{EVIDENCE_ENTITIES[evidence.entity_type]}</strong></div>
        <div><span>Subió</span><strong>{evidence.uploaded_by_name} · {formatDateTime(evidence.created_at)}</strong></div>
        {evidence.reviewed_by_name && <div><span>Revisó</span><strong>{evidence.reviewed_by_name} · {formatDateTime(evidence.reviewed_at)}</strong></div>}
      </div>
      {evidence.description && <p className="mb-3">{evidence.description}</p>}
      {canReview
        ? <Textarea label="Comentario para el autor (obligatorio al rechazar o pedir corrección)" rows={2}
            value={comment} onChange={(e) => setComment(e.target.value)} />
        : evidence.review_comment && <p className="hint-box">Comentario: {evidence.review_comment}</p>}
      {isOwn && hasPermission(P.REVIEW_EVIDENCE) && <p className="text-muted text-sm">No puedes revisar tu propia evidencia.</p>}
    </Modal>
  )
}
