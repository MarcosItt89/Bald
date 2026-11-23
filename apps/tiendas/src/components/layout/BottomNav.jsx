/**
 * BottomNav — barra inferior en celular: lo que más se usa en piso,
 * con «Precios» (consulta/escaneo) al centro. «Menú» abre el menú completo.
 * Solo muestra lo que el empleado puede usar (mismos permisos que el Sidebar).
 */
import { NavLink } from 'react-router-dom'
import { CheckSquare, LayoutDashboard, ListTodo, Menu, ScanLine } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { NAV_GROUPS, canAccess } from '../../config/navigation'

const ITEMS = [
  { path: '/dashboard', label: 'Inicio', icon: LayoutDashboard },
  { path: '/checklists', label: 'Checklists', icon: CheckSquare },
  { path: '/inventory/prices', label: 'Precios', icon: ScanLine, scan: true },
  { path: '/tasks', label: 'Tareas', icon: ListTodo },
]

const ALL = NAV_GROUPS.flatMap((g) => g.items)

export default function BottomNav({ onMenu }) {
  const auth = useAuth()
  const items = ITEMS.filter((it) => {
    const nav = ALL.find((n) => n.path === it.path)
    return nav && canAccess(nav, auth)
  })
  const scan = items.find((it) => it.scan)
  const side = items.filter((it) => !it.scan)
  // Hasta 4 posiciones + «Menú»; el escaneo va al centro si está.
  const slots = scan ? [...side.slice(0, 2), scan, ...side.slice(2, 3)] : side.slice(0, 4)

  return (
    <nav className="bottom-nav" aria-label="Accesos rápidos" style={{ gridTemplateColumns: `repeat(${slots.length + 1}, 1fr)` }}>
      {slots.map((it) => (
        <NavLink key={it.path} to={it.path} end
          className={({ isActive }) => `bottom-nav-item ${it.scan ? 'bottom-nav-scan' : ''} ${isActive ? 'active' : ''}`}>
          {it.scan
            ? <span className="bottom-nav-bubble"><it.icon size={24} /></span>
            : <it.icon size={20} />}
          <span>{it.label}</span>
        </NavLink>
      ))}
      <button type="button" className="bottom-nav-item" onClick={onMenu}>
        <Menu size={20} />
        <span>Menú</span>
      </button>
    </nav>
  )
}
