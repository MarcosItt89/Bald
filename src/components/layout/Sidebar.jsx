/**
 * Sidebar — menú lateral filtrado por permisos.
 * La lista de opciones vive en src/config/navigation.js.
 *
 * Superadmin: el grupo Plataforma va primero (su trabajo es el rendimiento de
 * las tiendas) y la operación de su propia empresa queda en una sección
 * plegable, cerrada por defecto. Conserva todos sus permisos; solo no los ve
 * hasta que los busca. Se abre sola si la página actual está ahí.
 */
import { useState } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { NAV_GROUPS, canAccess } from '../../config/navigation'
import { getInitials } from '../../utils/formatters'

const OPS_KEY = 'operalia.sidebar.operacion'
const readOpen = () => { try { return localStorage.getItem(OPS_KEY) === '1' } catch { return false } }
const writeOpen = (v) => { try { localStorage.setItem(OPS_KEY, v ? '1' : '0') } catch { /* modo privado */ } }

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
  const { pathname } = useLocation()
  const [opsOpen, setOpsOpen] = useState(readOpen)

  const groups = NAV_GROUPS
    .map((group) => ({ group, items: group.items.filter((item) => canAccess(item, auth)) }))
    .filter((g) => g.items.length)
  const platform = groups.filter((g) => g.group.platform)
  const operation = groups.filter((g) => !g.group.platform)
  const inOperation = operation.some((g) => g.items.some((i) => pathname === i.path || pathname.startsWith(`${i.path}/`)))
  const showOps = opsOpen || inOperation
  const toggleOps = () => { setOpsOpen(!showOps); writeOpen(!showOps) }

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <img src="/logo.svg" alt="" width="32" height="32" className="sidebar-brand-logo" />
        <div className="sidebar-brand-text">
          <span className="sidebar-brand-name">Operalia</span>
          <span className="sidebar-brand-company">{isPlatformAdmin ? 'Plataforma' : profile?.company_name}</span>
        </div>
      </div>

      <nav className="sidebar-nav">
        {isPlatformAdmin ? (<>
          {platform.map((g, i) => <NavGroup key={`p${i}`} {...g} onNavigate={onNavigate} />)}
          {operation.length > 0 && (
            <div className="nav-section">
              <button type="button" className="nav-section-toggle" onClick={toggleOps} aria-expanded={showOps}>
                {showOps ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                <span>Operación de {profile?.company_name ?? 'mi empresa'}</span>
              </button>
              {showOps && operation.map((g, i) => <NavGroup key={`o${i}`} {...g} onNavigate={onNavigate} />)}
            </div>
          )}
        </>) : groups.map((g, i) => <NavGroup key={i} {...g} onNavigate={onNavigate} />)}
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
