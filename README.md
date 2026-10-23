# Operalia

Plataforma operativa para empresas con varias sucursales. Reúne en una sola app web (instalable en el celular como PWA):
- inventario y movimientos;
- recibo de mercancía y proveedores;
- precios, cenefas y caducidades;
- checklists con evidencia fotográfica;
- tareas, pedidos internos y comunicados;
- estadísticas.

Cada persona ve solo lo que su rol y su sucursal permiten.

**Creadores:** Ramírez Guerra Marcos Yerán y Arámbula García Sarahy. La justificación y los objetivos están en [docs/producto/objetivos.md](docs/producto/objetivos.md).

## Tecnología

| Capa | Herramientas |
|---|---|
| Frontend | React 19, Vite, React Router, lucide-react, PWA (`vite-plugin-pwa`) |
| Backend | Supabase: PostgreSQL, Auth, Storage, Row Level Security, pg_cron |
| Escáner | `BarcodeDetector` nativo o ZXing; QR con `uqr` |
| Despliegue | Vercel (`vercel.json` redirige todas las rutas a `index.html`) |

La lógica sensible vive en la base de datos y el frontend solo la consume:
- permisos;
- alcance por empresa, zona, sucursal o departamento;
- folios;
- movimientos de inventario;
- tareas automáticas.

## Puesta en marcha (desarrollo)

Requisitos: Node 20 o superior y un proyecto de Supabase.

```bash
npm install
cp .env.example .env    # y llena las variables
npm run dev             # http://localhost:5173
```

Variables de `.env`, que también se configuran en Vercel → Settings → Environment Variables:

| Variable | Qué es |
|---|---|
| `VITE_SUPABASE_URL` | URL del proyecto (Supabase → Project Settings → API) |
| `VITE_SUPABASE_ANON_KEY` | Llave pública (*publishable/anon*). **Nunca** la `service_role`. |
| `VITE_AUTH_EMAIL_DOMAIN` | Dominio interno para convertir usuario en correo. Se inicia sesión con **usuario**, no con correo (`cajero` → `cajero@operalia.local`). |

| Comando | Para qué |
|---|---|
| `npm run dev` | Servidor de desarrollo |
| `npm run lint` | ESLint |
| `npm run build` | Compilación de producción en `dist/` |
| `npm run preview` | Sirve `dist/` para revisarlo |

## Base de datos

Todo está en [supabase/](supabase/). Cada archivo es **re-ejecutable**: no duplica datos ni borra lo instalado.

| Carpeta / archivo | Contenido |
|---|---|
| `migrations/` | Esquema: tablas, funciones, triggers, vistas, RLS, Storage y pg_cron (0001 → 0021) |
| `seed/` | Lo que la operación necesita: empresa, sucursales, departamentos, roles, permisos por rol, zonas, plantillas de checklist, puntos QR y la cuenta del propietario |
| `demo/` | **Solo para pruebas**: usuarios con contraseña `prueba123`, productos, inventario, proveedores, checklists, tareas y ejemplos |
| `instalacion-limpia.sql` | Migraciones + `seed/` (**producción**) |
| `pendiente.sql` | Migraciones + `seed/` + `demo/` (ambiente de pruebas) |
| `verificar.sql` | Solo lectura: dice qué está instalado y qué archivo correr si falta algo |

### Instalar

1. **Activa pg_cron:** en Supabase → Database → Extensions, activa `pg_cron`. Genera los checklists del día y manda los recordatorios.
2. **Ejecuta el instalador:** abre el SQL Editor, pega el instalador y ejecútalo:
   - `instalacion-limpia.sql` para producción;
   - `pendiente.sql` para pruebas.
3. **Comprueba la instalación:** ejecuta `verificar.sql`. Con la instalación limpia, las filas `demo/…` salen ❌ y es lo esperado.
4. **Producción:**
   - Crea en Supabase Auth la cuenta del propietario, con el correo que aparece en `seed/0010_propietario.sql`. Se liga sola al empleado pre-registrado.
   - Desde la app, da de alta al resto del personal.

Para actualizar una base que ya existe, basta con ejecutar las migraciones y semillas nuevas en orden (o el instalador completo, que es re-ejecutable). Cada cambio dice qué correr en su diario.

> Los usuarios demo están listados al inicio de `demo/0009_usuarios_y_demo.sql`. No instales `demo/` en producción. Si un ambiente con demo se vuelve real, cambia esas contraseñas.

## Estructura del frontend

```
src/
  app/         router (rutas protegidas por permiso) y guards
  config/      permissions.js (códigos de permiso) y navigation.js (menú)
  contexts/    AuthProvider: sesión, perfil, permisos, alcance y sucursal activa
  services/    un archivo por módulo; único lugar que habla con Supabase
  features/    una carpeta por pantalla o módulo
  components/  ui/ (botones, tablas, modales), charts/, domain/, layout/
  hooks/ lib/ utils/ constants/ styles/
```

El menú y el router usan el mismo permiso por opción (`navigation.js`), así que no se puede entrar a una pantalla escribiendo la URL.

## Cómo agregar una función

1. **Migración:** crea `supabase/migrations/00NN_nombre.sql`, re-ejecutable:
   - `if not exists`;
   - `drop policy if exists`;
   - restricciones dentro de `do $$ … exception when duplicate_object`.

   Incluye RLS y los permisos nuevos en `public.permissions`.
2. **Semillas:**
   - permisos por rol en `seed/00NN_nombre.sql`;
   - datos de ejemplo en `demo/00NN_nombre.sql`.
3. **Frontend:**
   - el código en `src/config/permissions.js`;
   - la opción en `navigation.js` y la ruta en `src/app/router.jsx`;
   - el servicio en `src/services/` y la pantalla en `src/features/`.
4. **Instaladores y verificación:**
   - `node supabase/build-pendiente.mjs` regenera los dos instaladores;
   - agrega sus comprobaciones a `supabase/verificar.sql`.
5. **Revisión:** `npm run lint` y `npm run build`.
6. **Diario:** escribe el cambio en [docs/diario-de-cambios/](docs/diario-de-cambios/).

Los `.sql` se guardan con saltos de línea LF (lo fuerza `.gitattributes`). Algunas migraciones parchean funciones existentes buscando texto exacto.
