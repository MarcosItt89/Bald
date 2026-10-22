# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Zonas** que agrupan sucursales, nuevo alcance de rol **`zone`** y rol **Jefe de Escáner**, que supervisa a los encargados de escáner de varias tiendas. Además, **ofertas por zona** con **precio propio por sucursal**.

---

# 🗄️ Base de datos

## Migración `0015_zonas_jefe_escaner.sql`
- **Zonas**: tabla `zones` (code, name, is_active) y `branches.zone_id`.
- **Alcance `zone`**: se agregó al check de `roles.scope`. La tabla `employee_zones` asigna las zonas de cada empleado y `auth_zone_ids()` devuelve las del usuario actual.
- **Seguridad (RLS)**. Revisé todo lo que depende del alcance o de la sucursal propia:

| Objeto | Cambio |
|---|---|
| `can_access_branch` | `zone` → todas las sucursales de sus zonas. Como casi todas las políticas de 0005 la usan, quedan cubiertas: inventario, movimientos, checklists, evidencias, cenefas, recibos y caducidades. |
| `can_access_department` | Sin cambio: `zone` cae en la rama de departamento (su departamento o los de `employee_departments`) dentro de sus sucursales. |
| `employees_select` / `employees_update` | Ve y, con permiso, gestiona a los empleados de sus sucursales. |
| `tg_employee_guard` | Solo un administrador asigna roles de alcance `zone`. Quien no es de empresa solo gestiona empleados de sucursales accesibles. |
| `is_my_notification` | Recibe los avisos de su departamento en sus sucursales. |
| `can_view_ticket` | Incluye `zone`. |
| `price_changes` (select/insert) | Crea ofertas solo para sus zonas. El gerente ve las ofertas de la zona de su tienda. |
| `zones`, `employee_zones` | Lectura en la empresa. Escritura: zonas con `manage_branches`; asignaciones solo un administrador. |
| `get_my_profile` | Devuelve `zone_ids` y `zone_names`. |

- **Ofertas por zona**: nueva columna `price_changes.zone_id`, excluyente con `branch_id`. El cambio aplica a cada sucursal activa de la zona y genera sus cenefas.
- **Precio por sucursal** (`branch_prices`):
  - Antes, cualquier cambio de precio, aunque fuera de una sola sucursal, cambiaba `products.price` para todas las tiendas.
  - Ahora los cambios de sucursal o de zona guardan el precio en `branch_prices`; los de toda la empresa siguen cambiando `products.price`.
  - `effective_price()` da el precio vigente. `v_inventory`, que usan la consulta de precios y el inventario, muestra el precio de cada sucursal y `has_branch_price`.
  - `old_price` de un cambio de sucursal es el precio vigente de esa sucursal.
- **Vistas**: `v_price_changes` incluye `zone_name`.

## Semilla `seed/0013_zonas_jefe_escaner.sql`
- **Zonas**: Norte, Sur, Este, Oeste y Centro. Sucursal Centro → zona Centro, Norte → Norte, Sur → Sur.
- **Rol `jefe_escaner`** (alcance `zone`): permisos de escáner, más validar cenefas, ver reportes y crear y asignar tareas. RLS limita las tareas al departamento Escáner de sus tiendas.
- **Usuarios demo**:
  - `jefe.escaner` / `prueba123`: zonas Centro y Norte. **No ve la Sucursal Sur.**
  - `escaner.norte` / `prueba123`: encargada de escáner de Norte.

## `verificar.sql`
- 7 comprobaciones nuevas de instalación (0015 y su semilla).
- **Sección nueva de pruebas de seguridad.** Se selecciona y se ejecuta aparte. Se hace pasar por `jefe.escaner` y comprueba que ve **0 filas** de sucursales fuera de sus zonas en sucursales accesibles, inventario, checklists, tareas, cenefas, empleados y evidencias. Muestra `current_user` para confirmar que corrió como `authenticated`.

---

# 🖥️ Frontend
- **Sesión**: `isZoneScope`, `isMultiBranch` y `zoneIds`. El jefe de zona trabaja con varias sucursales, igual que un administrador, pero solo las de sus zonas.
- **Selector de sucursal** (barra superior): para un jefe de zona muestra «Mis sucursales (Centro, Norte)» y solo esas tiendas. Si había guardada una sucursal que no es suya, se descarta.
- **Configuración → Zonas** (`/zones`, `manage_branches`): alta y edición con las sucursales de cada zona.
- **Sucursales**: selector de zona y columna Zona.
- **Empleados**: si el rol es de alcance zona, aparece «Zonas que supervisa» (obligatorio; solo lo edita un administrador). Solo un administrador ve los roles de empresa y de zona.
- **Cambios de precio**: «Aplicar en» Todas las sucursales (admin), Una zona (admin o jefe de zona) o Solo esta sucursal. La tabla muestra «Zona X» en el alcance.
- **Checklists**: el filtro de sucursal también aparece para el jefe de zona.
- **Estadísticas**:
  - Nuevo filtro **Zona**. Con «todas las sucursales de la zona», las consultas se limitan a esas tiendas; `byBranch` acepta una lista de sucursales.
  - En **Recibo y precios**, nuevo bloque **Cenefas por tienda**: % validadas en ≤ 48 h y pendientes de cada sucursal, para comparar encargados. Tiene CSV.

---

# ✅ Verificación
- `pendiente.sql` regenerado (21 archivos) y ejecutado dos veces en PGlite sin errores. `verificar.sql`: 45 comprobaciones en verde (salvo pg_cron, que no existe en PGlite).
- Pruebas de seguridad de `verificar.sql` como `jefe.escaner`: **8 de 8 OK**.
- Más pruebas en PGlite como `jefe.escaner`:
  - Sucursales accesibles: 001 y 002.
  - Crear tarea: ESC en Norte sí; ABA en Norte no; ESC en Sur no.
  - Oferta para la zona Sur: rechazada.
  - Oferta para la zona Norte: precio 37.00 solo en la sucursal 002 (Centro sigue en 32.00) y cenefa solo en 002. La ve `gerente.norte`; `gerente.centro` no.
  - Un gerente no puede asignar zonas ni dar el rol `jefe_escaner`.
- `npm run lint` y `npm run build` sin errores. Revisado a 360 px con un perfil de zona simulado (tu base aún no tiene la 0015): selector «Mis sucursales (Centro, Norte)», filtro de zona y página Zonas, sin errores de JS.

# ⚠️ Importante al aplicar
- **Aplica la migración antes de publicar este frontend.** El selector de sucursal ahora pide la zona de cada sucursal, y sin la tabla `zones` esa consulta falla.
- **Precio de referencia en el formulario**: el formulario de cambio de precio muestra como «Precio actual» el precio base del producto. El precio de cada sucursal se ve en Consulta de precios.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0015_zonas_jefe_escaner.sql`
2. `seed/0013_zonas_jefe_escaner.sql`
3. Opcional: la sección «PRUEBAS DE SEGURIDAD POR ZONA» de `verificar.sql`.
