/**
 * Lectura y validación del CSV de productos (Inventario → Importar).
 * Funciones puras (sin React ni Supabase), para poder probarlas solas.
 *
 *   decodeText(buffer)        UTF-8, o Latin-1 (windows-1252) si no es UTF-8 válido
 *   detectSeparator(text)     coma, punto y coma o tabulador (el más frecuente en el encabezado)
 *   parseCsv(text, sep)       filas → arreglos (comillas, "" escapadas y saltos dentro de comillas)
 *   readProductsCsv(buffer)   todo junto: { rows, columns, missing, unknown, info }
 *   validateRows(rows, ctx)   errores por fila y la acción (crear / actualizar)
 */

export const TEMPLATE_COLUMNS = ['sku', 'nombre', 'codigo_barras', 'departamento', 'categoria', 'marca', 'unidad',
  'costo', 'precio', 'existencia', 'minimo', 'controla_caducidad']
export const UNITS = ['pz', 'kg', 'g', 'l', 'ml', 'caja', 'paquete']
const NUMERIC = { costo: 'Costo', precio: 'Precio', existencia: 'Existencia', minimo: 'Mínimo' }

// Encabezados que también se aceptan (ya normalizados).
const HEADER_ALIASES = {
  codigo_de_barras: 'codigo_barras', codigobarras: 'codigo_barras', ean: 'codigo_barras', upc: 'codigo_barras',
  descripcion: 'nombre', producto: 'nombre', depto: 'departamento', categoria_producto: 'categoria',
  unidad_de_medida: 'unidad', um: 'unidad', costo_unitario: 'costo', precio_venta: 'precio',
  existencia_inicial: 'existencia', stock: 'existencia', inventario: 'existencia',
  stock_minimo: 'minimo', minimo_stock: 'minimo', min: 'minimo', caducidad: 'controla_caducidad',
}
const UNIT_ALIASES = {
  pieza: 'pz', piezas: 'pz', pza: 'pz', pzas: 'pz', pzs: 'pz', kilo: 'kg', kilos: 'kg', kilogramo: 'kg', kilogramos: 'kg',
  gramo: 'g', gramos: 'g', gr: 'g', litro: 'l', litros: 'l', lt: 'l', lts: 'l', mililitro: 'ml', mililitros: 'ml',
  cajas: 'caja', paquetes: 'paquete', paq: 'paquete',
}
const TRUE = ['si', 'sí', 's', 'true', 'verdadero', '1', 'x', 'yes', 'y']
const FALSE = ['no', 'n', 'false', 'falso', '0']

const stripAccents = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '')
export const normalizeHeader = (h) => {
  const k = stripAccents(String(h ?? '')).toLowerCase().trim().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
  return HEADER_ALIASES[k] ?? k
}

/** UTF-8 si el archivo lo es; si no, Latin-1 (lo que guarda Excel en Windows como «CSV»). */
export function decodeText(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
    return { text: text.charCodeAt(0) === 0xfeff ? text.slice(1) : text, encoding: 'UTF-8' } // sin BOM
  } catch {
    return { text: new TextDecoder('windows-1252').decode(bytes), encoding: 'Latin-1' }
  }
}

/** Separador más frecuente en la primera línea, fuera de comillas. */
export function detectSeparator(text) {
  const counts = { ',': 0, ';': 0, '\t': 0 }
  let quoted = false
  for (const ch of text) {
    if (ch === '"') quoted = !quoted
    else if (!quoted && (ch === '\n' || ch === '\r')) break
    else if (!quoted && ch in counts) counts[ch] += 1
  }
  const [best, n] = Object.entries(counts).sort((a, b) => b[1] - a[1])[0]
  return n > 0 ? best : ','
}

/** CSV → arreglo de filas (cada una, arreglo de celdas). Ignora filas vacías. */
export function parseCsv(text, sep) {
  const rows = []
  let row = []
  let cell = ''
  let quoted = false
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { cell += '"'; i += 1 } else quoted = false
      } else cell += ch
    } else if (ch === '"' && cell === '') quoted = true
    else if (ch === sep) { row.push(cell); cell = '' }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i += 1
      row.push(cell); cell = ''
      if (row.some((c) => c.trim() !== '')) rows.push(row)
      row = []
    } else cell += ch
  }
  row.push(cell)
  if (row.some((c) => c.trim() !== '')) rows.push(row)
  return rows
}

