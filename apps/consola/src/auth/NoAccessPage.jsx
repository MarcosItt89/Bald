/** «Sin acceso»: la cuenta inició sesión pero no es superadmin de la plataforma. */
import { ShieldX } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import Button from '@operalia/compartido/components/ui/Button.jsx'

export default function NoAccessPage() {
  const { session, logout, status, error, refreshProfile } = useAuth()
  const failed = status === 'error'
  return (
    <div className="consola-auth">
      <div className="consola-auth-card consola-noaccess">
        <ShieldX size={40} />
        <h1>{failed ? 'No se pudo verificar tu cuenta' : 'Sin acceso'}</h1>
        <p>{failed ? error : 'La Consola Operalia es solo para superadmins de la plataforma.'}</p>
        {session?.user?.email && <p className="text-muted text-sm">Sesión: {session.user.email}</p>}
        <div className="row-actions">
          {failed && <Button variant="outline" onClick={refreshProfile}>Reintentar</Button>}
          <Button variant="ghost" onClick={logout}>Cerrar sesión</Button>
        </div>
      </div>
    </div>
  )
}
