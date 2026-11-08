/**
 * StatCard — tarjeta de indicador (número grande + etiqueta + ícono).
 * Si recibe `to`, toda la tarjeta es un enlace al módulo correspondiente.
 *   tone: blue | orange | red | purple | green | slate
 */
import { Link } from 'react-router-dom'
import { AlertTriangle } from 'lucide-react'

export default function StatCard({ label, value, icon: Icon, tone = 'blue', to, alert, hint }) {
  const content = (
    <>
      <div className="stat-card-body">
        <div className="stat-card-info">
          <span className="stat-card-label">{label}</span>
          <span className="stat-card-value">{value ?? '—'}</span>
          {hint && <span className="stat-card-hint">{hint}</span>}
        </div>
        {Icon && <div className="stat-card-icon"><Icon size={24} /></div>}
      </div>
      {alert && (
        <div className="stat-card-alert"><AlertTriangle size={12} /><span>{alert}</span></div>
      )}
    </>
  )
  return to
    ? <Link to={to} className={`stat-card stat-${tone} stat-card-link`}>{content}</Link>
    : <div className={`stat-card stat-${tone}`}>{content}</div>
}
