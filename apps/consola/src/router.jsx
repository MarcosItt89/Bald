/**
 * Rutas de la Consola Operalia. Todas exigen superadmin (RequireConsola);
 * /login es pública. Las páginas se cargan bajo demanda.
 * La app de tiendas monta estas mismas páginas bajo /plataforma (transitorio).
 */
import { lazy, Suspense } from 'react'
import { createBrowserRouter } from 'react-router-dom'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import RequireConsola from './auth/RequireConsola'
import ConsolaLayout from './layout/ConsolaLayout'

const page = (loader) => lazy(loader)

const LoginPage             = page(() => import('./auth/LoginPage'))
const PlatformCompaniesPage = page(() => import('./pages/PlatformCompaniesPage'))
const NewCompanyPage        = page(() => import('./pages/NewCompanyPage'))
const PerformancePage       = page(() => import('./pages/PerformancePage'))
const LeadsPage             = page(() => import('./pages/LeadsPage'))
const PlatformSupportPage   = page(() => import('./pages/PlatformSupportPage'))
const PlatformTicketPage    = page(() => import('./pages/PlatformTicketPage'))
const BrandPage             = page(() => import('./pages/BrandPage'))
const NotFoundPage          = page(() => import('./pages/NotFoundPage'))

export const router = createBrowserRouter([
  { path: '/login', element: <Suspense fallback={<Loader full />}><LoginPage /></Suspense> },
  {
    path: '/',
    element: <RequireConsola><ConsolaLayout /></RequireConsola>,
    children: [
      { index: true, element: <PlatformCompaniesPage /> },
      { path: 'nueva', element: <NewCompanyPage /> },
      { path: 'rendimiento', element: <PerformancePage /> },
      { path: 'prospectos', element: <LeadsPage /> },
      { path: 'soporte', element: <PlatformSupportPage /> },
      { path: 'soporte/:id', element: <PlatformTicketPage /> },
      { path: 'marca', element: <BrandPage /> },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
])
