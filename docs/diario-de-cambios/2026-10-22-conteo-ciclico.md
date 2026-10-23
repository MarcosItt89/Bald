# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Conteo cíclico de inventario**: cada día se cuenta una lista corta de productos en lugar de hacer inventarios completos. Es la función 3 de 5 del último encargo.

---

# 🗄️ Base de datos

## Migración `0019_conteo_ciclico.sql`
- **`cycle_count_plans`**: sucursal, departamento y/o categoría (opcionales; vacío = toda la sucursal), frecuencia (diario, lunes a viernes o un día de la semana) y productos por conteo (1 a 100).
- **`cycle_count_tasks`**: una tarea por plan y día, con avance y resumen: contados, con diferencia y diferencia en pesos.
- **`cycle_count_items`**: la lista del día. Orden de prioridad:
  1. productos con **más diferencias** en conteos de los últimos 90 días;
  2. **mayor rotación** (salidas, mermas y transferencias de salida de los últimos 30 días);
  3. los que llevan **más tiempo sin contarse**.

  Lo contado en los últimos 3 días no se repite.
- **`generate_cycle_counts`**: genera las tareas del día. No duplica. Lo llama `run_daily_maintenance`, que pg_cron corre cada hora desde la 0012.
- **`record_cycle_count(renglón, cantidad)`** — **conteo a ciegas**:
  - Registra un movimiento `count`, que deja la existencia en lo contado.
  - Guarda la existencia esperada, la diferencia en piezas y la diferencia en pesos (con el `unit_cost` de la 0014).
  - Se puede recontar mientras la tarea siga abierta; la diferencia se mide contra lo esperado del primer conteo.
  - Rechaza cantidades negativas, usuarios sin permiso y tareas cerradas.
- **`v_cycle_count_items`**: la existencia y la diferencia **solo las ve** quien tiene `manage_cycle_counts` o `manage_inventory`. Quien cuenta no ve el número del sistema, así que no puede «copiarlo».
- **Permisos**: `perform_cycle_counts` (contar) y `manage_cycle_counts` (planes y diferencias).
- **RLS**: los planes se leen por sucursal y departamento, y se escriben con `manage_cycle_counts`. Las tareas y los renglones solo se leen (con permiso de conteo o de reportes); se escriben únicamente con las funciones.

## Semilla `seed/0016_conteo_ciclico.sql`
- **`perform_cycle_counts`**: admin, gerente, supervisor, almacén, abarrotes y caducidades.
- **`manage_cycle_counts`**: admin y gerente.
- **Planes**: Sucursal Centro «Conteo diario de Abarrotes» (8 productos) y Sucursal Norte «Conteo general» de lunes a viernes (5 productos). Las tareas de hoy se generan al final.

---

# 🖥️ Frontend
- **Inventario → Conteo cíclico** (`/inventory/cycle-counts`):
  - **Hoy**: tarjetas de las tareas con su avance. La lista muestra por qué está cada producto («Tuvo diferencias», «Alta rotación», «Sin contar hace tiempo»).
  - **Captura**: un campo por producto con teclado numérico y «Escanear», que ubica el producto en la lista y pone el cursor en su campo.
  - **Para el gerente**: ve la existencia del sistema y la diferencia en piezas y en pesos.
  - **Planes** (solo `manage_cycle_counts`): alta y edición.
- **Estadísticas → Inventario**:
  - Indicador **Exactitud de inventario**: % de productos contados sin diferencia, con variación contra el periodo anterior.
  - Bloque **Exactitud por departamento**, con la diferencia neta en pesos y CSV.

---

# ✅ Verificación
- `pendiente.sql` regenerado (28 archivos) y ejecutado dos veces en PGlite sin errores. `verificar.sql`: 64 comprobaciones en verde, salvo los jobs de pg_cron.
- Pruebas en PGlite:

| Caso | Resultado |
|---|---|
| Tareas generadas hoy | Centro 8 productos, Norte 5 ✅ |
| `abarrotes` ve el renglón | Sin existencia ni diferencia (a ciegas) ✅ |
| Cuenta 2 de menos en aceite | Diferencia −2 = −$66.00; movimiento `count` 60 → 58 ✅ |
| Cuenta exacta | Diferencia 0 ✅ |
| Cantidad negativa / cajero | Rechazados ✅ |
| Gerente | Ve sistema, contado, diferencia y pesos ✅ |
| Los 8 contados | Tarea «completed», 1 con diferencia ✅ |
| Contar en tarea cerrada | Rechazado ✅ |
| Volver a generar hoy | 0 nuevas ✅ |
| Siguiente conteo | El aceite (tuvo diferencia) sale primero, «differences» ✅ |
| Cajero (sin permiso) | No ve tareas ✅ |

- `npm run lint` y `npm run build` sin errores.
- Revisado a 360 px como quien cuenta y como gerente, con datos simulados porque tu base aún no tiene la 0019. Se corrigió el botón «Guardar», que se salía de la tarjeta en celular. Sin errores de JS.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0019_conteo_ciclico.sql`
2. `seed/0016_conteo_ciclico.sql`
