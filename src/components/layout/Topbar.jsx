import { Bell, LogOut, Menu } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../contexts/AuthContext'
import { MOCK_NOTIFICATION_COUNT } from '../../data/mockData'

export default function Topbar({ onMenuToggle }) {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  return (
    <header className="topbar">
      <div className="topbar-left">
        <button className="topbar-menu-btn" onClick={onMenuToggle}>
          <Menu size={20} />
        </button>
        <span className="topbar-branch">{user?.branch ?? ''}</span>
      </div>

      <div className="topbar-right">
        <button className="topbar-icon-btn" title="Notificaciones">
          <Bell size={18} />
          {MOCK_NOTIFICATION_COUNT > 0 && (
            <span className="topbar-badge">{MOCK_NOTIFICATION_COUNT}</span>
          )}
        </button>

        <div className="topbar-divider" />

        <div className="topbar-user">
          <div className="topbar-avatar">
            {user?.name?.[0]?.toUpperCase() ?? 'U'}
          </div>
          <div className="topbar-user-info">
            <span className="topbar-user-name">{user?.name ?? ''}</span>
            <span className="topbar-user-dept">{user?.department ?? ''}</span>
          </div>
        </div>

        <button className="topbar-icon-btn topbar-logout" onClick={handleLogout} title="Cerrar sesión">
          <LogOut size={18} />
        </button>
      </div>
    </header>
  )
}
