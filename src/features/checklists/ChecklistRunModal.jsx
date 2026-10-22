/**
 * ChecklistRunModal — responder, completar, reabrir y revisar un checklist.
 *
 * - Cada respuesta se guarda al momento (no se pierde si se cierra la ventana).
 * - Preguntas de tipo foto (o con "requiere foto") piden subir evidencia; la
 *   evidencia se liga a la respuesta.
 * - "Completar" se habilita cuando están las obligatorias y las fotos; la BD
 *   vuelve a validar lo mismo.
 * - Vencido: solo quien revisa puede reabrirlo.
 * - Completado: quien revisa (y no lo llenó) puede aprobar, rechazar o pedir
 *   corrección (esta última lo reabre y notifica a quien lo llenó).
 */
import { useCallback, useRef, useState } from 'react'
import { Camera, CheckCircle2, RotateCcw, ShieldAlert, Thermometer, TriangleAlert } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import {
  getRunDetail, saveAnswer, completeRun, reopenRun, reviewRun, cancelRun,
} from '../../services/checklistService'
import { uploadEvidence } from '../../services/evidenceService'
import { CHECKLIST_REVIEW_STATUS, CHECKLIST_RUN_STATUS } from '../../constants/status'
import { formatDateTime, formatTime } from '../../utils/formatters'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Badge from '../../components/ui/Badge'
import ProgressBar from '../../components/ui/ProgressBar'
import { Textarea } from '../../components/ui/Input'
import { ErrorState, Loader } from '../../components/ui/Feedback'
import EvidenceGallery, { EvidenceThumb } from '../../components/domain/EvidenceGallery'
import EvidenceUploader from '../../components/domain/EvidenceUploader'

const OPEN_STATUSES = ['pending', 'in_progress', 'reopened']
const hasValue = (a) => a && a.answer_value != null && String(a.answer_value).trim() !== ''

