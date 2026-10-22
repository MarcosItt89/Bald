/**
 * Topbar — barra superior: menú, sucursal, ayuda, notificaciones y usuario.
 *
 * El botón de Ayuda (salvavidas) solo aparece para quien puede levantar o
 * atender tickets (jefes, gerencia, soporte, admin).
 */
import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { ChevronDown, KeyRound, LifeBuoy, LogOut, Menu, Wrench } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { P } from '../../config/permissions'
import { getInitials } from '../../utils/formatters'
import BranchSwitcher from '../domain/BranchSwitcher'
import NotificationBell from './NotificationBell'
import ChangePasswordModal from './ChangePasswordModal'

export default function Topbar({ onMenuToggle }) {
  const { profile, logout, hasAny, hasPermission } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const reportFrom = encodeURIComponent(location.pathname + location.search)
  const onSupport = location.pathname.startsWith('/support')
  const [menuOpen, setMenuOpen] = useState(false)
  const [pwdOpen, setPwdOpen] = useState(false)
  const menuRef = useRef(null)

  useEffect(() => {
    if (!menuOpen) return undefined
    const close = (e) => { if (!menuRef.current?.contains(e.target)) setMenuOpen(false) }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [menuOpen])

  const handleLogout = async () => {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <header className="topbar">
      <div className="topbar-left">
        <button className="topbar-menu-btn" onClick={onMenuToggle} aria-label="Menú">
          <Menu size={20} />
        </button>
        <BranchSwitcher />
      </div>

      <div className="topbar-right">
        {hasPermission(P.CREATE_TICKETS) && !onSupport && (
          <Link to={`/support/new?from=${reportFrom}`} className="topbar-icon-btn topbar-help topbar-report" title="Reportar problema">
            <Wrench size={18} /><span className="topbar-help-label">Reportar problema</span>
          </Link>
        )}
        {hasAny([P.CREATE_TICKETS, P.MANAGE_TICKETS]) && (
          <Link to="/support" className="topbar-icon-btn topbar-help" title="Soporte">
            <LifeBuoy size={18} /><span className="topbar-help-label">Soporte</span>
          </Link>
        )}
        <NotificationBell />
        <div className="topbar-divider" />

        <div className="topbar-user-menu" ref={menuRef}>
          <button className="topbar-user" onClick={() => setMenuOpen((o) => !o)}>
            <div className="topbar-avatar">{getInitials(profile?.full_name)}</div>
            <div className="topbar-user-info">
              <span className="topbar-user-name">{profile?.full_name}</span>
              <span className="topbar-user-dept">{profile?.position ?? profile?.role_name}</span>
            </div>
            <ChevronDown size={14} />
          </button>
          {menuOpen && (
            <div className="dropdown dropdown-right">
              <div className="dropdown-header">
                <strong>@{profile?.username}</strong>
                <span>{profile?.role_name} · {profile?.department_name ?? 'Sin departamento'}</span>
              </div>
              <button className="dropdown-item" onClick={() => { setPwdOpen(true); setMenuOpen(false) }}>
                <KeyRound size={14} /> Cambiar contraseña
              </button>
              <button className="dropdown-item dropdown-danger" onClick={handleLogout}>
                <LogOut size={14} /> Cerrar sesión
              </button>
            </div>
          )}
        </div>
      </div>

      <ChangePasswordModal open={pwdOpen} onClose={() => setPwdOpen(false)} />
    </header>
  )
}
