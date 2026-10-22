/**
 * Servicio de evidencias (fotos / PDF) en Supabase Storage.
 *
 * Cada evidencia son dos cosas:
 *   1. El archivo en el bucket privado "evidence":
 *        {company_id}/{entity_type}/{yyyy-mm}/{uuid}.{ext}
 *   2. Una fila en evidence_files que lo liga a una entidad
 *      (respuesta de checklist, tarea, recibo, cenefa, ticket...).
 *
 * Las imágenes se ven con URL firmada temporal (1 h); nunca son públicas.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { byBranch, dayStart, dayEnd } from '../lib/queryHelpers'
import { compressImage } from '../utils/image'

const BUCKET = 'evidence'
const signedUrlCache = new Map()

export async function uploadEvidence({ file, companyId, entityType, entityId = null, branchId = null, description }) {
  if (!file) throw new Error('Selecciona un archivo.')
  const toUpload = await compressImage(file)
  if (toUpload.size > 10 * 1024 * 1024) throw new Error('El archivo supera 10 MB.')

  const ext = (toUpload.name.split('.').pop() || 'bin').toLowerCase()
  const month = new Date().toISOString().slice(0, 7)
  const path = `${companyId}/${entityType}/${month}/${crypto.randomUUID()}.${ext}`

  const { error: upErr } = await supabase.storage.from(BUCKET)
    .upload(path, toUpload, { contentType: toUpload.type, upsert: false })
  if (upErr) throw new Error(`No se pudo subir el archivo: ${upErr.message}`)

  try {
    return await unwrap(supabase.from('evidence_files').insert({
      entity_type: entityType,
      entity_id: entityId,
      branch_id: branchId,
      storage_path: path,
      file_name: file.name,
      mime_type: toUpload.type,
      size_bytes: toUpload.size,
      description: description || null,
    }).select().single())
  } catch (err) {
    await supabase.storage.from(BUCKET).remove([path]) // no dejar archivos huérfanos
    throw err
  }
}

export const getEvidence = ({ branchId, entityType, entityId, entityIds, status, statuses, from, to, limit = 120 } = {}) => {
  let q = byBranch(supabase.from('v_evidence').select('*'), branchId)
    .order('created_at', { ascending: false }).limit(limit)
  if (statuses) q = q.in('status', statuses)
  if (from) q = q.gte('created_at', dayStart(from))
  if (to) q = q.lte('created_at', dayEnd(to))
  if (entityType) q = q.eq('entity_type', entityType)
  if (entityId) q = q.eq('entity_id', entityId)
  if (entityIds) q = q.in('entity_id', entityIds)
  if (status) q = q.eq('status', status)
  return unwrap(q)
}

/** URL temporal para ver el archivo privado (se cachea 50 min). */
export async function getSignedUrl(path) {
  const cached = signedUrlCache.get(path)
  if (cached && cached.expires > Date.now()) return cached.url
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 3600)
  if (error) throw new Error(error.message)
  signedUrlCache.set(path, { url: data.signedUrl, expires: Date.now() + 50 * 60 * 1000 })
  return data.signedUrl
}

export const reviewEvidence = (id, status, comment) =>
  unwrap(supabase.from('evidence_files')
    .update({ status, review_comment: comment || null }).eq('id', id).select().single())

export async function deleteEvidence(evidence) {
  await unwrap(supabase.from('evidence_files').delete().eq('id', evidence.id))
  await supabase.storage.from(BUCKET).remove([evidence.storage_path])
}