export default function ChecklistRunModal({ runId, onClose, onChanged }) {
  const { hasPermission, profile } = useAuth()
  const toast = useToast()
  const load = useCallback(() => getRunDetail(runId), [runId])
  const { data, loading, error, reload } = useAsync(load)

  // Cambios hechos en esta sesión (se mezclan con lo que vino del servidor).
  const [localAnswers, setLocalAnswers] = useState({})
  const [localEvidence, setLocalEvidence] = useState([])
  const [busy, setBusy] = useState(null)
  const [reviewComment, setReviewComment] = useState('')

  if (loading && !data) return <Modal open onClose={onClose} title="Checklist"><Loader /></Modal>
  if (error) return <Modal open onClose={onClose} title="Checklist"><ErrorState error={error} onRetry={reload} /></Modal>

  const { run, questions } = data
  const answers = { ...Object.fromEntries(data.answers.map((a) => [a.question_id, a])), ...localAnswers }
  const evidence = [...data.evidence, ...localEvidence]
  const evidenceFor = (answer) => (answer ? evidence.filter((e) => e.entity_id === answer.id) : [])
  const runEvidence = [...data.runEvidence, ...localEvidence.filter((e) => e.entity_type === 'checklist_run')]

  const canFill = hasPermission(P.FILL_CHECKLISTS) && OPEN_STATUSES.includes(run.status)
  const canReview = hasPermission(P.REVIEW_CHECKLISTS)
  const isOwnRun = run.completed_by === profile.id

  const missingRequired = questions.filter((q) => q.is_required && !hasValue(answers[q.id])).length
  const missingPhotos = questions.filter((q) => q.requires_photo && evidenceFor(answers[q.id]).length === 0).length
  const answered = questions.filter((q) => hasValue(answers[q.id])).length
  // "Evidencia requerida" de la plantilla: basta una foto general o en alguna respuesta.
  const missingRunEvidence = run.requires_evidence && runEvidence.length === 0
    && !evidence.some((e) => e.entity_type === 'checklist_answer')
  const blockers = [
    missingRequired && `${missingRequired} respuesta(s)`,
    missingPhotos && `${missingPhotos} foto(s) de preguntas`,
    missingRunEvidence && 'la evidencia fotográfica del checklist',
  ].filter(Boolean)

  const persist = async (question, value, comment) => {
    const prev = answers[question.id]
    try {
      const saved = await saveAnswer(run.id, question.id, value, comment ?? prev?.comment)
      setLocalAnswers((m) => ({ ...m, [question.id]: saved }))
      return saved
    } catch (err) {
      toast.error(err.message)
      return null
    }
  }

  const action = async (key, fn, msg, closeAfter = true) => {
    setBusy(key)
    try {
      await fn()
      toast.success(msg)
      onChanged()
      if (closeAfter) onClose(); else reload()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setBusy(null)
    }
  }

  const footer = (
    <>
      <Button variant="ghost" onClick={onClose}>Cerrar</Button>
      {canReview && ['pending', 'in_progress', 'reopened', 'overdue'].includes(run.status) && (
        <Button variant="ghost" loading={busy === 'cancel'} onClick={() => {
          const reason = window.prompt('Motivo de la cancelación (p. ej. el departamento no abrió hoy):')
          if (reason?.trim()) action('cancel', () => cancelRun(run.id, reason.trim()), 'Checklist cancelado')
        }}>Cancelar checklist</Button>
      )}
      {canFill && (
        <Button variant="success" loading={busy === 'complete'} disabled={blockers.length > 0}
          title={blockers.length ? `Falta: ${blockers.join(', ')}` : ''}
          onClick={() => action('complete', () => completeRun(run.id), 'Checklist completado')}>
          <CheckCircle2 size={14} /> Completar
        </Button>
      )}
      {run.status === 'overdue' && canReview && (
        <Button loading={busy === 'reopen'} onClick={() => action('reopen', () => reopenRun(run.id), 'Checklist reabierto', false)}>
          <RotateCcw size={14} /> Reabrir
        </Button>
      )}
    </>
  )

  return (
    <Modal open onClose={onClose} title={run.title} size="lg" footer={footer}>
      <div className="detail-strip">
        <div><span>Estado</span><StatusBadge statusMap={CHECKLIST_RUN_STATUS} value={run.status} /></div>
        <div><span>Horario</span><strong>{formatTime(run.scheduled_start)}–{formatTime(run.scheduled_end)}</strong></div>
        <div><span>Departamento</span><strong>{run.department_name ?? 'General'}</strong></div>
        {run.started_at && <div><span>Inició</span><strong>{run.started_by_name} · {formatTime(run.started_at)}</strong></div>}
        {run.completed_at && <div><span>Completó</span><strong>{run.completed_by_name} · {formatDateTime(run.completed_at)}</strong></div>}
      </div>

      {run.status === 'overdue' && (
        <p className="hint-box hint-danger">Este checklist venció sin completarse.{canReview ? ' Puedes reabrirlo para que se llene.' : ' Pide a tu supervisor que lo reabra.'}</p>
      )}
      {run.status === 'cancelled' && (
        <p className="hint-box">Cancelado por {run.reviewed_by_name ?? '—'}{run.review_comment ? `: ${run.review_comment}` : ''}</p>
      )}
      {run.review_status === 'correction_required' && run.review_comment && OPEN_STATUSES.includes(run.status) && (
        <p className="hint-box hint-warning">Corrección solicitada por {run.reviewed_by_name}: {run.review_comment}</p>
      )}
      {canFill && <ProgressBar value={answered} total={questions.length} label={`${answered}/${questions.length} respondidas`} />}

      <ol className="question-list">
        {questions.map((q) => (
          <QuestionItem key={q.id} question={q} answer={answers[q.id]} evidence={evidenceFor(answers[q.id])}
            editable={canFill} onSave={persist}
            onEvidence={(ev) => setLocalEvidence((list) => [...list, ev])}
            companyId={profile.company_id} branchId={run.branch_id} />
        ))}
      </ol>

      {(run.requires_evidence || runEvidence.length > 0) && (
        <div className="review-box">
          <div className="review-head">
            <strong>Evidencia del checklist</strong>
            {run.requires_evidence && <span className={runEvidence.length || !missingRunEvidence ? 'photo-ok' : 'photo-pending'}>
              {missingRunEvidence ? 'Requerida para completar' : 'Cargada'}</span>}
            {canFill && (
              <EvidenceUploader entityType="checklist_run" entityId={run.id} branchId={run.branch_id} label="Tomar foto"
                onUploaded={(ev) => setLocalEvidence((list) => [...list, ev])} />
            )}
          </div>
          <EvidenceGallery items={runEvidence} emptyText="Aún no hay fotos generales" />
        </div>
      )}

      {canFill && blockers.length > 0 && answered > 0 && (
        <p className="hint-box hint-warning">Para completar falta: {blockers.join(', ')}.</p>
      )}

      {run.status === 'completed' && (
        <div className="review-box">
          <div className="review-head">
            <strong>Revisión</strong>
            <StatusBadge statusMap={CHECKLIST_REVIEW_STATUS} value={run.review_status} />
            {run.reviewed_by_name && <span className="text-muted text-sm">{run.reviewed_by_name} · {formatDateTime(run.reviewed_at)}</span>}
          </div>
          {run.review_comment && <p className="text-sm">{run.review_comment}</p>}
          {canReview && !isOwnRun && (
            <>
              <Textarea label="Comentario de revisión" value={reviewComment} onChange={(e) => setReviewComment(e.target.value)} rows={2} />
              <div className="row-actions">
                <Button size="sm" variant="success" loading={busy === 'approved'}
                  onClick={() => action('approved', () => reviewRun(run.id, 'approved', reviewComment), 'Checklist aprobado')}>Aprobar</Button>
                <Button size="sm" variant="outline" loading={busy === 'correction_required'}
                  onClick={() => (reviewComment.trim()
                    ? action('correction_required', () => reviewRun(run.id, 'correction_required', reviewComment), 'Se pidió corrección')
                    : toast.error('Explica qué se debe corregir'))}>Pedir corrección</Button>
                <Button size="sm" variant="danger" loading={busy === 'rejected'}
                  onClick={() => (reviewComment.trim()
                    ? action('rejected', () => reviewRun(run.id, 'rejected', reviewComment), 'Checklist rechazado')
                    : toast.error('Escribe el motivo del rechazo'))}>Rechazar</Button>
              </div>
            </>
          )}
          {canReview && isOwnRun && <p className="text-muted text-sm">No puedes revisar un checklist que tú completaste.</p>}
        </div>
      )}
    </Modal>
  )
}

