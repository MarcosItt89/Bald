/**
 * Servicio de la Plataforma (solo superadmins, tabla platform_admins).
 *
 * Objetivo: dar de alta y administrar las empresas cliente, ver cómo van,
 * acompañar a las nuevas y atender el soporte de todas las tiendas como
 * "Soporte Operalia".
 *
 * Todo pasa por funciones SQL de las migraciones 0024 y 0025 (SECURITY
 * DEFINER), que fallan si quien llama no es superadmin. Las de rendimiento
 * devuelven solo agregados. Las políticas RLS de cada empresa
 * no se abren: un superadmin no ve los datos de otra empresa por consultas
 * directas, solo por estas funciones.
 */
import { supabase, unwrap } from '../lib/supabaseClient'
import { emptyToNull, saveRow } from '../lib/queryHelpers'
import { normalizeCompanyCode } from '../config/env'

// ─── Empresas ────────────────────────────────────────────────────────────────
export const getCompanies = () => unwrap(supabase.rpc('platform_list_companies'))

/** Alta completa: empresa, semilla base, primera sucursal y propietario con su cuenta. */
export const provisionCompany = ({
  name, legalName, rfc, code, timezone, branchCode, branchName,
  ownerUsername, ownerFullName, ownerPassword, withDemo = false,
}) =>
  unwrap(supabase.rpc('provision_company', {
    p_name: name.trim(),
    p_legal_name: legalName?.trim() || null,
    p_rfc: rfc?.trim() || null,
    p_code: normalizeCompanyCode(code),
    p_timezone: timezone,
    p_branch_code: branchCode.trim(),
    p_branch_name: branchName.trim(),
    p_owner_username: ownerUsername.trim().toLowerCase(),
    p_owner_full_name: ownerFullName.trim(),
    p_owner_password: ownerPassword,
    p_with_demo: !!withDemo,
  }))

/** status: 'active' | 'suspended'. Suspendida: sus empleados pierden el acceso, sin borrar datos. */
export const setCompanyStatus = (companyId, status) =>
  unwrap(supabase.rpc('platform_set_company_status', { p_company_id: companyId, p_status: status }))

/** Salud de la cuenta (green | yellow | red, con motivos) y avance de arranque por empresa. */
export const getCompanyHealth = () => unwrap(supabase.rpc('platform_company_health'))

// ─── Rendimiento ─────────────────────────────────────────────────────────────
/** Una fila por empresa (branch_id null) y una por sucursal, con numeradores y denominadores. */
export const getPlatformKpis = ({ from, to }) =>
  unwrap(supabase.rpc('platform_company_kpis', { p_from: from, p_to: to }))

/** Serie diaria [{ day, value, base }]; companyId null = toda la plataforma. */
export const getPlatformTrend = ({ companyId, metric, from, to }) =>
  unwrap(supabase.rpc('platform_company_trend', { p_company_id: companyId || null, p_metric: metric, p_from: from, p_to: to }))

/** % de checklists completados por sucursal y día. */
export const getChecklistHeatmap = ({ companyId, from, to }) =>
  unwrap(supabase.rpc('platform_checklist_heatmap', { p_from: from, p_to: to, p_company_id: companyId || null }))

// ─── Prospectos ──────────────────────────────────────────────────────────────
// La empresa ligada se muestra con getCompanies(): un join a companies vendría
// vacío para otras empresas (RLS de companies).
export const getLeads = () =>
  unwrap(supabase.from('platform_leads').select('*').order('updated_at', { ascending: false }))

export const saveLead = (lead) => {
  const { created_by, created_at, updated_at, ...row } = lead // columnas que llena la base
  return saveRow('platform_leads', emptyToNull(row))
}

export const deleteLead = (id) => unwrap(supabase.from('platform_leads').delete().eq('id', id))

/** Liga el prospecto con la empresa que se le dio de alta (y lo marca ganado). */
export const linkLeadToCompany = (leadId, companyId) =>
  unwrap(supabase.from('platform_leads').update({ company_id: companyId, status: 'won' }).eq('id', leadId))

// ─── Soporte de tiendas ──────────────────────────────────────────────────────
/** status: un estado, 'active' (abiertos), 'done' (resueltos y cerrados) u 'overdue'. */
export const getPlatformTickets = ({ companyId, status, search, limit = 200 } = {}) =>
  unwrap(supabase.rpc('platform_list_tickets', {
    p_company_id: companyId || null,
    p_status: status || null,
    p_search: search?.trim() || null,
    p_limit: limit,
  }))

/** { ticket, messages } — conversación completa, con notas internas marcadas. */
export const getPlatformTicket = (id) => unwrap(supabase.rpc('platform_get_ticket', { p_ticket_id: id }))

/** Responde como "Soporte Operalia"; status opcional (p. ej. 'resolved'). */
export const replyPlatformTicket = (id, body, status = null) =>
  unwrap(supabase.rpc('platform_reply_ticket', { p_ticket_id: id, p_body: body?.trim() || null, p_status: status || null }))
