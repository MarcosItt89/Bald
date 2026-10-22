/**
 * Servicio de la Mesa de Ayuda (soporte interno, estilo osTicket).
 *
 * Objetivo: que jefes y gerentes reporten fallas o pidan mejoras de la
 * plataforma, y que el equipo de soporte les dé seguimiento con folio,
 * estados, prioridad, asignación, conversación y notas internas.
 *
 *   create_tickets → puede levantar tickets y ver los suyos
 *   manage_tickets → ve todos, responde, asigna, cambia estado, notas internas
 *
 * Estados: open → in_progress ⇄ waiting_user → resolved → closed
 * (los cambios automáticos al responder los hace el trigger SQL).
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { ilikeTerm } from '../lib/queryHelpers'

const ACTIVE = ['open', 'in_progress', 'waiting_user']
const DONE = ['resolved', 'closed']

export const getTickets = ({ status, createdBy, notCreatedBy, assignedTo, unassigned, overdue, search, limit = 200 } = {}) => {
  let q = supabase.from('v_support_tickets').select('*').order('updated_at', { ascending: false }).limit(limit)
  if (status === 'active') q = q.in('status', ACTIVE)
  else if (status === 'done') q = q.in('status', DONE)
  else if (status) q = q.eq('status', status)
  if (createdBy) q = q.eq('created_by', createdBy)
  if (notCreatedBy) q = q.neq('created_by', notCreatedBy)
  if (assignedTo) q = q.eq('assigned_to', assignedTo)
  if (unassigned) q = q.is('assigned_to', null)
  if (overdue) q = q.eq('is_overdue', true)
  if (search) {
    const t = ilikeTerm(search)
    q = q.or(`subject.ilike.${t},folio.ilike.${t},description.ilike.${t}`)
  }
  return unwrap(q)
}

export const getTicket = (id) =>
  unwrap(supabase.from('v_support_tickets').select('*').eq('id', id).single())

export const getMessages = (ticketId) =>
  unwrap(supabase.from('v_support_ticket_messages').select('*').eq('ticket_id', ticketId).order('created_at'))

export const getTopics = () =>
  unwrap(supabase.from('support_topics').select('*').eq('is_active', true).order('sort_order'))

export const getCannedResponses = () =>
  unwrap(supabase.from('support_canned_responses').select('id, title, body').eq('is_active', true).order('title'))

export const createTicket = ({ subject, description, category, module, priority = 'medium', topicId, location, blocksOperation, pageUrl }) =>
  unwrap(supabase.from('support_tickets').insert({
    subject, description, category, module: module || null, priority,
    topic_id: topicId || null,
    location: location?.trim() || null,
    blocks_operation: !!blocksOperation,
    page_url: pageUrl || window.location.href,
    user_agent: navigator.userAgent.slice(0, 250),
  }).select().single())

export const replyTicket = (ticketId, body, isInternal = false) =>
  unwrap(supabase.from('support_ticket_messages')
    .insert({ ticket_id: ticketId, body, is_internal: isInternal }).select().single())

export const updateTicket = (id, patch) =>
  unwrap(supabase.from('support_tickets').update(patch).eq('id', id).select().single())

/** Empleados cuyo rol tiene manage_tickets (para asignar tickets). */
export async function getSupportAgents() {
  const roles = await unwrap(supabase.from('role_permissions')
    .select('role_id').eq('permission_code', 'manage_tickets'))
  if (!roles.length) return []
  return unwrap(supabase.from('v_employees').select('id, full_name, role_name')
    .in('role_id', roles.map((r) => r.role_id)).eq('status', 'active').order('full_name'))
}

/** Suscripción en vivo a nuevos mensajes de un ticket. Devuelve función para cancelar. */
export function subscribeToTicket(ticketId, onMessage) {
  const channel = supabase
    .channel(`ticket-${ticketId}`)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'support_ticket_messages', filter: `ticket_id=eq.${ticketId}` },
      onMessage)
    .subscribe()
  return () => supabase.removeChannel(channel)
}
