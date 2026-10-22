/**
 * ChangePasswordModal — el usuario conectado cambia su propia contraseña.
 * Útil para que los perfiles de prueba cambien "prueba123" al primer ingreso.
 */
import { useState } from 'react'
import Modal from '../ui/Modal'
import Input from '../ui/Input'
import Button from '../ui/Button'
import { useToast } from '../../hooks/useToast'
import { changeOwnPassword } from '../../services/employeeService'

export default function ChangePasswordModal({ open, onClose, forced = false }) {
  const toast = useToast()
  const [form, setForm] = useState({ password: '', confirm: '' })
  const [saving, setSaving] = useState(false)

  const error = form.password && form.password.length < 8
    ? 'Mínimo 8 caracteres'
    : form.confirm && form.confirm !== form.password ? 'Las contraseñas no coinciden' : null

  const close = () => { setForm({ password: '', confirm: '' }); onClose?.() }

  const submit = async (e) => {
    e.preventDefault()
    if (error || !form.password) return
    setSaving(true)
    try {
      await changeOwnPassword(form.password)
      toast.success('Contraseña actualizada')
      close()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal open={open} onClose={forced ? undefined : close} title={forced ? 'Crea tu nueva contraseña' : 'Cambiar contraseña'} size="sm"
      footer={<>
        {!forced && <Button variant="ghost" onClick={close}>Cancelar</Button>}
        <Button type="submit" form="pwd-form" loading={saving} disabled={!!error || !form.confirm}>Guardar</Button>
      </>}>
      <form id="pwd-form" className="form-stack" onSubmit={submit}>
        {forced && <p className="hint-box">Entraste con una contraseña temporal. Crea una nueva para continuar.</p>}
        <Input label="Nueva contraseña" type="password" autoComplete="new-password" value={form.password}
          onChange={(e) => setForm({ ...form, password: e.target.value })} required />
        <Input label="Confirmar contraseña" type="password" autoComplete="new-password" value={form.confirm}
          onChange={(e) => setForm({ ...form, confirm: e.target.value })} error={error} required />
      </form>
    </Modal>
  )
}
