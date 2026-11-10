# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
9 de noviembre de 2026

## 🧩 Cambio registrado
**Seguridad (semillas sin datos personales ni superadmin demo, tope en la recuperación de contraseña, revisiones en `verificar.sql`); Bitácora de plataforma; Estadísticas calculadas en la base; bundle dividido; limpieza y orden del código.**

---

# 🔐 Seguridad

## 1 y 2. Semillas de producción
- **`seed/0010_propietario.sql`:**
  - **Datos personales:** se quitaron el correo y el nombre personales del administrador. Ninguna semilla de producción trae ya datos personales ni cuentas con contraseña.
  - **Superadmin:** se quitó la sección que hacía superadmin al usuario demo `gatopelon`.
  - **Lo que queda:** el propietario `chee`, sin cuenta.
- **Superadmin de pruebas:** pasó a **`demo/0010_superadmin_demo.sql`**, que solo trae `pendiente.sql`.
- **README:** sección nueva **«Nombrar al superadmin real»**:
  1. empleado con correo real;
  2. cuenta en Authentication → Users, que se liga sola por el correo;
  3. `insert into platform_admins` con el marcador `<CORREO>`;
  4. comprobar con `verificar.sql`.

  El administrador real de una tienda sigue los pasos 1 y 2.
- **Diario de 2026-10-29:** se quitó la mención del usuario personal.
- **Instalación limpia (PGlite):** queda solo la empresa `gatopelon`, con el propietario `chee`, 0 cuentas en Auth y 0 superadmins.

## 3. `verificar.sql`: cuentas demo
| Fila | ❌ cuando |
|---|---|
| sin cuentas demo (contraseña prueba123) en una base sin demo | **No** existen las empresas demo (Súper La Luna y Mercado Sol), pero hay cuentas `@gatopelon/@superluna/@mercadosol.operalia.local` cuya contraseña es `prueba123` |
| ningún superadmin es una cuenta demo | Algún `platform_admin` es una de esas cuentas con `prueba123`. En pruebas con demo sale ❌ **a propósito** (lo dice el encabezado) |

- **Cómo revisa la contraseña:** con `extensions.crypt` (pgcrypto vive en `extensions`, igual que en Supabase).
- **Probado en tres escenarios:**
  - con demo: solo la segunda fila sale ❌;
  - sin demo con cuentas olvidadas: las dos salen ❌;
  - sin demo y limpia: las dos salen ✅.
- **Fila «hay al menos un superadmin»:** ahora apunta a «README → Nombrar al superadmin real».

## 4. `request_password_reset` (migración 0032)
- **Tope nuevo:** máximo **20 solicitudes distintas por empresa por hora**, además del límite de una cada 15 minutos por empleado.
- **Pasado el tope:** responde igual, sin avisar a nadie y sin revelar nada.
- **Índice parcial nuevo:** `notifications_password_reset_idx`.
- **Probado:** 16 solicitudes seguidas generan 16 avisos; el tope corta a partir de 20.

# 🧹 Limpieza

## 5. Código sin usar
- **Archivos borrados:** `apps/tiendas/src/constants/demoAccounts.js` y `components/auth/Can.jsx`; nadie los importaba.
- **Exportaciones que nadie usaba:**
  - `getEmployeeDepartments`, `setReceivedQty`, `createRole` y `updateReceivingHeader`;
  - `getAuditLogs` (la reemplaza la Bitácora);
  - `APP_MODULES` y `createIsolatedClient`.
- **CSS:** **63 selectores** muertos en `global.css` (313 líneas): las cuentas demo del login, el dashboard viejo de actividad, la lista vieja de checklists, la rejilla de roles, las etiquetas de permisos y el «placeholder». Más 1 en `components.css`. Se quitó con un script que solo elimina selectores cuyas clases no menciona ningún JS/JSX; las clases armadas en tiempo de ejecución (`stat-${tone}`, `cl-run-${status}`, `chart-*`…) se conservaron.

## 6. Bundle
- **`packages/compartido/build/manualChunks.js`:** lo usan los dos `vite.config.js` y separa `react` (con react-dom, react-router y scheduler), `supabase` y `lucide`.

  | Bundle principal | Antes | Ahora |
  |---|---|---|
  | Tiendas | 545 KB | 44 KB, más `react` 277 KB, `supabase` 200 KB y `lucide` 36 KB |
  | Consola | 503 KB | Partido igual |

- **Aviso de chunks grandes:** desapareció.

## Orden del código
- **Puentes quitados:** se eliminaron las reexportaciones que quedaron de la separación en workspaces. Cada módulo se importa ahora de donde vive:
  - formato de reportes de `@operalia/compartido/reports/reportFormat.js`;
  - marca de `branding/brandingService.js`;
  - contraseña temporal de `utils/passwords.js`;
  - QR de `utils/qr.js`.
- **Imports agrupados en 66 archivos:**
  1. librerías;
  2. `@operalia/*`;
  3. relativos.

  El orden dentro de cada grupo no cambió. No se tocaron los archivos con imports de efecto (CSS).

# 🖥️ Plataforma (superadmin)

