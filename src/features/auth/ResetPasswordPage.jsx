import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { KeyRound, TriangleAlert } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useToast } from '../../hooks/useToast'
import { changeOwnPassword } from '../../services/employeeService'
import Input from '../../components/ui/Input'
import Button from '../../components/ui/Button'
import { Loader } from '../../components/ui/Feedback'

export default function ResetPasswordPage() {
  const { status, session } = useAuth()
  const navigate = useNavigate()
  const toast = useToast()
  const [form, setForm] = useState({ password: '', confirm: '' })
  const [saving, setSaving] = useState(false)

  const error = form.password && form.password.length < 8 ? 'Mínimo 8 caracteres'
    : form.confirm && form.confirm !== form.password ? 'Las contraseñas no coinciden' : null

  const submit = async (e) => {
    e.preventDefault()
    if (error) return
    setSaving(true)
    try {
      await changeOwnPassword(form.password)
      toast.success('Contraseña actualizada')
      navigate('/dashboard', { replace: true })
    } catch (err) { toast.error(err.message); setSaving(false) }
  }

  if (status === 'loading') return <Loader full />

  return (
    <div className="login-form-panel login-standalone">
      <div className="login-form-card">
        <div className="login-form-header">
          <img src="/logo.svg" alt="Operalia" width="48" height="48" className="login-form-logo login-form-logo-show" />
          <h2>Nueva contraseña</h2>
          <p>{session ? 'Escribe tu nueva contraseña' : 'Abre el enlace que llegó a tu correo'}</p>
        </div>
        {session ? (
          <form className="login-form" onSubmit={submit}>
            <Input label="Nueva contraseña" type="password" autoComplete="new-password" required autoFocus
              value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
            <Input label="Confirmar contraseña" type="password" autoComplete="new-password" required error={error}
              value={form.confirm} onChange={(e) => setForm({ ...form, confirm: e.target.value })} />
            <Button type="submit" className="btn-block" loading={saving} disabled={!!error || !form.confirm}>
              {!saving && <KeyRound size={16} />} Guardar contraseña
            </Button>
          </form>
        ) : (
          <div className="login-error"><TriangleAlert size={16} /><span>El enlace no es válido o ya expiró. Solicita uno nuevo desde el inicio de sesión.</span></div>
        )}
        <Link to="/login" className="link-btn login-forgot">Volver a iniciar sesión</Link>
      </div>
    </div>
  )
}
