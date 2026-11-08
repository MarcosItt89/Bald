/**
 * Sidebar — menú lateral filtrado por permisos.
 * La lista de opciones vive en src/config/navigation.js.
 *
 * Superadmin: ve el menú de su empresa como cualquier empleado, más el link a
 * la Consola Operalia (donde vive la plataforma) si VITE_CONSOLA_URL está definida.
 */
import { NavLink } from 'react-router-dom'
import { ExternalLink } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { NAV_GROUPS, canAccess } from '../../config/navigation'
import { getInitials } from '@operalia/compartido/utils/formatters.js'
import { env } from '@operalia/compartido/config/env.js'


function NavGroup({ group, items, onNavigate }) {
  return (
    <div className="nav-group">
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
}

export default function Sidebar({ onNavigate }) {
  const auth = useAuth()
  const { profile, isPlatformAdmin } = auth

  const groups = NAV_GROUPS
    .map((group) => ({ group, items: group.items.filter((item) => canAccess(item, auth)) }))
    .filter((g) => g.items.length)

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        {/* Marca de su empresa (0028). */}
        <img src={profile?.company_logo_url ? profile.company_logo_url : '/logo.svg'}
          alt="" width="32" height="32" className="sidebar-brand-logo" />
        <div className="sidebar-brand-text">
          <span className="sidebar-brand-name">Operalia</span>
          <span className="sidebar-brand-company">{profile?.company_display_name || profile?.company_name}</span>
        </div>
      </div>

      <nav className="sidebar-nav">
        {groups.map((g, i) => <NavGroup key={i} {...g} onNavigate={onNavigate} />)}
        {isPlatformAdmin && env.consolaUrl && (
          <div className="nav-group">
            <span className="nav-group-label">Plataforma</span>
            <a href={env.consolaUrl} target="_blank" rel="noopener noreferrer" className="nav-item">
              <ExternalLink size={16} className="nav-icon" />
              <span className="nav-label">Consola Operalia</span>
            </a>
          </div>
        )}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-user">
          <div className="sidebar-user-avatar">{getInitials(profile?.full_name)}</div>
          <div className="sidebar-user-info">
            <span className="sidebar-user-name">{profile?.full_name}</span>
            <span className="sidebar-user-role">{isPlatformAdmin ? 'Superadmin · ' : ''}{profile?.role_name}</span>
          </div>
        </div>
      </div>
    </aside>
  )
}
