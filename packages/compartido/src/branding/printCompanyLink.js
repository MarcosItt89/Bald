/**
 * printCompanyLink — hoja imprimible con el QR del link de acceso de una
 * empresa (/e/<código>), para pegarla en la tienda. El QR se genera en el
 * navegador con uqr (sin servicios externos).
 */
import { escapeHtml, qrSvg } from '../utils/qr.js'

export function printCompanyLink({ name, url }) {
  const win = window.open('', '_blank', 'width=700,height=800')
  if (!win) { window.alert('Permite las ventanas emergentes para imprimir.'); return }
  win.document.write(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Acceso · ${escapeHtml(name)}</title>
    <style>
      body{font-family:Arial,sans-serif;margin:24px;text-align:center;color:#111}
      .sheet{border:2px dashed #111;border-radius:12px;padding:32px 24px;max-width:520px;margin:0 auto}
      h1{font-size:30px;margin:0 0 6px}
      .lead{font-size:16px;margin:0 0 20px}
      .qr svg{width:320px;height:320px}
      .url{font-family:monospace;font-size:15px;margin-top:14px;word-break:break-all}
      .steps{font-size:13px;color:#333;margin-top:18px;line-height:1.6}
      @media print{body{margin:0}}
    </style></head><body><div class="sheet">
      <h1>${escapeHtml(name)}</h1>
      <p class="lead">Escanea para entrar a Operalia</p>
      <div class="qr">${qrSvg(url)}</div>
      <div class="url">${escapeHtml(url)}</div>
      <div class="steps">Abre la cámara de tu celular, escanea el código y entra con tu usuario y contraseña.<br>
      Tu celular recordará la empresa: no tendrás que escribirla.</div>
    </div><script>window.onload=()=>{window.print()}</script></body></html>`)
  win.document.close()
}
