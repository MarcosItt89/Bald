/**
 * Rutas de la aplicación.
 *
 * - Cada página se carga bajo demanda (React.lazy) → el primer render es más
 *   ligero y cada módulo descarga su código solo al abrirlo.
 * - Cada ruta declara el permiso que requiere (mismo formato que el menú).
 * - IMPORTANTE para Vercel: vercel.json redirige todas las rutas a index.html;
 *   sin eso, recargar /inventory daba 404.
 */
import { lazy, Suspense } from 'react'
import { createBrowserRouter, Navigate } from 'react-router-dom'
import MainLayout from '../components/layout/MainLayout'
import { RequireAuth, RequireAccess } from './guards'
import { P } from '../config/permissions'
import RouteError from '../features/errors/RouteError'
import { Loader } from '../components/ui/Feedback'

const page = (loader) => lazy(loader)

const LoginPage            = page(() => import('../features/auth/LoginPage'))
const ResetPasswordPage    = page(() => import('../features/auth/ResetPasswordPage'))
const DashboardPage        = page(() => import('../features/dashboard/DashboardPage'))
const InventoryPage        = page(() => import('../features/inventory/InventoryPage'))
const PriceCheckPage       = page(() => import('../features/inventory/PriceCheckPage'))
const StockMovementsPage   = page(() => import('../features/inventory/StockMovementsPage'))
const WastePage            = page(() => import('../features/waste/WastePage'))
const ReceivingPage        = page(() => import('../features/receiving/ReceivingPage'))
const ReceivingDetailPage  = page(() => import('../features/receiving/ReceivingDetailPage'))
const ReceivingSummaryPage = page(() => import('../features/receiving/ReceivingSummaryPage'))
const SuppliersPage        = page(() => import('../features/suppliers/SuppliersPage'))
const SupplierAccessPage   = page(() => import('../features/suppliers/SupplierAccessPage'))
const OrdersPage           = page(() => import('../features/orders/OrdersPage'))
const PriceChangesPage     = page(() => import('../features/priceChanges/PriceChangesPage'))
const ShelfTagsPage        = page(() => import('../features/priceChanges/ShelfTagsPage'))
const ExpirationsPage      = page(() => import('../features/expirations/ExpirationsPage'))
const ChecklistsPage       = page(() => import('../features/checklists/ChecklistsPage'))
const ChecklistHistoryPage = page(() => import('../features/checklists/ChecklistHistoryPage'))
const ChecklistTemplatesPage = page(() => import('../features/checklists/ChecklistTemplatesPage'))
const EvidencePage         = page(() => import('../features/evidence/EvidencePage'))
const TasksPage            = page(() => import('../features/tasks/TasksPage'))
const ReportsPage          = page(() => import('../features/reports/ReportsPage'))
const BranchesPage         = page(() => import('../features/branches/BranchesPage'))
const DepartmentsPage      = page(() => import('../features/departments/DepartmentsPage'))
const ZonesPage            = page(() => import('../features/zones/ZonesPage'))
const CheckpointsPage      = page(() => import('../features/checkpoints/CheckpointsPage'))
const EmployeesPage        = page(() => import('../features/employees/EmployeesPage'))
const RolesPage            = page(() => import('../features/roles/RolesPage'))
const PermissionsPage      = page(() => import('../features/roles/PermissionsPage'))
const SupportPage          = page(() => import('../features/support/SupportPage'))
const TicketDetailPage     = page(() => import('../features/support/TicketDetailPage'))
const NewTicketPage        = page(() => import('../features/support/NewTicketPage'))
const NotFoundPage         = page(() => import('../features/errors/NotFoundPage'))

