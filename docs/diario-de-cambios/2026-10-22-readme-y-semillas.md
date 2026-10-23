# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**README formal y separación de los datos demo** para poder instalar Operalia en producción sin usuarios ni datos de prueba.

---

# 🗄️ Base de datos
- **Semillas separadas en dos carpetas:**
  - `supabase/seed/`: lo que la operación necesita (empresa, sucursales, departamentos, roles, permisos por rol, zonas, plantillas de checklist, puntos QR y la cuenta del propietario).
  - `supabase/demo/`: usuarios con contraseña `prueba123`, productos, inventario, notificaciones de prueba, planes de conteo, historial de huecos y comunicados de ejemplo.
- **Archivos movidos o divididos:**
  - `seed/0009_usuarios_y_demo.sql` → `demo/`.
  - `seed/0010_notificaciones_y_marcos.sql` → `seed/0010_propietario.sql` (cuenta del dueño) + `demo/0010_notificaciones_prueba.sql`.
  - `seed/0013`, `0016`, `0017` y `0018` se quedan solo con lo base; lo de ejemplo pasa a `demo/0013_usuarios_zona`, `0016_planes_conteo`, `0017_huecos_historial` y `0018_comunicados_ejemplo`.
- **`build-pendiente.mjs`** genera dos instaladores:
  - `pendiente.sql`: todo, con demo. Ejecuta los archivos en el mismo orden que antes.
  - **`instalacion-limpia.sql`**: migraciones + `seed/`, para producción.
- **Propietario:** si aún no hay propietario, `seed/0010_propietario.sql` lo define. Es gatopelon cuando está la demo; si no, la cuenta del dueño. Antes, en una instalación nueva no quedaba propietario hasta la segunda pasada.
- **Saltos de línea:**
  - `.gitattributes` fuerza LF en los `.sql`. Al cambiar de rama, Git los había convertido a CRLF y los parches de funciones (0015, 0017 y 0019) ya no encontraban su texto.
  - Esas tres migraciones ahora quitan los CR antes de buscar, por si alguien instala desde un archivo con CRLF.
- **`verificar.sql`:**
  - Las comprobaciones de datos demo se rotulan `demo/…`; en una instalación limpia salen ❌ y es lo esperado.
  - «gatopelon es propietario» pasa a «la empresa tiene propietario».

# 📄 Documentación
- **`README.md`** reescrito; antes era la plantilla de Vite. Explica:
  - qué es Operalia y su tecnología;
  - variables de entorno y comandos;
  - cómo instalar la base (limpia o con demo) y verificarla;
  - la estructura del código;
  - los pasos para agregar una función.

# ✅ Verificación
- `pendiente.sql` ejecutado dos veces en PGlite: sin errores. `verificar.sql` (75 filas) en verde salvo pg_cron, igual que antes.
- **`instalacion-limpia.sql` ejecutado dos veces en PGlite, sin errores.** Resultado:
  - Datos base: 1 empleado (el dueño, propietario), 14 roles, 39 permisos, 212 permisos por rol, 3 sucursales y 12 plantillas.
  - Sin datos demo: 0 productos, 0 cuentas demo, 0 comunicados y 0 avisos.
  - En `verificar.sql` solo faltan las filas `demo/…` y pg_cron.
- `npm run lint` y `npm run build` sin errores.
