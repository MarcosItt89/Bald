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

| Comando | Para qué |
|---|---|
| `npm run dev` | Servidor de desarrollo |
| `npm run lint` | ESLint |
| `npm run build` | Compilación de producción en `dist/` |
| `npm run preview` | Sirve `dist/` para revisarlo |

## Arquitectura multiempresa

Operalia es **una sola base y una sola app para varias empresas cliente** (tabla `companies`). Cada empresa tiene sus sucursales, empleados, roles y datos.

- **Cada fila sabe de qué empresa es.** Casi todas las tablas tienen `company_id`. Las que no lo tienen, como respuestas de checklist o renglones de pedido, cuelgan de una tabla que sí lo tiene.
- **El aislamiento lo hace la base, no el frontend.** Toda tabla tiene Row Level Security (RLS). Sus políticas comparan contra funciones que dicen quién llama:
  - `auth_company_id()`, `auth_employee_id()`, `auth_role_scope()`, `has_permission()`;
  - `can_access_branch()` y `can_access_department()`, que además cubren el alcance por zona, sucursal o departamento.

  Aunque alguien llame a la API directamente, solo ve y toca lo de su empresa y su alcance.
- **Las vistas `v_*`** tienen `security_invoker`: respetan el RLS de quien consulta.
- **Storage (bucket `evidence`):** la primera carpeta de cada archivo es el id de la empresa. Solo se lee y se sube en la propia carpeta, y solo se borra lo propio.
- **Funciones SECURITY DEFINER** (las que saltan RLS):
  - toda función que la API puede llamar valida empresa, usuario o superadmin;
  - las internas, como `generate_checklist_runs` o `seed_company_base`, están revocadas para la API;
  - `anon` (sin sesión) solo ejecuta `request_password_reset` (migración 0026).
- **Empresa suspendida** (`companies.status = 'suspended'`): las funciones `auth_*` devuelven null, así que sus empleados no ven nada. Los procesos de pg_cron se la saltan. No se borra ningún dato.
- **Superadmin de la plataforma** (`platform_admins`): no abre el RLS de otras empresas. Ve otras empresas solo por las funciones `platform_*`, que exigen `is_platform_admin()` y devuelven agregados (o tickets de soporte, para atenderlos).

La prueba [supabase/pruebas/aislamiento.sql](supabase/pruebas/aislamiento.sql) comprueba todo esto (ver más abajo).

## Inicio de sesión

Cada empresa tiene un **código** (por ejemplo `gatopelon`). En el login, el empleado escribe:

| Campo | Ejemplo | Nota |
|---|---|---|
| Empresa | `gatopelon` | Se recuerda en el dispositivo; se escribe una sola vez |
| Usuario | `cajero` | Único dentro de su empresa (otra empresa puede tener su propio `cajero`) |
| Contraseña | — | La primera es temporal y se cambia al entrar |

- **Correo de Auth:** internamente Supabase Auth usa el correo `usuario@<código>.operalia.local` (`cajero@gatopelon.operalia.local`). Ese correo no existe; nadie lo escribe.
- **Correo real:** si alguien tiene uno registrado (como el propietario), puede entrar con él sin escribir la empresa.
- **Altas de personal:** las cuentas las crea un administrador o gerente desde **Configuración → Empleados** («Contraseña inicial» o «Crear cuenta»), con `admin_set_password`. El registro público de Supabase debe estar **desactivado**: Authentication → Sign In / Providers → «Allow new users to sign up».
- **Contraseña olvidada:** «¿Olvidaste tu contraseña?» pide empresa y usuario y avisa a su gerente y al administrador de esa empresa. Responde igual exista o no el usuario.

## Cuentas: empleados, propietario y plataforma

| Cuenta | Qué es | Cómo se crea |
|---|---|---|
| **Empleado** | Ve lo que su rol y su alcance (empresa, zona, sucursal, departamento o solo lo suyo) permiten, dentro de su empresa | Configuración → Empleados |
| **Propietario** | Uno por empresa (`employees.is_owner`), rol Administrador. Es el único que entra a **Roles** y **Permisos** y edita los datos de la empresa. Un administrador que no es propietario no cambia permisos. | Al dar de alta la empresa (Plataforma → Nueva empresa) o en el SQL Editor |
| **Superadmin** | Equipo de Operalia (tabla `platform_admins`). Ve el grupo **Plataforma** del menú. Es empleado de una empresa, por ejemplo `gatopelon` en Gato Pelón, y fuera de Plataforma solo ve esa empresa. | Solo en el SQL Editor (abajo) |

**Plataforma** (solo superadmins):
- **Empresas:** estado, salud de la cuenta (verde, amarillo o rojo), avance de arranque, y suspender o reactivar.
- **Rendimiento:** indicadores por empresa y sucursal, ranking, tendencia diaria y mapa de calor de checklists. Usa las definiciones de Estadísticas y solo devuelve agregados.
- **Prospectos:** cadenas interesadas y su estado.
- **Nueva empresa.**
- **Soporte de tiendas:** tickets de todas las empresas. Las respuestas llegan firmadas «Soporte Operalia».

