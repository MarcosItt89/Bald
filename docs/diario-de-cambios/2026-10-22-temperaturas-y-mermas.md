# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Temperaturas** como preguntas numéricas con rango dentro de los checklists, y **mermas** con motivo y costo: página de captura, merma automática al retirar caducidades y nuevas estadísticas.

---

# 🗄️ Base de datos

## Migración `0014_temperaturas_y_mermas.sql`

### A. Temperaturas
- **`checklist_questions`**: nuevas columnas `min_value`, `max_value`, `unit` y `equipment_name`.
- **`checklist_answers.out_of_range`**: lo calcula `trg_checklist_answer_range`.
  - Acepta coma decimal: `9,5` se guarda como `9.5`.
  - Rechaza lecturas que no sean un número.
- **Tarea automática** (reemplaza la función de 0013):
  - Una lectura fuera de rango crea la tarea «Temperatura fuera de rango: <equipo> <valor><unidad>» con prioridad *high*.
  - Avisa de inmediato al jefe del departamento y al gerente.
  - Si la lectura se corrige y queda en rango, la tarea pendiente se cancela.
- **Completar el checklist** exige comentario y foto en cada lectura fuera de rango (`trg_checklist_range_completion`).
- **Calificación**: fuera de rango cuenta como «No».

### B. Mermas
- **`inventory_movements`**: nuevas columnas `waste_reason` y `unit_cost`.
  - Valores de `waste_reason`: `expired`, `damaged`, `theft`, `mishandling`, `temperature`, `other`.
  - `trg_movement_cost` copia `products.cost` en `unit_cost` cuando viene vacío.
  - Las mermas sin motivo se rechazan.
  - Históricos: `unit_cost` toma el costo actual del producto, y `waste_reason` se deduce del texto («caduc…» → `expired`; lo demás → `other`).
- **Permiso `register_waste`**: con él se puede insertar merma (RLS `movements_insert`).
- **Evidencias**: nuevo tipo `inventory_movement`, para la foto de la merma.
- **Caducidades** (`trg_expiration_waste`): al retirar un lote o marcarlo vencido a mano se genera su merma `expired`.
  - Se genera una sola vez por lote.
  - La cantidad se limita a la existencia disponible.
  - El vencimiento automático del mantenimiento no la genera, porque el producto sigue en anaquel hasta que alguien lo retira.
- **Vistas**:
  - `v_inventory_movements` se recrea con las columnas nuevas y `total_cost`.
  - `v_tasks` se recrea para exponer `source_type` y `source_id` de 0013.

## Semilla `seed/0012_temperaturas_y_mermas.sql`
- **Preguntas sí/no de temperatura retiradas**, con `is_active = false` (el historial se conserva):
  - Gerencia: «Temperaturas de cámaras y vitrinas en rango» y «Cámaras cerradas y en rango».
  - Caducidades: «¿Alguna temperatura fuera de rango?».
- **Lecturas nuevas**:
  - Apertura: cámara de refrigeración (0 a 4 °C), cámara de congelación (−25 a −18 °C), vitrina de lácteos y vitrina de carnes (0 a 4 °C).
  - Cierre: «Cámaras cerradas» (sí/no) y las lecturas de refrigeración y congelación.
- **Control de temperaturas**: «Temperatura refrigerador lácteos» y «Temperatura vitrina carnes» reciben rango de 0 a 4 °C y su equipo.
- **`register_waste`** asignado a gerente, almacén, abarrotes, caducidades y admin.

---

# 🖥️ Frontend
- **Ejecución de checklist**:
  - Las lecturas con rango usan teclado numérico y muestran «Permitido: 0 a 4 °C».
  - Fuera de rango, el campo se pinta de rojo, se abre el comentario y se pide foto.
- **Plantillas**:
  - Las preguntas numéricas tienen campos de equipo, mínimo, máximo y unidad.
  - Las sí/no tienen la casilla «Crítica».
- **Mermas** (`/waste`, menú Inventario, permiso `register_waste`):
  - Producto por buscador o cámara, cantidad, motivo con íconos, nota y costo estimado.
  - Foto opcional para la última merma o para cualquier fila.
  - Lista del día con su total en pesos.
- **Caducidades**: «Retirar» solo cambia el estado; la merma la registra la base de datos.
- **Estadísticas**:
  - **Nueva pestaña Temperaturas**: una gráfica por equipo con el promedio diario y la banda del rango permitido (los puntos fuera de rango van en rojo), los indicadores de lecturas, fuera de rango, sin corregir y tiempo promedio hasta la corrección, y la lista de lecturas fuera de rango con su tarea y su tiempo de corrección. Esa lista sale de las tareas automáticas, así que conserva la lectura aunque después se haya corregido.
  - **Inventario**: merma en pesos por motivo (dona con paleta categórica de 6 colores validada), por departamento y top 10 productos, comparada con el periodo anterior.
- **Gráficas**:
  - `LineChart` acepta `band` y valores negativos.
  - `Donut` acepta `format`.
  - `Delta` acepta `format` (moneda).

---

# ✅ Verificación
- `pendiente.sql` regenerado (19 archivos) y ejecutado dos veces en PGlite sin errores.
- `verificar.sql` (38 comprobaciones) en verde; solo falta pg_cron, que no existe en PGlite.
- Pruebas en PGlite:
  - Lectura «9,5» en la vitrina de carnes → `out_of_range`, tarea *high* y avisos al supervisor de Caducidades y al gerente. Al corregir a 3, la tarea se cancela.
  - Completar con una lectura fuera de rango sin comentario ni foto → rechazado.
  - Merma sin motivo → rechazada. Merma «Dañado» → `unit_cost` 19.00. El cajero no puede registrar mermas (RLS).
  - Retirar un lote → una merma `expired` por 6 piezas.
- `npm run lint` y `npm run build` sin errores. Revisado a 360 px (Mermas y Temperaturas, con datos simulados porque tu base aún no tiene la 0014): sin errores de JS.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0014_temperaturas_y_mermas.sql`
2. `seed/0012_temperaturas_y_mermas.sql`
