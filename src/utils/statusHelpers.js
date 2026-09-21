// ─── PRODUCT STATUS ──────────────────────────────────────────────────────────
export const PRODUCT_STATUS = {
  active:    { label: 'Activo',     color: 'success' },
  low_stock: { label: 'Stock bajo', color: 'warning' },
  critical:  { label: 'Crítico',   color: 'danger'  },
  inactive:  { label: 'Inactivo',  color: 'default' },
}

// ─── CHECKLIST RUN STATUS ────────────────────────────────────────────────────
// Representa el estado de una ejecución diaria (checklist_runs)
export const CHECKLIST_RUN_STATUS = {
  pending:     { label: 'Pendiente',   color: 'warning' },
  in_progress: { label: 'En progreso', color: 'info'    },
  completed:   { label: 'Completado',  color: 'success' },
  overdue:     { label: 'Vencido',     color: 'danger'  },
  reopened:    { label: 'Reabierto',   color: 'warning' },
  cancelled:   { label: 'Cancelado',   color: 'default' },
}

// Alias para componentes que aún usan CHECKLIST_STATUS
export const CHECKLIST_STATUS = CHECKLIST_RUN_STATUS

// ─── CHECKLIST REVIEW STATUS ─────────────────────────────────────────────────
// Estado de la revisión del gerente sobre un checklist completado
export const CHECKLIST_REVIEW_STATUS = {
  pending_review:      { label: 'Por revisar',     color: 'warning' },
  approved:            { label: 'Aprobado',         color: 'success' },
  rejected:            { label: 'Rechazado',        color: 'danger'  },
  correction_required: { label: 'Corrección req.',  color: 'warning' },
}

// ─── ANSWER TYPES ────────────────────────────────────────────────────────────
export const ANSWER_TYPES = {
  yes:            'yes',
  no:             'no',
  not_applicable: 'not_applicable',
  text:           'text',
  number:         'number',
  option:         'option',
}

// ─── ORDER STATUS ─────────────────────────────────────────────────────────────
export const ORDER_STATUS = {
  pending_approval: { label: 'Pendiente aprobación', color: 'warning' },
  approved:         { label: 'Aprobado',              color: 'info'    },
  received:         { label: 'Recibido',              color: 'success' },
  cancelled:        { label: 'Cancelado',             color: 'danger'  },
}

// ─── TAG STATUS ───────────────────────────────────────────────────────────────
export const TAG_STATUS = {
  pending:   { label: 'Pendiente', color: 'warning' },
  printed:   { label: 'Impresa',   color: 'info'    },
  placed:    { label: 'Colocada',  color: 'success' },
  validated: { label: 'Validada',  color: 'success' },
}

// ─── TASK PRIORITY ────────────────────────────────────────────────────────────
export const TASK_PRIORITY = {
  low:      { label: 'Baja',    color: 'default' },
  medium:   { label: 'Media',   color: 'info'    },
  high:     { label: 'Alta',    color: 'warning' },
  critical: { label: 'Crítica', color: 'danger'  },
}

// ─── TASK STATUS ─────────────────────────────────────────────────────────────
export const TASK_STATUS = {
  pending:     { label: 'Pendiente',   color: 'warning' },
  in_progress: { label: 'En progreso', color: 'info'    },
  completed:   { label: 'Completada',  color: 'success' },
  cancelled:   { label: 'Cancelada',   color: 'default' },
}
