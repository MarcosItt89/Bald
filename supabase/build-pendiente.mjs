// Genera supabase/pendiente.sql uniendo migraciones + semillas en orden.
// Uso:  node supabase/build-pendiente.mjs
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const dir = path.dirname(fileURLToPath(import.meta.url))
const parts = [
  ...fs.readdirSync(path.join(dir, 'migrations')).sort().map((f) => `migrations/${f}`),
  ...fs.readdirSync(path.join(dir, 'seed')).sort().map((f) => `seed/${f}`),
]

const header = `-- =============================================================================
-- OPERALIA · pendiente.sql — INSTALACIÓN COMPLETA (pegar y ejecutar en SQL Editor)
-- Generado por supabase/build-pendiente.mjs a partir de migrations/* y seed/*.
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

const body = parts
  .map((p) => `\n\n-- >>>>>>>>>>>>>>>> ${p} <<<<<<<<<<<<<<<<\n${fs.readFileSync(path.join(dir, p), 'utf8')}`)
  .join('')

fs.writeFileSync(path.join(dir, 'pendiente.sql'), header + body)
console.log(`pendiente.sql generado con ${parts.length} archivos`)
