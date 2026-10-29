# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
30 de octubre de 2026

## 🧩 Cambio registrado
**Prueba de aislamiento entre empresas (`supabase/pruebas/aislamiento.sql`), correcciones de lo que encontró (migración 0026), revisión de todas las funciones SECURITY DEFINER y README con la arquitectura multiempresa.**

---

# 🧪 La prueba: `supabase/pruebas/aislamiento.sql`

- **Dónde se corre:** solo en el ambiente de pruebas, porque necesita los datos demo. Se ejecuta completa en el SQL Editor y tarda alrededor de un minuto.
- **No deja cambios:** todo corre dentro de un bloque que se deshace al final, y cada intento que llega a escribir se revierte en ese momento.

## Cómo se hace pasar por un usuario
Igual que la API:
```sql
select set_config('request.jwt.claims', '{"sub":"<user_id>","role":"authenticated"}', true);
set local role authenticated;   -- o anon
```

**Personas** (todas de Súper La Luna, más `anon`):

| Columna | Quién |
|---|---|
| `sucursal` | Empleado con rol de alcance `branch`, por ejemplo un gerente |
| `self` | Empleado con alcance `self`, por ejemplo un cajero |
| `propietario` | `luna.admin` |
| `anon` | Sin sesión |
| `admin_no_propietario` | Administrador creado solo para la prueba |

## Qué prueba
1. **Las 46 tablas y 23 vistas de `public`, y `storage.objects` (evidence):**
   - Cada persona intenta leer, insertar, actualizar y borrar filas de Gato Pelón.
   - En las tablas, intenta además **actualizar y borrar sin filtro**. Después se cuenta como postgres cuántas filas de Gato Pelón se tocaron.
   - Las filas de Gato Pelón se reconocen así:
     - por `company_id`;
     - en las tablas hijas, por su llave foránea a la tabla madre (los ids de la madre se calculan antes, como postgres);
     - en las vistas, por la regla de su tabla base.
2. **RPC de plataforma:** cada `platform_*` y `provision_company`, más `run_daily_maintenance` de otra empresa. Deben dar error para las 5 personas.
3. **Funciones que reciben un id** (`effective_price`, `checkpoint_for_run`, `announcement_matches`): con ids de Gato Pelón no deben responder nada.
4. **Roles:** el admin no propietario no cambia `role_permissions`, `employee_permissions` ni `roles`. El propietario sí; es el control positivo.
5. **Empresa suspendida:** Súper La Luna suspendida no lee ninguna tabla, vista ni archivo, y `get_my_profile()` devuelve null. Tampoco corre el mantenimiento de Gato Pelón.
6. **Olvidé mi contraseña:** `request_password_reset` responde igual en cuatro casos:
   - un usuario que existe;
   - uno que no existe;
   - uno que solo existe en otra empresa;
   - el código de otra empresa.

   No crea avisos en Gato Pelón.
7. **pg_cron:** un checklist por vencer y uno de ayer pendiente en cada empresa. Se corren las dos funciones para **todas** las empresas, sin filtrar, y la suspendida no debe recibir nada. Gato Pelón es el control.
8. **SECURITY DEFINER:** lista las funciones que la API puede llamar y las compara con la lista revisada. Una nueva sale ❌ «sin revisar».

## Cómo se validó la prueba misma
- **Controles positivos:**
  - cada persona tiene el rol esperado y ve los empleados de su propia empresa;
  - el propietario sí puede editar roles;
  - en pg_cron, la empresa activa sí recibe el proceso.

  Si el cambio de rol fallara, todo saldría en 0 y la prueba no valdría.
- **Fugas a propósito:** en una copia local abrí una política de lectura, una de actualización y una de inserción, una política de Storage y una vista sin `security_invoker`.
  - La primera versión de la prueba **no** detectaba dos de ellas:
    - **Inserción:** usaba `RETURNING`, que exige poder leer la fila nueva, así que daba error aunque la inserción pasara.
    - **Actualización:** el `WHERE` aplica la política de lectura y ocultaba la falla de la política de escritura.
  - Se corrigió:
    - las inserciones van sin `RETURNING` y se cuentan con `ROW_COUNT`;
    - se agregaron las escrituras sin filtro.
  - Ahora detecta todas las fugas que provoqué, salvo la inserción en `checklist_answers`: la frenó antes una regla de negocio y quedó como ⚠️, que es justo el caso que esa marca señala.
