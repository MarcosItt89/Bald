/**
 * useAuth() — acceso a la sesión desde cualquier componente.
 *
 *   const { profile, hasPermission, branchFilter, logout } = useAuth()
 *
 * Ver src/contexts/AuthProvider.jsx para la descripción de cada campo.
 */
import { useContext } from 'react'
import { AuthContext } from '../contexts/authContext'

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth debe usarse dentro de <AuthProvider>')
  return ctx
}
