// ─── MOCK DATA ─────────────────────────────────────────────────────────────
// Replace each section with a Supabase query when the corresponding table is ready.

import { DEPARTMENT_IDS } from '../utils/departments'

// ─── PERMISSIONS ────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('permissions').select('name')
export const PERMISSIONS = [
  'view_dashboard',
  'view_inventory',
  'view_prices',
  'scan_products',
  'report_price_difference',
  'create_orders',
  'approve_orders',
  'view_suppliers',
  'register_supplier_visit',
  'receive_products',
  'close_receiving',
  'fill_checklists',
  'review_checklists',
  'manage_checklist_templates',
  'upload_evidence',
  'review_evidence',
  'manage_expirations',
  'manage_price_changes',
  'manage_shelf_tags',
  'view_reports',
  'manage_employees',
  'manage_branches',
]

// ─── ROLES ───────────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('roles').select('*, role_permissions(permissions(name))')
export const ROLES = {
  admin: {
    id: 'admin',
    label: 'Admin General',
    permissions: PERMISSIONS,
  },

  gerente: {
    id: 'gerente',
    label: 'Gerente de Sucursal',
    permissions: [
      'view_dashboard',
      'view_inventory',
      'view_prices',
      'scan_products',
      'approve_orders',
      'create_orders',
      'view_suppliers',
      'receive_products',
      'close_receiving',
      'fill_checklists',
      'review_checklists',
      'manage_checklist_templates',
      'upload_evidence',
      'review_evidence',
      'manage_price_changes',
      'manage_shelf_tags',
      'manage_expirations',
      'view_reports',
      'manage_employees',
    ],
  },

  cajas: {
    id: 'cajas',
    label: 'Cajas',
    permissions: [
      'view_dashboard',
      'view_prices',
      'scan_products',
      'report_price_difference',
      'fill_checklists',
      'upload_evidence',
    ],
  },

  abarrotes: {
    id: 'abarrotes',
    label: 'Abarrotes',
    permissions: [
      'view_dashboard',
      'view_inventory',
      'view_prices',
      'scan_products',
      'create_orders',
      'fill_checklists',
      'upload_evidence',
    ],
  },

  recibo: {
    id: 'recibo',
    label: 'Recibo',
    permissions: [
      'view_dashboard',
      'view_inventory',
      'view_suppliers',
      'register_supplier_visit',
      'receive_products',
      'close_receiving',
      'fill_checklists',
      'upload_evidence',
    ],
  },

  proteccion: {
    id: 'proteccion',
    label: 'Protección',
    permissions: [
      'view_dashboard',
      'fill_checklists',
      'upload_evidence',
      'register_supplier_visit',
    ],
  },

  caducidades: {
    id: 'caducidades',
    label: 'Caducidades',
    permissions: [
      'view_dashboard',
      'view_inventory',
      'view_prices',
      'scan_products',
      'manage_expirations',
      'fill_checklists',
      'upload_evidence',
      'create_orders',
    ],
  },

  escaner: {
    id: 'escaner',
    label: 'Escáner',
    permissions: [
      'view_dashboard',
      'view_prices',
      'scan_products',
      'report_price_difference',
      'manage_price_changes',
      'manage_shelf_tags',
      'upload_evidence',
    ],
  },
}