Para agregar o quitar un superadmin, en el SQL Editor; la persona necesita un empleado con cuenta:
```sql
insert into public.platform_admins (user_id)
select e.user_id from public.employees e join public.companies c on c.id = e.company_id
where c.code = 'gatopelon' and e.username = 'USUARIO' and e.user_id is not null
on conflict do nothing;
-- quitar: delete from public.platform_admins where user_id = '…';
```

## Cómo se da de alta una tienda

1. **Prospecto** (opcional): regístralo en **Plataforma → Prospectos** (cadena, contacto, sucursales y giro) y avanza su estado: nuevo → demo → negociación → ganado.
2. **Alta:**
   - **Desde un prospecto ganado:** «Dar de alta» abre **Nueva empresa** con nombre, código sugerido y propietario llenos.
   - **Sin prospecto:** entra directo a Plataforma → Nueva empresa.
3. **Llena el formulario:**
   - empresa: nombre, razón social, RFC, **código** y zona horaria;
   - primera sucursal;
   - propietario: nombre, usuario y contraseña temporal, que se sugiere sola.

   Al guardar, `provision_company` lo hace todo en una transacción:
   - crea la empresa y su sucursal;
   - corre `seed_company_base`;
   - crea al propietario con su cuenta, que pedirá cambiar la contraseña;
   - registra el alta en auditoría.
4. **Comparte los datos de acceso:** la tarjeta final trae la URL de la app, el código de empresa, el usuario y la contraseña temporal para copiar.
5. **Acompaña el arranque:** en Plataforma → Empresas, el **avance de arranque** marca 5 pasos:
   - sucursales creadas;
   - empleados con cuenta;
   - productos cargados;
   - primera plantilla usada;
   - primer recibo cerrado.

   La **salud de la cuenta** avisa si la tienda deja de usar la app.

El `code` de una empresa no se cambia desde la app; solo en el SQL Editor.

## Base de datos

Todo está en [supabase/](supabase/). Cada archivo es **re-ejecutable**: no duplica datos ni borra lo instalado.

| Carpeta / archivo | Contenido |
|---|---|
| `migrations/` | Esquema: tablas, funciones, triggers, vistas, RLS, Storage y pg_cron (0001 → 0026) |
| `seed/` | Datos **base** que la operación necesita (ver abajo) |
| `demo/` | Datos **de ejemplo**, solo para pruebas (ver abajo) |
| `pruebas/` | Pruebas que se corren a mano en el ambiente de pruebas (`aislamiento.sql`) |
| `instalacion-limpia.sql` | Migraciones + `seed/` (**producción**) |
| `pendiente.sql` | Migraciones + `seed/` + `demo/` (ambiente de pruebas) |
| `verificar.sql` | Solo lectura: dice qué está instalado y qué archivo correr si falta algo |

### Semillas base vs. demo

| | Base: `seed/` y `seed_company_base(empresa)` | Demo: `demo/` y `seed_company_demo(empresa)` |
|---|---|---|
| **Para qué** | Lo mínimo para que una empresa opere | Probar y enseñar la app con datos |
| **Contenido** | Catálogo de permisos. Gato Pelón con sus 3 sucursales y su propietario `chee`, sin cuenta. Por empresa: departamentos, zonas, roles con sus permisos, temas de soporte, plantillas de checklist y puntos QR | Usuarios con contraseña `prueba123` y una 4.ª sucursal de Gato Pelón. Productos, inventario, proveedores, tareas y tickets. Súper La Luna (`superluna`) y Mercado Sol (`mercadosol`), con 4 sucursales cada una. 30 días de historial en las 3 empresas, prospectos de ejemplo |
| **Producción** | Sí: va en `instalacion-limpia.sql` | **Nunca** |
| **Empresa nueva** | `provision_company` corre `seed_company_base` | Solo si se marca «Cargar datos de ejemplo» y `demo/` está instalado |

- **Datos base de una empresa:** van en `seed_company_base` (migración 0023), no en un archivo suelto de `seed/`.
- **Usuarios demo:** están listados al inicio de `demo/0009_usuarios_y_demo.sql` (Gato Pelón) y de `demo/0019_empresas_demo.sql` (Súper La Luna y Mercado Sol).
- **Si un ambiente con demo se vuelve real,** cambia esas contraseñas.

### Instalar

1. **Activa pg_cron:** en Supabase → Database → Extensions, activa `pg_cron`. Genera los checklists del día y manda los recordatorios.
2. **Ejecuta el instalador:** abre el SQL Editor, pega el instalador y ejecútalo:
   - `instalacion-limpia.sql` para producción;
   - `pendiente.sql` para pruebas.
