# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
Nueva sección **Estadísticas** en `/reports` (permiso `view_reports`), que reemplaza el placeholder "en construcción". Sin cambios en la base de datos.

---

# 📊 Qué incluye

## Filtros (se guardan en la URL)
- **Sucursal:** mismo alcance que el selector del topbar. Admin, auditor y soporte eligen sucursal o "Todas"; el gerente y demás roles solo ven la suya.
- **Departamento**, **periodo** (Hoy, 7, 30, 90 días o personalizado) y **comparar con periodo anterior** (activado por defecto).
- Ejemplo: `/reports?tab=tasks&p=90&dept=<id>&cmp=0`

## Pestañas (se ocultan si el usuario no tiene permiso del módulo)
| Pestaña | Contenido |
|---|---|
| Resumen | 6 indicadores con variación vs. periodo anterior; cumplimiento diario de checklists; cumplimiento por departamento; tareas abiertas por antigüedad |
| Checklists | Completados / vencidos / cancelados; por turno; por departamento; mapa de calor departamento × día; top 10 preguntas con "No"; checklists que se completan tarde con frecuencia |
| Tareas | Creadas vs. cerradas por semana; a tiempo vs. atrasadas; tiempo de cierre por departamento y por responsable |
| Inventario | Bajo mínimo y agotados por departamento; movimientos por tipo; merma en cantidad y en pesos (`products.cost`); caducidades por semana |
| Recibo y precios | Recibos por proveedor y % con diferencias; cambios de precio aplicados; cenefas validadas en ≤ 48 h y pendientes |
| Soporte | Tickets abiertos; tiempo a primera respuesta; cumplimiento de SLA (`due_at`); tickets por categoría |

Cada número, barra, segmento o celda lleva a la página de detalle ya filtrada (solo si el usuario tiene acceso a esa página). Cada tabla o gráfica tiene **Exportar CSV**.

---

# 🧱 Archivos

## Nuevos
- `src/components/charts/` — `BarList`, `LineChart`, `Donut`, `Heatmap`: gráficas propias y ligeras, sin librerías. Usan los tokens `--chart-*` definidos en `components.css` a partir de las variables existentes, con valores para modo oscuro.
- `src/hooks/useElementWidth.js` — ancho responsivo para los SVG.
- `src/features/reports/reportFilters.js` — filtros en la URL, `useReport`, enlaces con verificación de permisos.
- `src/features/reports/reportUi.jsx` — `Delta`, `ReportSection` (con CSV) y `ReportState` (carga, error y "Sin datos en este periodo").
- `src/features/reports/tabs/*.jsx` — una pestaña por archivo.
- `src/components/ui/FilterChip.jsx` — muestra el filtro que llegó por URL y permite quitarlo.

## Modificados
- `src/services/reportService.js` — una función por pestaña (`getSummaryReport`, `getChecklistReport`, `getTaskReport`, `getInventoryReport`, `getReceivingReport`, `getSupportReport`) que solo pide las columnas necesarias. Se retiró `getOperationalReport`, que no se usaba.
- `src/config/navigation.js` — el menú dice "Estadísticas" (misma ruta).
- `src/constants/status.js` — `TASK_AGE_BUCKETS` y `taskAgeBucket()`.

## Páginas que ahora aceptan filtros por URL
| Página | Parámetros |
|---|---|
| `/tasks` | `tab=all`, `done=1`, `dept`, `prio`, `late=1`, `assignee`, `age` |
| `/checklists/history` | `from`, `to`, `status` (`all`, `completed`, `overdue`, `cancelled`), `dept`, `shift`, `template` |
| `/inventory` | `status` (incluye el nuevo `alerts` = bajo mínimo), `dept` |
| `/inventory/movements` | `type`, `from`, `to` |
| `/receiving` | `tab`, `supplier`, `diff` (`1` con diferencias, `0` sin) |
| `/expirations`, `/price-changes`, `/shelf-tags` | `tab` |
| `/evidence` | `tab`, `from`, `to` |
| `/support` | `tab`, `cat` (categoría) |

Además, en la pestaña "Todas" de `/tasks` ahora entra quien tenga `view_reports`, no solo quien tenga `manage_tasks`.

---

# ⚠️ Limitaciones conocidas
- Los cálculos se hacen en el navegador. Supabase devuelve como máximo **1000 filas por consulta**, así que en periodos largos con mucho movimiento (sobre todo `inventory_movements`) los totales pueden quedar cortos. Pendiente: moverlos a funciones SQL (`rpc`) que devuelvan agregados, como indica el comentario en `reportService.js`.
- "Productos bajo mínimo", "Agotados" y "Cenefas pendientes" muestran la existencia actual: no hay historial para compararlos con el periodo anterior.
- Las evidencias y los recibos no tienen departamento, así que el filtro de departamento no aplica a esos indicadores.

---

# ✅ Verificación
- `npm run lint` y `npm run build` sin errores.
- Revisado a 360 px y 1280 px con `gerente.centro`: las 6 pestañas cargan sin errores de JS y sin desplazamiento horizontal.
- Clic en "> 7 días" (tareas abiertas por antigüedad) abre `/tasks?tab=all&age=gt7` con las mismas 5 tareas que muestra la barra.
