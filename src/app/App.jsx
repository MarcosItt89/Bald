import { createBrowserRouter, RouterProvider } from 'react-router-dom'
import { AuthProvider } from '../contexts/AuthContext'
import { appRoutes } from './routes'

const router = createBrowserRouter(appRoutes)

export default function App() {
  return (
    <AuthProvider>
      <RouterProvider router={router} />
    </AuthProvider>
  )
}
