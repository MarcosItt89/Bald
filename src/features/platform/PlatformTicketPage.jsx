/**
 * PlatformTicketPage — un ticket de cualquier empresa, atendido como
 * «Soporte Operalia» (platform_get_ticket / platform_reply_ticket).
 * Las fotos adjuntas y la conversación en vivo se quedan dentro de la
 * empresa (Storage y Realtime respetan su RLS); aquí se recarga a mano.
 */
import { useCallback, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, CircleCheck, Lock, MapPin, RefreshCw, RotateCcw, Send } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { getPlatformTicket, replyPlatformTicket } from '../../services/platformService'
import { COMPANY_STATUS, PRIORITY, TICKET_CATEGORY, TICKET_STATUS, toOptions } from '../../constants/status'
import { formatDateTime } from '../../utils/formatters'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Select from '../../components/ui/Select'
import StatusBadge from '../../components/ui/StatusBadge'
import { ErrorState, Loader } from '../../components/ui/Feedback'
import { BlocksBadge, DueBadge } from '../support/supportUi'

export default function PlatformTicketPage() {
  const { id } = useParams()
  const toast = useToast()
  const [body, setBody] = useState('')
  const [nextStatus, setNextStatus] = useState('')
  const [sending, setSending] = useState(false)

  const load = useCallback(() => getPlatformTicket(id), [id])
  const { data, error, reload } = useAsync(load)

  if (error) return <ErrorState error={error} onRetry={reload} />
  if (!data) return <Loader />
  const { ticket: t, messages } = data
  const closed = t.status === 'closed'

  const act = async (text, status, msg) => {
    setSending(true)
    try {
      await replyPlatformTicket(t.id, text, status)
      setBody(''); setNextStatus('')
      toast.success(msg)
      reload()
    } catch (err) { toast.error(err.message) } finally { setSending(false) }
  }

  const send = (e) => {
    e.preventDefault()
    if (body.trim()) act(body, nextStatus, 'Respuesta enviada')
  }

  return (
    <div className="page">
      <Link to="/plataforma/soporte" className="back-link"><ArrowLeft size={14} /> Soporte de tiendas</Link>
      <PageHeader title={`${t.folio} · ${t.subject}`}
        subtitle={`${t.company_name} · ${t.topic_name ?? TICKET_CATEGORY[t.category] ?? t.category} · abierto por ${t.created_by_name ?? '—'} ${formatDateTime(t.created_at)}`}
        actions={<div className="badge-stack"><StatusBadge statusMap={TICKET_STATUS} value={t.status} /><BlocksBadge ticket={t} /><DueBadge ticket={t} /></div>} />
      <div className="ticket-layout">
        <div>
          <Card>
            {t.location && <p className="row-inline text-sm text-muted"><MapPin size={14} /> {t.location}</p>}
            <p className="ticket-description">{t.description}</p>
          </Card>

          <div className="ticket-thread">
            {messages.map((m) => (
              <div key={m.id} className={`ticket-msg ${m.is_platform ? 'ticket-msg-own' : ''} ${m.is_internal ? 'ticket-msg-internal' : ''}`}>
                <div className="ticket-msg-head">
                  <strong>{m.author_name ?? '—'}</strong>
                  {m.is_internal && <> · <Lock size={11} /> nota interna de la tienda</>}
                  <span>{formatDateTime(m.created_at)}</span>
                </div>
                <p>{m.body}</p>
              </div>
            ))}
            {!messages.length && <p className="text-muted text-sm">Aún no hay respuestas.</p>}
          </div>

          {!closed && (
            <form className="ticket-reply" onSubmit={send}>
              <textarea className="form-input form-textarea" rows={3} placeholder="Responder como Soporte Operalia…"
                value={body} onChange={(e) => setBody(e.target.value)} />
              <div className="row-actions">
                <Select value={nextStatus} placeholder="Sin cambiar el estado" onChange={(e) => setNextStatus(e.target.value)}
                  options={toOptions(TICKET_STATUS).filter((o) => o.value !== t.status && o.value !== 'open')} />
                <Button type="submit" size="sm" loading={sending} disabled={!body.trim()}><Send size={14} /> Enviar</Button>
              </div>
            </form>
          )}
          {closed && <p className="hint-box">Ticket cerrado. Reábrelo para responder.</p>}
        </div>

        <Card title="Detalles" action={<Button size="sm" variant="ghost" onClick={reload} title="Actualizar" aria-label="Actualizar"><RefreshCw size={14} /></Button>}>
          <div className="form-stack">
            <dl className="ticket-facts">
              <dt>Empresa</dt><dd>{t.company_name} <span className="mono text-muted">{t.company_code}</span> {t.company_status !== 'active' && <StatusBadge statusMap={COMPANY_STATUS} value={t.company_status} />}</dd>
              <dt>Sucursal</dt><dd>{[t.branch_name, t.department_name].filter(Boolean).join(' · ') || '—'}</dd>
              <dt>Prioridad</dt><dd><StatusBadge statusMap={PRIORITY} value={t.priority} /></dd>
              <dt>Atiende en tienda</dt><dd>{t.assigned_to_name ?? '—'}</dd>
              <dt>Vence</dt><dd>{t.due_at ? formatDateTime(t.due_at) : '—'}</dd>
              <dt>1.ª respuesta</dt><dd>{t.first_response_at ? formatDateTime(t.first_response_at) : 'pendiente'}</dd>
              {t.satisfaction && <><dt>Calificación</dt><dd>{'★'.repeat(t.satisfaction)}</dd></>}
            </dl>
            {!['resolved', 'closed'].includes(t.status) && (
              <Button variant="outline" loading={sending} onClick={() => act(null, 'resolved', 'Ticket resuelto')}><CircleCheck size={16} /> Marcar resuelto</Button>
            )}
            {['resolved', 'closed'].includes(t.status) && (
              <Button variant="outline" loading={sending} onClick={() => act(null, 'open', 'Ticket reabierto')}><RotateCcw size={16} /> Reabrir</Button>
            )}
            <p className="text-muted text-sm">Las fotos adjuntas solo se ven dentro de la empresa.</p>
          </div>
        </Card>
      </div>
    </div>
  )
}