3. **Comprueba la instalación:** ejecuta `verificar.sql`. Con la instalación limpia, las filas `demo/…` salen ❌ y es lo esperado.
4. **Producción:**
   - El propietario de Gato Pelón (`chee`) queda pre-registrado **sin cuenta**: créasela con `admin_set_password` (ver el diario 2026-10-27) y entra con empresa `gatopelon`. La cuenta con correo real de `seed/0010_propietario.sql` se liga sola al crearla en Supabase Auth.
   - Agrega al menos un superadmin (arriba) y da de alta al resto del personal desde la app.

Para actualizar una base que ya existe, basta con ejecutar las migraciones y semillas nuevas en orden (o el instalador completo, que es re-ejecutable). Cada cambio dice qué correr en su diario.

### Prueba de aislamiento

Solo en el **ambiente de pruebas**, porque necesita los datos demo (`pendiente.sql`). Abre el SQL Editor, pega **completo** [supabase/pruebas/aislamiento.sql](supabase/pruebas/aislamiento.sql) y ejecútalo. Tarda alrededor de un minuto. No deja cambios: todo corre dentro de un bloque que se deshace al final.

**Qué prueba:**
- **Personas:** se hace pasar por usuarios de Súper La Luna, con `request.jwt.claims` y `set local role authenticated`, igual que la API: un empleado de sucursal, uno de alcance `self` y el propietario. También prueba `anon`, sin sesión.
- **Tablas y vistas:** en cada tabla y vista de `public` y en `storage.objects` (evidence), intenta con datos de Gato Pelón leer, insertar, actualizar, borrar, y actualizar y borrar sin filtro.
- **RPC de plataforma:** nadie que no sea superadmin puede llamar `platform_*` ni `provision_company`.
- **Roles:** un administrador que no es propietario no cambia `role_permissions`, `employee_permissions` ni `roles`. El propietario sí, como control.
- **Empresa suspendida:** no lee nada ni corre el mantenimiento de otra empresa.
- **Contraseña olvidada:** `request_password_reset` responde igual exista o no el usuario y no avisa a otra empresa.
- **pg_cron:** los procesos se saltan las empresas suspendidas.
- **SECURITY DEFINER:** lista las funciones que la API puede llamar y si están revisadas.

**Cómo leer el resultado:** la primera fila es el resumen y lo que falla sale arriba.

| Marca | Significa |
|---|---|
| ✅ | Bloqueado por la seguridad, o permitido cuando es un control |
| ❌ | Falla: hay que corregirlo antes de publicar |
| ⚠️ | No concluyente: una regla del negocio, o una fila propia de la empresa que prueba, frenó la operación antes de llegar a la seguridad. Lee el mensaje. |
| — | Sin datos de Gato Pelón para probar |
| ℹ️ | Catálogo global (`permissions`), legible para todos |

Córrela después de cada migración que agregue tablas, políticas o funciones. Una función SECURITY DEFINER nueva sale ❌ «sin revisar» hasta que alguien confirme que valida empresa, usuario o superadmin y la agregue a la lista del paso 7 del script.

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

   **Aislamiento:**
   - **Tabla nueva:** lleva `company_id`, o cuelga de una tabla que lo tenga. Activa RLS con políticas que comparen contra `auth_company_id()`.
   - **Vista nueva:** `with (security_invoker = on)`.
   - **Función SECURITY DEFINER nueva:**
     - valida la empresa con `is distinct from public.auth_company_id()` (no con `<>`, que con null deja pasar), al usuario o al superadmin;
     - termina con `revoke all on function … from public, anon;` y `grant execute … to authenticated;` si la API la necesita;
     - se agrega a la lista revisada del paso 7 de `supabase/pruebas/aislamiento.sql`.
2. **Semillas:**
   - **Si la migración agrega un permiso:** la propia migración lo asigna a los roles de **todas** las empresas (`insert into role_permissions … from roles where code in (…)`) y además lo agregas a la matriz de `seed_company_base` (migración 0023), para que las empresas nuevas también lo reciban. El rol `admin` lo recibe solo (trigger de 0012);
   - datos base de la empresa (plantillas, catálogos): en `seed_company_base`, no en un archivo suelto de `seed/`;
   - datos de ejemplo en `demo/00NN_nombre.sql`.
3. **Frontend:**
   - el código en `src/config/permissions.js`;
   - la opción en `navigation.js` y la ruta en `src/app/router.jsx`;
   - el servicio en `src/services/` y la pantalla en `src/features/`.
4. **Instaladores y verificación:**
   - `node supabase/build-pendiente.mjs` regenera los dos instaladores;
   - agrega sus comprobaciones a `supabase/verificar.sql`.
5. **Revisión:**
   - `npm run lint` y `npm run build`;
   - en el ambiente de pruebas, `supabase/pruebas/aislamiento.sql` sin ❌.
6. **Diario:** escribe el cambio en [docs/diario-de-cambios/](docs/diario-de-cambios/).

Los `.sql` se guardan con saltos de línea LF (lo fuerza `.gitattributes`). Algunas migraciones parchean funciones existentes buscando texto exacto.
