/**
 * ForgotPasswordModal — pedir una contraseña nueva.
 * companyName: si el login ya conoce la empresa (recordada o por link /e/…),
 * no se vuelve a pedir; se muestra su nombre con «¿No es tu empresa? Cambiar».
 */
import { useState } from 'react'
import { KeyRound, MailCheck, ShieldCheck } from 'lucide-react'
import Modal from '../../components/ui/Modal'
import Input from '../../components/ui/Input'
import Button from '../../components/ui/Button'
import { requestPasswordReset } from '../../services/employeeService'
import { normalizeCompanyCode } from '../../config/env'

export default function ForgotPasswordModal({ open, onClose, initialCompany = '', companyName = null, initialValue = '' }) {
  const [company, setCompany] = useState(initialCompany)
  const [askCompany, setAskCompany] = useState(!companyName || !initialCompany)
  const [value, setValue] = useState(initialValue)
  const isEmail = value.includes('@')
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  const close = () => { setResult(null); setError(null); onClose() }

  const submit = async (e) => {
    e.preventDefault()
    setSending(true)
    setError(null)
    try { setResult(await requestPasswordReset(company, value)) } catch (err) { setError(err.message) } finally { setSending(false) }
  }

  return (
    <Modal open={open} onClose={close} title="¿Olvidaste tu contraseña?" size="sm"
      footer={result
        ? <Button onClick={close}>Entendido</Button>
        : <><Button variant="ghost" onClick={close}>Cancelar</Button><Button type="submit" form="forgot-form" loading={sending} disabled={!value.trim() || (!isEmail && !company)}><KeyRound size={14} /> Solicitar</Button></>}>
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
          <p className="text-muted text-sm">
            {askCompany ? 'Escribe tu empresa y tu usuario.' : 'Escribe tu usuario.'} Si tu cuenta tiene un correo real, escríbelo para recibir un enlace.
          </p>
          {!isEmail && !askCompany && (
            <div className="forgot-company">
              <span>Empresa: <strong>{companyName}</strong></span>
              <button type="button" className="link-btn" onClick={() => { setCompany(''); setAskCompany(true) }}>¿No es tu empresa? Cambiar</button>
            </div>
          )}
          {!isEmail && askCompany && (
            <Input label="Empresa" required autoCapitalize="none" spellCheck={false} value={company}
              onChange={(e) => setCompany(normalizeCompanyCode(e.target.value))} placeholder="ej. gatopelon" />
          )}
          <Input label="Usuario o correo" autoFocus autoCapitalize="none" spellCheck={false} value={value} onChange={(e) => setValue(e.target.value)} placeholder="ej. cajero" />
          {error && <p className="form-error">{error}</p>}
        </form>
      )}
    </Modal>
  )
}
