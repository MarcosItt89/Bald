/**
 * TicketDetailPage — conversación de un ticket y sus propiedades.
 * Soporte: responde, notas internas, respuestas predefinidas, asigna y cambia estado/prioridad.
 * Solicitante: responde, cierra, reabre y califica.
 * Los mensajes nuevos llegan en vivo (Realtime).
 */
import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Lock, MapPin, MessageSquareText, RotateCcw, Send, Star, CircleCheck, Link2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { P } from '../../config/permissions'
import { getTicket, getMessages, replyTicket, updateTicket, getSupportAgents, getCannedResponses, subscribeToTicket } from '../../services/supportService'
import { getEvidence } from '../../services/evidenceService'
import { PRIORITY, TICKET_CATEGORY, TICKET_STATUS, toOptions } from '../../constants/status'
import { formatDateTime } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import StatusBadge from '../../components/ui/StatusBadge'
import Select from '../../components/ui/Select'
import EvidenceGallery from '../../components/domain/EvidenceGallery'
import EvidenceUploader from '../../components/domain/EvidenceUploader'
import { ErrorState, Loader } from '../../components/ui/Feedback'
import { BlocksBadge, DueBadge } from './supportUi'

const none = () => Promise.resolve([])

function Rating({ value, onRate }) {
  return (
    <div className="rating" role="radiogroup" aria-label="Calificación">
      {[1, 2, 3, 4, 5].map((n) => (
        <button key={n} type="button" className={`rating-star ${value >= n ? 'rating-on' : ''}`} onClick={() => onRate(n)} aria-label={`${n} de 5`}>
          <Star size={26} />
        </button>
      ))}
    </div>
  )
}