function QuestionItem({ question: q, answer, evidence, editable, onSave, onEvidence, companyId, branchId }) {
  const toast = useToast()
  const fileRef = useRef(null)
  const [draft, setDraft] = useState(null) // texto/número en edición
  const [showComment, setShowComment] = useState(false)
  const [uploading, setUploading] = useState(false)
  const value = answer?.answer_value ?? ''
  const hasRange = q.answer_type === 'number' && (q.min_value != null || q.max_value != null)
  const reading = draft ?? value
  const outOfRange = hasRange && reading !== '' && !Number.isNaN(Number(String(reading).replace(',', '.')))
    && ((q.min_value != null && Number(String(reading).replace(',', '.')) < Number(q.min_value))
      || (q.max_value != null && Number(String(reading).replace(',', '.')) > Number(q.max_value)))
  const needsPhoto = q.requires_photo || q.answer_type === 'photo' || (hasRange && (outOfRange || answer?.out_of_range))

  const uploadPhoto = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setUploading(true)
    try {
      // La evidencia se liga a la respuesta. En preguntas tipo foto la
      // respuesta se crea sola; en las demás primero hay que contestar.
      const saved = answer ?? (q.answer_type === 'photo' ? await onSave(q, 'foto') : null)
      if (!saved) return
      const ev = await uploadEvidence({ file, companyId, entityType: 'checklist_answer', entityId: saved.id, branchId })
      onEvidence(ev)
      toast.success('Foto cargada')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setUploading(false)
    }
  }

  const stateClass = !hasValue(answer) ? 'q-pending' : value === 'no' || answer?.out_of_range ? 'q-fail' : 'q-ok'

  return (
    <li className={`question ${stateClass}`}>
      <div className="question-head">
        <span className="question-text">{q.text}{q.is_required && <span className="form-required"> *</span>}</span>
        {q.is_critical && <Badge color="danger" title="Un «No» crea una tarea urgente y avisa al gerente"><ShieldAlert size={11} /> Crítica</Badge>}
        {!q.is_active && <span className="text-muted text-sm">(pregunta retirada)</span>}
      </div>

      <div className="question-body">
        {q.answer_type === 'yes_no' && (
          <div className="segmented">
            {[['yes', 'Sí'], ['no', 'No'], ['na', 'N/A']].map(([v, label]) => (
              <button key={v} type="button" disabled={!editable}
                className={`segmented-btn ${value === v ? `segmented-active seg-${v}` : ''}`}
                title={value === v ? 'Clic de nuevo para desmarcar' : undefined}
                onClick={() => {
                  if (value === v) { onSave(q, null); return } // desmarcar
                  onSave(q, v)
                  if (v === 'no') setShowComment(true)
                }}>{label}</button>
            ))}
          </div>
        )}

        {hasRange && (
          <div className={`range-input ${outOfRange ? 'range-out' : ''}`}>
            <input className="form-input" disabled={!editable} type="text" inputMode="decimal" pattern="-?[0-9]*[.,]?[0-9]*"
              placeholder="Lectura" aria-label={`Lectura de ${q.equipment_name ?? q.text}`}
              value={reading} onChange={(e) => setDraft(e.target.value)}
              onBlur={() => {
                if (draft !== null && draft !== value) { onSave(q, draft); if (outOfRange) setShowComment(true) }
                setDraft(null)
              }} />
            <span className="range-unit">{q.unit}</span>
            <span className="range-hint"><Thermometer size={13} /> Permitido: {q.min_value ?? '−∞'} a {q.max_value ?? '∞'} {q.unit}</span>
          </div>
        )}

        {['text', 'signature', 'number'].includes(q.answer_type) && !hasRange && (
          <input className="form-input" disabled={!editable}
            type={q.answer_type === 'number' ? 'number' : 'text'} step="any"
            placeholder={q.answer_type === 'signature' ? 'Escribe tu nombre completo' : 'Respuesta'}
            value={draft ?? value}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={() => { if (draft !== null && draft !== value) onSave(q, draft); setDraft(null) }} />
        )}

        {q.answer_type === 'option' && (
          <select className="form-select" disabled={!editable} value={value} onChange={(e) => onSave(q, e.target.value)}>
            <option value="">Selecciona…</option>
            {(q.options ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
          </select>
        )}

        {needsPhoto && (
          <div className="question-photos">
            {evidence.map((ev) => <EvidenceThumb key={ev.id} evidence={ev} size={56} />)}
            {editable && (
              <>
                <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={uploadPhoto} />
                <Button size="sm" variant={evidence.length ? 'ghost' : 'outline'} loading={uploading}
                  disabled={q.answer_type !== 'photo' && !answer}
                  title={q.answer_type !== 'photo' && !answer ? 'Primero responde la pregunta' : undefined}
                  onClick={() => fileRef.current?.click()}>
                  {!uploading && <Camera size={14} />} {evidence.length ? 'Otra foto' : 'Tomar foto'}
                </Button>
              </>
            )}
            {!evidence.length && <span className="photo-pending">Foto requerida</span>}
          </div>
        )}
      </div>

      {(showComment || answer?.comment) && (
        <textarea className="form-input form-textarea question-comment" rows={2} disabled={!editable}
          placeholder="Comentario / incidencia" defaultValue={answer?.comment ?? ''}
          onBlur={(e) => { if (answer && e.target.value !== (answer.comment ?? '')) onSave(q, answer.answer_value, e.target.value) }} />
      )}
      {hasRange && (outOfRange || answer?.out_of_range) && (
        <p className="range-alert"><TriangleAlert size={14} /> Fuera de rango: se creó una tarea urgente y se avisó al gerente. Escribe qué hiciste en el comentario y toma una foto del termómetro.</p>
      )}
      {q.answer_type === 'yes_no' && value === 'no' && (
        <p className="text-sm text-muted">Se creó una tarea {q.is_critical ? 'urgente y se avisó al gerente' : 'para el jefe del departamento'}. Explica el problema en el comentario.</p>
      )}
      {editable && !showComment && !answer?.comment && hasValue(answer) && (
        <button type="button" className="link-btn" onClick={() => setShowComment(true)}>+ Agregar comentario</button>
      )}
    </li>
  )
}
