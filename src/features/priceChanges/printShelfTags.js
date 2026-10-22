/**
 * printShelfTags — abre una ventana con las cenefas en formato imprimible.
 *
 * Diseño de etiqueta: nombre del producto, precio grande, SKU, código de
 * barras (texto) y fecha. 3 columnas por hoja carta. Se usa la impresión
 * nativa del navegador (Ctrl+P) para no depender de librerías.
 */
import { formatCurrency, formatDate } from '../../utils/formatters'

const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]))

export function printShelfTags(tags) {
  const win = window.open('', '_blank', 'width=900,height=700')
  if (!win) { window.alert('Permite las ventanas emergentes para imprimir.'); return }

  const cards = tags.map((t) => `
    <div class="tag">
      <div class="name">${escapeHtml(t.product_name)}</div>
      <div class="price">${escapeHtml(formatCurrency(t.new_price ?? t.current_price))}</div>
      ${t.old_price ? `<div class="old">Antes ${escapeHtml(formatCurrency(t.old_price))}</div>` : ''}
      <div class="meta"><span>${escapeHtml(t.sku)}</span><span>${escapeHtml(formatDate(t.effective_date ?? t.created_at))}</span></div>
    </div>`).join('')

  win.document.write(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Cenefas</title>
    <style>
      body{font-family:Arial,sans-serif;margin:12px}
      .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
      .tag{border:2px solid #111;border-radius:6px;padding:10px;page-break-inside:avoid;height:130px;display:flex;flex-direction:column}
      .name{font-size:13px;font-weight:700;text-transform:uppercase;min-height:32px}
      .price{font-size:36px;font-weight:900;margin:auto 0 0}
      .old{font-size:11px;text-decoration:line-through;color:#555}
      .meta{display:flex;justify-content:space-between;font-size:10px;color:#333;margin-top:4px}
      @media print{body{margin:0}}
    </style></head><body><div class="grid">${cards}</div>
    <script>window.onload=()=>{window.print()}</script></body></html>`)
  win.document.close()
}
