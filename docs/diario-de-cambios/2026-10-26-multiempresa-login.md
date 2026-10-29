# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
26 de octubre de 2026

## 🧩 Cambio registrado
**Varias empresas cliente: el login pide el código de empresa.** Casi todo ya tenía `company_id` y RLS. Faltaba que el inicio de sesión supiera a qué empresa entra.

---

# 🗄️ Base de datos

## Migración `0022_multiempresa_login.sql`
- **`companies`**:
  - Columnas nuevas: `code` (único, solo `[a-z0-9-]`), `status` (`active` | `suspended`, por defecto `active`) y `plan` (por defecto `basico`).
  - Gato Pelón queda con `code = 'gatopelon'`. Si hubiera otra empresa sin código, recibe uno provisional `empresa-xxxxxxxx`.
  - Trigger `trg_company_platform_guard`: código, estado y plan solo se cambian desde el SQL Editor. Un administrador cliente no puede reactivarse ni cambiarse de plan.
- **Usuario único por empresa:**
  - Se elimina `employees_username_lower_key` (global) y se crea `employees_company_username_key` sobre `(company_id, lower(username))`.
  - La 0001 ya no crea el índice global, para que reinstalar no falle cuando dos empresas compartan un usuario.
- **Correo interno de Auth:** `usuario@<code>.operalia.local` (antes `usuario@operalia.local`). La función `employee_auth_email(empresa, usuario)` lo arma.
  - **`handle_new_auth_user`**: liga la cuenta por usuario **y** empresa; la empresa sale del dominio, lo que está antes de `.operalia.local`. Un correo real se liga por el correo registrado, o por usuario si es único. El formato viejo sin empresa ya no se liga.
  - **`admin_set_password`**: arma el correo con el código de la empresa del empleado (parche sobre la función de 0012).
  - **`request_password_reset(p_company_code, p_username)`**: la versión vieja `(p_username)` se **eliminó**, porque solo la usaba el login.
  - **Cuentas existentes:** se migran `auth.users.email`, `raw_user_meta_data.email`, `auth.identities.identity_data->>'email'` y `employees.email` de `@operalia.local` a `@<code>.operalia.local`. Se usa la empresa del empleado ligado, o `gatopelon` si la cuenta no está ligada. Es re-ejecutable.
- **Empresa suspendida = sin acceso:**
  - Estas funciones solo devuelven datos si la empresa del empleado está activa: `auth_employee_id`, `auth_company_id`, `auth_branch_id`, `auth_department_id`, `auth_role_scope`, `auth_role_code`, `my_permissions`, `auth_is_owner` y `get_my_profile`.
  - Con la empresa suspendida, RLS no deja ver nada y no se borra ningún dato.
  - `get_my_profile` ahora incluye `company_code`.

## Semillas
- **`seed/0008_catalogos.sql`:** la empresa se inserta con `code = 'gatopelon'`.
- **`demo/0009` y `demo/0013`:** crean las cuentas demo como `usuario@gatopelon.operalia.local` y buscan al empleado dentro de su empresa.

---

# 🖥️ Frontend
- **`src/config/env.js`:**
  - `usernameToEmail(companyCode, username)`. Un correo real, con @, se usa tal cual.
  - `normalizeCompanyCode`: minúsculas, sin acentos, solo `[a-z0-9-]`.
  - `readRememberedCompany` y `rememberCompany`, guardados en localStorage con `try/catch`.
  - Se eliminó `VITE_AUTH_EMAIL_DOMAIN`: el dominio es fijo, igual que en SQL.
- **Login:**
  - Campo **Empresa** antes de Usuario. Se recuerda en el dispositivo; si ya está recordada, el cursor empieza en Usuario.
  - El error ahora dice «Empresa, usuario o contraseña incorrectos».
- **¿Olvidaste tu contraseña?:** pide Empresa y Usuario. Con un correo real no pide empresa.
- **`employeeService`:**
  - El alta con contraseña ya **no usa `auth.signUp`** con la llave pública. Crea la cuenta con `admin_set_password`, ya confirmada y con contraseña temporal que se cambia al entrar.
  - Si eso falla, el empleado queda guardado y el mensaje lo dice; luego se usa «Crear cuenta».
- **Empleados:** la contraseña temporal se muestra y se copia junto con la **empresa**.
- **Cuenta sin acceso:** el aviso ahora menciona que la empresa puede estar suspendida.

---

# ⚠️ Configuración necesaria en Supabase
**Desactiva el registro público:** Supabase → **Authentication → Sign In / Providers → «Allow new users to sign up» → apagado**.

La app ya no lo necesita, porque las cuentas las crea `admin_set_password`. Con el registro abierto, cualquiera con la llave pública podría crear cuentas en Auth. Esas cuentas no tendrían acceso a datos, porque no se ligan a ningún empleado, pero no deben poder crearse.

«Confirm email» ya no importa para las altas desde la app: `admin_set_password` crea las cuentas confirmadas.

---

# ✅ Verificación
- `pendiente.sql` regenerado (38 archivos) y ejecutado dos veces en PGlite sin errores.
- `verificar.sql`: 79 comprobaciones en verde, salvo pg_cron. Las nuevas:
  - existe `companies.code`;
  - existe el índice por empresa y ya no el global;
  - existe `request_password_reset(código, usuario)` y no la versión vieja;
  - ninguna cuenta con `@operalia.local`.
- **Actualización de una base existente**, simulada en PGlite: se instaló el `pendiente.sql` del commit anterior y encima se aplicó la 0022 dos veces.

| Caso | Resultado |
|---|---|
| 16 cuentas `@operalia.local` | 16 → `@gatopelon.operalia.local` (Auth, identidades y empleados) ✅ |
| Perfil del cajero | `company_code = gatopelon` ✅ |
| Usuario `cajero` en otra empresa (Acme) | Permitido; duplicado en la misma empresa, rechazado ✅ |
| Cuenta `cajero@acme.operalia.local` | Se liga al cajero de Acme, no al de Gato Pelón ✅ |
| Dueño de Acme crea la cuenta de un empleado | `maria@acme.operalia.local`, confirmada ✅ |
| Dueño de Acme mira empleados de Gato Pelón | 0 ✅ |
| Admin de Acme cambia su plan | Rechazado ✅ |
| Contraseña olvidada `('acme', 'cajero')` | Avisa solo al dueño de Acme ✅ |
| Gato Pelón suspendida | Cajero: sin empresa, sin perfil, 0 productos; Acme sigue funcionando ✅ |
| Reactivada | El cajero vuelve a ver productos ✅ |
| `pendiente.sql` nuevo sobre la base ya migrada | Sin errores ni cuentas duplicadas ✅ |

- **Login revisado a 360 px:**
  - «GatoPelón » se normaliza a `gatopelon` y se envía `cajero@gatopelon.operalia.local`.
  - La recuperación envía `{p_company_code: "gatopelon", p_username: "cajero"}`.
  - La empresa se recuerda en una pestaña nueva y el cursor empieza en Usuario.
  - Sin errores de JS.
- `npm run lint` y `npm run build` sin errores.

# 📌 Para aplicar
1. SQL Editor: `migrations/0022_multiempresa_login.sql`.
2. SQL Editor: `verificar.sql` (revisa las filas 0022).
3. Supabase → Authentication: desactiva «Allow new users to sign up».
4. Publica el frontend. Desde ese momento todos entran con **Empresa** `gatopelon` + su usuario de siempre.
