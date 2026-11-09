/**
 * ReceivingCfdiPage — Recibo → «Desde factura XML» (permiso receive_products; migración 0031).
 *
 * 1. Lee en el navegador el XML de la factura CFDI 4.0 del proveedor.
 * 2. Busca al proveedor por RFC en la empresa; si no existe, ofrece darlo de alta.
 * 3. Empareja cada concepto con un producto:
 *      - «Recordado»: la clave del proveedor ya se emparejó antes (supplier_product_codes);
 *      - «Sugerido»: la clave coincide con un código de barras o SKU;
 *      - si no, el usuario lo elige con el buscador (o omite el concepto: fletes, servicios…).
 * 4. Crea el recibo EN CAPTURA con las partidas (esperado = cantidad de la factura,
 *    recibido = 0), recuerda las claves y guarda el XML como evidencia. Las
 *    existencias se mueven hasta que Recibo cuenta y cierra, como siempre.
 */
import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft, CheckCircle2, FileCode2, Plus, RotateCcw, Upload } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { formatCurrency, formatDateTime, formatNumber } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import Badge from '@operalia/compartido/components/ui/Badge.jsx'
import Modal from '@operalia/compartido/components/ui/Modal.jsx'
import Input from '@operalia/compartido/components/ui/Input.jsx'
import { Loader } from '@operalia/compartido/components/ui/Feedback.jsx'
import ProductPicker from '../../components/domain/ProductPicker'
import { P } from '../../config/permissions'
import { findSuppliersByRfc, saveSupplier } from '../../services/supplierService'
import {
  createReceivingFromCfdi, findProductsByCodes, findReceivingByUuid, getSupplierCodes,
} from '../../services/receivingService'
import { uploadEvidence } from '../../services/evidenceService'
import { parseCfdi } from './cfdi/parseCfdi'

const MAX_BYTES = 2 * 1024 * 1024
const SOURCE_BADGE = {
  recordado: { color: 'success', label: 'Recordado' },
  sugerido: { color: 'info', label: 'Sugerido' },
  elegido: { color: 'primary', label: 'Elegido' },
}

