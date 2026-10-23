/**
 * printCheckpoints — ventana imprimible con los QR de los puntos de control.
 * El QR se genera en el navegador con uqr (sin servicios externos).
 */
import { renderSVG } from 'uqr'

const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]))

export const qrSvg = (code) => renderSVG(code, { border: 1, ecc: 'M' })

export function printCheckpoints(points) {
  const win = window.open('', '_blank', 'width=900,height=700')
  if (!win) { window.alert('Permite las ventanas emergentes para imprimir.'); return }

  const cards = points.map((p) => `
    <div class="card">
      <div class="qr">${qrSvg(p.code)}</div>
      <div class="name">${escapeHtml(p.name)}</div>
      <div class="meta">${escapeHtml(p.branch?.name ?? '')}${p.department?.name ? ` · ${escapeHtml(p.department.name)}` : ''}</div>
      <div class="code">${escapeHtml(p.code)}</div>
      <div class="hint">Escanéalo en Operalia para iniciar el checklist</div>
    </div>`).join('')

  win.document.write(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Puntos QR</title>
    <style>
      body{font-family:Arial,sans-serif;margin:12px}
      .grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}
      .card{border:2px dashed #111;border-radius:8px;padding:14px;text-align:center;page-break-inside:avoid}
      .qr svg{width:190px;height:190px}
      .name{font-size:20px;font-weight:800;margin-top:6px}
      .meta{font-size:12px;color:#333;margin-top:2px}
      .code{font-family:monospace;font-size:14px;letter-spacing:1px;margin-top:6px}
      .hint{font-size:10px;color:#555;margin-top:4px}
      @media print{body{margin:0}}
    </style></head><body><div class="grid">${cards}</div>
    <script>window.onload=()=>{window.print()}</script></body></html>`)
  win.document.close()
}
