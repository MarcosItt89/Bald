/**
 * AuthProvider — sesión del usuario con Supabase Auth.
 *
 * Objetivo: saber en toda la app QUIÉN está conectado, QUÉ puede hacer
 * (permisos) y SOBRE QUÉ sucursal está trabajando.
 *
 * Flujo:
 *   1. Supabase emite INITIAL_SESSION / SIGNED_IN al montar o al iniciar sesión.
 *   2. Se llama a la función SQL get_my_profile() → empleado + rol + permisos.
 *   3. Si la cuenta no está ligada a un empleado activo → status 'noProfile'.
 *   4. Una vez al día se ejecuta run_daily_maintenance() (genera checklists del
 *      día, marca vencidos, aplica cambios de precio programados).
 *
 * La sesión persiste en localStorage (lo maneja supabase-js), por lo que
 * recargar la página ya NO cierra la sesión (error del prototipo anterior).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AuthContext } from './authContext'
import { supabase, unwrap, friendlyError } from '../lib/supabaseClient'
import { isSupabaseConfigured, usernameToEmail } from '../config/env'

const BRANCH_KEY = 'operalia.activeBranch'

const readStorage = (key) => {
  try { return localStorage.getItem(key) || null } catch { return null }
}
const writeStorage = (key, value) => {
  try { value ? localStorage.setItem(key, value) : localStorage.removeItem(key) } catch { /* modo privado */ }
}

/** Ejecuta el mantenimiento diario una sola vez por día y por navegador. */
async function runDailyMaintenance() {
  const key = `operalia.maintenance.${new Date().toDateString()}`
  try {
    if (sessionStorage.getItem(key)) return
    sessionStorage.setItem(key, '1')
  } catch { /* sin storage: se ejecuta igual, es idempotente */ }
  const { error } = await supabase.rpc('run_daily_maintenance')
  if (error) console.warn('[Operalia] Mantenimiento diario:', error.message)
}

export default function AuthProvider({ children }) {
  // status: 'loading' | 'signedOut' | 'signedIn' | 'noProfile' | 'error' | 'misconfigured'
  const [state, setState] = useState({
    status: isSupabaseConfigured ? 'loading' : 'misconfigured',
    session: null,
    profile: null,
    error: null,
  })
  const [activeBranchId, setActiveBranchIdState] = useState(() => readStorage(BRANCH_KEY))
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
      if (!profile) {
        setState({ status: 'noProfile', session, profile: null, error: null })
        return
      }
      setState({ status: 'signedIn', session, profile, error: null })
      runDailyMaintenance()
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

  const login = useCallback(async (identifier, password) => {
    const { error } = await supabase.auth.signInWithPassword({
      email: usernameToEmail(identifier),
      password,
    })
    if (error) {
      if (/invalid login credentials/i.test(error.message)) throw new Error('Usuario o contraseña incorrectos.')
      if (/email not confirmed/i.test(error.message)) {
        throw new Error('La cuenta no está confirmada. Desactiva "Confirm email" en Supabase o confirma el correo.')
      }
      throw new Error(friendlyError(error))
    }
    // Mientras llega el perfil, las rutas protegidas muestran "Cargando sesión…"
    // en lugar de rebotar a /login.
    setState((s) => ({ ...s, status: 'loading' }))
  }, [])

  const logout = useCallback(async () => {
    writeStorage(BRANCH_KEY, null)
    setActiveBranchIdState(null)
    await supabase.auth.signOut()
  }, [])

  const refreshProfile = useCallback(
    () => loadProfile(state.session, { force: true }),
    [loadProfile, state.session],
  )

  const setActiveBranchId = useCallback((id) => {
    writeStorage(BRANCH_KEY, id)
    setActiveBranchIdState(id || null)
  }, [])

  const value = useMemo(() => {
    const { profile } = state
    const permissions = new Set(profile?.permissions ?? [])
    const isCompanyScope = profile?.role_scope === 'company'
    const isZoneScope = profile?.role_scope === 'zone'
    // company y zone trabajan con varias sucursales (zone: solo las de sus zonas, lo asegura RLS).
    const isMultiBranch = isCompanyScope || isZoneScope
    // Sucursal usada para FILTRAR: multi-sucursal puede elegir (null = todas las visibles); el resto, la suya.
    const branchFilter = isMultiBranch ? activeBranchId : profile?.branch_id ?? null
    return {
      ...state,
      permissions,
      hasPermission: (p) => permissions.has(p),
      hasAny: (list) => list.some((p) => permissions.has(p)),
      isCompanyScope,
      isZoneScope,
      isMultiBranch,
      zoneIds: profile?.zone_ids ?? [],
      branchFilter,
      // Sucursal usada para CREAR registros (nunca null si el empleado tiene sucursal).
      workingBranchId: branchFilter ?? profile?.branch_id ?? null,
      activeBranchId,
      setActiveBranchId,
      login,
      logout,
      refreshProfile,
    }
  }, [state, activeBranchId, setActiveBranchId, login, logout, refreshProfile])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
