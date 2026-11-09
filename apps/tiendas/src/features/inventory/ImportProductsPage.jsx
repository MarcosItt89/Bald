/**
 * ImportProductsPage — Inventario → Importar productos (propietario o
 * administrador: manage_inventory y alcance de empresa; migración 0030).
 *
 * 1. Plantilla CSV descargable.
 * 2. Sube un CSV (también el que guarda Excel): detecta separador (coma, punto
 *    y coma o tabulador), codificación (UTF-8 o Latin-1) y coma decimal.
 * 3. Vista previa con los errores de cada fila (precio inválido, unidad no
 *    permitida, SKU o código repetido en el archivo, código de otro producto…).
 *    Con errores no se importa: hay que quitarlos o corregir el archivo.
 * 4. Importa en bloques de 500 con barra de progreso; al final, resumen
 *    descargable. La base vuelve a validar todo (import_products).
 */
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, Download, FileUp, ListX, Upload } from 'lucide-react'
import { useAuth } from '@operalia/compartido/hooks/useAuth.js'
import { useAsync } from '@operalia/compartido/hooks/useAsync.js'
import { useToast } from '@operalia/compartido/hooks/useToast.js'
import { downloadCsv } from '@operalia/compartido/utils/csv.js'
import { todayISO } from '@operalia/compartido/utils/formatters.js'
import PageHeader from '@operalia/compartido/components/ui/PageHeader.jsx'
import Card from '@operalia/compartido/components/ui/Card.jsx'
import Table from '@operalia/compartido/components/ui/Table.jsx'
import Button from '@operalia/compartido/components/ui/Button.jsx'
import Badge from '@operalia/compartido/components/ui/Badge.jsx'
import ProgressBar from '@operalia/compartido/components/ui/ProgressBar.jsx'
import StatCard from '@operalia/compartido/components/ui/StatCard.jsx'
import { getBranches, getDepartments } from '../../services/organizationService'
import { getImportCatalog, importProducts } from '../../services/inventoryService'
import { readProductsCsv, templateCsv, validateRows } from './import/productCsv'

const CHUNK = 500
const PAGE = 100
const MAX_BYTES = 10 * 1024 * 1024
const MODES = [
  { value: 'ambos', label: 'Crear nuevos y actualizar existentes' },
  { value: 'crear', label: 'Solo crear productos nuevos' },
  { value: 'actualizar', label: 'Solo actualizar existentes' },
]
const SEPARATORS = { ',': 'coma', ';': 'punto y coma', '\t': 'tabulador' }
const STATE_BADGE = { creado: 'success', actualizado: 'info', error: 'danger' }
const loadBranches = () => getBranches({ onlyActive: true })

const fmt = (n) => n.toLocaleString('es-MX')

