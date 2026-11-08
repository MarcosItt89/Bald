/**
 * Sesión de la Consola Operalia (Supabase Auth, la misma base que tiendas).
 *
 * Entra con correo y contraseña. Después pide get_my_profile() y solo deja
 * pasar a superadmins (is_platform_admin); cualquier otra cuenta queda en
 * status 'noAccess' y ve «Sin acceso». La seguridad real está en la base:
 * todas las funciones platform_* validan is_platform_admin() por su cuenta.
 *
 * status: 'loading' | 'signedOut' | 'signedIn' | 'noAccess' | 'error' | 'misconfigured'
 * Comparte AuthContext con el paquete compartido, así useAuth() funciona igual.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AuthContext } from '@operalia/compartido/contexts/authContext.js'
import { supabase, unwrap, friendlyError } from '@operalia/compartido/lib/supabaseClient.js'
import { isSupabaseConfigured } from '@operalia/compartido/config/env.js'

export default function ConsolaAuthProvider({ children }) {
  const [state, setState] = useState({
    status: isSupabaseConfigured ? 'loading' : 'misconfigured', session: null, profile: null, error: null,
  })
  const loadedUserRef = useRef(null)

  const loadProfile = useCallback(async (session, { force = false } = {}) => {
    if (!session) {
      loadedUserRef.current = null
      setState({ status: 'signedOut', session: null, profile: null, error: null })
      return
    }
    if (!force && loadedUserRef.current === session.user.id) {
      setState((s) => ({ ...s, session })) // solo refresco de token
      return
    }
    try {
      const profile = await unwrap(supabase.rpc('get_my_profile'))
      loadedUserRef.current = session.user.id
      setState({ status: profile?.is_platform_admin ? 'signedIn' : 'noAccess', session, profile: profile ?? null, error: null })
    } catch (err) {
      setState({ status: 'error', session, profile: null, error: err.message })
    }
  }, [])

  useEffect(() => {
    if (!supabase) return undefined
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_OUT') {
        loadedUserRef.current = null
        setState({ status: 'signedOut', session: null, profile: null, error: null })
        return
      }
      // setTimeout: supabase-js recomienda no llamar a la API dentro del callback.
      setTimeout(() => loadProfile(session), 0)
    })
    return () => data.subscription.unsubscribe()
  }, [loadProfile])

  const login = useCallback(async (email, password) => {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim().toLowerCase(), password })
    if (error) {
      if (/invalid login credentials/i.test(error.message)) throw new Error('Correo o contraseña incorrectos.')
      throw new Error(friendlyError(error))
    }
    setState((s) => ({ ...s, status: 'loading' }))
  }, [])

  const logout = useCallback(async () => { await supabase.auth.signOut() }, [])
  const refreshProfile = useCallback(() => loadProfile(state.session, { force: true }), [loadProfile, state.session])

  const value = useMemo(() => ({
    ...state,
    login,
    logout,
    refreshProfile,
    isPlatformAdmin: state.status === 'signedIn',
  }), [state, login, logout, refreshProfile])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
