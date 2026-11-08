/**
 * LoginPage — inicio de sesión de la Consola con correo y contraseña.
 * Solo los superadmins pasan; los demás ven «Sin acceso» después de entrar.
 */
import { useState } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { AlertCircle, LogIn, Settings } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import Button from '@operalia/compartido/components/ui/Button.jsx'

export default function LoginPage() {
  const { login, status } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const redirectTo = location.state?.from ?? '/'

  if (status === 'signedIn' || status === 'noAccess') return <Navigate to={redirectTo} replace />

  const submit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      await login(email, password)
      navigate(redirectTo, { replace: true })
    } catch (err) { setError(err.message) } finally { setLoading(false) }
  }

  return (
    <div className="consola-auth">
      <div className="consola-auth-card">
        <div className="consola-auth-header">
          <img src="/logo.svg" alt="" width="44" height="44" />
          <div><h1>Consola Operalia</h1><p>Solo para superadmins de la plataforma</p></div>
        </div>
        {status === 'misconfigured' && (
          <div className="login-error"><Settings size={16} /><span>Falta configurar Supabase: define VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY.</span></div>
        )}
        {error && <div className="login-error"><AlertCircle size={16} /><span>{error}</span></div>}
        <form onSubmit={submit} className="login-form">
          <div className="form-group">
            <label htmlFor="email" className="form-label">Correo</label>
            <input id="email" type="email" className="form-input" value={email} onChange={(e) => setEmail(e.target.value)}
              required autoFocus autoComplete="username" autoCapitalize="none" spellCheck={false} placeholder="tu@correo.com" />
          </div>
          <div className="form-group">
            <label htmlFor="password" className="form-label">Contraseña</label>
            <input id="password" type="password" className="form-input" value={password} onChange={(e) => setPassword(e.target.value)}
              required autoComplete="current-password" />
          </div>
          <Button type="submit" className="btn-block" loading={loading} disabled={!email || !password || status === 'misconfigured'}>
            {!loading && <LogIn size={16} />} Entrar
          </Button>
        </form>
      </div>
    </div>
  )
}
