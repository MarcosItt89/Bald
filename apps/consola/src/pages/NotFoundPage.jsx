import { Link } from 'react-router-dom'
import { EmptyState } from '@operalia/compartido/components/ui/Feedback.jsx'

export default function NotFoundPage() {
  return (
    <div className="page">
      <EmptyState title="Página no encontrada" action={<Link to="/">Ir a Empresas</Link>} />
    </div>
  )
}
