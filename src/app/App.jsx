/**
 * App — raíz de la aplicación.
 *
 * Orden de proveedores:
 *   ToastProvider  → mensajes emergentes disponibles en todas partes
 *   AuthProvider   → sesión de Supabase, perfil y permisos
 *   RouterProvider → rutas (src/app/router.jsx)
 */
import { RouterProvider } from 'react-router-dom'
import AuthProvider from '../contexts/AuthProvider'
import ToastProvider from '../contexts/ToastProvider'
import { router } from './router'

export default function App() {
  return (
    <ToastProvider>
      <AuthProvider>
        <RouterProvider router={router} />
      </AuthProvider>
    </ToastProvider>
  )
}
