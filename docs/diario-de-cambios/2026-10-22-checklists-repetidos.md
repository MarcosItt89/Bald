# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
Checklists que se **repiten varias veces al día** (rondas), por ejemplo la ronda de carritos cada 2 horas.

---

# 🗄️ Base de datos

## Migración `0016_checklists_repetidos.sql`
- **`checklist_templates.repeat_every_minutes`**: `null` = una vez al día; mínimo 30 minutos (restricción `checklist_templates_repeat_chk`).
- **`checklist_templates.repeat_until`**: último inicio permitido. Si está vacío, se usa el cierre de la sucursal o, si no tiene, el `end_time` de la plantilla.
- **Restricción única de `checklist_runs`**: pasa de (plantilla, sucursal, fecha) a **(plantilla, sucursal, fecha, hora de inicio)**. La vieja se busca por sus columnas, no por su nombre, así que la migración es re-ejecutable.
- **`checklist_runs.round_no` y `rounds_total`**: para mostrar «Ronda 3 de 7» sin cálculos en la vista.
- **`generate_checklist_runs`**:
  - Crea una corrida por intervalo con `generate_series`. Cada ronda dura lo mismo que la ventana original, sin pasar de 23:59.
  - Respeta los horarios relativos a apertura y cierre de la 0013.
  - **Guarda nueva**: si una plantilla ya tiene corridas ese día en esa sucursal, no agrega más. Así, cambiar la hora o la repetición de una plantilla aplica desde el día siguiente y no duplica corridas.
- **`v_checklist_runs`**: se recrea para incluir `round_no`, `rounds_total` y `repeat_every_minutes`.
- **Lo que ya funcionaba por corrida y no necesitó cambios**: el marcado de vencidos (usa el `scheduled_end` de cada ronda), la cancelación de 0010 (cancela una ronda) y la tarea automática de 0013/0014 (se liga a la respuesta de esa ronda).

## Ajustes a migraciones anteriores (re-ejecución)
- **`on conflict do nothing`**: la 0003 y la 0013 usaban `on conflict (template_id, branch_id, scheduled_date)`. Al reejecutar `pendiente.sql` esa restricción ya no existe, así que ahora usan `on conflict do nothing`, que funciona con la restricción vieja y con la nueva.
- **Guarda «ya hay corridas ese día»**: se agregó también al generador de la 0003 y al de la 0013.

## Semilla `seed/0014_checklists_repetidos.sql`
«Ronda de carritos y canastillas» (Cajas), cada 2 h de 08:00 a 20:00: 7 rondas de 2 horas. Sus 4 preguntas: carritos recolectados, canastillas acomodadas, carritos dañados (cantidad) y foto.

---

# 🖥️ Frontend
- **Checklists**:
  - Las plantillas con rondas se agrupan en **una tarjeta por plantilla y sucursal**.
  - Muestra «Ronda 5 de 7» con la hora de la ronda actual: la que está en proceso, si no la vigente, si no la siguiente.
  - Debajo hay fichas con todas las rondas del día, coloreadas por estado (completada, vencida, en progreso o futura, esta con borde punteado). Una ficha abre o inicia esa ronda.
  - Una ronda futura no se puede iniciar hasta 10 minutos antes de su hora; muestra «Desde 16:00».
- **Plantillas**: nuevos campos «Repetir» (una vez, 30 min, 1 h, 2 h, 3 h, 4 h) y «Hasta (último inicio)». La lista muestra «Diaria · cada 2 h».
- **Dashboard**:
  - «Checklists pendientes» ya no cuenta las rondas que todavía no empiezan.
  - «Checklists de hoy» muestra solo la ronda vigente de cada plantilla, con «ronda X de Y».
- **Estadísticas → Checklists**:
  - **Cumplimiento por hora del día**: barras por hora de inicio.
  - **Cumplimiento por ronda**: mapa de calor plantilla × hora de la ronda, solo para las plantillas que se repiten. Clic → historial de esa plantilla.

---

# ✅ Verificación
- `pendiente.sql` regenerado (23 archivos) y ejecutado dos veces en PGlite sin errores. `verificar.sql`: 50 comprobaciones en verde (salvo pg_cron, que no existe en PGlite).
- Pruebas en PGlite:
  - Ronda de carritos: 7 rondas (08–10, 10–12 … 20–22), con «round_no / rounds_total».
  - Las plantillas sin repetición siguen con **1 corrida por día**, también después de reejecutar todo.
  - Regenerar el mismo día no crea nada.
  - Una plantilla nueva cada 30 min de 07:00 a 08:00 con ventana de 15 min genera 07:00–07:15, 07:30–07:45 y 08:00–08:15.
  - Repetir cada 20 min → rechazado por la base de datos.
- `npm run lint` y `npm run build` sin errores. Revisado a 360 px con rondas simuladas (tu base aún no tiene la 0016): una tarjeta con 7 fichas y la ronda vigente marcada, sin errores de JS.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0016_checklists_repetidos.sql`
2. `seed/0014_checklists_repetidos.sql`

Las rondas de la plantilla de ejemplo aparecen desde hoy, porque la semilla genera las corridas al final.
