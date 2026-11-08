/**
 * BrandPage — Marca de cada empresa (versión superadmin de «Mi empresa»).
 * Elige una empresa (?empresa=<id>) y edita su nombre visible, color y logo
 * con el editor compartido; al lado, su link de acceso (/e/<código>) y su QR.
 * Lee la marca con platform_get_company_branding (0029) y la guarda con
 * set_company_branding (0028), que acepta superadmin.
 */
import { useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Palette } from 'lucide-react'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import BrandEditor from '@operalia/compartido/branding/BrandEditor.jsx'
import { CompanyLinkPanel } from '@operalia/compartido/branding/CompanyLink.jsx'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import { EmptyState, ErrorState, Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import { getCompanies, getCompanyBrandingById } from '../services/platformService'

export default function BrandPage() {
  const [params, setParams] = useSearchParams()
  const companyId = params.get('empresa') ?? ''
  const companies = useAsync(getCompanies)
  const loadBrand = useCallback(() => (companyId ? getCompanyBrandingById(companyId) : Promise.resolve(null)), [companyId])
  const brand = useAsync(loadBrand)
  const company = brand.data?.id === companyId ? brand.data : null // sin datos viejos al cambiar de empresa

  return (
    <div className="page">
      <PageHeader icon={Palette} title="Marca" subtitle="Nombre visible, color y logo de cada empresa, y su link de acceso" />
      {companies.error && <ErrorState error={companies.error} onRetry={companies.reload} />}

      <div className="filters">
        <select className="filter-select" aria-label="Empresa" value={companyId}
          onChange={(e) => setParams(e.target.value ? { empresa: e.target.value } : {}, { replace: true })}>
          <option value="">Elige una empresa…</option>
          {(companies.data ?? []).map((c) => (
            <option key={c.id} value={c.id}>{c.name}{c.status !== 'active' ? ' (suspendida)' : ''}</option>
          ))}
        </select>
      </div>

      {!companyId && <EmptyState icon={Palette} title="Elige una empresa" message="Su marca se aplica en la app de tiendas y en su pantalla de inicio de sesión." />}
      {companyId && brand.error && <ErrorState error={brand.error} onRetry={brand.reload} />}
      {companyId && !brand.error && !company && (brand.loading ? <Loader /> : <EmptyState icon={Palette} title="Empresa no encontrada" />)}
      {company && (
        <>
          <BrandEditor key={company.id} company={company} onSaved={brand.reload}
            subtitle={`Se aplica en la app de ${company.name} y en su pantalla de inicio de sesión`} />
          <Card title="Link de acceso y QR" subtitle={`Código ${company.code}`}>
            <CompanyLinkPanel company={company} />
          </Card>
        </>
      )}
    </div>
  )
}
