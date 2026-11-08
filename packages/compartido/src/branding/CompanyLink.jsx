/**
 * Link de acceso de una empresa (/e/<código>) y su QR: copiar, ver e imprimir.
 * Con él los empleados entran sin escribir la empresa (la recuerda el dispositivo).
 *   <CompanyLinkPanel company={{ name, code, status }} />   bloque para una página
 *   <CompanyLinkModal company={…} onClose={…} />           el mismo bloque en un modal
 */
import { useMemo } from 'react'
import { Copy, Printer } from 'lucide-react'
import { useToast } from '../hooks/useToast'
import { companyLink, companyLinkMisconfigured } from '../config/env'
import { qrSvg } from '../utils/qr'
import { printCompanyLink } from './printCompanyLink'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'

export function CompanyLinkPanel({ company, showPrint = true }) {
  const toast = useToast()
  const url = companyLink(company.code)
  const qr = useMemo(() => qrSvg(url), [url])
  const copy = async () => {
    try { await navigator.clipboard.writeText(url); toast.success('Link copiado') } catch { toast.error('No se pudo copiar; selecciónalo y cópialo a mano') }
  }
  return (
    <div className="form-stack">
      <p className="text-muted text-sm">Con este link (o su QR) los empleados de {company.name} entran sin escribir la empresa: el dispositivo la recuerda.</p>
      {companyLinkMisconfigured && (
        <p className="form-error">Falta VITE_TIENDAS_URL: define el dominio de la app de tiendas en la Consola (Vercel → Environment Variables). Mientras tanto este link no funciona.</p>
      )}
      <div className="company-link-row">
        <code className="company-link-url">{url}</code>
        <Button size="sm" variant="outline" onClick={copy}><Copy size={14} /> Copiar</Button>
      </div>
      {/* SVG generado localmente por uqr a partir del link (sin datos de usuario). */}
      <div className="company-link-qr" role="img" aria-label={`Código QR de ${url}`} dangerouslySetInnerHTML={{ __html: qr }} />
      {company.status && company.status !== 'active' && <p className="form-error">La empresa está suspendida: el link mostrará «Empresa no encontrada» hasta reactivarla.</p>}
      {showPrint && (
        <div className="row-actions">
          <Button variant="outline" onClick={() => printCompanyLink({ name: company.name, url })}><Printer size={14} /> Imprimir QR</Button>
        </div>
      )}
    </div>
  )
}

export function CompanyLinkModal({ company, onClose }) {
  const url = companyLink(company.code)
  return (
    <Modal open onClose={onClose} title={`Link de acceso · ${company.name}`} size="sm"
      footer={<>
        <Button variant="ghost" onClick={onClose}>Cerrar</Button>
        <Button variant="outline" onClick={() => printCompanyLink({ name: company.name, url })}><Printer size={14} /> Imprimir QR</Button>
      </>}>
      <CompanyLinkPanel company={company} showPrint={false} />
    </Modal>
  )
}
