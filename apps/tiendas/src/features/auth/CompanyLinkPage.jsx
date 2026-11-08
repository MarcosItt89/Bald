/**
 * CompanyLinkPage — ruta pública /e/:codigo (link o QR de la empresa).
 *
 * Pide la marca pública de la empresa (get_company_branding). Si existe y está
 * activa: recuerda el código en el dispositivo, aplica su marca y manda a
 * /login, donde el empleado ya no escribe la empresa. Si no existe (o está
 * suspendida) solo dice «Empresa no encontrada», sin más detalles.
 *
 * Con sesión iniciada no cambia nada: manda al inicio.
 */
import { useEffect, useState } from 'react'
import { Link, Navigate, useNavigate, useParams } from 'react-router-dom'
import { Building2, WifiOff } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { normalizeCompanyCode, rememberCompany } from '@operalia/compartido/config/env.js'
import { getCompanyBranding } from '../../services/organizationService'
import { applyBrand, saveBrand } from '@operalia/compartido/theme/brand.js'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'

export default function CompanyLinkPage() {
  const { codigo } = useParams()
  const { status } = useAuth()
  const navigate = useNavigate()
  const [result, setResult] = useState('loading') // loading | notFound | offline
  const code = normalizeCompanyCode(codigo)

  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    if (!code || status === 'loading' || status === 'signedIn') return undefined
    let active = true
    getCompanyBranding(code)
      .then((b) => {
        if (!active) return
        if (!b) { setResult('notFound'); return }
        rememberCompany(code)
        saveBrand({ code, color: b.brand_color, logoUrl: b.logo_url, name: b.display_name || b.name })
        applyBrand(b.brand_color)
        navigate('/login', { replace: true })
      })
      .catch(() => { if (active) setResult('offline') })
    return () => { active = false }
  }, [code, status, attempt, navigate])
  const retry = () => { setResult('loading'); setAttempt((n) => n + 1) }

  if (status === 'signedIn') return <Navigate to="/" replace />
  const shown = code ? result : 'notFound'
  if (shown === 'loading') return <Loader full text="Abriendo…" />

  return (
    <div className="company-link-page">
      <div className="company-link-card">
        {shown === 'notFound'
          ? <><Building2 size={36} /><h1>Empresa no encontrada</h1><p>Revisa el link o pide uno nuevo a tu encargado.</p></>
          : <><WifiOff size={36} /><h1>No se pudo abrir el link</h1><p>Revisa tu conexión e inténtalo de nuevo.</p>
            <Button onClick={retry}>Reintentar</Button></>}
        <Link to="/login" className="company-link-login">Ir al inicio de sesión</Link>
      </div>
    </div>
  )
}
