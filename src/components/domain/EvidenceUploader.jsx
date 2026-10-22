/**
 * EvidenceUploader — botón para tomar/adjuntar foto o PDF como evidencia.
 *
 * En celular abre la cámara o la galería. La imagen se comprime antes de
 * subirla (src/utils/image.js) y queda ligada a la entidad indicada.
 *
 *   <EvidenceUploader entityType="task" entityId={task.id} onUploaded={reload} />
 */
import { useRef, useState } from 'react'
import { Camera } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useToast } from '../../hooks/useToast'
import { uploadEvidence } from '../../services/evidenceService'
import Button from '../ui/Button'

export default function EvidenceUploader({
  entityType, entityId = null, branchId = null, onUploaded, label = 'Adjuntar foto',
  disabled = false, size = 'sm', variant = 'outline', description,
}) {
  const inputRef = useRef(null)
  const [uploading, setUploading] = useState(false)
  const { profile, workingBranchId } = useAuth()
  const toast = useToast()

  const handleFile = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = '' // permite volver a elegir el mismo archivo
    if (!file) return
    setUploading(true)
    try {
      const evidence = await uploadEvidence({
        file,
        companyId: profile.company_id,
        entityType,
        entityId,
        branchId: branchId ?? workingBranchId,
        description,
      })
      toast.success('Evidencia cargada')
      onUploaded?.(evidence)
    } catch (err) {
      toast.error(err.message)
    } finally {
      setUploading(false)
    }
  }

  return (
    <>
      <input ref={inputRef} type="file" accept="image/*" capture="environment" hidden onChange={handleFile} />
      <Button variant={variant} size={size} loading={uploading} disabled={disabled}
        onClick={() => inputRef.current?.click()}>
        {!uploading && <Camera size={14} />} {uploading ? 'Subiendo…' : label}
      </Button>
    </>
  )
}
