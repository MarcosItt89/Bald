/**
 * MainLayout — estructura de todas las páginas internas:
 * Sidebar (menú) + Topbar (barra superior) + contenido de la ruta (<Outlet/>).
 *
 * - En escritorio el botón ☰ colapsa el menú.
 * - En celular el menú se abre encima del contenido y se cierra al navegar.
 * - <Suspense> muestra un loader mientras se descarga el código de la página
 *   (las páginas se cargan bajo demanda con React.lazy, ver router.jsx).
 */
import { Suspense, useState } from 'react'
import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import Topbar from './Topbar'
import { Loader } from '../ui/Feedback'

const isMobile = () => window.matchMedia('(max-width: 900px)').matches

export default function MainLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(() => !isMobile())

  return (
    <div className={`app-shell ${sidebarOpen ? 'sidebar-open' : 'sidebar-collapsed'}`}>
      <Sidebar onNavigate={() => { if (isMobile()) setSidebarOpen(false) }} />
      {sidebarOpen && <div className="sidebar-backdrop" onClick={() => setSidebarOpen(false)} />}
      <div className="main-area">
        <Topbar onMenuToggle={() => setSidebarOpen((open) => !open)} />
        <main className="page-content">
          <Suspense fallback={<Loader />}>
            <Outlet />
          </Suspense>
        </main>
      </div>
    </div>
  )
}