/** ¿Los números usan coma decimal? (Excel en configuración regional de España, p. ej.) */
export function detectDecimalComma(objects, sep) {
  let comma = 0
  let dot = 0
  for (const o of objects) {
    for (const k of Object.keys(NUMERIC)) {
      const v = (o[k] ?? '').replace(/[\s$]/g, '')
      if (/^-?\d+,\d{1,2}$/.test(v) || /^-?\d{1,3}(\.\d{3})+,\d+$/.test(v)) comma += 1
      else if (/^-?\d+\.\d{1,2}$/.test(v) || /^-?\d{1,3}(,\d{3})+\.\d+$/.test(v)) dot += 1
    }
  }
  return comma > dot || (comma === dot && sep === ';' && comma > 0)
}

/** '1.234,50' / '1,234.50' / '$ 12' → '1234.50' / '12'. Vacío → ''. Inválido → null. */
export function parseNumber(raw, decimalComma) {
  let v = String(raw ?? '').replace(/[\s$]/g, '')
  if (v === '') return ''
  const lastDot = v.lastIndexOf('.')
  const lastComma = v.lastIndexOf(',')
  if (lastDot >= 0 && lastComma >= 0) {
    v = lastComma > lastDot ? v.replace(/\./g, '').replace(',', '.') : v.replace(/,/g, '')
  } else if (lastComma >= 0) {
    v = !decimalComma && /^-?\d{1,3}(,\d{3})+$/.test(v) ? v.replace(/,/g, '') : v.replace(',', '.')
  } else if (lastDot >= 0 && decimalComma && /^-?\d{1,3}(\.\d{3})+$/.test(v)) {
    v = v.replace(/\./g, '')
  }
  return /^-?\d+(\.\d+)?$/.test(v) ? v : null
}

/** Archivo → objetos con las columnas de la plantilla. */
export function readProductsCsv(buffer) {
  const { text, encoding } = decodeText(buffer)
  const sep = detectSeparator(text)
  const [header = [], ...body] = parseCsv(text, sep)
  const keys = header.map(normalizeHeader)
  const objects = body.map((cells, i) => {
    const o = { fila: i + 2 } // la fila 1 es el encabezado, como en Excel
    keys.forEach((k, j) => { if (TEMPLATE_COLUMNS.includes(k)) o[k] = (cells[j] ?? '').trim() })
    return o
  })
  const decimalComma = detectDecimalComma(objects, sep)
  return {
    rows: objects,
    columns: keys.filter((k) => TEMPLATE_COLUMNS.includes(k)),
    missing: ['sku'].filter((k) => !keys.includes(k)),
    unknown: header.filter((h, j) => h.trim() && !TEMPLATE_COLUMNS.includes(keys[j])),
    info: { encoding, separator: sep, decimalComma },
  }
}

const parseBool = (v) => {
  const s = stripAccents(String(v ?? '')).toLowerCase().trim()
  if (s === '') return ''
  if (TRUE.includes(s)) return 'sí'
  if (FALSE.includes(s)) return 'no'
  return null
}

/**
 * Valida cada fila contra el archivo y el catálogo de la empresa.
 * ctx: { mode: 'crear'|'actualizar'|'ambos', decimalComma,
 *        skus: Map<sku, true>, barcodeOwner: Map<código, sku>, departments: [{ code, name }] }
 * Devuelve [{ fila, action: 'crear'|'actualizar', errors: [], data }] — data es lo que se manda a import_products.
 */
