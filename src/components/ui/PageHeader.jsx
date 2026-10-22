/**
 * PageHeader — título de la página, subtítulo y botones de acción.
 *   <PageHeader title="Inventario" subtitle="120 productos" actions={<Button/>} />
 */
export default function PageHeader({ title, subtitle, actions, icon: Icon }) {
  return (
    <div className="page-header">
      <div>
        <h1 className="page-title">{Icon && <Icon size={22} className="page-title-icon" />}{title}</h1>
        {subtitle && <p className="page-subtitle">{subtitle}</p>}
      </div>
      {actions && <div className="page-actions">{actions}</div>}
    </div>
  )
}
