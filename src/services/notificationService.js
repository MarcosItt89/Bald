/**
 * Servicio de notificaciones del usuario (campana del Topbar).
 *
 * Tipos de notificación (supabase/migrations/0008_notificaciones_departamento.sql):
 *   - personales: las crean triggers (tarea asignada, pedido aprobado, ticket...)
 *   - de departamento: avisos para todos los integrantes de un departamento
 * La vista v_my_notifications ya calcula `is_read` para el usuario actual
 * (las de departamento se marcan leídas por persona en notification_reads).
 */
import { supabase, unwrap } from '../lib/supabaseClient'

export const getNotifications = (limit = 30) =>
  unwrap(supabase.from('v_my_notifications').select('*').order('created_at', { ascending: false }).limit(limit))

export const markAsRead = (id) => unwrap(supabase.rpc('mark_notification_read', { p_id: id }))

export const markAllAsRead = () => unwrap(supabase.rpc('mark_all_notifications_read'))

/**
 * Avisa cuando llega cualquier notificación nueva visible para el usuario.
 * Sin filtro por employee_id: Realtime aplica RLS y solo entrega las
 * personales y las de su departamento.
 */
export function subscribeToNotifications(employeeId, onInsert) {
  const channel = supabase
    .channel(`notifications-${employeeId}`)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications' },
      (payload) => onInsert(payload.new))
    .subscribe()
  return () => supabase.removeChannel(channel)
}