export default function TicketDetailPage() {
  const { id } = useParams()
  const { hasPermission, profile } = useAuth()
  const toast = useToast()
  const isAgent = hasPermission(P.MANAGE_TICKETS)
  const [body, setBody] = useState('')
  const [internal, setInternal] = useState(false)
  const [sending, setSending] = useState(false)

  const loadTicket = useCallback(() => getTicket(id), [id])
  const ticket = useAsync(loadTicket)
  const loadMessages = useCallback(() => getMessages(id), [id])
  const messages = useAsync(loadMessages)
  const loadPhotos = useCallback(() => getEvidence({ entityType: 'support_ticket', entityId: id }), [id])
  const photos = useAsync(loadPhotos)
  const { data: agents = [] } = useAsync(isAgent ? getSupportAgents : none)
  const { data: canned = [] } = useAsync(isAgent ? getCannedResponses : none)

  const reloadMessages = messages.reload
  useEffect(() => subscribeToTicket(id, () => reloadMessages()), [id, reloadMessages])

  if (ticket.error) return <ErrorState error={ticket.error} onRetry={ticket.reload} />
  if (!ticket.data) return <Loader />
  const t = ticket.data
  const closed = t.status === 'closed'
  const done = ['resolved', 'closed'].includes(t.status)
  const isOwner = t.created_by === profile.id
  const canReply = isAgent || isOwner

  const patch = async (p, msg) => {
    try { await updateTicket(t.id, p); toast.success(msg); ticket.reload() } catch (err) { toast.error(err.message) }
  }

  const send = async (e) => {
    e.preventDefault()
    if (!body.trim()) return
    setSending(true)
    try { await replyTicket(t.id, body.trim(), internal); setBody(''); setInternal(false); messages.reload(); ticket.reload() } catch (err) { toast.error(err.message) } finally { setSending(false) }
  }

  const insertCanned = (cid) => {
    const c = canned.find((x) => x.id === cid)
    if (c) setBody((b) => (b.trim() ? `${b.trim()}\n\n${c.body}` : c.body))
  }

  return (
    <div className="page">
      <Link to="/support" className="back-link"><ArrowLeft size={14} /> Soporte</Link>
      <PageHeader title={`${t.folio} · ${t.subject}`}
        subtitle={`${t.topic_name ?? TICKET_CATEGORY[t.category]} · abierto por ${t.created_by_name} ${formatDateTime(t.created_at)}`}
        actions={<div className="badge-stack"><StatusBadge statusMap={TICKET_STATUS} value={t.status} /><BlocksBadge ticket={t} /><DueBadge ticket={t} /></div>} />
      <div className="ticket-layout">
        <div>
          <Card>
            {t.location && <p className="row-inline text-sm text-muted"><MapPin size={14} /> {t.location}</p>}
            <p className="ticket-description">{t.description}</p>
            {(photos.data?.length > 0 || (canReply && !closed)) && (
              <div className="ticket-photos">
                <EvidenceGallery items={photos.data ?? []} emptyText="" />
                {canReply && !closed && <EvidenceUploader entityType="support_ticket" entityId={t.id} branchId={t.branch_id} label="Agregar foto" onUploaded={photos.reload} />}
              </div>
            )}
          </Card>

          <div className="ticket-thread">
            {(messages.data ?? []).map((m) => (
              <div key={m.id} className={`ticket-msg ${m.author_id === profile.id ? 'ticket-msg-own' : ''} ${m.is_internal ? 'ticket-msg-internal' : ''}`}>
                <div className="ticket-msg-head"><strong>{m.author_name}</strong>{m.is_internal && <> · <Lock size={11} /> nota interna</>}<span>{formatDateTime(m.created_at)}</span></div>
                <p>{m.body}</p>
              </div>
            ))}
            {!messages.data?.length && <p className="text-muted text-sm">Aún no hay respuestas.</p>}
          </div>

          {canReply && !closed && (
            <form className={`ticket-reply ${internal ? 'ticket-reply-internal' : ''}`} onSubmit={send}>
              {isAgent && canned.length > 0 && (
                <Select value="" placeholder="Insertar respuesta predefinida…" options={canned.map((c) => ({ value: c.id, label: c.title }))}
                  onChange={(e) => insertCanned(e.target.value)} />
              )}
              <textarea className="form-input form-textarea" rows={3} placeholder={internal ? 'Nota visible solo para soporte…' : 'Escribe una respuesta…'}
                value={body} onChange={(e) => setBody(e.target.value)} />
              <div className="row-actions">
                {isAgent && <label className="checkbox"><input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} /> <Lock size={13} /> Nota interna</label>}
                <Button type="submit" size="sm" loading={sending} disabled={!body.trim()}><Send size={14} /> Enviar</Button>
              </div>
            </form>
          )}
          {closed && <p className="hint-box">Ticket cerrado.{isOwner && ' Reábrelo si el problema volvió.'}</p>}
        </div>

        <Card title="Detalles">
          <div className="form-stack">
            {isAgent ? (<>
              <Select label="Estado" value={t.status} options={toOptions(TICKET_STATUS)} onChange={(e) => patch({ status: e.target.value }, 'Estado actualizado')} />
              <Select label="Prioridad" value={t.priority} options={toOptions(PRIORITY)} onChange={(e) => patch({ priority: e.target.value }, 'Prioridad actualizada')} />
              <Select label="Asignado a" value={t.assigned_to ?? ''} placeholder="Sin asignar" options={agents.map((a) => ({ value: a.id, label: a.full_name }))}
                onChange={(e) => patch({ assigned_to: e.target.value || null }, 'Ticket asignado')} />
              {!t.assigned_to && <Button variant="outline" size="sm" onClick={() => patch({ assigned_to: profile.id, status: t.status === 'open' ? 'in_progress' : t.status }, 'Ticket tomado')}>Tomar ticket</Button>}
            </>) : (<>
              <p><strong>Prioridad:</strong> <StatusBadge statusMap={PRIORITY} value={t.priority} /></p>
              <p><strong>Atiende:</strong> {t.assigned_to_name ?? 'Pendiente de asignar'}</p>
            </>)}

            <dl className="ticket-facts">
              <dt>Sucursal</dt><dd>{[t.branch_name, t.department_name].filter(Boolean).join(' · ') || '—'}</dd>
              <dt>Vence</dt><dd>{t.due_at ? formatDateTime(t.due_at) : '—'}</dd>
              <dt>1.ª respuesta</dt><dd>{t.first_response_at ? formatDateTime(t.first_response_at) : 'pendiente'}</dd>
              {t.satisfaction && <><dt>Calificación</dt><dd>{'★'.repeat(t.satisfaction)}</dd></>}
            </dl>
            {isAgent && t.page_url && <a className="link-btn" href={t.page_url} target="_blank" rel="noreferrer"><Link2 size={13} /> Página reportada</a>}

            {isOwner && !done && (
              <Button variant="outline" onClick={() => patch({ status: 'closed' }, 'Ticket cerrado')}><CircleCheck size={16} /> Ya quedó, cerrar ticket</Button>
            )}
            {isOwner && done && (
              <Button variant="outline" onClick={() => patch({ status: 'open' }, 'Ticket reabierto')}><RotateCcw size={16} /> Reabrir</Button>
            )}
            {isOwner && done && !t.satisfaction && (
              <div className="rating-box">
                <span className="form-label"><MessageSquareText size={14} /> ¿Cómo te atendimos?</span>
                <Rating value={t.satisfaction ?? 0} onRate={(n) => patch({ satisfaction: n }, 'Gracias por calificar')} />
              </div>
            )}
          </div>
        </Card>
      </div>
    </div>
  )
}
