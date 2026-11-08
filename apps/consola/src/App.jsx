import { RouterProvider } from 'react-router-dom'
import ToastProvider from '@operalia/compartido/contexts/ToastProvider.jsx'
import ConsolaAuthProvider from './auth/ConsolaAuthProvider'
import { router } from './router'

export default function App() {
  return (
    <ToastProvider>
      <ConsolaAuthProvider>
        <RouterProvider router={router} />
      </ConsolaAuthProvider>
    </ToastProvider>
  )
}
