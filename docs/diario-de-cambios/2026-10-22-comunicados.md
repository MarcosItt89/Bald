# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Comunicados con acuse de lectura**: avisos oficiales para toda la empresa, una zona, una sucursal o un departamento. Cada empleado confirma «Leído» y quien publica ve quién falta. Es la función 5 de 5 del último encargo.

---

# 🗄️ Base de datos

## Migración `0021_comunicados.sql`
- **`announcements`**: título, cuerpo, adjunto opcional, alcance, fecha de vigencia (`valid_until`), estado (vigente o archivado) y quién publicó.
  - Alcances: `company`, `zone`, `branch` o `department`. Un departamento sin sucursal es ese departamento en todas las sucursales.
  - Una restricción valida que cada alcance traiga solo su zona, sucursal o departamento.
- **`announcement_reads`**: una fila por empleado que confirmó, con la hora.
- **`announcement_matches(empleado, alcance…)`**: decide si un comunicado le llega a un empleado:
  - por su sucursal (y la zona de esa sucursal);
  - por las zonas que tiene asignadas;
  - por su departamento principal o sus departamentos adicionales.
- **Publicar** (`can_publish_announcement`) requiere `publish_announcements` y alcance suficiente:
  - **Empresa:** solo roles de alcance empresa.
  - **Zona:** las zonas propias.
  - **Sucursal o departamento:** las sucursales y departamentos a los que el usuario tiene acceso.
  - **Departamento en todas las sucursales:** solo alcance empresa.
- **Al publicar** (trigger `trg_announcement_notify`):
  - Cada empleado activo del alcance recibe una notificación «Comunicado: <título>» que abre `/announcements?id=…`.
  - Si quien publica está dentro del alcance, queda como leído.
- **`mark_announcement_read`**: confirma la lectura. Solo funciona si el comunicado es para ti, y también marca leída su notificación.
- **`announcement_progress(id)`**: lista a cada persona del alcance con su sucursal, departamento y hora de lectura. La pueden ver quien publicó y quien tiene `manage_announcements` con alcance de empresa.
- **`v_announcements`**: el comunicado con:
  - nombres de publicador, zona, sucursal y departamento;
  - `is_expired`, `my_read_at` e `is_for_me`;
  - totales `audience`/`read_count`, solo para quien puede ver el avance.
- **RLS**:
  - **Ver:** cada quien ve los comunicados vigentes de su alcance; el publicador ve los suyos; `manage_announcements` (empresa) ve todos.
  - **Editar o archivar:** el publicador, o `manage_announcements`.
  - **Alcance:** no se puede cambiar después de publicar (trigger `trg_announcement_guard`).
  - **Lecturas:** solo se escriben con la función.
- **Adjuntos**: bucket privado `announcements` (imagen o PDF, 10 MB), con ruta `{empresa}/{uuid}.{ext}`.
  - Lo lee cualquiera de la empresa con URL firmada.
  - Sube quien tiene `publish_announcements`; borra quien lo subió.
- **Permisos**: `publish_announcements` y `manage_announcements`.

## Semilla `seed/0018_comunicados.sql`
- **`publish_announcements`**: admin, gerente, supervisor y jefe de escáner.
- **`manage_announcements`**: admin.
- **Ejemplos**:
  - «Nuevo canal de comunicados»: toda la empresa, vigente 30 días.
  - «Inventario general el domingo»: Sucursal Centro, vigente 7 días.

---

# 🖥️ Frontend
- **Comunicados** (`/announcements`), en el menú para todos, debajo de Dashboard:
  - **Para mí**: los comunicados vigentes, con los que faltan de confirmar primero (borde ámbar). Cada uno muestra publicador, fecha, alcance, vigencia, cuerpo y adjunto (se abre con URL firmada). Botón **Marcar como leído**.
  - **Anteriores**: los vencidos.
  - **Publicados por mí** (o **Todos los publicados** con `manage_announcements`):
    - barra de avance «9/15 leído · faltan 6»;
    - **Quién falta**: por sucursal, con barra y la lista de personas pendientes (y opcionalmente las que ya leyeron, con su hora);
    - **Archivar**.
  - **Publicar**: título, mensaje, alcance (solo los que el rol permite), zona, sucursal o departamento, «vigente hasta» (por defecto 7 días) y adjunto.
- Al abrir la notificación, la página se va a la pestaña del comunicado y lo resalta.
- **Dashboard**: aviso «Tienes N comunicados por confirmar» con el título, que lleva a Comunicados.

---

# ✅ Verificación
- `pendiente.sql` regenerado (32 archivos) y ejecutado dos veces en PGlite sin errores.
- `verificar.sql`: 75 comprobaciones; todas en verde salvo los jobs de pg_cron, que PGlite no tiene.
- Pruebas en PGlite:

| Caso | Resultado |
|---|---|
| Semilla: comunicado a Centro / a la empresa | 14 y 16 avisos; el publicador queda leído ✅ |
| Cajero (Centro) | Ve ambos; sin totales (no es publicador) ✅ |
| Gerente Norte | Solo ve el de empresa ✅ |
| Cajero confirma | Leído y su notificación marcada ✅ |
| Gerente Norte confirma uno de Centro | «Este comunicado no es para ti» ✅ |
| Cajero pide el avance | Rechazado ✅ |
| Gerente Centro ve avance | 15 personas, 2 leídos ✅ |
| Admin ve avance de empresa | Centro 15 (1 leído), Norte 2 ✅ |
| Gerente publica a la empresa o a Norte / cajero publica | Rechazado por RLS ✅ |
| Gerente publica a Cajas de Centro | 2 avisos; cajero lo ve, abarrotes no ✅ |
| Jefe de escáner publica a zona Norte / a zona Sur | Publicado (2 avisos) / rechazado ✅ |
| Cambiar el alcance después de publicar | Rechazado ✅ |
| Archivar | El cajero ya no lo ve ✅ |
| Insertar una lectura directo en la tabla | Rechazado ✅ |

- `npm run lint` y `npm run build` sin errores.
- Revisado a 360 px como cajero (Para mí y el aviso del Dashboard) y como gerente (Publicados, Quién falta y Publicar), con datos simulados porque tu base aún no tiene la 0021. Sin desbordes ni errores de JS.
- Se corrigió que el formulario no mostrara la sucursal a los roles de una sola sucursal.

# 📌 Para aplicar
En el SQL Editor, en este orden:
1. `migrations/0021_comunicados.sql`
2. `seed/0018_comunicados.sql`
