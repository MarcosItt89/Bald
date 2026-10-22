import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { ArrowLeft, Camera, CircleCheck, CircleHelp, MapPin, Send, TriangleAlert, Wrench, X } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { useToast } from '../../hooks/useToast'
import { createTicket, getTopics } from '../../services/supportService'
import { NAV_GROUPS } from '../../config/navigation'
import { uploadEvidence } from '../../services/evidenceService'
import PageHeader from '../../components/ui/PageHeader'
import Card from '../../components/ui/Card'
import Button from '../../components/ui/Button'
import Input, { Textarea } from '../../components/ui/Input'
import { ErrorState, Loader } from '../../components/ui/Feedback'
import { topicIcon } from './supportTopics'

const OTHER = { id: null, code: 'other', name: 'Otro problema', category: 'other', self_help: null }

export default function NewTicketPage() {
  const [params] = useSearchParams()
  const from = params.get('from')
  const fromPath = from?.split('?')[0]
  const fromLabel = fromPath && (NAV_GROUPS.flatMap((g) => g.items).filter((i) => fromPath.startsWith(i.path)).sort((a, b) => b.path.length - a.path.length)[0]?.label ?? fromPath)
  const navigate = useNavigate()
  const toast = useToast()
  const { profile, workingBranchId } = useAuth()
  const { data: topics, loading, error, reload } = useAsync(getTopics)
  const [step, setStep] = useState('topic')
  const [topic, setTopic] = useState(null)
  const [form, setForm] = useState({ location: '', blocks: null, description: '' })
  const [photo, setPhoto] = useState(null)
  const [saving, setSaving] = useState(false)
  const fileRef = useRef(null)

  const preview = useMemo(() => (photo ? URL.createObjectURL(photo) : null), [photo])
  useEffect(() => () => preview && URL.revokeObjectURL(preview), [preview])

  const pick = (t) => {
    setTopic(t)
    setStep(t.self_help ? 'help' : 'details')
  }

  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const subject = form.location.trim() ? `${topic.name} · ${form.location.trim()}` : topic.name
      const t = await createTicket({
        subject,
        description: form.description.trim(),
        category: topic.category,
        topicId: topic.id,
        location: form.location,
        blocksOperation: form.blocks,
        module: fromLabel || null,
        pageUrl: from ? `${window.location.origin}${from}` : null,
      })
      if (photo) {
        try {
          await uploadEvidence({ file: photo, companyId: profile.company_id, entityType: 'support_ticket', entityId: t.id, branchId: t.branch_id ?? workingBranchId, description: 'Foto del reporte' })
        } catch (err) { toast.error(`Ticket creado, pero la foto no se subió: ${err.message}`) }
      }
      toast.success(`Ticket ${t.folio} enviado`)
      navigate(`/support/${t.id}`, { replace: true })
    } catch (err) {
      toast.error(err.message)
      setSaving(false)
    }
  }

  if (error) return <ErrorState error={error} onRetry={reload} />

  return (
    <div className="page page-narrow">
      <Link to="/support" className="back-link"><ArrowLeft size={14} /> Soporte</Link>
      <PageHeader icon={Wrench} title="Reportar un problema" subtitle={fromLabel ? `Desde ${fromLabel}` : 'Te ayudamos a resolverlo'} />

      <ol className="wizard-steps">
        {['¿Qué pasa?', 'Revisa', 'Detalles'].map((label, i) => (
          <li key={label} className={['topic', 'help', 'details'].indexOf(step) >= i ? 'wizard-step-done' : ''}>{label}</li>
        ))}
      </ol>

      {step === 'topic' && (loading ? <Loader /> : (
        <div className="topic-grid">
          {[...(topics ?? []), OTHER].map((t) => {
            const Icon = t === OTHER ? CircleHelp : topicIcon(t)
            return (
              <button key={t.code} type="button" className="topic-btn" onClick={() => pick(t)}>
                <Icon size={26} />
                <span>{t.name}</span>
              </button>
            )
          })}
        </div>
      ))}

      {step === 'help' && topic && (
        <Card title={<span className="row-inline"><CircleHelp size={16} /> Antes de enviar, revisa esto</span>}>
          <p className="text-muted text-sm">{topic.name}</p>
          <ol className="self-help-list">
            {topic.self_help.split('\n').filter(Boolean).map((line) => <li key={line}>{line.replace(/^\d+\.\s*/, '')}</li>)}
          </ol>
          <div className="wizard-actions">
            <Button variant="outline" onClick={() => { toast.success('¡Qué bien! No se creó ningún ticket'); navigate(-1) }}>
              <CircleCheck size={16} /> Ya se resolvió
            </Button>
            <Button onClick={() => setStep('details')}><TriangleAlert size={16} /> Sigue fallando</Button>
          </div>
          <button type="button" className="link-btn" onClick={() => setStep('topic')}>Elegir otro tema</button>
        </Card>
      )}

      {step === 'details' && topic && (
        <Card>
          <form className="form-stack" onSubmit={submit}>
            <p className="row-inline"><strong>{topic.name}</strong><button type="button" className="link-btn" onClick={() => setStep('topic')}>Cambiar</button></p>
            <Input label={<span className="row-inline"><MapPin size={14} /> Ubicación</span>} placeholder="Ej. Caja 3, pasillo 5, oficina"
              value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} />
            <div>
              <span className="form-label">¿Detiene la operación?</span>
              <div className="yes-no">
                <button type="button" className={`yes-no-btn ${form.blocks === true ? 'yes-no-danger' : ''}`} onClick={() => setForm({ ...form, blocks: true })}>Sí, no puedo trabajar</button>
                <button type="button" className={`yes-no-btn ${form.blocks === false ? 'yes-no-active' : ''}`} onClick={() => setForm({ ...form, blocks: false })}>No, puedo seguir</button>
              </div>
            </div>
            <Textarea label="Descripción" required rows={4} placeholder="¿Qué pasa? ¿Desde cuándo? ¿Qué intentaste?"
              value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            <div>
              <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={(e) => { setPhoto(e.target.files?.[0] ?? null); e.target.value = '' }} />
              {preview ? (
                <div className="photo-preview">
                  <img src={preview} alt="Foto del problema" />
                  <button type="button" className="photo-remove" onClick={() => setPhoto(null)} aria-label="Quitar foto"><X size={16} /></button>
                </div>
              ) : (
                <Button variant="outline" onClick={() => fileRef.current?.click()}><Camera size={16} /> Agregar foto</Button>
              )}
            </div>
            <Button type="submit" className="btn-block" loading={saving} disabled={form.blocks === null || !form.description.trim()}>
              {!saving && <Send size={16} />} Enviar reporte
            </Button>
            {form.blocks === null && <p className="text-muted text-sm">Indica si el problema detiene la operación.</p>}
          </form>
        </Card>
      )}
    </div>
  )
}