// ─── USERS ───────────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('employees').select('*, roles(*)').eq('id', authUser.id)
export const MOCK_USERS = [
  {
    id: '1',
    name: 'Carlos Admin',
    email: 'admin@operalia.mx',
    password: 'admin123',
    role: 'admin',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Administración',
    departmentId: null,
    avatar: null,
  },
  {
    id: '2',
    name: 'Laura Gerente',
    email: 'gerente@operalia.mx',
    password: 'gerente123',
    role: 'gerente',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Gerencia',
    departmentId: null,
    avatar: null,
  },
  {
    id: '3',
    name: 'Mario Recibo',
    email: 'recibo@operalia.mx',
    password: 'recibo123',
    role: 'recibo',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Recibo',
    departmentId: DEPARTMENT_IDS.RECIBO,
    avatar: null,
  },
  {
    id: '4',
    name: 'Ana Cajera',
    email: 'caja@operalia.mx',
    password: 'caja123',
    role: 'cajas',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Cajas',
    departmentId: DEPARTMENT_IDS.CAJAS,
    avatar: null,
  },
  {
    id: '5',
    name: 'Pedro Abarrotes',
    email: 'abarrotes@operalia.mx',
    password: 'abarrotes123',
    role: 'abarrotes',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Abarrotes',
    departmentId: DEPARTMENT_IDS.ABARROTES,
    avatar: null,
  },
  {
    id: '6',
    name: 'Rosa Escáner',
    email: 'escaner@operalia.mx',
    password: 'escaner123',
    role: 'escaner',
    branch: 'Sucursal Centro',
    branchId: 'b1',
    department: 'Escáner',
    departmentId: DEPARTMENT_IDS.ESCANER,
    avatar: null,
  },
]

// ─── BRANCHES ────────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('branches').select('*').eq('company_id', user.company_id)
export const MOCK_BRANCHES = [
  { id: 'b1', name: 'Sucursal Centro', address: 'Av. Principal 100', city: 'Tijuana', status: 'active', manager: 'Laura Gerente' },
  { id: 'b2', name: 'Sucursal Norte',  address: 'Blvd. Norte 250',   city: 'Tijuana', status: 'active', manager: 'Pedro López' },
  { id: 'b3', name: 'Sucursal Sur',    address: 'Calle Sur 45',      city: 'Tijuana', status: 'inactive', manager: 'Sin asignar' },
]

// ─── DEPARTMENTS (operativos por sucursal) ────────────────────────────────────
// TODO: Replace with: supabase.from('departments').select('*').eq('branch_id', user.branch_id)
export const MOCK_DEPARTMENTS = [
  { id: DEPARTMENT_IDS.CAJAS,       name: 'Cajas',       branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'Ana Cajera',   employees: 8 },
  { id: DEPARTMENT_IDS.ABARROTES,   name: 'Abarrotes',   branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'Pedro Abarrotes', employees: 5 },
  { id: DEPARTMENT_IDS.RECIBO,      name: 'Recibo',      branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'Mario Recibo', employees: 3 },
  { id: DEPARTMENT_IDS.PROTECCION,  name: 'Protección',  branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'Juan Soria',   employees: 4 },
  { id: DEPARTMENT_IDS.CADUCIDADES, name: 'Caducidades', branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'María Torres', employees: 2 },
  { id: DEPARTMENT_IDS.ESCANER,     name: 'Escáner',     branchId: 'b1', branch: 'Sucursal Centro', supervisor: 'Rosa Escáner', employees: 2 },
]

// ─── PRODUCTS / INVENTORY ────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('inventory').select('*, products(*)').eq('branch_id', user.branch_id)
export const MOCK_PRODUCTS = [
  { id: 'p1', sku: 'ABR-001', barcode: '7501055300001', name: 'Arroz 1kg',           category: 'Abarrotes', department: 'Abarrotes', stock: 45, minStock: 20, price: 28.50, status: 'active',    branch: 'Sucursal Centro' },
  { id: 'p2', sku: 'ABR-002', barcode: '7501055300002', name: 'Frijol 1kg',          category: 'Abarrotes', department: 'Abarrotes', stock: 12, minStock: 15, price: 32.00, status: 'low_stock', branch: 'Sucursal Centro' },
  { id: 'p3', sku: 'ABR-003', barcode: '7501055300003', name: 'Aceite vegetal 1L',   category: 'Abarrotes', department: 'Abarrotes', stock: 60, minStock: 25, price: 45.00, status: 'active',    branch: 'Sucursal Centro' },
  { id: 'p4', sku: 'ABR-004', barcode: '7501055300004', name: 'Azúcar 1kg',          category: 'Abarrotes', department: 'Abarrotes', stock:  3, minStock: 20, price: 22.00, status: 'critical',  branch: 'Sucursal Centro' },
  { id: 'p5', sku: 'ABR-005', barcode: '7501055300005', name: 'Leche entera 1L',     category: 'Lácteos',   department: 'Abarrotes', stock: 18, minStock: 30, price: 24.00, status: 'low_stock', branch: 'Sucursal Centro' },
  { id: 'p6', sku: 'CAD-001', barcode: '7501055300006', name: 'Yogur fresa 200g',    category: 'Lácteos',   department: 'Caducidades', stock: 22, minStock: 10, price: 18.50, status: 'active', branch: 'Sucursal Centro' },
]

