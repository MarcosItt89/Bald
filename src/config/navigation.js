/**
 * Menú lateral de Operalia.
 *
 * Objetivo: definir en UN solo lugar qué opciones existen y qué permiso
 * requiere cada una. El Sidebar oculta las que el usuario no puede usar y
 * el router (src/app/router.jsx) protege las mismas rutas con el mismo
 * permiso, así no se puede entrar escribiendo la URL (error del prototipo).
 *
 *   permission: un permiso requerido
 *   anyOf:      basta con tener uno de la lista
 */
import {
  LayoutDashboard, Package, Tag, ArrowLeftRight, Truck, ClipboardCheck, ShoppingCart,
  DollarSign, Tags, CalendarClock, CheckSquare, Camera, ListTodo, Building, DoorOpen,
  BarChart3, Building2, Layers, Users, Shield, KeyRound, LifeBuoy, History, FileSpreadsheet,
} from 'lucide-react'
import { P } from './permissions'

export const NAV_GROUPS = [
  {
    label: null,
    items: [
      { icon: LayoutDashboard, label: 'Dashboard', path: '/dashboard', permission: P.VIEW_DASHBOARD },
    ],
  },
  {
    label: 'Inventario',
    items: [
      { icon: Package,        label: 'Inventario',          path: '/inventory',           permission: P.VIEW_INVENTORY },
      { icon: Tag,            label: 'Consulta de precios', path: '/inventory/prices',    permission: P.VIEW_PRICES },
      { icon: ArrowLeftRight, label: 'Movimientos',         path: '/inventory/movements', permission: P.VIEW_INVENTORY },
    ],
  },
  {
    label: 'Recibo y proveedores',
    items: [
      { icon: Truck,           label: 'Recibo de mercancía', path: '/receiving',         permission: P.RECEIVE_PRODUCTS },
      { icon: FileSpreadsheet, label: 'Resumen de recibos',  path: '/receiving/summary', anyOf: [P.RECEIVE_PRODUCTS, P.VIEW_REPORTS] },
      { icon: DoorOpen,        label: 'Accesos proveedores', path: '/supplier-access',   permission: P.REGISTER_SUPPLIER_VISIT },
      { icon: Building,        label: 'Proveedores',         path: '/suppliers',         permission: P.VIEW_SUPPLIERS },
    ],
  },
  {
    label: 'Precios',
    items: [
      { icon: DollarSign, label: 'Cambios de precio', path: '/price-changes', anyOf: [P.MANAGE_PRICE_CHANGES, P.VIEW_REPORTS] },
      { icon: Tags,       label: 'Cenefas',           path: '/shelf-tags',    anyOf: [P.MANAGE_SHELF_TAGS, P.VALIDATE_SHELF_TAGS] },
    ],
  },
  {
    label: 'Operación diaria',
    items: [
      { icon: CheckSquare,    label: 'Checklists',        path: '/checklists',         anyOf: [P.FILL_CHECKLISTS, P.REVIEW_CHECKLISTS] },
      { icon: History,        label: 'Historial',         path: '/checklists/history', anyOf: [P.REVIEW_CHECKLISTS, P.VIEW_REPORTS] },
      { icon: ListTodo,       label: 'Tareas',            path: '/tasks',              anyOf: [P.VIEW_TASKS, P.MANAGE_TASKS] },
      { icon: ShoppingCart,   label: 'Pedidos internos',  path: '/orders',             anyOf: [P.CREATE_ORDERS, P.APPROVE_ORDERS] },
      { icon: CalendarClock,  label: 'Caducidades',       path: '/expirations',        permission: P.MANAGE_EXPIRATIONS },
      { icon: Camera,         label: 'Evidencias',        path: '/evidence',           anyOf: [P.UPLOAD_EVIDENCE, P.REVIEW_EVIDENCE] },
    ],
  },
  {
    label: 'Análisis',
    items: [
      { icon: BarChart3, label: 'Reportes', path: '/reports', permission: P.VIEW_REPORTS },
    ],
  },
  {
    label: 'Configuración',
    items: [
      { icon: ClipboardCheck, label: 'Plantillas checklist', path: '/checklists/templates', permission: P.MANAGE_CHECKLIST_TEMPLATES },
      { icon: Building2, label: 'Sucursales',    path: '/branches',    permission: P.MANAGE_BRANCHES },
      { icon: Layers,    label: 'Departamentos', path: '/departments', permission: P.MANAGE_BRANCHES },
      { icon: Users,     label: 'Empleados',     path: '/employees',   permission: P.MANAGE_EMPLOYEES },
      { icon: Shield,    label: 'Roles',         path: '/roles',       anyOf: [P.MANAGE_ROLES, P.MANAGE_EMPLOYEES] },
      { icon: KeyRound,  label: 'Permisos',      path: '/permissions', permission: P.MANAGE_ROLES },
    ],
  },
  {
    label: 'Ayuda',
    items: [
      { icon: LifeBuoy, label: 'Soporte', path: '/support', anyOf: [P.CREATE_TICKETS, P.MANAGE_TICKETS] },
    ],
  },
]

/** ¿El usuario puede ver este ítem? (misma regla para menú y rutas) */
export const canAccess = (item, { hasPermission, hasAny }) =>
  item.permission ? hasPermission(item.permission) : item.anyOf ? hasAny(item.anyOf) : true
