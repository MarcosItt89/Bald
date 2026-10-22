import { useState } from 'react'
import { KeyRound, MailCheck, ShieldCheck } from 'lucide-react'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Button from '../../components/ui/Button'
import { requestPasswordReset } from '../../services/employeeService'

export default function ForgotPasswordModal({ open, onClose, initialValue = '' }) {
  const [value, setValue] = useState(initialValue)
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  const close = () => { setResult(null); setError(null); onClose() }

  const submit = async (e) => {
    e.preventDefault()
    setSending(true)
    setError(null)
    try { setResult(await requestPasswordReset(value)) } catch (err) { setError(err.message) } finally { setSending(false) }
  }

  return (
    <Modal open={open} onClose={close} title="¿Olvidaste tu contraseña?" size="sm"
      footer={result
        ? <Button onClick={close}>Entendido</Button>
        : <><Button variant="ghost" onClick={close}>Cancelar</Button><Button type="submit" form="forgot-form" loading={sending} disabled={!value.trim()}><KeyRound size={14} /> Solicitar</Button></>}>
      {result === 'admin' && (
        <div className="forgot-done">
          <ShieldCheck size={36} />
          <p><strong>Solicitud enviada.</strong></p>
          <p className="text-muted text-sm">Si el usuario existe, avisamos a tu gerente y al administrador. Te darán una contraseña temporal y al entrar podrás crear la tuya.</p>
        </div>
      )}
      {result === 'email' && (
        <div className="forgot-done">
          <MailCheck size={36} />
          <p><strong>Revisa tu correo.</strong></p>
          <p className="text-muted text-sm">Si el correo está registrado, te llegará un enlace para crear una nueva contraseña.</p>
        </div>
      )}
      {!result && (
        <form id="forgot-form" className="form-stack" onSubmit={submit}>
          <p className="text-muted text-sm">Escribe tu usuario. Si tu cuenta tiene un correo real, escríbelo para recibir un enlace.</p>
          <Input label="Usuario o correo" autoFocus autoCapitalize="none" spellCheck={false} value={value} onChange={(e) => setValue(e.target.value)} placeholder="ej. cajero" />
          {error && <p className="form-error">{error}</p>}
        </form>
      )}
    </Modal>
  )
}
