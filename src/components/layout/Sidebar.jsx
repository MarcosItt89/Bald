/**
 * Sidebar — menú lateral filtrado por permisos.
 * La lista de opciones vive en src/config/navigation.js.
 */
import { NavLink } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { NAV_GROUPS, canAccess } from '../../config/navigation'
import { getInitials } from '../../utils/formatters'

export default function Sidebar({ onNavigate }) {
  const auth = useAuth()
  const { profile } = auth

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <img src="/logo.svg" alt="" width="32" height="32" className="sidebar-brand-logo" />
        <div className="sidebar-brand-text">
          <span className="sidebar-brand-name">Operalia</span>
          <span className="sidebar-brand-company">{profile?.company_name}</span>
        </div>
      </div>

      <nav className="sidebar-nav">
        {NAV_GROUPS.map((group, gi) => {
          const items = group.items.filter((item) => canAccess(item, auth))
          if (!items.length) return null
          return (
            <div key={gi} className="nav-group">
              {group.label && <span className="nav-group-label">{group.label}</span>}
              {items.map((item) => (
                <NavLink
                  key={item.path}
                  to={item.path}
                  end
                  onClick={onNavigate}
                  className={({ isActive }) => `nav-item ${isActive ? 'nav-item-active' : ''}`}
                >
                  <item.icon size={16} className="nav-icon" />
                  <span className="nav-label">{item.label}</span>
                </NavLink>
              ))}
            </div>
          )
        })}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-user">
          <div className="sidebar-user-avatar">{getInitials(profile?.full_name)}</div>
          <div className="sidebar-user-info">
            <span className="sidebar-user-name">{profile?.full_name}</span>
            <span className="sidebar-user-role">{profile?.role_name}</span>
          </div>
        </div>
      </div>
    </aside>
  )
}
