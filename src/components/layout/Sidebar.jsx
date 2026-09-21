import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard, Package, Tag, ArrowLeftRight, Truck, ShoppingCart,
  DollarSign, CheckSquare, Camera, ClipboardList, Users, FileText,
  Building2, Layers, UserCheck, Shield, Key, ChevronRight,
  AlertCircle, Scan,
} from 'lucide-react'
import { useAuth } from '../../contexts/AuthContext'

// Cada ítem especifica el permiso mínimo requerido para verlo.
// Si permission es null, el ítem siempre se muestra al usuario autenticado.
const NAV_GROUPS = [
  {
    label: null,
    items: [
      { icon: LayoutDashboard, label: 'Dashboard', path: '/dashboard', permission: 'view_dashboard' },
    ],
  },
  {
    label: 'Inventario',
    items: [
      { icon: Package,        label: 'Inventario',          path: '/inventory',           permission: 'view_inventory'  },
      { icon: Tag,            label: 'Consulta de precios', path: '/inventory/prices',    permission: 'view_prices'     },
      { icon: ArrowLeftRight, label: 'Movimientos',         path: '/inventory/movements', permission: 'view_inventory'  },
    ],
  },
  {
    label: 'Operaciones',
    items: [
      { icon: Truck,        label: 'Recibo de mercancía', path: '/receiving',     permission: 'receive_products'     },
      { icon: ShoppingCart, label: 'Pedidos internos',    path: '/orders',        permission: 'create_orders'        },
      { icon: DollarSign,   label: 'Cambios de precio',   path: '/price-changes', permission: 'manage_price_changes' },
      { icon: Tag,          label: 'Cenefas',             path: '/shelf-tags',    permission: 'manage_shelf_tags'    },
      { icon: AlertCircle,  label: 'Caducidades',         path: '/expirations',   permission: 'manage_expirations'   },
    ],
  },
  {
    label: 'Operaciones diarias',
    items: [
      { icon: CheckSquare,  label: 'Checklists', path: '/checklists', permission: 'fill_checklists' },
      { icon: Camera,       label: 'Evidencias', path: '/evidence',   permission: 'upload_evidence' },
      { icon: ClipboardList,label: 'Tareas',     path: '/tasks',      permission: 'fill_checklists' },
    ],
  },
  {
    label: 'Proveedores',
    items: [
      { icon: Users,    label: 'Proveedores', path: '/suppliers',       permission: 'view_suppliers'       },
      { icon: FileText, label: 'Accesos',     path: '/supplier-access', permission: 'register_supplier_visit' },
    ],
  },
  {
    label: 'Reportes',
    items: [
      { icon: FileText, label: 'Reportes', path: '/reports', permission: 'view_reports' },
    ],
  },
  {
    label: 'Configuración',
    items: [
      { icon: Building2,  label: 'Sucursales',    path: '/branches',    permission: 'manage_branches'  },
      { icon: Layers,     label: 'Departamentos', path: '/departments', permission: 'manage_branches'  },
      { icon: UserCheck,  label: 'Empleados',     path: '/employees',   permission: 'manage_employees' },
      { icon: Shield,     label: 'Roles',         path: '/roles',       permission: 'manage_employees' },
      { icon: Key,        label: 'Permisos',      path: '/permissions', permission: 'manage_employees' },
    ],
  },
]

export default function Sidebar() {
  const { user, hasPermission } = useAuth()

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <span className="sidebar-brand-icon">O</span>
        <span className="sidebar-brand-name">Operalia</span>
      </div>

      <nav className="sidebar-nav">
        {NAV_GROUPS.map((group, gi) => {
          const visibleItems = group.items.filter(item =>
            !item.permission || hasPermission(item.permission)
          )
          if (visibleItems.length === 0) return null
          return (
            <div key={gi} className="nav-group">
              {group.label && (
                <span className="nav-group-label">{group.label}</span>
              )}
              {visibleItems.map(item => (
                <NavLink
                  key={item.path}
                  to={item.path}
                  className={({ isActive }) =>
                    `nav-item ${isActive ? 'nav-item-active' : ''}`
                  }
                >
                  <item.icon size={16} className="nav-icon" />
                  <span className="nav-label">{item.label}</span>
                  <ChevronRight size={14} className="nav-arrow" />
                </NavLink>
              ))}
            </div>
          )
        })}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-user">
          <div className="sidebar-user-avatar">
            {user?.name?.[0]?.toUpperCase() ?? 'U'}
          </div>
          <div className="sidebar-user-info">
            <span className="sidebar-user-name">{user?.name ?? 'Usuario'}</span>
            <span className="sidebar-user-role">{user?.roleLabel ?? ''}</span>
          </div>
        </div>
      </div>
    </aside>
  )
}
