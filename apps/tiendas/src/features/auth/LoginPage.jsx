/**
 * LoginPage — inicio de sesión con EMPRESA, USUARIO y contraseña.
 *
 * El empleado escribe el código de su empresa ("gatopelon"), su usuario
 * ("cajero") y su contraseña. useAuth().login lo convierte a
 * cajero@gatopelon.operalia.local para Supabase Auth. La empresa se recuerda
 * en el dispositivo. Un correo real (con @) entra sin empresa.
 *
 * Si ya hay sesión, redirige al inicio (o a la página que se intentaba abrir).
 *
 * Empresa recordada (link /e/<código> o un inicio anterior): el campo Empresa
 * se oculta y se muestran el logo y el nombre de la empresa, con «¿No es tu
 * empresa? Cambiar». Un correo real (con @) sigue entrando sin empresa.
 *
 * Marca (0028): con el código de empresa escrito se pide su marca pública
 * (get_company_branding) y se muestran su logo, su nombre y su color. Mientras
 * tanto se usa la última marca guardada en el dispositivo.
 */
import { useEffect, useState } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Eye, EyeOff, LogIn, AlertCircle, Settings } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { normalizeCompanyCode, readRememberedCompany, rememberCompany } from '@operalia/compartido/config/env.js'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import { useDebouncedValue } from '@operalia/compartido/hooks/useDebouncedValue.js'
import { getCompanyBranding } from '../../services/organizationService'
import { applyBrand, readSavedBrand } from '@operalia/compartido/theme/brand.js'
import ForgotPasswordModal from './ForgotPasswordModal'

export default function LoginPage() {
  const { login, status } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [company, setCompany] = useState(readRememberedCompany)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [forgotOpen, setForgotOpen] = useState(false)
  // Empresa ya conocida en este dispositivo → no se pide.
  const [askCompany, setAskCompany] = useState(() => !readRememberedCompany())
  const [brand, setBrand] = useState(() => {
    const saved = readSavedBrand()
    return saved && saved.code === readRememberedCompany() ? saved : null
  })
  const brandCode = useDebouncedValue(company)

  // Marca de la empresa escrita (o la de Operalia si no existe o está suspendida).
  useEffect(() => {
    if (status !== 'signedOut') return undefined
    if (brandCode.length < 2) { applyBrand(null); return undefined }
    let active = true
    getCompanyBranding(brandCode)
      .then((b) => {
        if (!active) return
        const next = b ? { code: brandCode, color: b.brand_color, logoUrl: b.logo_url, name: b.display_name || b.name } : null
        setBrand(next)
        applyBrand(next?.color)
      })
      .catch(() => {}) // sin marca: se queda la de Operalia
    return () => { active = false }
  }, [brandCode, status])
  const shownBrand = brand && brand.code === company ? brand : null
  const logo = shownBrand?.logoUrl || '/logo.svg'
  const companyName = shownBrand?.name ?? company
  const changeCompany = () => { setCompany(''); setAskCompany(true) }

  const redirectTo = location.state?.from ?? '/'
  if (status === 'signedIn') return <Navigate to={redirectTo} replace />

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    try {
      await login(company, username, password)
      if (!username.includes('@')) rememberCompany(normalizeCompanyCode(company))
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
          <img src={logo} alt="" width="64" height="64" className="login-logo-img" />
          <h1 className="login-brand-title">{shownBrand?.name ?? 'Operalia'}</h1>
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
            <img src={logo} alt={shownBrand?.name ?? 'Operalia'} width="48" height="48" className="login-form-logo" />
            {askCompany ? (
              <><h2>Iniciar sesión</h2><p>Ingresa tu empresa, usuario y contraseña</p></>
            ) : (
              <>
                <h2 className="login-company-name">{companyName}</h2>
                <p>Inicia sesión con tu usuario y contraseña</p>
                <button type="button" className="link-btn login-change-company" onClick={changeCompany}>¿No es tu empresa? Cambiar</button>
              </>
            )}
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
            {askCompany && (
              <div className="form-group">
                <label htmlFor="company" className="form-label">Empresa</label>
                <input id="company" className="form-input" placeholder="ej. gatopelon" value={company}
                  onChange={(e) => setCompany(normalizeCompanyCode(e.target.value))} required={!username.includes('@')}
                  autoFocus={!company} autoComplete="organization" autoCapitalize="none" spellCheck={false} />
              </div>
            )}

            <div className="form-group">
              <label htmlFor="username" className="form-label">Usuario</label>
              <input id="username" className="form-input" placeholder="ej. cajero" value={username}
                onChange={(e) => setUsername(e.target.value)} required autoFocus={!askCompany}
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
              disabled={(!company && !username.includes('@')) || !username || !password || status === 'misconfigured'}>
              {!loading && <LogIn size={16} />} Entrar
            </Button>
          </form>
          <button type="button" className="link-btn login-forgot" onClick={() => setForgotOpen(true)}>¿Olvidaste tu contraseña?</button>
          {forgotOpen && <ForgotPasswordModal open onClose={() => setForgotOpen(false)} initialCompany={company} companyName={askCompany ? null : companyName} initialValue={username} />}

        </div>
      </div>
    </div>
  )
}
