/**
 * PlatformMovedPage — /plataforma/* (pública).
 * La plataforma de superadmin se movió a la Consola Operalia (apps/consola).
 * Muestra el aviso y el link a la misma página en la Consola:
 * /plataforma/soporte/123 → <consola>/soporte/123. El link sale de
 * VITE_CONSOLA_URL; si no está definida, solo se muestra el aviso.
 */
import { Link, useLocation } from 'react-router-dom'
import { ArrowRight, MonitorCog } from 'lucide-react'
import { env } from '@operalia/compartido/config/env.js'

export default function PlatformMovedPage() {
  const { pathname, search } = useLocation()
  const sub = pathname.replace(/^\/plataforma/, '') || '/'
  const target = env.consolaUrl ? `${env.consolaUrl}${sub}${search}` : null

  return (
    <div className="company-link-page">
      <div className="company-link-card">
        <MonitorCog size={36} />
        <h1>La plataforma se movió a la Consola</h1>
        <p>Empresas, rendimiento, marca, prospectos, altas y soporte de tiendas ahora están en la Consola Operalia, con su propio inicio de sesión.</p>
        {target
          ? <a href={target} className="btn btn-primary">Ir a la Consola <ArrowRight size={16} /></a>
          : <p>Pide el link de la Consola al equipo de Operalia.</p>}
        <Link to="/" className="company-link-login">Volver a Operalia</Link>
      </div>
    </div>
  )
}
