/**
 * StatusBadge — traduce un código de estado a etiqueta + color.
 *   <StatusBadge statusMap={TASK_STATUS} value="in_progress" />  →  "En progreso" (azul)
 * Los mapas viven en src/constants/status.js.
 */
import Badge from './Badge'

export default function StatusBadge({ statusMap, value }) {
  if (value == null) return <span className="text-muted">—</span>
  const status = statusMap?.[value] ?? { label: value, color: 'default' }
  return <Badge color={status.color}>{status.label}</Badge>
}