## 7. Topbar en /plataforma
Ya estaba resuelto: desde el cambio anterior, `/plataforma/*` de tiendas es solo el aviso público, sin Topbar. La Consola tiene su propia barra, sin selector de sucursal, «Reportar problema» ni «Soporte».

## 8. KPIs de Rendimiento
- **Clase nueva `report-kpis-8`:** 4 columnas en escritorio y 2 en pantallas de 1100 px o menos, y también en celular.
- **Resultado medido:** 8 tarjetas en 2 filas de 4 a 1280 px, y en 4 filas de 2 a 900 y 360 px. Sin tarjetas huérfanas.

## 9. Bitácora (migración 0032)
- **`platform_audit_log(límite, empresa, evento)`:** SECURITY DEFINER; valida `is_platform_admin()`. Reúne:
  - **`alta`, `suspension` y `reactivacion`:** desde `audit_logs` (`provision_company` y `platform_set_company_status`);
  - **`marca`:** solo los cambios que hizo **un superadmin**; los del propietario no entran;
  - **`soporte`:** las respuestas `is_platform` de los tickets, firmadas «Soporte Operalia».
- **Consola → Bitácora** (`/bitacora`):
  - **Filtros:** por empresa y evento, guardados en la URL.
  - **Clic en un renglón:** abre el ticket, la Marca o el Rendimiento de esa empresa.
  - **CSV:** se descarga.
- **Probado con eventos reales:**
  - suspender y reactivar Mercado Sol, cambiar su marca y responder un ticket: salen 4 eventos;
  - los filtros funcionan;
  - la propietaria que cambia su marca no aparece y no puede leer la bitácora.

# 📊 Estadísticas en la base (10, migración 0033)
- **TODO cerrado:** se resolvió el pendiente de `reportService.js`. Hay **una función SQL por pestaña** que devuelve **el mismo JSON** que antes armaba el navegador:
  - `report_summary`, `report_checklists` y `report_management` (Gerencia);
  - `report_tasks`, `report_inventory` y `report_temperatures`;
  - `report_receiving` y `report_support`.
- **Seguridad:** SECURITY INVOKER, así que leen con el RLS de quien consulta. Las secciones dependen de los mismos permisos que antes revisaba el navegador (`can`).
- **Fechas:** los días «locales» usan la zona horaria de la empresa (`companies.timezone`).
- **Sin tope de 1000 filas:** antes, en periodos largos, los totales podían quedar cortos.
- **Utilidades:** `report_pct`, `report_delta`, `report_week`, `report_days`, `report_weeks`, `report_tz` y `report_runs`.
- **Índices nuevos:** `checklist_answers(question_id)` y `tasks(branch_id, completed_at)`.
- **`reportService.js`:** pasó de 550 a 56 líneas (solo llamadas RPC).
  - Se quitaron `deptName` (ReportsPage) y `can` (useReport).
  - Resumen recibe la antigüedad de las tareas como números en lugar de listas.
- **Pruebas en PGlite**, con 30 días de demo:
  - **Formato:** las 8 funciones devuelven todas las llaves que usan las pestañas.
  - **Totales:** cuadran con consultas directas: corridas (3240), % de checklists, mermas y su costo, tickets y tareas creadas.
  - **Filtros:** una sucursal da 810 = referencia; un arreglo vacío (zona sin sucursales) da 0.
  - **RLS:** un gerente solo ve su sucursal (810). `anon` no puede ejecutarlas.
  - **Errores corregidos durante las pruebas:** un agrupado inválido en `report_inventory`, y Resumen y Temperaturas, que hacían una consulta por día (ahora es una sola lectura agrupada).
  - **Gerencia sale en 0%** con la demo porque sus checklists solo tienen lecturas numéricas, no respuestas sí/no. Es lo mismo que daba el cálculo anterior.
- **Navegador:** las 7 pestañas cargan con el JSON **real** que devolvió la base (1280, 900 y 360 px): 0 errores de estado y 0 errores JS.

# 🧪 Pruebas
- **Instaladores:**
  - `pendiente.sql` corre **dos veces** sin errores;
  - `instalacion-limpia.sql` corre **dos veces** sin errores y deja la base sin cuentas, superadmins ni datos personales.
- **`verificar.sql` con demo:** 107 filas. Solo salen ❌ pg_cron, que la copia local no tiene, y «ningún superadmin es una cuenta demo», que es lo esperado en pruebas.
- **Aislamiento: 0 ❌** en 462 pruebas. `platform_audit_log` se suma a la lista revisada y bloquea a todos los que no son superadmin.
- **Navegador:** Estadísticas, Bitácora y KPIs 4×2 a 1280, 900 y 360 px, sin scroll horizontal ni errores.
- `npm run lint` y `npm run build` (las dos apps) en verde.

# ▶️ Qué correr en Supabase
1. `migrations/0032_seguridad_bitacora.sql` y `migrations/0033_estadisticas_sql.sql`.
2. **Producción:** nombra al superadmin real (README) y quita al demo si existe:
   `delete from platform_admins where user_id in (select id from auth.users where email like '%.operalia.local');`. Revisa antes que no sea tu cuenta.
3. `verificar.sql`: en producción, las filas «seguridad» deben salir ✅.
4. En el ambiente de pruebas, `pruebas/aislamiento.sql`: **0 con ❌**.
