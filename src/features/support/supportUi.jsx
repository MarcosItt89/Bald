import { useEffect, useState } from 'react'
import { Clock, Siren } from 'lucide-react'
import Badge from '../../components/ui/Badge'

const span = (ms) => {
  const min = Math.round(Math.abs(ms) / 60000)
  if (min < 60) return `${min} min`
  const h = Math.round(min / 60)
  return h < 48 ? `${h} h` : `${Math.round(h / 24)} d`
}

export function DueBadge({ ticket }) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 60000)
    return () => clearInterval(id)
  }, [])
  if (!ticket?.due_at || ['resolved', 'closed'].includes(ticket.status)) return null
  const diff = new Date(ticket.due_at) - now
  if (diff < 0) return <Badge color="danger" title="Fuera del tiempo de atención"><Siren size={11} /> Vencido hace {span(diff)}</Badge>
  return <Badge color={diff < 2 * 3600000 ? 'warning' : 'default'} title="Tiempo restante de atención"><Clock size={11} /> Vence en {span(diff)}</Badge>
}

export function BlocksBadge({ ticket }) {
  if (!ticket?.blocks_operation) return null
  return <Badge color="danger">Detiene operación</Badge>
}
