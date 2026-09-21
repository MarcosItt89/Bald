import { useState } from 'react'
import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import Topbar from './Topbar'

export default function MainLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(true)

  return (
    <div className={`app-shell ${sidebarOpen ? '' : 'sidebar-collapsed'}`}>
      <Sidebar />
      <div className="main-area">
        <Topbar onMenuToggle={() => setSidebarOpen(p => !p)} />
        <main className="page-content">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
