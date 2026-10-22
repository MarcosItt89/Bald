/**
 * NotificationBell — campana con las notificaciones del usuario.
 *
 * - Carga las últimas 30 al montar.
 * - Se suscribe a Realtime: las nuevas aparecen sin recargar la página.
 * - Al hacer clic en una, se marca como leída y navega a su módulo.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Bell, CheckCheck } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import {
  getNotifications, markAllAsRead, markAsRead, subscribeToNotifications,
} from '../../services/notificationService'
import { formatRelative } from '../../utils/formatters'

export default function NotificationBell() {
  const { profile } = useAuth()
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  const load = useCallback(() => getNotifications(30), [])
  const { data: items = [], mutate } = useAsync(load)
  const unread = items.filter((n) => !n.is_read).length

  useEffect(() => {
    if (!profile?.id) return undefined
    // Las nuevas siempre llegan sin leer; se evita duplicarlas si ya estaban.
    return subscribeToNotifications(profile.id, (n) => mutate((list = []) => (list.some((x) => x.id === n.id)
      ? list
      : [{ ...n, is_read: false, is_department: !n.employee_id }, ...list].slice(0, 30))))
  }, [profile?.id, mutate])

  useEffect(() => {
    if (!open) return undefined
    const close = (e) => { if (!ref.current?.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [open])

  const openItem = async (n) => {
    setOpen(false)
    if (!n.is_read) {
      mutate((list) => list.map((x) => (x.id === n.id ? { ...x, is_read: true } : x)))
      markAsRead(n.id).catch(() => {})
    }
    if (n.link) navigate(n.link)
  }

  const readAll = async () => {
    mutate((list) => list.map((x) => ({ ...x, is_read: true })))
    await markAllAsRead().catch(() => {})
  }

  return (
    <div className="topbar-notifications" ref={ref}>
      <button className="topbar-icon-btn" title="Notificaciones" onClick={() => setOpen((o) => !o)}>
        <Bell size={18} />
        {unread > 0 && <span className="topbar-badge">{unread > 9 ? '9+' : unread}</span>}
      </button>
      {open && (
        <div className="dropdown dropdown-right notif-dropdown">
          <div className="dropdown-header dropdown-header-row">
            <strong>Notificaciones</strong>
            {unread > 0 && (
              <button className="link-btn" onClick={readAll}><CheckCheck size={13} /> Marcar leídas</button>
            )}
          </div>
          {items.length === 0 && <p className="dropdown-empty">No tienes notificaciones</p>}
          <div className="notif-list">
            {items.map((n) => (
              <button key={n.id} className={`notif-item ${n.is_read ? '' : 'notif-unread'}`} onClick={() => openItem(n)}>
                <span className="notif-title">{n.title}</span>
                {n.is_department && <span className="notif-tag">Aviso de departamento</span>}
                {n.body && <span className="notif-body">{n.body}</span>}
                <span className="notif-time">{formatRelative(n.created_at)}</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
