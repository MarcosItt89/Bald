/**
 * Comunicados con acuse de lectura (0021).
 * Al publicar, la base avisa a cada empleado del alcance (empresa, zona,
 * sucursal o departamento). Cada quien confirma con mark_announcement_read y
 * el publicador ve quién falta con announcement_progress.
 * El adjunto va al bucket privado «announcements»: {company_id}/{uuid}.{ext}.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { emptyToNull } from '../lib/queryHelpers'
import { compressImage } from '../utils/image'

const BUCKET = 'announcements'

export const getAnnouncements = ({ limit = 200 } = {}) =>
  unwrap(supabase.from('v_announcements').select('*').order('published_at', { ascending: false }).limit(limit))

/** Comunicados vigentes sin confirmar (para el Dashboard). */
export const getUnreadAnnouncements = () =>
  unwrap(supabase.from('v_announcements').select('id, title, published_at, published_by_name')
    .eq('status', 'active').eq('is_for_me', true).eq('is_expired', false).is('my_read_at', null)
    .order('published_at', { ascending: false }))

export const markAnnouncementRead = (id) =>
  unwrap(supabase.rpc('mark_announcement_read', { p_id: id }))

export const getAnnouncementProgress = (id) =>
  unwrap(supabase.rpc('announcement_progress', { p_id: id }))

export const archiveAnnouncement = (id) =>
  unwrap(supabase.from('announcements').update({ status: 'archived' }).eq('id', id))

export async function publishAnnouncement({ file, companyId, ...form }) {
  let attachment = {}
  if (file) {
    const toUpload = await compressImage(file)
    if (toUpload.size > 10 * 1024 * 1024) throw new Error('El adjunto supera 10 MB.')
    const ext = (toUpload.name.split('.').pop() || 'bin').toLowerCase()
    const path = `${companyId}/${crypto.randomUUID()}.${ext}`
    const { error } = await supabase.storage.from(BUCKET).upload(path, toUpload, { contentType: toUpload.type, upsert: false })
    if (error) throw new Error(`No se pudo subir el adjunto: ${error.message}`)
    attachment = { attachment_path: path, attachment_name: file.name, attachment_type: toUpload.type }
  }
  const scoped = {
    zone_id: form.scope === 'zone' ? form.zone_id : null,
    branch_id: ['branch', 'department'].includes(form.scope) ? form.branch_id : null,
    department_id: form.scope === 'department' ? form.department_id : null,
  }
  try {
    return await unwrap(supabase.from('announcements').insert(emptyToNull({
      company_id: companyId, title: form.title.trim(), body: form.body.trim(), scope: form.scope,
      valid_until: form.valid_until, ...scoped, ...attachment,
    })).select().single())
  } catch (err) {
    if (attachment.attachment_path) await supabase.storage.from(BUCKET).remove([attachment.attachment_path])
    throw err
  }
}

export async function getAttachmentUrl(path) {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 3600)
  if (error) throw new Error(error.message)
  return data.signedUrl
}