- **⚠️ no concluyente:** a veces una regla del negocio frena la operación antes de llegar a la seguridad.
  - **Ejemplos:** «Este checklist está completado y ya no acepta respuestas», o una llave foránea de una fila **propia** en un borrado sin filtro.
  - Eso no prueba ni descarta una fuga, así que no se cuenta como ✅. Hoy hay 9, todas de ese tipo; se listan con su mensaje.

# 🔧 Lo que falló y cómo se corrigió (migración `0026_aislamiento_empresas.sql`)

| # | Falla | Por qué pasaba | Corrección |
|---|---|---|---|
| 1 | Un empleado de una empresa **suspendida** (o un usuario sin empleado) podía correr `run_daily_maintenance(<otra empresa>)`: generar checklists, marcar vencidos, aplicar cambios de precio y caducar lotes de otra empresa | La validación era `p_company_id <> auth_company_id()`. Con la empresa suspendida, `auth_company_id()` es null; `x <> null` da null y el `if` no frenaba | `is distinct from`, que con null sí frena. El mismo cambio, por higiene, en toda función SECURITY DEFINER con `<> public.auth_company_id()`. Las demás ya estaban protegidas por un segundo chequeo (`has_permission`), pero así no dependen de él |
| 2 | **pg_cron procesaba empresas suspendidas:** les mandaba recordatorios y les corría el mantenimiento | Los jobs hacen `select f(id) from companies` sin filtrar, y las funciones no revisaban el estado | `run_daily_maintenance` devuelve `{ skipped: 'empresa suspendida' }` y `send_checklist_reminders` devuelve 0 si la empresa no está activa. Además, los jobs se reprograman con `where status = 'active'` |
| 3 | **`effective_price`** devolvía el precio de un producto de **otra** empresa, incluso a `anon` | Era SECURITY DEFINER y no revisaba empresa | Solo responde sobre productos de la empresa de quien llama, o en modo sistema (aplicar cambios programados) |
| 4 | **`checkpoint_for_run`** devolvía el punto QR de un checklist de otra empresa, incluso a `anon` | Igual que la 3 | Solo responde sobre checklists de la empresa de quien llama, o en modo sistema |
| 5 | **`announcement_matches`** respondía si un empleado de otra empresa está en tal sucursal o zona | Igual que la 3 | Solo responde sobre empleados de la propia empresa, o en modo sistema |
| 6 | **`anon`** podía ejecutar `auth_is_owner`, `auth_zone_ids`, `can_view_ticket`, `checkpoint_for_run` y `effective_price` | Supabase da EXECUTE a `anon` y a PUBLIC en cada función nueva, y esas migraciones no lo revocaban | Se revoca EXECUTE a PUBLIC y `anon` en **todas** las funciones de `public`, salvo `request_password_reset`. Antes se le da explícitamente a `authenticated` donde ya lo tenía, para que no se pierda nada. Para funciones futuras de postgres: `alter default privileges … revoke execute on functions from anon` |

**Comprobado sin cambios:**
- **Lectura de datos de otra empresa:** con las cuatro personas, en ninguna de las 69 tablas y vistas ni en Storage.
- **RPC de plataforma:** ninguna se puede llamar sin ser superadmin.
- **Roles:** el admin no propietario no cambia roles ni permisos.
- **Empresa suspendida:** no lee nada.
- **`request_password_reset`:** responde igual en los cuatro casos y no toca otra empresa.

**Regresión:** después de 0026 siguen pasando todas las pruebas anteriores:
- `verificar.sql` (95 filas), la instalación limpia y la actualización desde el instalador anterior;
- roles y propietario, alta de empresas, soporte de plataforma y rendimiento;
- cambios de precio (`old_price` sale de `effective_price`), comunicados (audiencia y avisos) y el mantenimiento que llama el frontend al entrar.

**Copia local:** la imita mejor ahora:
- `auth.uid()` lee `request.jwt.claims`, como en Supabase;
- tiene los privilegios por defecto de Supabase: `anon` y `authenticated` reciben tablas y funciones nuevas.

# 🔐 Funciones SECURITY DEFINER (101)

