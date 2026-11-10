/**
 * ConsolaLayout — menú lateral + barra superior de la Consola Operalia.
 * Usa las mismas clases de estilo que la app de tiendas (paquete compartido).
 * En celular el menú se abre encima del contenido y se cierra al navegar.
 */
import { Suspense, useState } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { Activity, CirclePlus, Globe, Handshake, Headset, LogOut, Menu, Palette, ScrollText } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { getInitials } from '@operalia/compartido/utils/formatters.js'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'

const NAV = [
  { icon: Globe,      label: 'Empresas',      path: '/' },
  { icon: Activity,   label: 'Rendimiento',   path: '/rendimiento' },
  { icon: Palette,    label: 'Marca',         path: '/marca' },
  { icon: Handshake,  label: 'Prospectos',    path: '/prospectos' },
  { icon: CirclePlus, label: 'Nueva empresa', path: '/nueva' },
  { icon: Headset,    label: 'Soporte de tiendas', path: '/soporte' },
  { icon: ScrollText, label: 'Bitácora',      path: '/bitacora' },
]

const isMobile = () => window.matchMedia('(max-width: 900px)').matches

export default function ConsolaLayout() {
  const { profile, session, logout } = useAuth()
  const navigate = useNavigate()
  const [open, setOpen] = useState(() => !isMobile())
  const onNavigate = () => { if (isMobile()) setOpen(false) }
  const signOut = async () => { await logout(); navigate('/login', { replace: true }) }

  return (
    <div className={`app-shell ${open ? 'sidebar-open' : 'sidebar-collapsed'}`}>
      <aside className="sidebar">
        <div className="sidebar-brand">
          <img src="/logo.svg" alt="" width="32" height="32" className="sidebar-brand-logo" />
          <div className="sidebar-brand-text">
            <span className="sidebar-brand-name">Operalia</span>
            <span className="sidebar-brand-company">Consola</span>
          </div>
        </div>
        <nav className="sidebar-nav">
          <div className="nav-group">
            <span className="nav-group-label">Plataforma</span>
            {NAV.map((item) => (
              <NavLink key={item.path} to={item.path} end={item.path === '/'} onClick={onNavigate}
                className={({ isActive }) => `nav-item ${isActive ? 'nav-item-active' : ''}`}>
                <item.icon size={16} className="nav-icon" />
                <span className="nav-label">{item.label}</span>
              </NavLink>
            ))}
          </div>
        </nav>
        <div className="sidebar-footer">
          <div className="sidebar-user">
            <div className="sidebar-user-avatar">{getInitials(profile?.full_name)}</div>
            <div className="sidebar-user-info">
              <span className="sidebar-user-name">{profile?.full_name}</span>
              <span className="sidebar-user-role">Superadmin</span>
            </div>
          </div>
        </div>
      </aside>
      {open && <div className="sidebar-backdrop" onClick={() => setOpen(false)} />}
      <div className="main-area">
        <header className="topbar">
          <div className="topbar-left">
            <button className="topbar-menu-btn" onClick={() => setOpen((v) => !v)} aria-label="Menú"><Menu size={20} /></button>
            <span className="consola-topbar-title">Consola Operalia</span>
          </div>
          <div className="topbar-right">
            <span className="consola-topbar-email text-muted text-sm">{session?.user?.email}</span>
            <button type="button" className="topbar-icon-btn" onClick={signOut} title="Cerrar sesión" aria-label="Cerrar sesión"><LogOut size={18} /></button>
          </div>
        </header>
        <main className="page-content">
          <Suspense fallback={<Loader />}><Outlet /></Suspense>
        </main>
      </div>
    </div>
  )
}
