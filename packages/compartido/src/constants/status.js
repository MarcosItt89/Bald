/**
 * Catálogos de estados y opciones.
 *
 * Objetivo: traducir los códigos que guarda la base de datos (en inglés,
 * p. ej. 'in_progress') a etiquetas en español y a un color de Badge.
 * Cada mapa sigue la forma { codigo: { label, color } } que consume
 * <StatusBadge statusMap={...} value={...} />.
 *
 * Los códigos DEBEN coincidir con los CHECK de supabase/migrations/0001.
 */

// ─── INVENTARIO ──────────────────────────────────────────────────────────────
export const INVENTORY_STATUS = {
  normal:       { label: 'Normal',          color: 'success' },
  low:          { label: 'Bajo stock',      color: 'warning' },
  critical:     { label: 'Crítico',         color: 'danger'  },
  out_of_stock: { label: 'Sin existencia',  color: 'danger'  },
  review:       { label: 'En revisión',     color: 'info'    },
}

export const MOVEMENT_TYPES = {
  in:             { label: 'Entrada',               color: 'success', sign: +1 },
  out:            { label: 'Salida',                color: 'warning', sign: -1 },
  adjustment_in:  { label: 'Ajuste (+)',            color: 'info',    sign: +1 },
  adjustment_out: { label: 'Ajuste (−)',            color: 'info',    sign: -1 },
  receiving:      { label: 'Recibo',                color: 'success', sign: +1 },
  waste:          { label: 'Merma',                 color: 'danger',  sign: -1 },
  return:         { label: 'Devolución',            color: 'success', sign: +1 },
  transfer_in:    { label: 'Transferencia entrada', color: 'primary', sign: +1 },
  transfer_out:   { label: 'Transferencia salida',  color: 'primary', sign: -1 },
  count:          { label: 'Conteo físico',         color: 'default', sign: 0  },
}

export const UNITS = {
  pz: 'Pieza', kg: 'Kilogramo', g: 'Gramo', l: 'Litro', ml: 'Mililitro', caja: 'Caja', paquete: 'Paquete',
}

// ─── RECIBO / PROVEEDORES ────────────────────────────────────────────────────
export const RECEIVING_STATUS = {
  in_progress: { label: 'En captura', color: 'info'    },
  completed:   { label: 'Cerrado',    color: 'success' },
  cancelled:   { label: 'Cancelado',  color: 'default' },
}

export const SUPPLIER_STATUS = {
  active:   { label: 'Activo',    color: 'success' },
  inactive: { label: 'Inactivo',  color: 'default' },
  blocked:  { label: 'Bloqueado', color: 'danger'  },
}

// ─── CHECKLISTS ──────────────────────────────────────────────────────────────
export const CHECKLIST_RUN_STATUS = {
  pending:     { label: 'Pendiente',   color: 'warning' },
  in_progress: { label: 'En progreso', color: 'info'    },
  completed:   { label: 'Completado',  color: 'success' },
  overdue:     { label: 'Vencido',     color: 'danger'  },
  reopened:    { label: 'Reabierto',   color: 'warning' },
  cancelled:   { label: 'Cancelado',   color: 'default' },
}

export const CHECKLIST_REVIEW_STATUS = {
  pending_review:      { label: 'Por revisar',      color: 'warning' },
  approved:            { label: 'Aprobado',         color: 'success' },
  rejected:            { label: 'Rechazado',        color: 'danger'  },
  correction_required: { label: 'Corrección req.',  color: 'warning' },
}

export const SHIFTS = {
  apertura: 'Apertura', manana: 'Mañana', tarde: 'Tarde', cierre: 'Cierre', nocturno: 'Nocturno', especial: 'Especial',
}

export const ANSWER_TYPES = {
  yes_no:    'Sí / No',
  text:      'Texto',
  number:    'Número',
  option:    'Opción',
  photo:     'Foto',
  signature: 'Firma (nombre)',
}

export const FREQUENCIES = { daily: 'Diario', weekdays: 'Lunes a viernes', weekly: 'Semanal' }

// ─── EVIDENCIAS ──────────────────────────────────────────────────────────────
export const EVIDENCE_STATUS = {
  pending:             { label: 'Pendiente',       color: 'warning' },
  approved:            { label: 'Aprobada',        color: 'success' },
  rejected:            { label: 'Rechazada',       color: 'danger'  },
  correction_required: { label: 'Corrección req.', color: 'warning' },
}

