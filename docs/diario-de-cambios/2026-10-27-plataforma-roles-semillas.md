# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
27 de octubre de 2026

## 🧩 Cambio registrado
**Superadmin de la plataforma separado del propietario de cada empresa, Roles y Permisos solo para el propietario, y semillas por empresa con dos empresas demo con historial.**

---

# 🗄️ Base de datos

## Migración `0023_plataforma_roles_semillas.sql`

### A. Superadmin de la plataforma
- **`platform_admins`** (`user_id` → `auth.users`, `created_at`):
  - Con RLS, solo un superadmin puede leerla.
  - Nadie la escribe desde la API; se administra en el SQL Editor.
- **`is_platform_admin()`**: `security definer`, solo para usuarios autenticados.
- **`get_my_profile()`** ahora incluye `is_owner` e `is_platform_admin`.

### B. Roles y permisos solo para el propietario
- **`can_manage_roles()`** = `has_permission('manage_roles')` **y** (`auth_is_owner()` o `is_platform_admin()`).
- **Políticas que ahora la exigen:** `roles_write`, `role_permissions_write` y `employee_permissions_write`.
- **Sin cambio:** asignar un rol a un empleado sigue con `manage_employees` y las restricciones de alcance de `tg_employee_guard`.
- **Cuenta del propietario:** antes, `admin_set_password` impedía crearle la cuenta a un propietario pre-registrado. Ahora:
  - Desde el **SQL Editor** (modo sistema) se crea o restablece cualquier cuenta.
  - Un **superadmin**, desde la app, crea la cuenta de un propietario que aún no la tiene y gestiona administradores.
  - Cuando el propietario ya tiene cuenta, su contraseña solo la cambia él.

### B. Revisión de RLS (0005 a 0021)

**Corregido** (dependía solo de un permiso y alcanzaba de más):

| Política | Antes | Ahora |
|---|---|---|
| `companies_update` | `manage_branches` | `manage_branches` + propietario o superadmin |
| `branches_write`, `departments_write`, `zones_write` | `manage_branches` en la empresa | Además, rol de alcance **empresa**. Un rol de sucursal al que se le diera `manage_branches` editaba todas las sucursales. |
| `employee_departments_write` | `manage_employees`, cualquier empleado de la empresa | Solo empleados de sus sucursales (o alcance empresa) |
| `order_items_write` | `approve_orders` sin revisar sucursal | `approve_orders` + acceso al departamento o sucursal del pedido |
| `price_changes_update` | `manage_price_changes` en toda la empresa | El mismo alcance que para crearlos (0015): empresa, zona propia o sucursal propia |
| `notifications_insert` | `manage_tasks`: avisos a cualquier sucursal o a toda la empresa | Solo a una sucursal a la que se tiene acceso |

**Dudoso** (no lo cambié: es decisión de negocio):

| Política | Qué pasa hoy | Por qué es dudoso |
|---|---|---|
| `templates_write` / `questions_write` | `manage_checklist_templates` (lo tiene el **gerente**, alcance sucursal) | Las plantillas son de **toda la empresa**: un gerente puede editar o borrar plantillas que usan las demás sucursales. |
| `products_write` / `barcodes_write` | `manage_inventory` (gerente y **almacén**) | El catálogo es de toda la empresa, y `products.price` se puede editar directo sin pasar por Cambios de precio ni generar cenefa. |
| `suppliers_write` | `manage_suppliers` (gerente) | El catálogo de proveedores es de toda la empresa. |
| `audit_select` | `view_audit_logs` (gerente) | La auditoría no tiene sucursal: el gerente ve cambios de toda la empresa (altas de empleados, contraseñas restablecidas). |
| `evidence_update` | `review_evidence` + sucursal | Las evidencias sin sucursal (tickets de soporte) las puede revisar cualquier revisor de la empresa. |
| `employees_insert` | `manage_employees` en la empresa | La sucursal la valida el trigger `tg_employee_guard`, no la política. Funciona, pero depende del trigger. |

### C. Semilla base por empresa
- **`seed_company_base(empresa)`**: re-ejecutable. Solo **agrega** lo que falta; no quita permisos que el propietario haya cambiado ni duplica plantillas. Siembra:
  - departamentos y zonas;
  - roles de sistema (incluido `jefe_escaner`) con la matriz completa de permisos hasta la 0021 (el admin recibe todos);
  - temas de soporte y respuestas rápidas;
  - plantillas de checklist con sus preguntas: Gerencia, Limpieza y recolecciones de Cajas, Tarimas, y Ronda de carritos;
  - lecturas de temperatura con rango;
  - puntos QR de cada sucursal existente;
  - los checklists del día.
