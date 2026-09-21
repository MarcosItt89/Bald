import { createContext, useContext, useState } from 'react'
import { MOCK_USERS, ROLES } from '../data/mockData'

// TODO: Replace mock login with supabase.auth.signInWithPassword() when Auth is ready
// TODO: Replace logout with supabase.auth.signOut()
// TODO: Derive permissions from employee record joined with role_permissions table

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [error, setError] = useState(null)

  const login = (email, password) => {
    const found = MOCK_USERS.find(u => u.email === email && u.password === password)
    if (!found) {
      setError('Correo o contraseña incorrectos')
      return false
    }
    const { password: _pw, ...safeUser } = found
    const roleData = ROLES[safeUser.role] ?? { label: safeUser.role, permissions: [] }
    setUser({ ...safeUser, roleLabel: roleData.label, permissions: roleData.permissions })
    setError(null)
    return true
  }

  const logout = () => setUser(null)

  const hasPermission = (permission) => user?.permissions?.includes(permission) ?? false

  return (
    <AuthContext.Provider value={{ user, error, login, logout, hasPermission }}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => useContext(AuthContext)