/** [ruta, componente, regla de acceso] — la regla usa { permission } o { anyOf }. */
const PROTECTED = [
  ['dashboard',            DashboardPage,          { permission: P.VIEW_DASHBOARD }],
  ['inventory',            InventoryPage,          { permission: P.VIEW_INVENTORY }],
  ['inventory/prices',     PriceCheckPage,         { permission: P.VIEW_PRICES }],
  ['inventory/movements',  StockMovementsPage,     { permission: P.VIEW_INVENTORY }],
  ['waste',                WastePage,              { permission: P.REGISTER_WASTE }],
  ['receiving',            ReceivingPage,          { permission: P.RECEIVE_PRODUCTS }],
  ['receiving/summary',    ReceivingSummaryPage,   { anyOf: [P.RECEIVE_PRODUCTS, P.VIEW_REPORTS] }],
  ['receiving/:id',        ReceivingDetailPage,    { anyOf: [P.RECEIVE_PRODUCTS, P.VIEW_REPORTS] }],
  ['suppliers',            SuppliersPage,          { permission: P.VIEW_SUPPLIERS }],
  ['supplier-access',      SupplierAccessPage,     { permission: P.REGISTER_SUPPLIER_VISIT }],
  ['orders',               OrdersPage,             { anyOf: [P.CREATE_ORDERS, P.APPROVE_ORDERS] }],
  ['price-changes',        PriceChangesPage,       { anyOf: [P.MANAGE_PRICE_CHANGES, P.VIEW_REPORTS] }],
  ['shelf-tags',           ShelfTagsPage,          { anyOf: [P.MANAGE_SHELF_TAGS, P.VALIDATE_SHELF_TAGS] }],
  ['expirations',          ExpirationsPage,        { permission: P.MANAGE_EXPIRATIONS }],
  ['checklists',           ChecklistsPage,         { anyOf: [P.FILL_CHECKLISTS, P.REVIEW_CHECKLISTS] }],
  ['checklists/history',   ChecklistHistoryPage,   { anyOf: [P.REVIEW_CHECKLISTS, P.VIEW_REPORTS] }],
  ['checklists/templates', ChecklistTemplatesPage, { permission: P.MANAGE_CHECKLIST_TEMPLATES }],
  ['checklists/checkpoints', CheckpointsPage,      { permission: P.MANAGE_CHECKPOINTS }],
  ['evidence',             EvidencePage,           { anyOf: [P.UPLOAD_EVIDENCE, P.REVIEW_EVIDENCE] }],
  ['tasks',                TasksPage,              { anyOf: [P.VIEW_TASKS, P.MANAGE_TASKS] }],
  ['reports',              ReportsPage,            { permission: P.VIEW_REPORTS }],
  ['branches',             BranchesPage,           { permission: P.MANAGE_BRANCHES }],
  ['departments',          DepartmentsPage,        { permission: P.MANAGE_BRANCHES }],
  ['zones',                ZonesPage,              { permission: P.MANAGE_BRANCHES }],
  ['employees',            EmployeesPage,          { permission: P.MANAGE_EMPLOYEES }],
  ['roles',                RolesPage,              { anyOf: [P.MANAGE_ROLES, P.MANAGE_EMPLOYEES] }],
  ['permissions',          PermissionsPage,        { permission: P.MANAGE_ROLES }],
  ['support',              SupportPage,            { anyOf: [P.CREATE_TICKETS, P.MANAGE_TICKETS] }],
  ['support/new',          NewTicketPage,          { anyOf: [P.CREATE_TICKETS] }],
  ['support/:id',          TicketDetailPage,       { anyOf: [P.CREATE_TICKETS, P.MANAGE_TICKETS] }],
]

export const router = createBrowserRouter([
  {
    path: '/login',
    element: <Suspense fallback={<Loader full />}><LoginPage /></Suspense>,
    errorElement: <RouteError />,
  },
  {
    path: '/reset-password',
    element: <Suspense fallback={<Loader full />}><ResetPasswordPage /></Suspense>,
    errorElement: <RouteError />,
  },
  {
    path: '/',
    element: <RequireAuth><MainLayout /></RequireAuth>,
    errorElement: <RouteError />,
    children: [
      { index: true, element: <Navigate to="/dashboard" replace /> },
      ...PROTECTED.map(([path, Component, rule]) => ({
        path,
        element: <RequireAccess item={rule}><Component /></RequireAccess>,
      })),
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])
