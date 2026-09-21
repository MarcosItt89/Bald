import Badge from './Badge'

export default function StatusBadge({ statusMap, value }) {
  const status = statusMap?.[value] ?? { label: value, color: 'default' }
  return <Badge color={status.color}>{status.label}</Badge>
}
