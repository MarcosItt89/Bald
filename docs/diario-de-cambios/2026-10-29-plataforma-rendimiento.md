# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
29 de octubre de 2026

## 🧩 Cambio registrado
**Plataforma → Rendimiento: cómo van las tiendas y sus sucursales. Herramientas para sumar tiendas: salud de la cuenta, avance de arranque y prospectos.**

---

# 🗄️ Base de datos

## Migración `0025_plataforma_rendimiento.sql`

Todas las funciones son `security definer`, fallan si `not is_platform_admin()` y devuelven **solo agregados**: conteos, sumas y porcentajes, nunca filas de una empresa. Los días se cuentan en la zona horaria de cada empresa.

### Definiciones (las mismas de Estadísticas, `src/services/reportService.js`)

| Métrica | Cálculo | De dónde sale en Estadísticas |
|---|---|---|
| Checklists completados | completados ÷ corridas del periodo sin canceladas | `runCompliance` |
| Checklists a tiempo | completados antes del fin de su horario ÷ corridas | `isLate` del reporte de checklists, al revés |
| Tareas vencidas | abiertas con fecha límite pasada, hoy | `v_tasks.is_late` (`openLate`) |
| Tareas a tiempo (tendencia) | cerradas el día de su fecha límite o antes | `taskOnTime` |
| Mermas | movimientos `waste`; valor = cantidad × (`unit_cost` o costo del producto) | `costOf` |
| Exactitud del conteo cíclico | productos contados sin diferencia ÷ contados | `countAccuracy` |
| Huecos abiertos | `shelf_gaps` con estado `open`, hoy | — |
| Tickets dentro de SLA | tickets del periodo con vencimiento: cumplido si se resolvió o cerró antes de `due_at`, o si sigue abierto y aún no vence | `slaOf` |
| Usuarios de 7 días | empleados activos con `auth.users.last_sign_in_at` de los últimos 7 días | — |

**Dos precisiones:**
- **Checklists que todavía no terminan su horario:** solo cuentan los que ya lo cerraron. Los de hoy que siguen dentro de su ventana aún no se pueden calificar; si contaran, «hoy» saldría siempre en 0 %. Estadísticas sí los cuenta.
- **Tiempo de atención de huecos:** no existía en Estadísticas. Son las horas de `reported_at` a `resolved_at` de los huecos resueltos en el periodo, con la misma fórmula de las horas de cierre de tareas.

### Funciones
- **`platform_company_kpis(p_from, p_to)`:**
  - devuelve una fila por empresa (`branch_id` null) y una por sucursal;
  - trae numeradores y denominadores, así el frontend suma la plataforma completa sin promediar porcentajes;
  - el periodo máximo es de un año.
- **`platform_company_trend(p_company_id, p_metric, p_from, p_to)`:**
  - devuelve la serie diaria `{ day, value, base }`;
  - con `p_company_id` null, calcula toda la plataforma;
  - métricas: `checklist_pct`, `checklist_on_time_pct`, `tasks_on_time_pct`, `waste_value`, `waste_count`, `count_accuracy_pct`, `gaps_reported`, `gap_hours` y `tickets_created`.
- **`platform_checklist_heatmap(p_from, p_to, p_company_id)`:** % de checklists completados por sucursal y día, hasta 93 días.
- **`platform_company_health()`:** salud de la cuenta y avance de arranque de cada empresa (ver abajo).

### Salud de la cuenta (últimos 7 días)
La empresa toma el peor color de los tres criterios:

| Criterio | Verde | Amarillo | Rojo |
|---|---|---|---|
| **Uso:** % de empleados con cuenta que entraron | ≥ 60 % | ≥ 30 % | < 30 % |
| **Checklists a tiempo:** solo de los que ya terminaron su horario | ≥ 60 % | ≥ 45 % (o sin corridas) | < 45 % |
| **Tickets abiertos por sucursal activa** | ≤ 1 | ≤ 2 | > 2 |

La función también devuelve los motivos en texto, por ejemplo «36 % de los usuarios entró en 7 días». Los umbrales están en un solo lugar, `platform_company_health`, por si quieres ajustarlos.

### Avance de arranque
Son 5 pasos y cada uno vale 20 %:
1. **Sucursales creadas:** tantas como dijo su prospecto ganado, o al menos 1 si no tiene prospecto.
2. **Empleados con cuenta**, además del propietario: al menos uno por sucursal.
3. **Productos cargados:** al menos uno.
4. **Primera plantilla usada:** al menos un checklist completado.
5. **Primer recibo cerrado:** al menos un recibo con estado `completed`.

### Prospectos: `platform_leads`
- **Campos:**
  - cadena, contacto, correo, teléfono, número de sucursales, giro y notas;
  - estado: `new`, `demo`, `negotiation`, `won` o `lost`;
  - `company_id`, que se llena al darla de alta;
  - `created_by`, que la base llena con quien lo crea.
- **Acceso:** con RLS, solo un superadmin lee y escribe. Ninguna empresa los ve.

