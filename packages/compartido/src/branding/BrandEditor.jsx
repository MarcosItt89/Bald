/**
 * BrandEditor — edita la MARCA de una empresa (migración 0028): nombre visible,
 * color principal (con ajuste de contraste AA) y logo, con vista previa.
 * Guarda con set_company_branding(); el logo va a company-branding/{empresa}/.
 *   App de tiendas: el propietario, su empresa (Configuración → Mi empresa).
 *   Consola: el superadmin, cualquier empresa (Marca).
 * company: { id, name, display_name, brand_color, logo_url }. Al cambiar de
 * empresa, móntalo con key={company.id}.
 */
import { useEffect, useMemo, useState } from 'react'
import { ImageUp, RotateCcw, Trash2 } from 'lucide-react'
import { useToast } from '../hooks/useToast'
import { LOGO_MAX_BYTES, LOGO_TYPES, removeCompanyLogo, saveCompanyBranding, uploadCompanyLogo } from './brandingService'
import { DEFAULT_BRAND_COLOR, brandPalette } from '../theme/brand'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Input from '../components/ui/Input'

const HEX = /^#[0-9a-f]{6}$/i

export default function BrandEditor({ company, onSaved, subtitle = 'Se aplica en toda la app para los empleados de la empresa y en su pantalla de inicio de sesión' }) {
  const toast = useToast()
  const [form, setForm] = useState(null)
  const [file, setFile] = useState(null)
  const [saving, setSaving] = useState(false)

  // Formulario a partir de lo guardado.
  const initial = useMemo(() => company && {
    displayName: company.display_name ?? '',
    color: company.brand_color ?? DEFAULT_BRAND_COLOR,
    logoUrl: company.logo_url ?? null,
  }, [company])
  const f = form ?? initial

  // Vista previa local del archivo elegido.
  const filePreview = useMemo(() => (file ? URL.createObjectURL(file) : null), [file])
  useEffect(() => () => { if (filePreview) URL.revokeObjectURL(filePreview) }, [filePreview])

  const set = (patch) => setForm({ ...f, ...patch })
  const validColor = HEX.test(f.color)
  const palette = brandPalette(validColor ? f.color : DEFAULT_BRAND_COLOR)
  const logo = filePreview ?? f.logoUrl
  const name = f.displayName.trim() || company.name
  const dirty = Boolean(file) || f.displayName !== initial.displayName || f.color.toLowerCase() !== initial.color.toLowerCase() || f.logoUrl !== initial.logoUrl

  const pickFile = (e) => {
    const picked = e.target.files?.[0]
    e.target.value = ''
    if (!picked) return
    if (!LOGO_TYPES.includes(picked.type)) { toast.error('El logo debe ser PNG, SVG o WebP'); return }
    if (picked.size > LOGO_MAX_BYTES) { toast.error(`El logo pesa ${Math.round(picked.size / 1024)} KB; el máximo es 500 KB`); return }
    setFile(picked)
  }

  const save = async (e) => {
    e.preventDefault()
    if (!validColor) { toast.error('Color inválido: usa el formato #RRGGBB'); return }
    setSaving(true)
    let uploaded = null
    try {
      if (file) uploaded = await uploadCompanyLogo(company.id, file)
      const logoUrl = uploaded ?? f.logoUrl
      await saveCompanyBranding({ companyId: company.id, displayName: f.displayName, brandColor: f.color.toLowerCase(), logoUrl })
      // El logo anterior ya no se usa: se borra (si falla, solo queda el archivo).
      if (initial.logoUrl && initial.logoUrl !== logoUrl) removeCompanyLogo(initial.logoUrl).catch(() => {})
      setFile(null)
      setForm(null)
      await onSaved?.()
      toast.success('Marca guardada')
    } catch (err) {
      if (uploaded) removeCompanyLogo(uploaded).catch(() => {})
      toast.error(err.message)
    } finally { setSaving(false) }
  }

  const reset = () => { setFile(null); setForm(null) }

  return (
    <form onSubmit={save} className="brand-layout">
      <Card title="Marca" subtitle={subtitle}>
        <div className="form-stack">
          <Input label="Nombre visible" maxLength={60} value={f.displayName} placeholder={company.name}
            onChange={(e) => set({ displayName: e.target.value })}
            hint="Se muestra en el menú y en el inicio de sesión. Vacío = el nombre de la empresa." />

          <div className="form-group">
            <label htmlFor="brand-color" className="form-label">Color principal</label>
            <div className="brand-color-row">
              <input id="brand-color" type="color" className="brand-color-swatch" value={validColor ? f.color : DEFAULT_BRAND_COLOR}
                onChange={(e) => set({ color: e.target.value })} aria-label="Elegir color" />
              <input className={`form-input mono ${validColor ? '' : 'input-error'}`} value={f.color} maxLength={7}
                onChange={(e) => set({ color: e.target.value.startsWith('#') ? e.target.value : `#${e.target.value}` })}
                aria-label="Color en hexadecimal" spellCheck={false} />
              <Button variant="ghost" size="sm" onClick={() => set({ color: DEFAULT_BRAND_COLOR })} title="Azul de Operalia"><RotateCcw size={14} /> Original</Button>
            </div>
            {palette.adjusted
              ? <span className="form-hint">Para que el texto blanco se lea bien (contraste AA), los botones usarán <span className="mono">{palette.primary}</span> ({palette.contrast}:1).</span>
              : <span className="form-hint">Contraste con texto blanco: {palette.contrast}:1</span>}
          </div>

          <div className="form-group">
            <span className="form-label">Logo</span>
            <div className="brand-logo-row">
              <div className="brand-logo-box">{logo ? <img src={logo} alt="Logo" /> : <span className="text-muted text-sm">Sin logo</span>}</div>
              <div className="form-stack">
                <label className="btn btn-outline btn-sm brand-upload">
                  <ImageUp size={14} /> {logo ? 'Cambiar logo' : 'Subir logo'}
                  <input type="file" accept={LOGO_TYPES.join(',')} onChange={pickFile} hidden />
                </label>
                {logo && (
                  <Button variant="ghost" size="sm" onClick={() => { setFile(null); set({ logoUrl: null }) }}><Trash2 size={14} /> Quitar logo</Button>
                )}
              </div>
            </div>
            <span className="form-hint">PNG, SVG o WebP, hasta 500 KB. Mejor cuadrado y con fondo transparente.</span>
          </div>

          <div className="row-actions">
            <Button variant="ghost" onClick={reset} disabled={!dirty || saving}>Descartar</Button>
            <Button type="submit" loading={saving} disabled={!dirty || !validColor}>Guardar marca</Button>
          </div>
        </div>
      </Card>

      <Card title="Vista previa">
        <div className="brand-preview" style={{ '--primary': palette.primary, '--primary-dark': palette.primaryDark, '--primary-light': palette.primaryLight, '--primary-deep': palette.primaryDeep }}>
          <div className="brand-preview-sidebar">
            <img src={logo || '/logo.svg'} alt="" width="28" height="28" />
            <div><strong>Operalia</strong><small>{name}</small></div>
          </div>
          <div className="brand-preview-nav"><span className="brand-preview-active">Dashboard</span><span>Inventario</span></div>
          <div className="brand-preview-body">
            <Button size="sm">Guardar</Button>
            <span className="badge badge-primary">Nuevo</span>
            <a href="#vista-previa" onClick={(e) => e.preventDefault()}>Ver detalle</a>
          </div>
          <div className="brand-preview-login">
            <img src={logo || '/logo.svg'} alt="" width="40" height="40" />
            <strong>{name}</strong>
            <Button size="sm" className="btn-block">Entrar</Button>
          </div>
        </div>
      </Card>
    </form>
  )
}
