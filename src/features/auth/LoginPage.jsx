import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Eye, EyeOff, LogIn, AlertCircle } from 'lucide-react'
import { useAuth } from '../../contexts/AuthContext'

export default function LoginPage() {
  const { login, error } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    const ok = login(email.trim(), password)
    setLoading(false)
    if (ok) navigate('/dashboard')
  }

  return (
    <div className="login-page">
      {/* Panel izquierdo — branding */}
      <div className="login-brand">
        <div className="login-brand-content">
          <div className="login-logo">O</div>
          <h1 className="login-brand-title">Operalia</h1>
          <p className="login-brand-subtitle">
            Plataforma operativa modular para empresas con sucursales
          </p>
          <ul className="login-feature-list">
            <li>Inventario y consulta de precios</li>
            <li>Recibo de mercancía y proveedores</li>
            <li>Checklists y evidencias diarias</li>
            <li>Reportes y cambios de precio</li>
          </ul>
        </div>
      </div>

      {/* Panel derecho — formulario */}
      <div className="login-form-panel">
        <div className="login-form-card">
          <div className="login-form-header">
            <h2>Bienvenido de vuelta</h2>
            <p>Ingresa tus credenciales para continuar</p>
          </div>

          {error && (
            <div className="login-error">
              <AlertCircle size={16} />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="login-form" noValidate>
            <div className="form-group">
              <label htmlFor="email" className="form-label">Correo electrónico</label>
              <input
                id="email"
                type="email"
                className="form-input"
                placeholder="empleado@empresa.mx"
                value={email}
                onChange={e => setEmail(e.target.value)}
                required
                autoFocus
                autoComplete="email"
              />
            </div>

            <div className="form-group">
              <label htmlFor="password" className="form-label">Contraseña</label>
              <div className="input-with-icon">
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  className="form-input"
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                />
                <button
                  type="button"
                  className="input-icon-btn"
                  onClick={() => setShowPassword(p => !p)}
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              className="btn btn-primary btn-block"
              disabled={loading || !email || !password}
            >
              {loading ? (
                <span className="spinner-sm" />
              ) : (
                <>
                  <LogIn size={16} />
                  Iniciar sesión
                </>
              )}
            </button>
          </form>

          {/* Credenciales de demo */}
          <div className="login-demo">
            <p className="login-demo-title">Cuentas de demostración</p>
            <div className="login-demo-grid">
              {[
                { role: 'Admin',      email: 'admin@operalia.mx',     pwd: 'admin123'     },
                { role: 'Gerente',    email: 'gerente@operalia.mx',   pwd: 'gerente123'   },
                { role: 'Recibo',     email: 'recibo@operalia.mx',    pwd: 'recibo123'    },
                { role: 'Cajas',      email: 'caja@operalia.mx',      pwd: 'caja123'      },
                { role: 'Abarrotes',  email: 'abarrotes@operalia.mx', pwd: 'abarrotes123' },
                { role: 'Escáner',    email: 'escaner@operalia.mx',   pwd: 'escaner123'   },
              ].map(u => (
                <button
                  key={u.role}
                  type="button"
                  className="demo-btn"
                  onClick={() => { setEmail(u.email); setPassword(u.pwd) }}
                >
                  {u.role}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
