// Fuente única de verdad para departamentos operativos.
// TODO: Reemplazar con: supabase.from('departments').select('*').eq('branch_id', user.branch_id)

export const DEPARTMENT_IDS = {
  CAJAS:       'cajas',
  ABARROTES:   'abarrotes',
  RECIBO:      'recibo',
  PROTECCION:  'proteccion',
  CADUCIDADES: 'caducidades',
  ESCANER:     'escaner',
}

export const DEPARTMENTS = [
  { id: DEPARTMENT_IDS.CAJAS,       label: 'Cajas',       color: '#2563eb' },
  { id: DEPARTMENT_IDS.ABARROTES,   label: 'Abarrotes',   color: '#16a34a' },
  { id: DEPARTMENT_IDS.RECIBO,      label: 'Recibo',      color: '#9333ea' },
  { id: DEPARTMENT_IDS.PROTECCION,  label: 'Protección',  color: '#dc2626' },
  { id: DEPARTMENT_IDS.CADUCIDADES, label: 'Caducidades', color: '#ea580c' },
  { id: DEPARTMENT_IDS.ESCANER,     label: 'Escáner',     color: '#0891b2' },
]

export const getDepartmentLabel = (id) =>
  DEPARTMENTS.find(d => d.id === id)?.label ?? id
