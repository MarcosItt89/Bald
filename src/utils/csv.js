/**
 * Exportación a CSV (se abre directo en Excel).
 *
 * Objetivo: que cualquier tabla pueda descargarse sin librerías externas.
 * Se antepone BOM UTF-8 para que Excel respete acentos y ñ.
 *
 *   downloadCsv('inventario.csv', rows, [
 *     { key: 'sku', label: 'SKU' },
 *     { key: 'stock', label: 'Existencia' },
 *     { label: 'Precio', value: (r) => r.price.toFixed(2) },
 *   ])
 */
const escapeCell = (value) => {
  if (value == null) return ''
  const s = String(value)
  return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function toCsv(rows, columns) {
  const header = columns.map((c) => escapeCell(c.label)).join(',')
  const body = rows.map((row) =>
    columns.map((c) => escapeCell(c.value ? c.value(row) : row[c.key])).join(','))
  return [header, ...body].join('\n')
}

export function downloadCsv(filename, rows, columns) {
  const blob = new Blob(['﻿' + toCsv(rows, columns)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