// ─── SUPPLIERS ───────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('suppliers').select('*').eq('company_id', user.company_id)
export const MOCK_SUPPLIERS = [
  { id: 's1', code: 'PROV-001', name: 'Distribuidora Nacional',  type: 'Abarrotes',   contact: 'Jorge Martínez', phone: '664-123-4567', status: 'active'   },
  { id: 's2', code: 'PROV-002', name: 'Lácteos del Noroeste',   type: 'Lácteos',     contact: 'Rosa Sánchez',   phone: '664-234-5678', status: 'active'   },
  { id: 's3', code: 'PROV-003', name: 'Congelados y Frescos SA', type: 'Congelados',  contact: 'Manuel Cruz',    phone: '664-345-6789', status: 'active'   },
  { id: 's4', code: 'PROV-004', name: 'Bebidas y Refrescos MX',  type: 'Bebidas',     contact: 'Patricia León',  phone: '664-456-7890', status: 'inactive' },
]

// ─── CHECKLIST RUNS ──────────────────────────────────────────────────────────
// Representa ejecuciones diarias (checklist_runs), NO las plantillas.
// Arquitectura futura:
//   checklist_templates → checklist_questions
//   checklist_assignments → checklist_runs → checklist_answers → evidence_files
//   checklist_runs → checklist_reviews
//
// TODO: Replace with:
//   supabase.from('checklist_runs')
//     .select('*, checklist_assignments(*, checklist_templates(*)), checklist_answers(count)')
//     .eq('branch_id', user.branch_id)
//     .gte('scheduled_date', today)
export const MOCK_CHECKLIST_RUNS = [
  // ── PENDIENTES ──
  {
    id: 'run1',
    templateId: 'tpl1',
    title: 'Apertura — Cajas',
    department: 'Cajas',
    departmentId: DEPARTMENT_IDS.CAJAS,
    branchId: 'b1',
    schedule: 'Apertura',
    scheduledDate: '2026-06-12',
    scheduledStart: '07:00',
    scheduledEnd: '08:30',
    status: 'pending',
    startedAt: null,
    completedAt: null,
    completedBy: null,
    totalQuestions: 5,
    answeredQuestions: 0,
    requiresEvidence: true,
    questions: [
      { id: 'q1',  text: '¿Las cajas están limpias y operativas?',         required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q2',  text: '¿El sistema de punto de venta inicia correctamente?', required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q3',  text: '¿El fondo de caja está completo?',               required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q4',  text: '¿El área está despejada y señalizada?',           required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q5',  text: '¿Se tomó fotografía de apertura?',               required: true,  requiresPhoto: true,  answer: null, comment: '', evidenceUploaded: false },
    ],
  },
  {
    id: 'run2',
    templateId: 'tpl2',
    title: 'Apertura — Abarrotes',
    department: 'Abarrotes',
    departmentId: DEPARTMENT_IDS.ABARROTES,
    branchId: 'b1',
    schedule: 'Apertura',
    scheduledDate: '2026-06-12',
    scheduledStart: '07:00',
    scheduledEnd: '08:30',
    status: 'pending',
    startedAt: null,
    completedAt: null,
    completedBy: null,
    totalQuestions: 4,
    answeredQuestions: 0,
    requiresEvidence: false,
    questions: [
      { id: 'q6',  text: '¿Los anaqueles están surtidos?',                  required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q7',  text: '¿Los precios están actualizados en anaquel?',     required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q8',  text: '¿No hay productos caducados en exhibición?',      required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q9',  text: '¿El área está limpia y ordenada?',                required: true,  requiresPhoto: false, answer: null, comment: '' },
    ],
  },
  {
    id: 'run3',
    templateId: 'tpl3',
    title: 'Rondín mañana — Protección',
    department: 'Protección',
    departmentId: DEPARTMENT_IDS.PROTECCION,
    branchId: 'b1',
    schedule: 'Mañana',
    scheduledDate: '2026-06-12',
    scheduledStart: '08:00',
    scheduledEnd: '09:00',
    status: 'pending',
    startedAt: null,
    completedAt: null,
    completedBy: null,
    totalQuestions: 4,
    answeredQuestions: 0,
    requiresEvidence: true,
    questions: [
      { id: 'q10', text: '¿Todas las salidas de emergencia están libres?',  required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q11', text: '¿Las cámaras de seguridad funcionan?',            required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q12', text: '¿No hay incidencias en el estacionamiento?',      required: true,  requiresPhoto: false, answer: null, comment: '' },
      { id: 'q13', text: '¿Evidencia fotográfica del rondín tomada?',       required: true,  requiresPhoto: true,  answer: null, comment: '', evidenceUploaded: false },
    ],
  },

  // ── EN PROGRESO ──
  {
    id: 'run4',
    templateId: 'tpl4',
    title: 'Revisión caducidades — Caducidades',
    department: 'Caducidades',
    departmentId: DEPARTMENT_IDS.CADUCIDADES,
    branchId: 'b1',
    schedule: 'Mañana',
    scheduledDate: '2026-06-12',
    scheduledStart: '08:00',
    scheduledEnd: '10:00',
    status: 'in_progress',
    startedAt: '2026-06-12T08:15:00',
    completedAt: null,
    completedBy: 'María Torres',
    totalQuestions: 5,
    answeredQuestions: 3,
    requiresEvidence: true,
    questions: [
      { id: 'q14', text: '¿Se revisaron lácteos?',                         required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q15', text: '¿Se revisaron embutidos?',                       required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q16', text: '¿Se revisaron bebidas?',                         required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q17', text: '¿Hay productos próximos a vencer (≤ 3 días)?',   required: true,  requiresPhoto: false, answer: null,  comment: '' },
      { id: 'q18', text: '¿Foto de productos detectados con fecha?',       required: true,  requiresPhoto: true,  answer: null,  comment: '', evidenceUploaded: false },
    ],
  },
  {
    id: 'run5',
    templateId: 'tpl5',
    title: 'Recibo proveedor — Recibo',
    department: 'Recibo',
    departmentId: DEPARTMENT_IDS.RECIBO,
    branchId: 'b1',
    schedule: 'Mañana',
    scheduledDate: '2026-06-12',
    scheduledStart: '09:00',
    scheduledEnd: '11:00',
    status: 'in_progress',
    startedAt: '2026-06-12T09:05:00',
    completedAt: null,
    completedBy: 'Mario Recibo',
    totalQuestions: 4,
    answeredQuestions: 2,
    requiresEvidence: false,
    questions: [
      { id: 'q19', text: '¿Se verificó que la factura coincide con el pedido?', required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q20', text: '¿Se inspeccionaron las condiciones del producto?',    required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q21', text: '¿Se registraron las diferencias encontradas?',        required: true,  requiresPhoto: false, answer: null,  comment: '' },
      { id: 'q22', text: '¿El almacén está listo para recibir mercancía?',      required: true,  requiresPhoto: false, answer: null,  comment: '' },
    ],
  },

  // ── COMPLETADOS (historial) ──
  {
    id: 'run6',
    templateId: 'tpl6',
    title: 'Actualización precios — Escáner',
    department: 'Escáner',
    departmentId: DEPARTMENT_IDS.ESCANER,
    branchId: 'b1',
    schedule: 'Mañana',
    scheduledDate: '2026-06-12',
    scheduledStart: '07:30',
    scheduledEnd: '09:00',
    status: 'completed',
    startedAt: '2026-06-12T07:35:00',
    completedAt: '2026-06-12T08:50:00',
    completedBy: 'Rosa Escáner',
    totalQuestions: 3,
    answeredQuestions: 3,
    requiresEvidence: true,
    reviewStatus: 'pending_review',
    questions: [
      { id: 'q23', text: '¿Todos los cambios de precio fueron aplicados?',  required: true,  requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q24', text: '¿Las cenefas pendientes fueron colocadas?',       required: true,  requiresPhoto: false, answer: true,  comment: '2 cenefas aún en impresión' },
      { id: 'q25', text: '¿Foto de anaqueles con cenefas actualizadas?',    required: true,  requiresPhoto: true,  answer: true,  comment: '', evidenceUploaded: true },
    ],
  },
  {
    id: 'run7',
    templateId: 'tpl1',
    title: 'Apertura — Cajas (ayer)',
    department: 'Cajas',
    departmentId: DEPARTMENT_IDS.CAJAS,
    branchId: 'b1',
    schedule: 'Apertura',
    scheduledDate: '2026-06-11',
    scheduledStart: '07:00',
    scheduledEnd: '08:30',
    status: 'completed',
    startedAt: '2026-06-11T07:05:00',
    completedAt: '2026-06-11T07:55:00',
    completedBy: 'Ana Cajera',
    totalQuestions: 5,
    answeredQuestions: 5,
    requiresEvidence: true,
    reviewStatus: 'approved',
    questions: [
      { id: 'q26', text: '¿Las cajas están limpias y operativas?',              required: true, requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q27', text: '¿El sistema de punto de venta inicia correctamente?', required: true, requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q28', text: '¿El fondo de caja está completo?',                    required: true, requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q29', text: '¿El área está despejada y señalizada?',               required: true, requiresPhoto: false, answer: true,  comment: '' },
      { id: 'q30', text: '¿Se tomó fotografía de apertura?',                    required: true, requiresPhoto: true,  answer: true,  comment: '', evidenceUploaded: true },
    ],
  },

  // ── VENCIDO ──
  {
    id: 'run8',
    templateId: 'tpl7',
    title: 'Cierre tarde — Abarrotes',
    department: 'Abarrotes',
    departmentId: DEPARTMENT_IDS.ABARROTES,
    branchId: 'b1',
    schedule: 'Cierre',
    scheduledDate: '2026-06-11',
    scheduledStart: '21:00',
    scheduledEnd: '22:00',
    status: 'overdue',
    startedAt: null,
    completedAt: null,
    completedBy: null,
    totalQuestions: 4,
    answeredQuestions: 0,
    requiresEvidence: false,
    questions: [
      { id: 'q31', text: '¿Se acomodó y surtió el anaquel de cierre?',   required: true, requiresPhoto: false, answer: null, comment: '' },
      { id: 'q32', text: '¿Se actualizaron precios del día?',             required: true, requiresPhoto: false, answer: null, comment: '' },
      { id: 'q33', text: '¿El área quedó limpia y ordenada?',             required: true, requiresPhoto: false, answer: null, comment: '' },
      { id: 'q34', text: '¿Se reportaron faltantes del día?',             required: true, requiresPhoto: false, answer: null, comment: '' },
    ],
  },
]

// ─── TASKS ───────────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('tasks').select('*, employees(name)').eq('branch_id', user.branch_id)
export const MOCK_TASKS = [
  { id: 't1', title: 'Actualizar cenefas de lácteos',           department: 'Escáner',     assignee: 'Rosa Escáner',  dueDate: '2026-06-13', status: 'pending',     priority: 'high',     evidence: true  },
  { id: 't2', title: 'Revisión de temperatura cámaras frío',    department: 'Caducidades', assignee: 'María Torres',  dueDate: '2026-06-12', status: 'in_progress', priority: 'critical', evidence: false },
  { id: 't3', title: 'Conteo de inventario abarrotes',          department: 'Abarrotes',   assignee: 'Pedro Abarrotes', dueDate: '2026-06-14', status: 'pending',     priority: 'medium',   evidence: false },
  { id: 't4', title: 'Verificar sellos de seguridad almacén',   department: 'Protección',  assignee: 'Juan Soria',    dueDate: '2026-06-12', status: 'completed',   priority: 'low',      evidence: false },
]

// ─── PRICE CHANGES ───────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('price_changes').select('*, products(*), shelf_tags(status)')
export const MOCK_PRICE_CHANGES = [
  { id: 'pc1', sku: 'ABR-001', product: 'Arroz 1kg',         oldPrice: 25.00, newPrice: 28.50, effectiveDate: '2026-06-12', needsTag: true,  tagStatus: 'pending'   },
  { id: 'pc2', sku: 'ABR-002', product: 'Frijol 1kg',        oldPrice: 30.00, newPrice: 32.00, effectiveDate: '2026-06-11', needsTag: true,  tagStatus: 'placed'    },
  { id: 'pc3', sku: 'ABR-005', product: 'Leche entera 1L',   oldPrice: 22.00, newPrice: 24.00, effectiveDate: '2026-06-10', needsTag: false, tagStatus: 'validated' },
]

// ─── ORDERS ──────────────────────────────────────────────────────────────────
// TODO: Replace with: supabase.from('orders').select('*, order_items(count), employees(name)')
export const MOCK_ORDERS = [
  { id: 'or1', title: 'Pedido Abarrotes — semana 24',    department: 'Abarrotes', requestedBy: 'Pedro Abarrotes', date: '2026-06-10', status: 'pending_approval', items: 12 },
  { id: 'or2', title: 'Pedido Caducidades — semana 24',  department: 'Caducidades', requestedBy: 'María Torres', date: '2026-06-09', status: 'approved',          items: 5  },
  { id: 'or3', title: 'Pedido insumos Recibo',           department: 'Recibo',    requestedBy: 'Mario Recibo',   date: '2026-06-08', status: 'received',          items: 8  },
]

// ─── NOTIFICATIONS (centralizado) ───────────────────────────────────────────
// TODO: Replace with real-time subscription: supabase.channel('notifications').on(...)
export const MOCK_NOTIFICATION_COUNT =
  MOCK_CHECKLIST_RUNS.filter(r => r.status === 'pending' || r.status === 'overdue').length +
  MOCK_TASKS.filter(t => t.status === 'pending' && t.priority === 'critical').length

// ─── DASHBOARD ───────────────────────────────────────────────────────────────
// TODO: Replace with Supabase queries filtered by branch/company
export const MOCK_DASHBOARD = {
  pendingTasks:        MOCK_TASKS.filter(t => t.status === 'pending').length,
  pendingChecklists:   MOCK_CHECKLIST_RUNS.filter(r => r.status === 'pending').length,
  overdueChecklists:   MOCK_CHECKLIST_RUNS.filter(r => r.status === 'overdue').length,
  lowStockProducts:    MOCK_PRODUCTS.filter(p => p.status === 'low_stock' || p.status === 'critical').length,
  pendingOrders:       MOCK_ORDERS.filter(o => o.status === 'pending_approval').length,
  pendingPriceChanges: MOCK_PRICE_CHANGES.filter(p => p.tagStatus === 'pending').length,
  recentActivity: [
    { id: 1, type: 'checklist', message: 'Checklist Apertura — Escáner completado',         user: 'Rosa Escáner',   time: 'Hace 30 min'  },
    { id: 2, type: 'price',     message: 'Cambio de precio aplicado: Frijol 1kg',            user: 'Sistema',        time: 'Hace 1 hora'  },
    { id: 3, type: 'order',     message: 'Pedido Caducidades aprobado',                      user: 'Laura Gerente',  time: 'Hace 2 horas' },
    { id: 4, type: 'task',      message: 'Tarea "Verificar sellos almacén" completada',      user: 'Juan Soria',     time: 'Hace 3 horas' },
    { id: 5, type: 'receiving', message: 'Recibo PROV-001 finalizado — 8 productos',         user: 'Mario Recibo',   time: 'Ayer 17:30'   },
  ],
}