export const EVIDENCE_ENTITIES = {
  checklist_run:    'Checklist',
  checklist_answer: 'Pregunta de checklist',
  inventory_movement: 'Merma',
  task:             'Tarea',
  receiving_order:  'Recibo',
  price_change:     'Cambio de precio',
  shelf_tag:        'Cenefa',
  order:            'Pedido',
  expiration:       'Caducidad',
  support_ticket:   'Ticket de soporte',
  product:          'Producto',
  supplier_visit:   'Visita de proveedor',
  other:            'General',
}

// ─── PEDIDOS ─────────────────────────────────────────────────────────────────
export const ORDER_STATUS = {
  requested: { label: 'Solicitado',  color: 'warning' },
  in_review: { label: 'En revisión', color: 'info'    },
  approved:  { label: 'Aprobado',    color: 'primary' },
  rejected:  { label: 'Rechazado',   color: 'danger'  },
  sent:      { label: 'Enviado',     color: 'info'    },
  received:  { label: 'Recibido',    color: 'success' },
  closed:    { label: 'Cerrado',     color: 'default' },
  cancelled: { label: 'Cancelado',   color: 'default' },
}

/**
 * Transiciones permitidas (espejo de tg_order_flow en 0003). La UI solo
 * muestra los botones válidos; la BD vuelve a validar.
 *   who: 'approver' requiere approve_orders; 'either' = aprobador o solicitante.
 */
export const ORDER_TRANSITIONS = {
  requested: [
    { to: 'in_review', label: 'Pasar a revisión', who: 'approver' },
    { to: 'approved',  label: 'Aprobar',          who: 'approver' },
    { to: 'rejected',  label: 'Rechazar',         who: 'approver', needsComment: true },
    { to: 'cancelled', label: 'Cancelar',         who: 'either' },
  ],
  in_review: [
    { to: 'approved', label: 'Aprobar',  who: 'approver' },
    { to: 'rejected', label: 'Rechazar', who: 'approver', needsComment: true },
  ],
  approved: [
    { to: 'sent',      label: 'Marcar enviado', who: 'approver' },
    { to: 'cancelled', label: 'Cancelar',       who: 'either' },
  ],
  sent:     [{ to: 'received', label: 'Confirmar recepción', who: 'either' }],
  received: [{ to: 'closed',   label: 'Cerrar pedido',       who: 'either' }],
}

// ─── PRECIOS Y CENEFAS ───────────────────────────────────────────────────────
export const PRICE_CHANGE_STATUS = {
  scheduled: { label: 'Programado', color: 'info'    },
  applied:   { label: 'Aplicado',   color: 'success' },
  cancelled: { label: 'Cancelado',  color: 'default' },
}

export const TAG_STATUS = {
  pending:   { label: 'Pendiente', color: 'warning' },
  printed:   { label: 'Impresa',   color: 'info'    },
  placed:    { label: 'Colocada',  color: 'primary' },
  validated: { label: 'Validada',  color: 'success' },
  rejected:  { label: 'Rechazada', color: 'danger'  },
}

// ─── CADUCIDADES ─────────────────────────────────────────────────────────────
/** Motivos de merma (inventory_movements.waste_reason). */
export const WASTE_REASONS = {
  expired:     { label: 'Caducado',    color: 'warning' },
  damaged:     { label: 'Dañado',      color: 'danger'  },
  theft:       { label: 'Robo',        color: 'danger'  },
  mishandling: { label: 'Mal manejo',  color: 'warning' },
  temperature: { label: 'Temperatura', color: 'info'    },
  other:       { label: 'Otro',        color: 'default' },
}

export const EXPIRATION_STATUS = {
  active:    { label: 'En anaquel', color: 'success' },
  markdown:  { label: 'Rebajado',   color: 'info'    },
  withdrawn: { label: 'Retirado',   color: 'default' },
  expired:   { label: 'Vencido',    color: 'danger'  },
  sold_out:  { label: 'Agotado',    color: 'default' },
}

/** Semáforo por días restantes. */
export const expirationUrgency = (daysLeft) => {
  if (daysLeft < 0)  return { label: 'Vencido',      color: 'danger'  }
  if (daysLeft <= 3) return { label: `${daysLeft} día(s)`, color: 'danger'  }
  if (daysLeft <= 7) return { label: `${daysLeft} días`,   color: 'warning' }
  return { label: `${daysLeft} días`, color: 'success' }
}

