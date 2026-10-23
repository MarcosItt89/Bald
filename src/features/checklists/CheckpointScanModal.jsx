/**
 * CheckpointScanModal — para iniciar un checklist que exige estar en el punto:
 * se escanea el QR con la cámara (o se escribe el código impreso bajo el QR).
 * La validación la hace la base de datos (start_checklist_with_checkpoint).
 */
import { useState } from 'react'
import { QrCode, ScanLine } from 'lucide-react'
import { useToast } from '../../hooks/useToast'
import { startRunWithCheckpoint } from '../../services/checkpointService'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import Input from '../../components/ui/Input'
import BarcodeScanner from '../inventory/BarcodeScanner'

export default function CheckpointScanModal({ run, onClose, onStarted }) {
  const toast = useToast()
  const [scanning, setScanning] = useState(true)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (value) => {
    if (!value.trim()) return
    setBusy(true)
    try {
      await startRunWithCheckpoint(run.id, value.trim())
      toast.success(`Punto verificado: ${run.checkpoint_name ?? 'QR correcto'}`)
      onStarted(run.id)
    } catch (err) {
      toast.error(err.message)
      setScanning(false)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal open onClose={onClose} size="sm" title={<span className="row-inline"><QrCode size={18} /> Escanea el punto</span>}
      footer={<><Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button loading={busy} disabled={!code.trim()} onClick={() => submit(code)}>Verificar código</Button></>}>
      <div className="qr-scan">
        <p>Para iniciar <strong>{run.title}</strong> ve a <strong>{run.checkpoint_name ?? 'el punto indicado'}</strong> y escanea su código QR.</p>
        {!scanning && (
          <Button variant="outline" onClick={() => setScanning(true)}><ScanLine size={16} /> Abrir cámara</Button>
        )}
        <Input label="¿El QR no se lee? Escribe el código impreso" placeholder="OPQ-…" autoCapitalize="characters"
          value={code} onChange={(e) => setCode(e.target.value.toUpperCase())}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); submit(code) } }} />
      </div>
      {scanning && !busy && (
        <BarcodeScanner onClose={() => setScanning(false)} onDetected={(value) => { setScanning(false); setCode(value); submit(value) }} />
      )}
    </Modal>
  )
}
