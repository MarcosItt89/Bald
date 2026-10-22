/**
 * EvidenceGallery / EvidenceThumb — miniaturas de evidencias privadas.
 *
 * Cada miniatura pide una URL firmada temporal a Supabase Storage. Al hacer
 * clic se abre el archivo completo en otra pestaña (o se llama onSelect).
 */
import { useCallback } from 'react'
import { FileText, ImageOff } from 'lucide-react'
import { useAsync } from '../../hooks/useAsync'
import { getSignedUrl } from '../../services/evidenceService'
import { EVIDENCE_STATUS } from '../../constants/status'
import StatusBadge from '../ui/StatusBadge'

export function EvidenceThumb({ evidence, showStatus = false, onSelect, size = 72 }) {
  const load = useCallback(() => getSignedUrl(evidence.storage_path), [evidence.storage_path])
  const { data: url, error } = useAsync(load)
  const isPdf = evidence.mime_type === 'application/pdf'

  const body = error ? <ImageOff size={20} />
    : !url ? <span className="spinner-sm spinner-dark" />
    : isPdf ? <FileText size={24} />
    : <img src={url} alt={evidence.file_name ?? 'Evidencia'} loading="lazy" />

  const handleClick = (e) => {
    if (onSelect) { e.preventDefault(); onSelect(evidence, url) }
  }

  return (
    <div className="evidence-thumb-wrap">
      <a className="evidence-thumb" style={{ width: size, height: size }} href={url ?? undefined}
        target="_blank" rel="noreferrer" onClick={handleClick} title={evidence.file_name}>
        {body}
      </a>
      {showStatus && <StatusBadge statusMap={EVIDENCE_STATUS} value={evidence.status} />}
    </div>
  )
}

export default function EvidenceGallery({ items = [], showStatus = false, onSelect, emptyText = 'Sin evidencias' }) {
  if (!items.length) return <p className="text-muted text-sm">{emptyText}</p>
  return (
    <div className="evidence-gallery">
      {items.map((ev) => <EvidenceThumb key={ev.id} evidence={ev} showStatus={showStatus} onSelect={onSelect} />)}
    </div>
  )
}
