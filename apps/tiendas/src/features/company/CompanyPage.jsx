/**
 * CompanyPage — Configuración → Mi empresa (propietario o superadmin).
 * La MARCA de la empresa (migración 0028) con el editor compartido
 * (BrandEditor, también lo usa la Consola). Al guardar recarga el perfil para
 * que el color y el logo se apliquen en toda la app.
 */
import { useCallback } from 'react'
import { Palette } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import BrandEditor from '@operalia/compartido/branding/BrandEditor.jsx'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import { ErrorState, Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import { getMyCompany } from '../../services/organizationService'

export default function CompanyPage() {
  const { profile, refreshProfile } = useAuth()
  const load = useCallback(() => getMyCompany(profile.company_id), [profile.company_id])
  const { data: company, error, reload } = useAsync(load)

  if (error) return <ErrorState error={error} onRetry={reload} />
  if (!company) return <Loader />

  return (
    <div className="page">
      <PageHeader icon={Palette} title="Mi empresa" subtitle={`${company.name} · código ${company.code}`} />
      <BrandEditor company={company} subtitle="Se aplica en toda la app para los empleados de tu empresa y en su pantalla de inicio de sesión"
        onSaved={async () => { await reload(); await refreshProfile() }} />
    </div>
  )
}
