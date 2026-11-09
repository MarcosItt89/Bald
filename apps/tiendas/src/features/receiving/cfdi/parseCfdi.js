/**
 * Lee en el navegador el XML de una factura CFDI 4.0 (también 3.3) del proveedor.
 * DOMParser con 'application/xml' no ejecuta scripts ni descarga entidades externas.
 *
 *   parseCfdi(texto) → {
 *     version, uuid, serie, folio, fecha, total, moneda, tipo,
 *     emisor: { rfc, nombre }, receptor: { rfc, nombre },
 *     conceptos: [{ linea, clave, noIdentificacion, descripcion, cantidad, valorUnitario, unidad, claveUnidad, importe }]
 *   }
 * Lanza Error con un mensaje para el usuario si no es una factura de ingreso timbrada.
 *
 * clave: NoIdentificacion del proveedor. Si el concepto no la trae, se usa la
 * descripción («desc:…»), para poder recordar el emparejamiento igual.
 */
const NAMESPACES = {
  'http://www.sat.gob.mx/cfd/4': '4.0',
  'http://www.sat.gob.mx/cfd/3': '3.3',
}
const TIPOS = { I: 'ingreso', E: 'egreso (nota de crédito)', T: 'traslado', N: 'nómina', P: 'pago' }
const UUID_RE = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/

const kids = (el, name) => (el ? [...el.children].filter((c) => c.localName === name) : [])
const kid = (el, name) => kids(el, name)[0] ?? null
const attr = (el, name) => (el?.getAttribute(name) ?? '').trim()
const num = (v) => (v === '' || Number.isNaN(Number(v)) ? null : Number(v))

export const conceptKey = (c) => c.noIdentificacion || `desc:${c.descripcion.toLowerCase().replace(/\s+/g, ' ').trim()}`

export function parseCfdi(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml')
  if (doc.getElementsByTagName('parsererror').length) throw new Error('El archivo no es un XML válido')
  const root = doc.documentElement
  if (root.localName !== 'Comprobante') throw new Error('El XML no es una factura CFDI (no tiene cfdi:Comprobante)')
  const version = NAMESPACES[root.namespaceURI]
  if (!version) throw new Error('El XML no usa el formato del SAT (CFDI 4.0)')

  const tipo = attr(root, 'TipoDeComprobante')
  if (tipo !== 'I') throw new Error(`Es un CFDI de ${TIPOS[tipo] ?? `tipo «${tipo}»`}; solo se reciben facturas de ingreso`)

  // El UUID está en el complemento TimbreFiscalDigital (cualquier nivel dentro de cfdi:Complemento).
  const timbre = [...root.getElementsByTagName('*')].find((e) => e.localName === 'TimbreFiscalDigital')
  const uuid = attr(timbre, 'UUID').toUpperCase()
  if (!UUID_RE.test(uuid)) throw new Error('La factura no está timbrada: falta el folio fiscal (UUID) del SAT')

  const emisor = kid(root, 'Emisor')
  const receptor = kid(root, 'Receptor')
  const conceptos = kids(kid(root, 'Conceptos'), 'Concepto').map((c, i) => {
    const concepto = {
      linea: i + 1,
      noIdentificacion: attr(c, 'NoIdentificacion'),
      descripcion: attr(c, 'Descripcion'),
      cantidad: num(attr(c, 'Cantidad')),
      valorUnitario: num(attr(c, 'ValorUnitario')),
      unidad: attr(c, 'Unidad') || attr(c, 'ClaveUnidad'),
      claveUnidad: attr(c, 'ClaveUnidad'),
      claveProdServ: attr(c, 'ClaveProdServ'),
      importe: num(attr(c, 'Importe')),
    }
    return { ...concepto, clave: conceptKey(concepto) }
  })
  if (!conceptos.length) throw new Error('La factura no tiene conceptos')

  return {
    version,
    uuid,
    serie: attr(root, 'Serie'),
    folio: attr(root, 'Folio'),
    fecha: attr(root, 'Fecha'),
    total: num(attr(root, 'Total')),
    moneda: attr(root, 'Moneda') || 'MXN',
    tipo,
    emisor: { rfc: attr(emisor, 'Rfc').toUpperCase(), nombre: attr(emisor, 'Nombre') },
    receptor: { rfc: attr(receptor, 'Rfc').toUpperCase(), nombre: attr(receptor, 'Nombre') },
    conceptos,
  }
}
