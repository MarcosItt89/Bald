/**
 * Compresión de imágenes en el navegador antes de subirlas.
 *
 * Objetivo: una foto de celular pesa 3–8 MB; redimensionada a 1600 px en
 * JPEG 80 % queda en ~300 KB. Ahorra datos móviles del empleado y espacio en
 * Supabase Storage. Si el navegador no puede decodificar el formato (p. ej.
 * HEIC fuera de Safari) se sube el archivo original.
 */
const MAX_SIDE = 1600
const QUALITY = 0.8

export async function compressImage(file) {
  if (!file.type.startsWith('image/') || file.type === 'image/gif') return file
  try {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height))
    if (scale === 1 && file.size < 1_000_000) return file

    const canvas = document.createElement('canvas')
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', QUALITY))
    if (!blob || blob.size >= file.size) return file
    return new File([blob], file.name.replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' })
  } catch {
    return file
  }
}