| Tipo | Cuántas | ¿Riesgo? |
|---|---|---|
| Triggers | 42 | No se pueden llamar por la API (devuelven `trigger`); corren solo dentro de un INSERT/UPDATE/DELETE que ya pasó el RLS |
| Internas, revocadas para la API | 11 | `apply_price_change`, `demo_company_history`, `demo_seed_user`, `employee_auth_email`, `generate_checklist_runs`, `generate_cycle_counts`, `notify_employee`, `platform_admin_employees`, `seed_company_base`, `seed_company_demo`, `send_checklist_reminders` |
| Expuestas a `authenticated` | 47 | Revisadas una por una (abajo) |
| Expuestas a `anon` | 1 | `request_password_reset` (pantalla de login) |

Revisión de las 48 expuestas (✅ = valida empresa, usuario o superadmin):

| Función | Cómo valida |
|---|---|
| `auth_company_id`, `auth_employee_id`, `auth_branch_id`, `auth_department_id`, `auth_role_code`, `auth_role_scope`, `auth_is_owner`, `auth_zone_ids`, `has_permission`, `my_permissions`, `get_my_profile`, `is_platform_admin`, `can_manage_roles` | ✅ Solo sobre el usuario que llama (`auth.uid()`); no reciben empresa |
| `clear_must_change_password` | ✅ Solo la cuenta propia |
| `can_access_branch`, `can_access_department`, `can_publish_announcement` | ✅ Comparan contra la empresa y el alcance de quien llama |
| `can_view_ticket`, `is_my_notification` | ✅ Comparan contra el empleado y el alcance de quien llama. Ya no son de `anon` (0026) |
| `company_today` | ✅ Solo devuelve la fecha de hoy en la zona horaria de una empresa; no lee datos |
| `announcement_counts`, `announcement_progress`, `can_track_announcement`, `mark_announcement_read` | ✅ Validan empresa |
| `announcement_matches` | ✅ Valida empresa (**corregida en 0026**) |
| `mark_notification_read`, `mark_all_notifications_read` | ✅ Solo avisos propios |
| `admin_set_password` | ✅ Valida empresa, permiso y alcance. Con un propietario sin cuenta, también el superadmin |
| `close_shelf_gap`, `create_order_from_shelf_gap`, `report_shelf_gap`, `report_price_difference` | ✅ Validan empresa, permiso y sucursal |
| `record_cycle_count`, `start_checklist_with_checkpoint` | ✅ Validan empresa, permiso y departamento |
| `run_daily_maintenance` | ✅ Solo su empresa (**corregida en 0026**) y se salta las suspendidas |
| `effective_price`, `checkpoint_for_run` | ✅ Validan empresa (**corregidas en 0026**; antes ❌) |
| `provision_company` y las 10 `platform_*` | ✅ Validan superadmin |
| `request_password_reset` | ✅ Pública por diseño: responde igual exista o no el usuario |

**Antes de 0026 no validaban:**
- `effective_price`, `checkpoint_for_run` y `announcement_matches`: no revisaban la empresa;
- `run_daily_maintenance`: la revisaba con `<>`, que con null deja pasar.

# 📖 README
- **Secciones nuevas:**
  - **Arquitectura multiempresa:** RLS, vistas, Storage, SECURITY DEFINER, empresas suspendidas y superadmin;
  - **Cuentas:** empleado, propietario y superadmin, con el SQL para agregar un superadmin;
  - **Cómo se da de alta una tienda:** de prospecto a arranque;
  - **Semillas base vs. demo**, en una tabla;
  - **Prueba de aislamiento:** cómo correrla y cómo leer ✅, ❌, ⚠️, — e ℹ️.
- **«Cómo agregar una función»:** suma las reglas de aislamiento para tablas, vistas y funciones nuevas, y pide correr la prueba sin ❌.

# ✅ Revisión
`npm run lint` y `npm run build` pasan; no hubo cambios en el frontend.

# ▶️ Qué correr en Supabase
1. `migrations/0026_aislamiento_empresas.sql`. Reprograma los dos jobs de pg_cron; si pg_cron no está activo, solo avisa.
2. `verificar.sql`: las 3 filas de 0026 deben salir ✅.
3. **Solo en el ambiente de pruebas:** `pruebas/aislamiento.sql`. El resumen debe decir **0 con ❌**.