- **Se aplica a todas las empresas** que ya existen al correr la 0023.
- **Datos que salieron de las migraciones:**
  - la 0011 ya no inserta temas ni respuestas;
  - la 0012 ya no inserta plantillas ni activa la Sucursal Sur.

  En una **instalación nueva** esos datos nunca se creaban, porque se insertaban «para todas las empresas» antes de que existiera alguna. Ahora sí se crean.

## Semillas (`seed/`)
- **`seed/0008_catalogos.sql`**: catálogo global de permisos, empresa Gato Pelón y sus 3 sucursales (Sur ya activa), `seed_company_base` y la zona de cada sucursal.
- **Eliminadas** `seed/0011` a `seed/0018`: su contenido está en `seed_company_base`.
- **`seed/0010_propietario.sql`**:
  - **`chee`**: empleado nuevo de Gato Pelón, rol admin y **propietario** (`is_owner`). Queda pre-registrado **sin cuenta**.
  - A **`gatopelon`** se le quita la propiedad: solo puede haber un propietario por empresa (índice `employees_one_owner_idx` de 0012, y la propiedad solo se transfiere en modo sistema).
  - **`gatopelon`** se registra en `platform_admins` y sigue siendo admin de Gato Pelón.

## Demo (`demo/`, nunca en producción)
- **`demo/0009_usuarios_y_demo.sql`**:
  - `demo_seed_user(empresa, …)`: crea el empleado y su cuenta confirmada.
  - `seed_company_demo(empresa)`, parametrizada: productos, inventario de todas las sucursales, proveedores, plantillas por departamento, tareas, pedidos, cambios de precio, caducidades, tickets y planes de conteo cíclico.
  - Gato Pelón: usuarios de prueba y **cuarta sucursal** (004 Playas).
  - La contraseña demo de `gatopelon` pasa a `prueba123`; en una base que ya tiene esa cuenta, no cambia.
- **`demo/0013`**: usa `demo_seed_user`.
- **`demo/0016`**: eliminado; los planes de conteo están en `seed_company_demo`.
- **`demo/0017` y `demo/0018`**: filtran por Gato Pelón, porque el usuario y el código de sucursal ya no son únicos entre empresas.
- **`demo/0019_empresas_demo.sql`**:
  - **Súper La Luna** (`superluna`, propietario `luna.admin`) y **Mercado Sol** (`mercadosol`, propietario `sol.admin`). Cada una con 4 sucursales, su semilla base y su demo, y usuarios `gerente1`…`gerente4` más el personal de la sucursal 001. Contraseña `prueba123`.
  - **`demo_company_history(empresa, 30)`**: 30 días de historial de checklists, lecturas de temperatura, tareas, mermas, conteos cíclicos, huecos y tickets.
    - Cada sucursal tiene un nivel de cumplimiento distinto (0.96, 0.88, 0.74 o 0.58), en otro orden en cada empresa.
    - El historial no deja avisos viejos en la campana.

Resultado en PGlite, con historial de 30 días:

| Empresa | Sucursal | % checklists | Temp. fuera | % tareas | Merma | % exactitud | Huecos |
|---|---|---|---|---|---|---|---|
| Mercado Sol | Valle | 96 | 3 | 97 | $483 | 98 | 21 |
| Mercado Sol | Maneadero | 87 | 9 | 84 | $1,427 | 90 | 27 |
| Mercado Sol | Sauzal | 74 | 18 | 67 | $4,510 | 76 | 32 |
| Mercado Sol | Centro | 56 | 20 | 57 | $4,733 | 59 | 47 |
| Súper La Luna | Otay | 97 | 4 | 98 | $784 | 95 | 16 |
| Súper La Luna | Playas | 89 | 9 | 87 | $1,241 | 89 | 20 |
| Súper La Luna | Rosarito | 75 | 26 | 69 | $3,614 | 73 | 31 |
| Súper La Luna | Centro | 56 | 34 | 57 | $4,459 | 67 | 56 |

---

