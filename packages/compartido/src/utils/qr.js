/**
 * Códigos QR generados en el navegador con uqr (sin servicios externos) y
 * escape de HTML para las hojas imprimibles.
 */
import { renderSVG } from 'uqr'

export const escapeHtml = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]))

export const qrSvg = (code) => renderSVG(code, { border: 1, ecc: 'M' })