function downloadTemplate() {
  const url = URL.createObjectURL(new Blob([templateCsv()], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = 'plantilla-productos.csv'
  a.click()
  URL.revokeObjectURL(url)
}

export default function ImportProductsPage() {
  const { workingBranchId } = useAuth()
  const toast = useToast()
  const { data: branches = [] } = useAsync(loadBranches)
  const [branchId, setBranchId] = useState(workingBranchId ?? '')
  const [mode, setMode] = useState('ambos')
  const [file, setFile] = useState(null)         // { name, parsed, catalog, departments }
  const [reading, setReading] = useState(false)
  const [removed, setRemoved] = useState(() => new Set())
  const [view, setView] = useState('todas')
  const [page, setPage] = useState(0)
  const [progress, setProgress] = useState(null) // { done, total, block, blocks }
  const [results, setResults] = useState(null)
  const branch = branchId || branches[0]?.id || ''

  const checked = useMemo(() => (file ? validateRows(
    file.parsed.rows.filter((r) => !removed.has(r.fila)),
    { mode, decimalComma: file.parsed.info.decimalComma, ...file.catalog, departments: file.departments },
  ) : []), [file, removed, mode])
  const withErrors = checked.filter((r) => r.errors.length)
  const toCreate = checked.filter((r) => !r.errors.length && r.action === 'crear').length
  const toUpdate = checked.filter((r) => !r.errors.length && r.action === 'actualizar').length
  const shown = view === 'errores' ? withErrors : view === 'todas' ? checked : checked.filter((r) => !r.errors.length && r.action === view)
  const pages = Math.max(1, Math.ceil(shown.length / PAGE))
  const importing = progress && !results

  // Avisa antes de cerrar la pestaña a media importación.
  useEffect(() => {
    if (!importing) return undefined
    const warn = (e) => { e.preventDefault(); e.returnValue = '' }
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [importing])

  const pickFile = async (e) => {
    const picked = e.target.files?.[0]
    e.target.value = ''
    if (!picked) return
    if (/\.(xlsx|xlsm|xls|ods)$/i.test(picked.name)) {
      toast.error('Ese es un libro de Excel. Guárdalo como «CSV UTF-8 (delimitado por comas)» o «CSV» y súbelo.')
      return
    }
    if (picked.size > MAX_BYTES) { toast.error('El archivo pesa más de 10 MB'); return }
    setReading(true)
    try {
      const [buffer, catalog, departments] = await Promise.all([picked.arrayBuffer(), getImportCatalog(), getDepartments()])
      const parsed = readProductsCsv(buffer)
      if (parsed.missing.length) throw new Error('El archivo no tiene la columna «sku». Descarga la plantilla para ver el formato.')
      if (!parsed.rows.length) throw new Error('El archivo no tiene filas de productos')
      if (parsed.rows.length > 20000) throw new Error(`El archivo tiene ${fmt(parsed.rows.length)} filas; el máximo es 20,000 por importación`)
      setFile({ name: picked.name, parsed, catalog, departments })
      setRemoved(new Set())
      setResults(null)
      setProgress(null)
      setView('todas')
      setPage(0)
    } catch (err) {
      toast.error(err.message)
    } finally { setReading(false) }
  }

  const removeErrors = () => {
    setRemoved((prev) => new Set([...prev, ...withErrors.map((r) => r.fila)]))
    setView('todas')
    setPage(0)
  }

  const runImport = async () => {
    const valid = checked.filter((r) => !r.errors.length)
    const blocks = Math.ceil(valid.length / CHUNK)
    const out = []
    setProgress({ done: 0, total: valid.length, block: 1, blocks })
    for (let b = 0; b < blocks; b += 1) {
      const chunk = valid.slice(b * CHUNK, (b + 1) * CHUNK)
      setProgress({ done: b * CHUNK, total: valid.length, block: b + 1, blocks })
      try {
        const res = await importProducts(branch, chunk.map((r) => r.data), mode)
        const byFila = new Map(res.map((x) => [x.fila, x]))
        chunk.forEach((r) => out.push({ ...(byFila.get(r.fila) ?? { estado: 'error', motivo: 'Sin respuesta para esta fila' }), fila: r.fila, sku: r.data.sku, nombre: r.data.nombre ?? '' }))
      } catch (err) {
        // Si un bloque falla completo (red, sesión), se marca y se sigue con el siguiente.
        chunk.forEach((r) => out.push({ fila: r.fila, sku: r.data.sku, nombre: r.data.nombre ?? '', estado: 'error', motivo: `Bloque ${b + 1}: ${err.message}` }))
      }
    }
    setProgress({ done: valid.length, total: valid.length, block: blocks, blocks })
    setResults(out)
    const errs = out.filter((r) => r.estado === 'error').length
    if (errs) toast.error(`Importación terminada con ${fmt(errs)} ${errs === 1 ? 'error' : 'errores'}`); else toast.success('Importación terminada')
  }

  const downloadSummary = () => downloadCsv(`importacion-productos_${todayISO()}.csv`, results, [
    { key: 'fila', label: 'Fila' }, { key: 'sku', label: 'SKU' }, { key: 'nombre', label: 'Nombre' },
    { key: 'estado', label: 'Estado' }, { key: 'motivo', label: 'Motivo' },
  ])

  const reset = () => { setFile(null); setResults(null); setProgress(null); setRemoved(new Set()) }
  const tally = results && results.reduce((a, r) => ({ ...a, [r.estado]: (a[r.estado] ?? 0) + 1 }), {})
  const info = file?.parsed.info

  return (
    <div className="page">
      <Link to="/inventory" className="back-link"><ArrowLeft size={14} /> Inventario</Link>
      <PageHeader icon={FileUp} title="Importar productos"
        subtitle="Alta y actualización del catálogo desde un CSV (o un Excel guardado como CSV)"
        actions={<Button size="sm" variant="outline" onClick={downloadTemplate}><Download size={14} /> Plantilla CSV</Button>} />

      {!results && (
        <Card title="Archivo">
          <div className="import-setup">
            <div className="form-group">
              <label htmlFor="imp-branch" className="form-label">Sucursal para existencias y mínimos</label>
              <select id="imp-branch" className="form-input" value={branch} disabled={importing}
                onChange={(e) => setBranchId(e.target.value)}>
                {branches.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label htmlFor="imp-mode" className="form-label">Qué hacer</label>
              <select id="imp-mode" className="form-input" value={mode} disabled={importing} onChange={(e) => setMode(e.target.value)}>
                {MODES.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
              </select>
            </div>
            <div className="form-group">
              <span className="form-label">CSV</span>
              <label className={`btn btn-outline ${reading || importing ? 'btn-disabled' : ''}`}>
                <Upload size={14} /> {reading ? 'Leyendo…' : file ? 'Cambiar archivo' : 'Elegir archivo'}
                <input type="file" accept=".csv,.txt,text/csv" hidden onChange={pickFile} disabled={reading || importing} />
              </label>
            </div>
          </div>
          <p className="form-hint">
            Columnas: sku, nombre, codigo_barras, departamento (código o nombre), categoria, marca, unidad (pz, kg, g, l, ml, caja, paquete),
            costo, precio, existencia, minimo y controla_caducidad (sí/no). Al actualizar, una celda vacía deja el dato como está.
            La existencia se carga una sola vez por producto y sucursal (movimiento «Carga inicial»).
          </p>
        </Card>
      )}

      {file && !results && (
        <>
          <p className="text-muted text-sm import-info">
            <strong>{file.name}</strong> · {fmt(file.parsed.rows.length)} filas · separador {SEPARATORS[info.separator]} · {info.encoding}
            {info.decimalComma ? ' · coma decimal' : ''}
            {removed.size > 0 && ` · ${fmt(removed.size)} filas quitadas`}
            {file.parsed.unknown.length > 0 && ` · columnas ignoradas: ${file.parsed.unknown.join(', ')}`}
          </p>
          <div className="stat-grid">
            <StatCard label="Nuevos" value={fmt(toCreate)} tone="green" />
            <StatCard label="Se actualizan" value={fmt(toUpdate)} tone="blue" />
            <StatCard label="Con errores" value={fmt(withErrors.length)} tone={withErrors.length ? 'red' : 'slate'} />
          </div>

          {importing ? (
            <Card title={`Importando… bloque ${progress.block} de ${progress.blocks}`}>
              <ProgressBar value={progress.done} total={progress.total} />
              <p className="text-muted text-sm">{fmt(progress.done)} de {fmt(progress.total)} productos. No cierres esta pestaña.</p>
            </Card>
          ) : (
            <div className="row-actions import-actions">
              {withErrors.length > 0 && (
                <Button variant="outline" onClick={removeErrors}><ListX size={14} /> Quitar {fmt(withErrors.length)} filas con error</Button>
              )}
              <Button onClick={runImport} disabled={withErrors.length > 0 || !checked.length || !branch}
                title={withErrors.length ? 'Corrige o quita las filas con error' : undefined}>
                <Upload size={14} /> Importar {fmt(checked.length)} productos
              </Button>
            </div>
          )}
          {withErrors.length > 0 && !importing && (
            <p className="form-error">Hay filas con errores: corrígelas en el archivo y vuelve a subirlo, o quítalas para importar el resto.</p>
          )}

          <Card title="Vista previa" flush
            action={(
              <select className="filter-select" aria-label="Filtrar filas" value={view} onChange={(e) => { setView(e.target.value); setPage(0) }}>
                <option value="todas">Todas ({fmt(checked.length)})</option>
                <option value="errores">Con errores ({fmt(withErrors.length)})</option>
                <option value="crear">Nuevos ({fmt(toCreate)})</option>
                <option value="actualizar">Se actualizan ({fmt(toUpdate)})</option>
              </select>
            )}>
            <Table data={shown.slice(page * PAGE, (page + 1) * PAGE)} rowKey="fila" emptyText="Sin filas"
              rowClassName={(r) => (r.errors.length ? 'row-error' : '')}
              columns={[
                { key: 'fila', label: 'Fila', render: (v) => <span className="mono">{v}</span> },
                { key: 'sku', label: 'SKU', render: (_, r) => <span className="mono">{r.data.sku ?? '—'}</span> },
                { key: 'nombre', label: 'Nombre', render: (_, r) => r.data.nombre ?? <span className="text-muted">sin cambio</span> },
                { key: 'codigo', label: 'Código', render: (_, r) => <span className="mono">{r.source.codigo_barras || '—'}</span> },
                { key: 'unidad', label: 'Unidad', render: (_, r) => r.source.unidad || '—' },
                { key: 'precio', label: 'Precio', align: 'right', render: (_, r) => r.data.precio ?? r.source.precio ?? '—' },
                { key: 'existencia', label: 'Exist.', align: 'right', render: (_, r) => r.data.existencia ?? r.source.existencia ?? '—' },
                { key: 'accion', label: 'Resultado', render: (_, r) => (r.errors.length
                  ? <ul className="import-errors">{r.errors.map((m) => <li key={m}>{m}</li>)}</ul>
                  : <Badge color={r.action === 'crear' ? 'success' : 'info'}>{r.action === 'crear' ? 'Nuevo' : 'Se actualiza'}</Badge>) },
              ]} />
            {pages > 1 && (
              <div className="import-pager">
                <Button size="sm" variant="ghost" disabled={page === 0} onClick={() => setPage(page - 1)}>Anterior</Button>
                <span className="text-sm text-muted">Página {page + 1} de {pages}</span>
                <Button size="sm" variant="ghost" disabled={page >= pages - 1} onClick={() => setPage(page + 1)}>Siguiente</Button>
              </div>
            )}
          </Card>
        </>
      )}

      {results && (
        <Card title="Resumen de la importación" subtitle={file?.name}
          action={<>
            <Button size="sm" variant="outline" onClick={downloadSummary}><Download size={14} /> Descargar resumen</Button>
            <Button size="sm" onClick={reset}><FileUp size={14} /> Importar otro archivo</Button>
          </>}>
          <div className="stat-grid">
            <StatCard label="Creados" value={fmt(tally.creado ?? 0)} tone="green" />
            <StatCard label="Actualizados" value={fmt(tally.actualizado ?? 0)} tone="blue" />
            <StatCard label="Errores" value={fmt(tally.error ?? 0)} tone={tally.error ? 'red' : 'slate'} />
          </div>
          {tally.error > 0 && (
            <Table data={results.filter((r) => r.estado === 'error').slice(0, 200)} rowKey="fila" columns={[
              { key: 'fila', label: 'Fila' }, { key: 'sku', label: 'SKU' },
              { key: 'estado', label: 'Estado', render: (v) => <Badge color={STATE_BADGE[v]}>{v}</Badge> },
              { key: 'motivo', label: 'Motivo' },
            ]} />
          )}
        </Card>
      )}
    </div>
  )
}
