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
 *   when:       bandera de useAuth() que debe ser verdadera (ej. 'canManageRoles')
 */
import {
  LayoutDashboard, Package, Tag, ArrowLeftRight, Truck, ClipboardCheck, ShoppingCart,
  DollarSign, Tags, CalendarClock, CheckSquare, Camera, ListTodo, Building, DoorOpen,
  BarChart3, Building2, Layers, Users, Shield, KeyRound, LifeBuoy, History, FileSpreadsheet, Trash2, Map as MapIcon, QrCode, ClipboardList, PackageSearch, Megaphone,
  Globe, CirclePlus, Headset, Activity, Handshake,
} from 'lucide-react'
import { P } from './permissions'

export const NAV_GROUPS = [
  {
    label: null,
    items: [
      { icon: LayoutDashboard, label: 'Dashboard', path: '/dashboard', permission: P.VIEW_DASHBOARD },
      { icon: Megaphone,       label: 'Comunicados', path: '/announcements' },
    ],
  },
  {
    label: 'Inventario',
    items: [
      { icon: Package,        label: 'Inventario',          path: '/inventory',           permission: P.VIEW_INVENTORY },
      { icon: Tag,            label: 'Consulta de precios', path: '/inventory/prices',    permission: P.VIEW_PRICES },
      { icon: ArrowLeftRight, label: 'Movimientos',         path: '/inventory/movements', permission: P.VIEW_INVENTORY },
      { icon: Trash2,         label: 'Mermas',              path: '/waste',               permission: P.REGISTER_WASTE },
      { icon: ClipboardList,  label: 'Conteo cíclico',      path: '/inventory/cycle-counts', anyOf: [P.PERFORM_CYCLE_COUNTS, P.MANAGE_CYCLE_COUNTS] },
      { icon: PackageSearch,  label: 'Huecos en anaquel',   path: '/inventory/shelf-gaps', anyOf: [P.REPORT_SHELF_GAPS, P.MANAGE_SHELF_GAPS] },
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
      { icon: BarChart3, label: 'Estadísticas', path: '/reports', permission: P.VIEW_REPORTS },
    ],
  },
  {
    label: 'Configuración',
    items: [
      { icon: ClipboardCheck, label: 'Plantillas checklist', path: '/checklists/templates', permission: P.MANAGE_CHECKLIST_TEMPLATES },
      { icon: QrCode,         label: 'Puntos QR',            path: '/checklists/checkpoints', permission: P.MANAGE_CHECKPOINTS },
      { icon: Building2, label: 'Sucursales',    path: '/branches',    permission: P.MANAGE_BRANCHES },
      { icon: MapIcon,   label: 'Zonas',         path: '/zones',       permission: P.MANAGE_BRANCHES },
      { icon: Layers,    label: 'Departamentos', path: '/departments', permission: P.MANAGE_BRANCHES },
      { icon: Users,     label: 'Empleados',     path: '/employees',   permission: P.MANAGE_EMPLOYEES },
      { icon: Shield,    label: 'Roles',         path: '/roles',       when: 'canManageRoles' },
      { icon: KeyRound,  label: 'Permisos',      path: '/permissions', when: 'canManageRoles' },
    ],
  },
  {
    label: 'Ayuda',
    items: [
      { icon: LifeBuoy, label: 'Soporte', path: '/support', anyOf: [P.CREATE_TICKETS, P.MANAGE_TICKETS] },
    ],
  },
  {
    // Solo superadmins (tabla platform_admins): empresas cliente, su rendimiento, prospectos y soporte de todas las tiendas.
    label: 'Plataforma',
    items: [
      { icon: Globe,      label: 'Empresas',           path: '/plataforma',             when: 'isPlatformAdmin' },
      { icon: Activity,   label: 'Rendimiento',        path: '/plataforma/rendimiento', when: 'isPlatformAdmin' },
      { icon: Handshake,  label: 'Prospectos',         path: '/plataforma/prospectos',  when: 'isPlatformAdmin' },
      { icon: CirclePlus, label: 'Nueva empresa',      path: '/plataforma/nueva',       when: 'isPlatformAdmin' },
      { icon: Headset,    label: 'Soporte de tiendas', path: '/plataforma/soporte',     when: 'isPlatformAdmin' },
    ],
  },
]

/** ¿El usuario puede ver este ítem? (misma regla para menú y rutas) */
export const canAccess = (item, auth) =>
  (!item.when || Boolean(auth[item.when]))
  && (item.permission ? auth.hasPermission(item.permission) : item.anyOf ? auth.hasAny(item.anyOf) : true)
