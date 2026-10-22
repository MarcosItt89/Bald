/**
 * BarcodeScanner — lectura de códigos de barras con la cámara.
 *
 * Estrategia en dos niveles:
 *   1. BarcodeDetector nativo (Chrome/Edge en Android): sin librerías.
 *   2. Si no existe (iPhone, Firefox, escritorio): se carga ZXing con
 *      import() dinámico. Vite lo separa en su propio chunk, así solo se
 *      descarga la primera vez que alguien abre el escáner.
 * El lector USB sigue funcionando en la caja de búsqueda (escribe + Enter).
 */
import { useEffect, useRef, useState } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'

const FORMATS = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'qr_code']
const hasNativeDetector = typeof window !== 'undefined' && 'BarcodeDetector' in window
const CAMERA = { video: { facingMode: 'environment' }, audio: false }

/** Escaneo con la API nativa. Devuelve función para detener. */
async function startNative(video, onCode) {
  const stream = await navigator.mediaDevices.getUserMedia(CAMERA)
  const detector = new window.BarcodeDetector({ formats: FORMATS })
  let stopped = false
  let raf
  video.srcObject = stream
  await video.play()
  const scan = async () => {
    if (stopped) return
    try {
      const codes = await detector.detect(video)
      if (codes.length) { onCode(codes[0].rawValue); return }
    } catch { /* frame no listo todavía */ }
    raf = requestAnimationFrame(scan)
  }
  scan()
  return () => { stopped = true; cancelAnimationFrame(raf); stream.getTracks().forEach((t) => t.stop()) }
}

/** Escaneo con ZXing (carga diferida). Devuelve función para detener. */
async function startZxing(video, onCode) {
  const { BrowserMultiFormatReader } = await import('@zxing/browser')
  const reader = new BrowserMultiFormatReader()
  const controls = await reader.decodeFromConstraints(CAMERA, video, (result) => {
    if (result) onCode(result.getText())
  })
  return () => controls.stop()
}

export default function BarcodeScanner({ onDetected, onClose }) {
  const videoRef = useRef(null)
  // El callback vive en un ref para no reiniciar la cámara si el padre re-renderiza.
  const onDetectedRef = useRef(onDetected)
  useEffect(() => { onDetectedRef.current = onDetected })
  const [status, setStatus] = useState(hasNativeDetector ? 'Apunta la cámara al código…' : 'Cargando lector…')
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!navigator.mediaDevices?.getUserMedia) {
      setTimeout(() => setError('Este navegador no permite usar la cámara (se requiere HTTPS). Usa un lector USB.'), 0)
      return undefined
    }
    let stop = null
    let cancelled = false
    let done = false
    const onCode = (code) => {
      if (done) return
      done = true
      stop?.()
      onDetectedRef.current(code)
    }
    ;(hasNativeDetector ? startNative : startZxing)(videoRef.current, onCode)
      .then((stopFn) => {
        if (cancelled) { stopFn(); return }
        stop = stopFn
        setStatus('Apunta la cámara al código…')
      })
      .catch((err) => {
        if (cancelled) return
        setError(err?.name === 'NotAllowedError'
          ? 'Permiso de cámara denegado. Actívalo en la configuración del navegador.'
          : 'No se pudo iniciar la cámara o el lector de códigos.')
      })
    return () => { cancelled = true; stop?.() }
  }, [])

  return (
    <Modal open onClose={onClose} title="Escanear código" size="sm"
      footer={<Button variant="ghost" onClick={onClose}>Cerrar</Button>}>
      {error
        ? <p className="hint-box hint-danger">{error}</p>
        : <>
          <video ref={videoRef} className="scanner-video" muted playsInline />
          <p className="text-muted text-sm mt-2">{status}</p>
        </>}
    </Modal>
  )
}
