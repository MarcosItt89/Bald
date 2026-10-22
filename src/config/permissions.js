/**
 * Catálogo de permisos que el frontend sabe verificar.
 *
 * Objetivo: evitar "strings mágicos" repartidos por el código. Si se escribe
 * mal un permiso, el error aparece al importar (undefined) y no en silencio.
 *
 * Fuente de verdad: tabla public.permissions (supabase/seed/0007_catalogos.sql).
 * Si agregas uno aquí, agrégalo también allá (y viceversa).
 *
 * El frontend usa los permisos SOLO para mostrar/ocultar opciones. La
 * seguridad real la aplican las políticas RLS y los triggers en Supabase.
 */
export const P = Object.freeze({
  VIEW_DASHBOARD:             'view_dashboard',
  VIEW_INVENTORY:             'view_inventory',
  MANAGE_INVENTORY:           'manage_inventory',
  VIEW_PRICES:                'view_prices',
  SCAN_PRODUCTS:              'scan_products',
  REPORT_PRICE_DIFFERENCE:    'report_price_difference',
  CREATE_ORDERS:              'create_orders',
  APPROVE_ORDERS:             'approve_orders',
  VIEW_SUPPLIERS:             'view_suppliers',
  MANAGE_SUPPLIERS:           'manage_suppliers',
  REGISTER_SUPPLIER_VISIT:    'register_supplier_visit',
  RECEIVE_PRODUCTS:           'receive_products',
  CLOSE_RECEIVING:            'close_receiving',
  FILL_CHECKLISTS:            'fill_checklists',
  REVIEW_CHECKLISTS:          'review_checklists',
  MANAGE_CHECKLIST_TEMPLATES: 'manage_checklist_templates',
  UPLOAD_EVIDENCE:            'upload_evidence',
  REVIEW_EVIDENCE:            'review_evidence',
  MANAGE_EXPIRATIONS:         'manage_expirations',
  REGISTER_WASTE:             'register_waste',
  MANAGE_PRICE_CHANGES:       'manage_price_changes',
  MANAGE_SHELF_TAGS:          'manage_shelf_tags',
  VALIDATE_SHELF_TAGS:        'validate_shelf_tags',
  VIEW_TASKS:                 'view_tasks',
  MANAGE_TASKS:               'manage_tasks',
  VIEW_REPORTS:               'view_reports',
  VIEW_AUDIT_LOGS:            'view_audit_logs',
  MANAGE_EMPLOYEES:           'manage_employees',
  MANAGE_BRANCHES:            'manage_branches',
  MANAGE_ROLES:               'manage_roles',
  CREATE_TICKETS:             'create_tickets',
  MANAGE_TICKETS:             'manage_tickets',
})

/** Alcances de rol (roles.scope) con su explicación para la UI. */
export const ROLE_SCOPES = {
  company:    { label: 'Empresa',      help: 'Ve todas las sucursales de la empresa' },
  branch:     { label: 'Sucursal',     help: 'Ve toda su sucursal' },
  department: { label: 'Departamento', help: 'Ve sus departamentos dentro de su sucursal' },
  self:       { label: 'Personal',     help: 'Ve su departamento; en tareas solo las propias' },
}