export default function ReceivingCfdiPage() {
  const { profile, workingBranchId, hasPermission } = useAuth()
  const toast = useToast()
  const navigate = useNavigate()
  const [file, setFile] = useState(null)        // File del XML
  const [cfdi, setCfdi] = useState(null)        // factura leída
  const [duplicate, setDuplicate] = useState(null)
  const [suppliers, setSuppliers] = useState(null)
  const [supplierId, setSupplierId] = useState('')
  const [creatingSupplier, setCreatingSupplier] = useState(false)
  const [lines, setLines] = useState([])        // [{ ...concepto, product, source, omit, suggestion }]
  const [matchedFor, setMatchedFor] = useState('') // «proveedor|uuid» ya emparejado
  const [reading, setReading] = useState(false)
  const [saving, setSaving] = useState(false)

  const supplier = suppliers?.find((s) => s.id === supplierId) ?? null
  const matching = Boolean(supplierId && cfdi) && matchedFor !== `${supplierId}|${cfdi?.uuid}`
  const included = lines.filter((l) => !l.omit)
  const pending = included.filter((l) => !l.product).length
  const invalidQty = included.filter((l) => !(l.cantidad > 0)).length
  const canCreate = cfdi && supplier && !duplicate && included.length > 0 && !pending && !invalidQty && workingBranchId && !saving

  const reset = () => { setFile(null); setCfdi(null); setDuplicate(null); setSuppliers(null); setSupplierId(''); setLines([]) }

  const pickFile = async (e) => {
    const picked = e.target.files?.[0]
    e.target.value = ''
    if (!picked) return
    if (!/\.xml$/i.test(picked.name) && !/xml/.test(picked.type)) { toast.error('Elige el archivo .xml de la factura (no el PDF)'); return }
    if (picked.size > MAX_BYTES) { toast.error('El XML pesa más de 2 MB'); return }
    setReading(true)
    try {
      const parsed = parseCfdi(await picked.text())
      const [dup, found] = await Promise.all([findReceivingByUuid(parsed.uuid), findSuppliersByRfc(parsed.emisor.rfc)])
      setFile(picked)
      setCfdi(parsed)
      setDuplicate(dup)
      setSuppliers(found)
      setSupplierId(found.find((s) => s.status === 'active')?.id ?? found[0]?.id ?? '')
      setLines(parsed.conceptos.map((c) => ({ ...c, product: null, source: null, omit: false })))
    } catch (err) {
      toast.error(err.message)
    } finally { setReading(false) }
  }

  // Al tener proveedor: empareja con lo recordado y sugiere por código de barras / SKU.
  useEffect(() => {
    if (!supplierId || !cfdi) return undefined
    let active = true
    Promise.all([getSupplierCodes(supplierId), findProductsByCodes(cfdi.conceptos.map((c) => c.noIdentificacion))])
      .then(([remembered, suggested]) => {
        if (!active) return
        setLines((prev) => prev.map((l) => {
          if (l.source === 'elegido') return l
          const r = remembered.get(l.clave)
          if (r) return { ...l, product: r, source: 'recordado', suggestion: null }
          const sug = suggested.get(l.noIdentificacion)
          return sug ? { ...l, product: sug.product, source: 'sugerido', suggestion: sug.via } : { ...l, product: null, source: null }
        }))
      })
      .catch((err) => { if (active) toast.error(err.message) })
      .finally(() => { if (active) setMatchedFor(`${supplierId}|${cfdi.uuid}`) })
    return () => { active = false }
  }, [supplierId, cfdi, toast])

  const setLine = (linea, patch) => setLines((prev) => prev.map((l) => (l.linea === linea ? { ...l, ...patch } : l)))

  const create = async () => {
    setSaving(true)
    try {
      const res = await createReceivingFromCfdi({
        branchId: workingBranchId,
        supplierId,
        invoice: { uuid: cfdi.uuid, serie: cfdi.serie, folio: cfdi.folio, fecha: cfdi.fecha, total: cfdi.total, moneda: cfdi.moneda },
        items: included.map((l) => ({
          product_id: l.product.id, cantidad: l.cantidad, valor_unitario: l.valorUnitario,
          clave: l.clave, descripcion: l.descripcion, unidad: l.unidad,
          recordar: l.source !== 'recordado', // lo elegido o sugerido queda recordado para la próxima
        })),
      })
      try {
        await uploadEvidence({ file, companyId: profile.company_id, entityType: 'receiving_order', entityId: res.id,
          branchId: workingBranchId, description: `Factura CFDI ${cfdi.uuid}` })
        toast.success(`Recibo ${res.folio} creado en captura con ${res.partidas} partidas`)
      } catch (err) {
        toast.error(`Recibo ${res.folio} creado, pero no se pudo guardar el XML: ${err.message}`)
      }
      navigate(`/receiving/${res.id}`)
    } catch (err) {
      toast.error(err.message)
      setSaving(false)
    }
  }

  const invoiceName = [cfdi?.serie, cfdi?.folio].filter(Boolean).join('-') || '—'

  return (
    <div className="page">
      <Link to="/receiving" className="back-link"><ArrowLeft size={14} /> Recibos</Link>
      <PageHeader icon={FileCode2} title="Recibo desde factura XML"
        subtitle="Sube el XML (CFDI 4.0) de la factura del proveedor: se crea el recibo en captura con sus partidas"
        actions={cfdi && <Button size="sm" variant="ghost" onClick={reset}><RotateCcw size={14} /> Otra factura</Button>} />

      {!cfdi && (
        <Card>
          <div className="cfdi-drop">
            <FileCode2 size={36} />
            <p>Elige el archivo <strong>.xml</strong> que te mandó el proveedor junto con el PDF.</p>
            <label className={`btn btn-primary ${reading ? 'btn-disabled' : ''}`}>
              <Upload size={14} /> {reading ? 'Leyendo…' : 'Elegir XML'}
              <input type="file" accept=".xml,text/xml,application/xml" hidden onChange={pickFile} disabled={reading} />
            </label>
            <p className="form-hint">El archivo se lee en tu navegador. Las existencias no cambian hasta que cuentes y cierres el recibo.</p>
          </div>
        </Card>
      )}

      {cfdi && (
        <>
          <div className="detail-strip">
            <div><span>Proveedor (emisor)</span><strong>{cfdi.emisor.nombre || '—'}</strong><small className="mono">{cfdi.emisor.rfc}</small></div>
            <div><span>Factura</span><strong>{invoiceName}</strong><small>{formatDateTime(cfdi.fecha)}</small></div>
            <div><span>Total</span><strong>{formatCurrency(cfdi.total ?? 0)}</strong><small>{cfdi.moneda}</small></div>
            <div><span>Folio fiscal (UUID)</span><strong className="mono cfdi-uuid">{cfdi.uuid}</strong></div>
            <div><span>Conceptos</span><strong>{cfdi.conceptos.length}</strong></div>
          </div>

          {duplicate && (
            <p className="hint-box hint-danger">
              Esta factura ya está en el recibo <Link to={`/receiving/${duplicate.id}`}>{duplicate.folio}</Link>. Cancélalo si quieres volver a registrarla.
            </p>
          )}

          <Card title="Proveedor">
            {suppliers.length > 0 ? (
              <div className="form-stack">
                {suppliers.length > 1 ? (
                  <select className="form-input" aria-label="Proveedor" value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
                    {suppliers.map((s) => <option key={s.id} value={s.id}>{s.code} · {s.name}{s.status !== 'active' ? ' (inactivo)' : ''}</option>)}
                  </select>
                ) : (
                  <p><CheckCircle2 size={14} className="td-ok" /> <strong>{supplier?.name}</strong> <span className="text-muted">· {supplier?.code} · encontrado por RFC</span></p>
                )}
                {supplier && supplier.status !== 'active' && <p className="form-error">Este proveedor está {supplier.status === 'blocked' ? 'bloqueado' : 'inactivo'}.</p>}
              </div>
            ) : (
              <div className="form-stack">
                <p>No hay ningún proveedor con RFC <strong className="mono">{cfdi.emisor.rfc}</strong> en tu empresa.</p>
                {hasPermission(P.MANAGE_SUPPLIERS)
                  ? <div><Button size="sm" onClick={() => setCreatingSupplier(true)}><Plus size={14} /> Dar de alta «{cfdi.emisor.nombre || cfdi.emisor.rfc}»</Button></div>
                  : <p className="text-muted text-sm">Pide a quien administra proveedores que lo dé de alta con ese RFC.</p>}
              </div>
            )}
          </Card>

          {supplier && (
            <Card title="Partidas" flush
              action={matching ? <span className="text-muted text-sm">Emparejando…</span>
                : <span className="text-sm">{included.length - pending} de {included.length} emparejadas{lines.length - included.length ? ` · ${lines.length - included.length} omitidas` : ''}</span>}>
              {matching && !lines.some((l) => l.product) ? <Loader /> : (
                <div className="cfdi-lines">
                  {lines.map((l) => (
                    <div key={l.linea} className={`cfdi-line ${l.omit ? 'cfdi-line-omit' : !l.product ? 'cfdi-line-pending' : ''}`}>
                      <div className="cfdi-line-concept">
                        <span className="mono text-muted">{l.noIdentificacion || 'sin clave'}</span>
                        <strong>{l.descripcion}</strong>
                        <span className="text-sm">
                          {formatNumber(l.cantidad ?? 0, 3)} {l.unidad} × {formatCurrency(l.valorUnitario ?? 0)}
                          {!(l.cantidad > 0) && <span className="td-danger"> · cantidad inválida</span>}
                        </span>
                      </div>
                      <div className="cfdi-line-product">
                        {l.omit ? (
                          <><span className="text-muted">Omitida: no entra al recibo</span>
                            <button type="button" className="link-btn" onClick={() => setLine(l.linea, { omit: false })}>Incluir</button></>
                        ) : l.product ? (
                          <>
                            <ProductPicker value={l.product} label="Producto"
                              onSelect={(p) => setLine(l.linea, { product: p, source: p ? 'elegido' : null })} />
                            <Badge color={SOURCE_BADGE[l.source]?.color}>{SOURCE_BADGE[l.source]?.label}{l.source === 'sugerido' ? ` por ${l.suggestion}` : ''}</Badge>
                          </>
                        ) : (
                          <>
                            <ProductPicker value={null} label="Elige el producto"
                              onSelect={(p) => setLine(l.linea, { product: p, source: p ? 'elegido' : null })} />
                            <button type="button" className="link-btn" onClick={() => setLine(l.linea, { omit: true })}>Omitir (flete, servicio…)</button>
                          </>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          )}

          {supplier && (
            <div className="row-actions cfdi-actions">
              {!workingBranchId && <span className="form-error">Elige una sucursal arriba para crear el recibo.</span>}
              {pending > 0 && <span className="text-muted text-sm">Faltan {pending} partidas por emparejar u omitir.</span>}
              <Button onClick={create} loading={saving} disabled={!canCreate}>
                <CheckCircle2 size={14} /> Crear recibo en captura
              </Button>
            </div>
          )}
        </>
      )}

      {creatingSupplier && (
        <NewSupplierModal cfdi={cfdi} onClose={() => setCreatingSupplier(false)}
          onCreated={(s) => { setSuppliers([s]); setSupplierId(s.id); setCreatingSupplier(false) }} />
      )}
    </div>
  )
}

/** Alta rápida del proveedor con los datos del emisor de la factura. */
function NewSupplierModal({ cfdi, onClose, onCreated }) {
  const toast = useToast()
  const [form, setForm] = useState({
    code: cfdi.emisor.rfc.slice(0, 12), name: cfdi.emisor.nombre || cfdi.emisor.rfc,
    legal_name: cfdi.emisor.nombre, rfc: cfdi.emisor.rfc,
  })
  const [saving, setSaving] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const s = await saveSupplier({ ...form, status: 'active' })
      toast.success(`Proveedor ${s.name} dado de alta`)
      onCreated(s)
    } catch (err) { toast.error(err.message); setSaving(false) }
  }
  return (
    <Modal open onClose={onClose} title="Nuevo proveedor"
      footer={<><Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button type="submit" form="cfdi-supplier" loading={saving}>Dar de alta</Button></>}>
      <form id="cfdi-supplier" className="form-stack" onSubmit={submit}>
        <Input label="Código" required value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })}
          hint="Único en tu empresa. Se sugiere el RFC." />
        <Input label="Nombre comercial" required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        <Input label="Razón social" value={form.legal_name} onChange={(e) => setForm({ ...form, legal_name: e.target.value })} />
        <Input label="RFC" required value={form.rfc} readOnly hint="Viene de la factura" />
      </form>
    </Modal>
  )
}
