/** useToast() — devuelve { success, error, info } para mostrar mensajes. */
import { useContext } from 'react'
import { ToastContext } from '../contexts/toastContext'

export function useToast() {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast debe usarse dentro de <ToastProvider>')
  return ctx
}