export function validateRows(rows, { mode, decimalComma, skus, barcodeOwner, departments }) {
  const deptKeys = new Set(departments.flatMap((d) => [d.code, d.name].filter(Boolean).map((x) => x.toLowerCase().trim())))
  const bySku = new Map()
  const byBarcode = new Map()
  rows.forEach((r) => {
    if (r.sku) bySku.set(r.sku, [...(bySku.get(r.sku) ?? []), r.fila])
    if (r.codigo_barras) byBarcode.set(r.codigo_barras, [...(byBarcode.get(r.codigo_barras) ?? []), r.fila])
  })

  return rows.map((r) => {
    const errors = []
    const data = { fila: r.fila }
    const sku = (r.sku ?? '').trim()
    const exists = sku && skus.has(sku)
    const action = exists ? 'actualizar' : 'crear'

    if (!sku) errors.push('Falta el SKU')
    else if (sku.length > 64) errors.push('SKU demasiado largo (máximo 64)')
    else if (bySku.get(sku).length > 1) errors.push(`SKU repetido en el archivo (filas ${bySku.get(sku).join(', ')})`)
    if (exists && mode === 'crear') errors.push('El SKU ya existe (modo: solo crear)')
    if (sku && !exists && mode === 'actualizar') errors.push('El SKU no existe (modo: solo actualizar)')
    data.sku = sku

    const nombre = (r.nombre ?? '').trim()
    if (!nombre && action === 'crear') errors.push('Falta el nombre (producto nuevo)')
    if (nombre.length > 200) errors.push('Nombre demasiado largo (máximo 200)')
    data.nombre = nombre

    const code = (r.codigo_barras ?? '').trim()
    if (code) {
      if (/^\d+(\.\d+)?e\+?\d+$/i.test(code.replace(',', '.'))) {
        errors.push(`Código de barras en notación científica (${code}): en Excel dale formato de texto a esa columna`)
      } else if (code.length > 50) errors.push('Código de barras demasiado largo (máximo 50)')
      else if (byBarcode.get(code).length > 1) errors.push(`Código de barras repetido en el archivo (filas ${byBarcode.get(code).join(', ')})`)
      else if (barcodeOwner.has(code) && barcodeOwner.get(code) !== sku) errors.push(`El código de barras ${code} ya es del producto ${barcodeOwner.get(code)}`)
    }
    data.codigo_barras = code

    const dept = (r.departamento ?? '').trim()
    if (dept && !deptKeys.has(dept.toLowerCase())) errors.push(`El departamento «${dept}» no existe`)
    data.departamento = dept

    const unitRaw = stripAccents((r.unidad ?? '').trim().toLowerCase()).replace(/\.$/, '')
    const unit = UNIT_ALIASES[unitRaw] ?? unitRaw
    if (unit && !UNITS.includes(unit)) errors.push(`Unidad no permitida: «${r.unidad}» (${UNITS.join(', ')})`)
    data.unidad = unit

    for (const [k, label] of Object.entries(NUMERIC)) {
      const n = parseNumber(r[k], decimalComma)
      if (n === null) errors.push(`${label} inválido: «${r[k]}»`)
      else if (n !== '' && Number(n) < 0) errors.push(`${label} no puede ser negativo`)
      data[k] = n ?? ''
    }

    const exp = parseBool(r.controla_caducidad)
    if (exp === null) errors.push(`Controla caducidad inválido: «${r.controla_caducidad}» (usa sí o no)`)
    data.controla_caducidad = exp ?? ''

    data.categoria = (r.categoria ?? '').trim()
    data.marca = (r.marca ?? '').trim()
    // Celdas vacías no se mandan: al actualizar significan «no cambiar».
    Object.keys(data).forEach((k) => { if (data[k] === '') delete data[k] })
    return { fila: r.fila, action, errors, data, source: r }
  })
}

/** Plantilla con encabezados y dos ejemplos (UTF-8 con BOM, para que Excel respete acentos). */
export function templateCsv() {
  const rows = [
    TEMPLATE_COLUMNS,
    ['ABR-001', 'Arroz blanco 1 kg', '7501000000017', 'ABR', 'Granos', 'Del Valle', 'pz', '18.50', '27.90', '24', '6', 'no'],
    ['LAC-010', 'Leche entera 1 L', '7501000000024', 'Lácteos', 'Leche', 'La Norteña', 'pz', '21.00', '28.50', '36', '12', 'sí'],
  ]
  return '﻿' + rows.map((r) => r.map((c) => (/[",;\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c)).join(',')).join('\r\n')
}
