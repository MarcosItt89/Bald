# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Huecos en anaquel**: el empleado escanea un producto que no está en piso y el sistema decide qué hacer según la existencia. Es la función 4 de 5 del último encargo.

---

# 🗄️ Base de datos

## Migración `0020_huecos_anaquel.sql`
- **`shelf_gaps`**: sucursal, producto, departamento del producto, existencia al reportar, `has_stock` («hay en bodega, no en piso»), estado (abierto, surtido o descartado), tarea y pedido ligados, nota y número de reportes.
  - Un producto no abre dos huecos en la misma sucursal. Si ya hay uno abierto, el nuevo reporte se suma (`report_count`).
- **`report_shelf_gap(sucursal, producto, nota)`** cruza con `inventory.stock`:
  - **Hay existencia** → crea la tarea a **Almacén** «Surtir a piso: <producto>», con prioridad alta, vencimiento hoy, la existencia y la ubicación. También avisa al departamento de Almacén. Es una sola tarea por hueco (`tasks.source_type = 'shelf_gap'`).
  - **Sin existencia** → no crea tarea. Responde con la cantidad sugerida para el pedido: lo que falta para el máximo, o el mínimo.
- **`create_order_from_shelf_gap(hueco, cantidad)`**: crea un pedido interno con prioridad alta («Faltante en anaquel: <producto>»), para el departamento del producto. Requiere `create_orders` y no permite dos pedidos en curso para el mismo hueco.
- **`close_shelf_gap(hueco, 'resolved' | 'dismissed')`**: con `manage_shelf_gaps`. Al cerrar el hueco, también se cierra su tarea pendiente.
- **Cierre automático**:
  - Si la tarea se completa, el hueco queda surtido; si se cancela, queda descartado.
  - Si el pedido se recibe o se cierra, el hueco queda surtido.
- **Permisos**: `report_shelf_gaps` (reportar) y `manage_shelf_gaps` (ver los de toda la sucursal y cerrarlos).
- **RLS**:
  - Cada quien ve los huecos que reportó.
  - Con `manage_shelf_gaps` se ven los de la sucursal; con `view_reports`, los de su alcance.
  - Solo se escribe con las funciones.
- **`tasks_update`**: quien tiene `manage_shelf_gaps` puede cerrar las tareas «Surtir a piso» de su departamento aunque no tengan responsable. `trg_task_rules` solo le deja cambiar el estado.
- **`v_shelf_gaps`**: el hueco con producto, departamento, ubicación, quién lo reportó y el estado de la tarea y del pedido.

## Semilla `seed/0017_huecos_anaquel.sql`
- **`report_shelf_gaps`**: admin, gerente, supervisor, jefe de cajas, cajas, abarrotes, almacén, caducidades y escáner.
- **`manage_shelf_gaps`**: admin, gerente, supervisor y almacén.
- **Historial**: 6 huecos ya resueltos en Sucursal Centro, en los últimos días, para que Estadísticas tenga datos.

---

# 🖥️ Frontend
- **Inventario → Huecos en anaquel** (`/inventory/shelf-gaps`):
  - **Reportar hueco**: botón «Escanear producto» (cámara) o buscador por nombre, SKU o código, con nota opcional. El aviso dice qué pasó:
    - «Hay 45 pz en sistema. Se creó la tarea «Surtir a piso» para Almacén».
    - «Sin existencia en sistema. Sugerencia: crea un pedido», con el botón **Crear pedido** y la cantidad sugerida.
  - **Abiertos / Cerrados**: cada hueco muestra:
    - «Hay en bodega» o «Sin existencia»;
    - el estado de la tarea y el folio del pedido;
    - cuántas veces se reportó, quién lo reportó y cuándo.
  - **Acciones**: «Pedir» (sin existencia), y «Surtido» o «Descartar» para quien gestiona huecos.
- **Tareas**: en «Mis tareas», Almacén ve y puede completar las tareas «Surtir a piso» sin responsable.
- **Estadísticas → Inventario**:
  - Indicador **Hay en bodega, no en piso**, que muestra cuántos de los huecos del periodo tenían existencia en sistema.
  - Bloque **Faltantes en anaquel por departamento** («2 había en bodega · 1 sin existencia»), con CSV.

---

# ✅ Verificación
- `pendiente.sql` regenerado (30 archivos) y ejecutado dos veces en PGlite sin errores.
- `verificar.sql`: 69 comprobaciones; todas en verde salvo los jobs de pg_cron, que PGlite no tiene.
- Pruebas en PGlite:

| Caso | Resultado |
|---|---|
| Cajero reporta Arroz (45 pz en sistema) | Tarea «Surtir a piso: Arroz 1 kg» a ALM, prioridad alta + aviso a Almacén ✅ |
| Abarrotes reporta el mismo producto | Se suma el reporte (×2), sin segunda tarea ✅ |
| Reporta producto sin existencia | Sin tarea, sugiere 40 ✅ |
| Cajero (sin `create_orders`) crea pedido | Rechazado ✅ |
| Abarrotes crea pedido | «Faltante en anaquel: …», solicitado, alta, 12 ✅ |
| Segundo pedido para el mismo hueco | Rechazado ✅ |
| Recibo (sin permiso) reporta | Rechazado ✅ |
| Escribir directo en `shelf_gaps` | 0 filas (solo con funciones) ✅ |
| Almacén completa la tarea | Hueco surtido ✅ |
| Pedido aprobado → enviado → recibido | Hueco surtido ✅ |
| Nuevo reporte tras cerrar | Hueco y tarea nuevos ✅ |
| Cajero descarta / gerente descarta | Rechazado / descartado y tarea cancelada ✅ |

- `npm run lint` y `npm run build` sin errores.
- Revisado a 360 px como abarrotes (sin existencia → Crear pedido) y como almacén (hay existencia → tarea; Surtido / Descartar), con datos simulados porque tu base aún no tiene la 0020. Sin desbordes ni errores de JS. También se revisó el bloque de Estadísticas.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0020_huecos_anaquel.sql`
2. `seed/0017_huecos_anaquel.sql`
