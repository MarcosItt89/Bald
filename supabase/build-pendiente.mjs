// Genera los dos instaladores (pegar y ejecutar en el SQL Editor):
//   pendiente.sql           migraciones + semillas base + datos demo (pruebas)
//   instalacion-limpia.sql  migraciones + semillas base, sin usuarios ni datos demo
// Las semillas se ordenan por número; con el mismo número va primero seed/ y
// luego demo/ (algunas semillas base ajustan plantillas que crea la demo 0009).
// Uso:  node supabase/build-pendiente.mjs
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const dir = path.dirname(fileURLToPath(import.meta.url))
const list = (folder) => fs.readdirSync(path.join(dir, folder)).filter((f) => f.endsWith('.sql')).sort().map((f) => `${folder}/${f}`)
const num = (p) => path.basename(p).slice(0, 4)
const seeds = (withDemo) => [...list('seed'), ...(withDemo ? list('demo') : [])]
  .sort((a, b) => num(a).localeCompare(num(b)) || (a.startsWith('seed/') ? -1 : 1) - (b.startsWith('seed/') ? -1 : 1))

const header = (name, title) => `-- =============================================================================
-- OPERALIA · ${name} — ${title} (pegar y ejecutar en SQL Editor)
-- Generado por supabase/build-pendiente.mjs a partir de migrations/*, seed/*${name === 'pendiente.sql' ? ' y demo/*' : ''}.
-- No lo edites a mano: cambia los archivos fuente y vuelve a generarlo.
-- Es re-ejecutable: no duplica datos ni borra lo ya instalado.
-- =============================================================================

-- ─── PASO 0 · LIMPIEZA DEL ESQUEMA DEL PROTOTIPO ANTERIOR ────────────────────
-- El proyecto tenía 13 tablas de un prototipo con columnas incompatibles
-- (p. ej. employees sin username / user_id). Solo se eliminan si se detecta
-- ese esquema viejo; si ya está instalado Operalia, este paso no hace nada.
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'employees')
     and not exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'employees' and column_name = 'username') then
    raise notice 'Esquema anterior detectado: se eliminan las tablas del prototipo';
    drop table if exists
      public.audit_logs, public.notifications, public.evidence_files,
      public.checklist_answers, public.checklist_runs, public.checklist_questions,
      public.checklist_templates, public.employees, public.role_permissions,
      public.roles, public.permissions, public.departments, public.branches,
      public.companies
    cascade;
  end if;
end $$;
`

const build = (name, title, withDemo) => {
  const parts = [...list('migrations'), ...seeds(withDemo)]
  const body = parts
    .map((p) => `\n\n-- >>>>>>>>>>>>>>>> ${p} <<<<<<<<<<<<<<<<\n${fs.readFileSync(path.join(dir, p), 'utf8')}`)
    .join('')
  fs.writeFileSync(path.join(dir, name), header(name, title) + body)
  console.log(`${name} generado con ${parts.length} archivos`)
}

build('pendiente.sql', 'INSTALACIÓN COMPLETA CON DATOS DEMO', true)
build('instalacion-limpia.sql', 'INSTALACIÓN PARA PRODUCCIÓN, SIN DATOS DEMO', false)