# 🖥️ Frontend
- **`AuthProvider`**: expone `isOwner`, `isPlatformAdmin` y **`canManageRoles`** (la misma regla que `can_manage_roles()`).
- **`navigation.js`**:
  - Roles y Permisos usan `when: 'canManageRoles'`.
  - Antes, Roles se mostraba a quien tenía `manage_employees`; ya no.
  - `canAccess` acepta `when` (una bandera de `useAuth()`); lo usan el menú, el router y los enlaces de Estadísticas.
- **`router.jsx`**: `/roles` y `/permissions` con la misma regla. Escribir la URL no basta.
- **`RolesPage`**: edita solo con `canManageRoles`.
- No había más enlaces a Roles o Permisos en `src/`. Empleados sigue asignando roles con `manage_employees`.

---

# 🔑 Cómo crearle la cuenta a `chee` (sin poner la contraseña en archivos)
La contraseña debe tener **mínimo 8 caracteres**. Al entrar por primera vez, la app pide cambiarla.

**Opción 1, desde la app, como superadmin:**
1. Entra con empresa `gatopelon`, usuario `gatopelon`.
2. Ve a **Configuración → Empleados → Chee → Crear cuenta**.
3. Escribe o genera la contraseña temporal y guarda.

**Opción 2, desde el SQL Editor de Supabase:**
```sql
select public.admin_set_password(
  (select id from public.employees
    where company_id = 'c0000000-0000-4000-8000-000000000001' and username = 'chee'),
  'ESCRIBE-AQUI-LA-CONTRASEÑA');
```
No guardes esa consulta con la contraseña en el repositorio.

Después, `chee` entra con empresa `gatopelon`, usuario `chee` y esa contraseña. Desde entonces solo él cambia su contraseña.

> La contraseña anterior de `gatopelon` estuvo en `demo/0009` en el historial de git. Como ahora es superadmin, cámbiala en tu base, desde su menú «Cambiar contraseña».

---

# ✅ Verificación
- **Instalación completa** (`pendiente.sql`, 31 archivos), dos pasadas en PGlite, sin errores.
  - Gato Pelón, Súper La Luna y Mercado Sol quedan con 4 sucursales, propietario (`chee`, `luna.admin`, `sol.admin`), 14 roles, 212 permisos por rol, 21 plantillas, 10 temas y 8 puntos QR.
  - `verificar.sql` (84 filas): todo en verde salvo pg_cron. La prueba de seguridad por zona también pasa.
- **Instalación limpia** (25 archivos), dos pasadas: solo `chee` (propietario) y la cuenta con correo real, sin demo.
- **Actualización** de una base existente (`pendiente.sql` anterior + 0022, 0023, `seed/0008` y `seed/0010`, dos veces cada uno):
  - `chee` queda como propietario y `gatopelon` como superadmin;
  - se agregan los permisos y temas que faltaban;
  - sin plantillas ni preguntas duplicadas.
- **Seguridad:**

| Caso | Resultado |
|---|---|
| Superadmin (no propietario) edita roles | Permitido ✅ |
| Propietario `luna.admin` edita roles | Permitido ✅ |
| Admin **no** propietario edita roles o permisos especiales | Rechazado ✅ |
| Gerente cambia el rol de un empleado de su sucursal | Permitido ✅ |
| Admin no propietario edita la empresa | 0 filas; el propietario sí ✅ |
| Gerente toca departamentos de un empleado de otra sucursal | 0 filas ✅ |
| Gerente crea la cuenta de `chee` | Rechazado ✅ |
| Superadmin crea la cuenta de `chee` | Confirmada y con cambio obligatorio ✅ |
| Superadmin restablece a `chee` ya con cuenta | Rechazado ✅ |
| Superadmin toca al propietario de otra empresa | «Empleado no encontrado» ✅ |
| `luna.admin` ve otras empresas o sus productos | Solo la suya; 0 productos ajenos ✅ |

- `npm run lint` y `npm run build` sin errores.

# 📌 Para aplicar en tu Supabase (después de la 0022)
1. `migrations/0023_plataforma_roles_semillas.sql`
2. `seed/0008_catalogos.sql`
3. `seed/0010_propietario.sql`
4. **Opcional, solo si quieres los datos demo:**
   - `demo/0009_usuarios_y_demo.sql`
   - `demo/0013_usuarios_zona.sql`
   - `demo/0019_empresas_demo.sql` (tarda unos segundos por el historial)
5. `verificar.sql`
6. Crea la cuenta de `chee` (ver arriba) y cambia la contraseña de `gatopelon`.