// ─── TAREAS ──────────────────────────────────────────────────────────────────
/** Antigüedad de tareas abiertas (días completos desde que se crearon). */
export const TASK_AGE_BUCKETS = [
  { key: 'lt1', label: '< 1 día' },
  { key: '1-3', label: '1–3 días' },
  { key: '4-7', label: '4–7 días' },
  { key: 'gt7', label: '> 7 días' },
]

export const taskAgeBucket = (createdAt) => {
  const days = Math.floor((Date.now() - new Date(createdAt)) / 864e5)
  return days < 1 ? 'lt1' : days <= 3 ? '1-3' : days <= 7 ? '4-7' : 'gt7'
}

export const PRIORITY = {
  low:      { label: 'Baja',    color: 'default' },
  medium:   { label: 'Media',   color: 'info'    },
  high:     { label: 'Alta',    color: 'warning' },
  critical: { label: 'Crítica', color: 'danger'  },
}

export const TASK_STATUS = {
  pending:     { label: 'Pendiente',   color: 'warning' },
  in_progress: { label: 'En progreso', color: 'info'    },
  completed:   { label: 'Completada',  color: 'success' },
  cancelled:   { label: 'Cancelada',   color: 'default' },
}

// ─── MESA DE AYUDA ───────────────────────────────────────────────────────────
export const TICKET_STATUS = {
  open:         { label: 'Abierto',             color: 'warning' },
  in_progress:  { label: 'En atención',         color: 'info'    },
  waiting_user: { label: 'Esperando respuesta', color: 'primary' },
  resolved:     { label: 'Resuelto',            color: 'success' },
  closed:       { label: 'Cerrado',             color: 'default' },
}

export const TICKET_CATEGORY = {
  bug:      'Error / falla',
  access:   'Acceso y contraseñas',
  data:     'Datos incorrectos',
  feature:  'Sugerencia / mejora',
  training: 'Duda de uso',
  hardware: 'Equipo / impresora / lector',
  network:  'Red, WiFi o antena',
  pos:      'Caja o terminal',
  printer:  'Impresora',
  scanner:  'Lector o báscula',
  other:    'Otro',
}

/** Módulos que el usuario puede elegir al reportar un problema. */
export const APP_MODULES = [
  'Dashboard', 'Inventario', 'Consulta de precios', 'Recibo', 'Proveedores', 'Pedidos',
  'Cambios de precio', 'Cenefas', 'Caducidades', 'Checklists', 'Evidencias', 'Tareas',
  'Reportes', 'Empleados', 'Roles y permisos', 'Inicio de sesión', 'Otro',
]

// ─── ORGANIZACIÓN ────────────────────────────────────────────────────────────
export const BRANCH_TYPES = {
  tienda: 'Tienda', express: 'Express', almacen: 'Almacén', cedis: 'CEDIS', restaurante: 'Restaurante', otro: 'Otro',
}

export const ACTIVE_STATUS = {
  active:    { label: 'Activo',     color: 'success' },
  inactive:  { label: 'Inactivo',   color: 'default' },
  suspended: { label: 'Suspendido', color: 'danger'  },
}

/** Empresas cliente (companies.status, migración 0022). */
export const COMPANY_STATUS = {
  active:    { label: 'Activa',     color: 'success' },
  suspended: { label: 'Suspendida', color: 'danger'  },
}

/** Salud de la cuenta de una empresa (platform_company_health, migración 0025). */
export const ACCOUNT_HEALTH = {
  green:  { label: 'Sana',      color: 'success' },
  yellow: { label: 'Atención',  color: 'warning' },
  red:    { label: 'En riesgo', color: 'danger'  },
}

/** Prospectos de la plataforma (platform_leads.status). */
export const LEAD_STATUS = {
  new:         { label: 'Nuevo',       color: 'info'    },
  demo:        { label: 'Demo',        color: 'primary' },
  negotiation: { label: 'Negociación', color: 'warning' },
  won:         { label: 'Ganado',      color: 'success' },
  lost:        { label: 'Perdido',     color: 'default' },
}

/** Convierte un mapa { code: {label} | label } a opciones de <Select>. */
export const toOptions = (map) =>
  Object.entries(map).map(([value, v]) => ({ value, label: typeof v === 'string' ? v : v.label }))
