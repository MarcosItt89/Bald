# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
Checklists diarios de **Gerencia** (apertura y cierre de tienda), preguntas **críticas**, **tarea automática** cuando una respuesta es «No», horarios relativos a la apertura y cierre de cada sucursal, y comparación de sucursales en Estadísticas.

---

# 🗄️ Base de datos

## Migración `0013_checklists_criticos_y_horarios.sql`
- **`checklist_questions.is_critical`**: marca las preguntas de seguridad y valores.
- **Tarea automática por «No»**: el trigger `trg_checklist_answer_task` se dispara cuando una respuesta sí/no es «No».
  - Crea una tarea para el departamento del checklist, con vencimiento el día del checklist. Si la pregunta es crítica, la prioridad es *high* y el título empieza con «CRÍTICO:».
  - Avisa a los jefes del departamento (quienes tienen `review_checklists`). Si es crítica, avisa también al gerente de la sucursal. Quien respondió no recibe aviso.
  - Si la respuesta se corrige y la tarea sigue pendiente, la tarea se cancela sola.
  - `tasks.source_type` / `tasks.source_id` ligan la tarea con la respuesta, así no se duplica.
- **Horarios relativos a la sucursal**:
  - En `checklist_templates`: `schedule_anchor` (`fixed` | `opening` | `closing`), `start_offset_minutes` y `end_offset_minutes`.
  - `generate_checklist_runs` calcula la ventana de cada sucursal con `checklist_window()`. La ventana no cruza la medianoche: el inicio se recorta a 00:00 y el fin a 23:59.
  - Si la sucursal no tiene `opening_time` / `closing_time`, se usan `start_time` / `end_time`.

## Semilla `seed/0011_checklists_gerencia.sql`
7 plantillas diarias del departamento GER (36 preguntas, 10 críticas). No se duplican por título.

| Plantilla | Turno | Ventana (relativa) | Si la tienda abre 07:00 y cierra 22:00 | Evidencia |
|---|---|---|---|---|
| Apertura · Exterior y seguridad | apertura | apertura −60 a 0 min | 06:00–07:00 | Sí |
| Apertura · Piso de venta | apertura | apertura −30 a +30 | 06:30–07:30 | Sí |
| Apertura · Perecederos y frío | apertura | apertura −30 a +30 | 06:30–07:30 | Sí |
| Apertura · Cajas y personal | apertura | apertura −15 a +30 | 06:45–07:30 | No |
| Cierre · Piso y perecederos | cierre | cierre −60 a 0 | 21:00–22:00 | No |
| Cierre · Cajas y valores | cierre | cierre −30 a +30 | 21:30–22:30 | Sí |
| Cierre · Seguridad | cierre | cierre 0 a +60 | 22:00–23:00 | Sí |

- **Críticas:** salidas de emergencia, alarma (desactivada y activada), cámaras, sin caducados en exhibición, fondo de caja, cortes de caja, efectivo en caja fuerte, diferencias de caja reportadas, puertas y accesos cerrados.
- **Temperaturas:** siguen como sí/no por ahora.
- **«Pendientes para el turno de mañana»:** pregunta de texto opcional.
- **Gerentes:** el rol gerente tiene `fill_checklists`, `review_checklists` y `upload_evidence`. Los gerentes sin departamento quedan en Gerencia.
- **Al final:** ejecuta `generate_checklist_runs` para hoy.

## Corrección en `0004_vistas.sql`
Al ejecutar `pendiente.sql` por segunda vez fallaba con «cannot drop columns from view». Las migraciones 0011, 0012 y 0013 agregan columnas a `v_support_tickets`, `v_employees` y `tasks`, y `create or replace view` no permite quitar ni reordenar columnas. Ahora la 0004 elimina sus vistas antes de recrearlas, y las migraciones posteriores vuelven a crear sus versiones extendidas.

---

# 🖥️ Frontend
- **Checklists**:
  - Nueva pestaña **«Míos»**: los checklists del departamento del usuario. Es la pestaña por defecto; al gerente le muestra los de Gerencia.
  - En la ejecución, las preguntas críticas muestran la insignia «Crítica».
  - Al responder «No», aparece un aviso de que se creó una tarea.
- **Estadísticas → Checklists**: nuevo bloque **«Gerencia: apertura y cierre»**.
  - Barra por sucursal con su calificación del periodo (apertura y cierre por separado).
  - Mapa de calor sucursal × día; con más de 31 días se agrupa por semana.
  - Calificación = respuestas «Sí» ÷ preguntas sí/no programadas, sin contar las «N/A». Un checklist que no se llenó cuenta como no cumplido.
  - Clic en una celda: historial de Gerencia de ese día.
  - Exportar CSV por sucursal y día.
  - `reportService.fetchAll` pagina de 1000 en 1000 para no topar con el límite de filas de Supabase.

---

# ✅ Verificación
- `pendiente.sql` regenerado (17 archivos) y ejecutado dos veces seguidas en PGlite sin errores.
- En PGlite:
  - Ventanas por sucursal correctas: Centro cierra a las 23:00, así que su cierre va de 22:00 a 23:59; una sucursal que abre a las 08:00 queda con 07:00–08:00.
  - «No» crítico del gerente → tarea *high*. «No» del cajero → tarea *medium* y aviso a `jefe.cajas`. Al corregir la respuesta a «Sí», la tarea se cancela.
- `npm run lint` y `npm run build` sin errores. Revisado a 360 px: sin errores de JS.

# 📌 Para aplicar
En el SQL Editor de Supabase, en este orden:
1. `migrations/0013_checklists_criticos_y_horarios.sql`.
2. `seed/0011_checklists_gerencia.sql`.

**No ejecutes `0004_vistas.sql` por separado.** Elimina las vistas y las recrea en su versión original, sin las columnas de 0009, 0011 y 0012. Su corrección solo importa cuando se ejecuta `pendiente.sql` completo.
