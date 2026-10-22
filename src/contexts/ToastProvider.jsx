/**
 * ToastProvider — mensajes breves de confirmación o error.
 *
 * Objetivo: dar retroalimentación inmediata tras guardar, aprobar, etc.
 * (el prototipo anterior no avisaba nada al usuario).
 *
 *   const toast = useToast()
 *   toast.success('Pedido creado')
 *   toast.error(err.message)
 */
import { useCallback, useMemo, useState } from 'react'
import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react'
import { ToastContext } from './toastContext'

const ICONS = { success: CheckCircle2, error: AlertCircle, info: Info }
let nextId = 1

export default function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([])

  const dismiss = useCallback((id) => setToasts((list) => list.filter((t) => t.id !== id)), [])

  const push = useCallback((type, message, duration = 4000) => {
    const id = nextId++
    setToasts((list) => [...list.slice(-3), { id, type, message }]) // máximo 4 visibles
    setTimeout(() => dismiss(id), type === 'error' ? duration + 2000 : duration)
  }, [dismiss])

  const api = useMemo(() => ({
    success: (m) => push('success', m),
    error: (m) => push('error', m),
    info: (m) => push('info', m),
  }), [push])

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="toast-stack" role="status" aria-live="polite">
        {toasts.map((t) => {
          const Icon = ICONS[t.type]
          return (
            <div key={t.id} className={`toast toast-${t.type}`}>
              <Icon size={16} />
              <span>{t.message}</span>
              <button className="toast-close" onClick={() => dismiss(t.id)} aria-label="Cerrar">
                <X size={14} />
              </button>
            </div>
          )
        })}
      </div>
    </ToastContext.Provider>
  )
}
