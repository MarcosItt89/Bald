import { Navigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import MainLayout from '../components/layout/MainLayout'

import LoginPage              from '../features/auth/LoginPage'
import DashboardPage          from '../features/dashboard/DashboardPage'
import BranchesPage           from '../features/branches/BranchesPage'
import DepartmentsPage        from '../features/departments/DepartmentsPage'
import EmployeesPage          from '../features/employees/EmployeesPage'
import RolesPage              from '../features/roles/RolesPage'
import PermissionsPage        from '../features/roles/PermissionsPage'
import InventoryPage          from '../features/inventory/InventoryPage'
import PriceCheckPage         from '../features/inventory/PriceCheckPage'
import StockMovementsPage     from '../features/inventory/StockMovementsPage'
import SuppliersPage          from '../features/suppliers/SuppliersPage'
import SupplierAccessPage     from '../features/suppliers/SupplierAccessPage'
import ReceivingPage          from '../features/receiving/ReceivingPage'
import ReceivingSummaryPage   from '../features/receiving/ReceivingSummaryPage'
import ChecklistsPage         from '../features/checklists/ChecklistsPage'
import ChecklistHistoryPage   from '../features/checklists/ChecklistHistoryPage'
import EvidencePage           from '../features/evidence/EvidencePage'
import OrdersPage             from '../features/orders/OrdersPage'
import PriceChangesPage       from '../features/priceChanges/PriceChangesPage'
import ShelfTagsPage          from '../features/priceChanges/ShelfTagsPage'
import TasksPage              from '../features/tasks/TasksPage'
import ReportsPage            from '../features/reports/ReportsPage'
import ExpirationsPage        from '../features/expirations/ExpirationsPage'

function ProtectedRoute({ children }) {
  const { user } = useAuth()
  if (!user) return <Navigate to="/login" replace />
  return children
}

export const appRoutes = [
  {
    path: '/login',
    element: <LoginPage />,
  },
  {
    path: '/',
    element: (
      <ProtectedRoute>
        <MainLayout />
      </ProtectedRoute>
    ),
    children: [
      { index: true,                     element: <Navigate to="/dashboard" replace /> },
      { path: 'dashboard',               element: <DashboardPage /> },
      { path: 'inventory',               element: <InventoryPage /> },
      { path: 'inventory/prices',        element: <PriceCheckPage /> },
      { path: 'inventory/movements',     element: <StockMovementsPage /> },
      { path: 'receiving',               element: <ReceivingPage /> },
      { path: 'receiving/summary',       element: <ReceivingSummaryPage /> },
      { path: 'orders',                  element: <OrdersPage /> },
      { path: 'price-changes',           element: <PriceChangesPage /> },
      { path: 'shelf-tags',              element: <ShelfTagsPage /> },
      { path: 'expirations',             element: <ExpirationsPage /> },
      { path: 'checklists',              element: <ChecklistsPage /> },
      { path: 'checklists/history',      element: <ChecklistHistoryPage /> },
      { path: 'evidence',                element: <EvidencePage /> },
      { path: 'tasks',                   element: <TasksPage /> },
      { path: 'suppliers',               element: <SuppliersPage /> },
      { path: 'supplier-access',         element: <SupplierAccessPage /> },
      { path: 'reports',                 element: <ReportsPage /> },
      { path: 'branches',                element: <BranchesPage /> },
      { path: 'departments',             element: <DepartmentsPage /> },
      { path: 'employees',               element: <EmployeesPage /> },
      { path: 'roles',                   element: <RolesPage /> },
      { path: 'permissions',             element: <PermissionsPage /> },
      { path: '*',                       element: <Navigate to="/dashboard" replace /> },
    ],
  },
]