# 💻 Frontend
- **Rendimiento** (`/plataforma/rendimiento`):
  - filtro de periodo (7, 30 o 90 días, o personalizado) y exportación a CSV de todas las filas de empresa y sucursal;
  - fila de KPIs totales de la plataforma (`StatCard`);
  - **ranking** por cualquiera de 10 métricas, de empresas o de sucursales (`BarList`, con el mejor arriba);
  - **tendencia** diaria con selector de tienda y métrica (`LineChart`);
  - **mapa de calor** de cumplimiento por sucursal y día, de los últimos 31 días del periodo (`Heatmap`). Usa la tienda elegida en la tendencia.
  - Cada sección tiene su propio «Exportar CSV».
- **Empresas:**
  - columnas nuevas de **Salud** (con su motivo) y **Arranque** (barra de avance);
  - al hacer clic en una fila se abre el detalle de los tres criterios y de los cinco pasos.
- **Prospectos** (`/plataforma/prospectos`):
  - pestañas En proceso, Ganados, Perdidos y Todos, con alta y edición en una ventana;
  - un prospecto **ganado** sin empresa tiene el botón **«Dar de alta»**, que abre Nueva empresa con el nombre, el código sugerido y el propietario llenos. Al crear la empresa, el prospecto queda ligado.
- **Menú:** Plataforma tiene ahora Empresas, Rendimiento, Prospectos, Nueva empresa y Soporte de tiendas. Las rutas nuevas exigen `isPlatformAdmin`.
- **Archivos nuevos y modificados:**
  - **Nuevos:** `PerformancePage.jsx`, `LeadsPage.jsx` y `platformMetrics.js`, con el catálogo de métricas y los totales.
  - **Funciones nuevas en `platformService.js`:** `getPlatformKpis`, `getPlatformTrend`, `getChecklistHeatmap`, `getCompanyHealth` y CRUD de prospectos.
  - **Estados en `constants/status.js`:** `ACCOUNT_HEALTH` y `LEAD_STATUS`.

# 🧪 Demo
- **`demo/0019`:** la calidad de cada sucursal ahora también se escala por empresa (Gato Pelón × 1.08, Súper La Luna × 0.93, Mercado Sol × 0.78). Así los totales de las empresas se distinguen y no solo sus sucursales. Solo afecta instalaciones nuevas, porque el historial no se regenera si ya existe.
- **`demo/0025_rendimiento_demo.sql`** (nuevo):
  - 30 días de historial también para Gato Pelón;
  - últimos inicios de sesión simulados: ~85 % en Gato Pelón, ~55 % en Súper La Luna y ~20 % en Mercado Sol. Solo toca cuentas que nunca han entrado;
  - de 0 a 4 huecos abiertos por sucursal;
  - 7 prospectos de ejemplo. Súper La Luna y Mercado Sol quedan ligadas a su prospecto ganado y «Abarrotes Doña Mary» queda ganado sin dar de alta.

Resultado con las 3 tiendas demo, últimos 30 días:

| Empresa | Checklists a tiempo | Merma | Exactitud | Uso 7 días | Salud |
|---|---|---|---|---|---|
| Gato Pelón | 74 % | $6,143 | 85 % | 88 % | 🟢 Sana |
| Súper La Luna | 55 % | $10,474 | 74 % | 50 % | 🟡 Atención |
| Mercado Sol | 40 % | $14,704 | 62 % | 36 % | 🔴 En riesgo |

Por sucursal, el rango va de 97 % (Sucursal Norte) a 22 % (Sol Centro) de checklists a tiempo.

# ✅ Pruebas (PGlite)
- **Instaladores:**
  - `pendiente.sql` corre dos veces sin errores;
  - `verificar.sql`, con 92 filas, sale en verde salvo pg_cron;
  - la instalación limpia no cambia;
  - la actualización desde el instalador anterior (0022 → 0025 + `seed/`) no duplica plantillas ni preguntas.
- **Funciones:**
  - las sucursales suman lo mismo que el total de su empresa;
  - un no superadmin recibe error en todas las funciones;
  - un periodo invertido o una métrica desconocida se rechazan;
  - la tendencia responde con las 9 métricas, por empresa y para toda la plataforma.
- **Prospectos:** el superadmin los crea y edita (`created_by` firmado). Una propietaria ve 0 prospectos y no puede insertar. Un estado inválido se rechaza.
- **Pantallas:** se probaron con Supabase simulado, usando las respuestas reales de esta base, a 1280 y 360 px:
  - Rendimiento, Empresas con su detalle de salud y Prospectos se ven sin scroll horizontal;
  - «Dar de alta» llena Nueva empresa con «Abarrotes Doña Mary», el código `abarrotesdonamary` y la propietaria María López.
- `npm run lint` y `npm run build` pasan.

# ▶️ Qué correr en Supabase
1. `migrations/0025_plataforma_rendimiento.sql`, después de 0024.
2. **Solo en pruebas:** `demo/0025_rendimiento_demo.sql`. El cambio de `demo/0019` solo aplica a una base nueva.
3. `verificar.sql`
4. Publica el frontend.
