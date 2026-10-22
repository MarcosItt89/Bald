/**
 * LoginPage — inicio de sesión con USUARIO y contraseña.
 *
 * El usuario escribe "gatopelon" (no un correo). useAuth().login lo convierte
 * a gatopelon@operalia.local para Supabase Auth. También acepta un correo
 * completo por si en el futuro se usan correos reales.
 *
 * Si ya hay sesión, redirige al dashboard (o a la página que se intentaba abrir).
 */
import { useState } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Eye, EyeOff, LogIn, AlertCircle, Settings } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import Button from '../../components/ui/Button'
import ForgotPasswordModal from './ForgotPasswordModal'

export default function LoginPage() {
  const { login, status } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [forgotOpen, setForgotOpen] = useState(false)

  const redirectTo = location.state?.from ?? '/dashboard'
  if (status === 'signedIn') return <Navigate to={redirectTo} replace />

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      await login(username, password)
      navigate(redirectTo, { replace: true })
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="login-page">
      <div className="login-brand">
        <div className="login-brand-content">
          <img src="/logo.svg" alt="" width="64" height="64" className="login-logo-img" />
          <h1 className="login-brand-title">Operalia</h1>
          <p className="login-brand-subtitle">
            Plataforma operativa modular para empresas con sucursales: cada acción con quién, cuándo, dónde y con qué evidencia.
          </p>
          <ul className="login-feature-list">
            <li>Inventario, consulta de precios y movimientos</li>
            <li>Recibo de mercancía y control de proveedores</li>
            <li>Checklists con evidencia fotográfica</li>
            <li>Cambios de precio, cenefas y caducidades</li>
            <li>Mesa de ayuda para soporte interno</li>
          </ul>
        </div>
      </div>

      <div className="login-form-panel">
        <div className="login-form-card">
          <div className="login-form-header">
            <img src="/logo.svg" alt="Operalia" width="48" height="48" className="login-form-logo" />
            <h2>Iniciar sesión</h2>
            <p>Ingresa tu usuario y contraseña</p>
          </div>

          {status === 'misconfigured' && (
            <div className="login-error">
              <Settings size={16} />
              <span>Falta configurar Supabase: define VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY en .env</span>
            </div>
          )}
          {error && (
            <div className="login-error"><AlertCircle size={16} /><span>{error}</span></div>
          )}

          <form onSubmit={handleSubmit} className="login-form">
            <div className="form-group">
              <label htmlFor="username" className="form-label">Usuario</label>
              <input id="username" className="form-input" placeholder="ej. gatopelon" value={username}
                onChange={(e) => setUsername(e.target.value)} required autoFocus
                autoComplete="username" autoCapitalize="none" spellCheck={false} />
            </div>

            <div className="form-group">
              <label htmlFor="password" className="form-label">Contraseña</label>
              <div className="input-with-icon">
                <input id="password" type={showPassword ? 'text' : 'password'} className="form-input"
                  placeholder="••••••••" value={password} onChange={(e) => setPassword(e.target.value)}
                  required autoComplete="current-password" />
                <button type="button" className="input-icon-btn" onClick={() => setShowPassword((p) => !p)}
                  aria-label={showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'}>
                  {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            <Button type="submit" className="btn-block" loading={loading}
              disabled={!username || !password || status === 'misconfigured'}>
              {!loading && <LogIn size={16} />} Entrar
            </Button>
          </form>
          <button type="button" className="link-btn login-forgot" onClick={() => setForgotOpen(true)}>¿Olvidaste tu contraseña?</button>
          {forgotOpen && <ForgotPasswordModal open onClose={() => setForgotOpen(false)} initialValue={username} />}

        </div>
      </div>
    </div>
  )
}
