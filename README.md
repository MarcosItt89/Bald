# Operalia

Plataforma operativa para empresas con varias sucursales. Reúne en una sola app web (instalable en el celular como PWA):
- inventario y movimientos;
- recibo de mercancía y proveedores;
- precios, cenefas y caducidades;
- checklists con evidencia fotográfica;
- tareas, pedidos internos y comunicados;
- estadísticas.

Cada persona ve solo lo que su rol y su sucursal permiten.

Son **dos apps** en este repo, sobre la misma base de Supabase:

| App | Carpeta | Para quién |
|---|---|---|
| **Operalia** (tiendas) | `apps/tiendas` | Los empleados de cada empresa cliente (PWA) |
| **Consola Operalia** | `apps/consola` | El equipo de Operalia (superadmins): empresas, rendimiento, marca, prospectos, altas y soporte |

**Creadores:** Ramírez Guerra Marcos Yerán y Arámbula García Sarahy. La justificación y los objetivos están en [docs/producto/objetivos.md](docs/producto/objetivos.md).

## Tecnología

| Capa | Herramientas |
|---|---|
| Frontend | React 19, Vite, React Router, lucide-react, PWA (`vite-plugin-pwa`) |
| Backend | Supabase: PostgreSQL, Auth, Storage, Row Level Security, pg_cron |
| Escáner | `BarcodeDetector` nativo o ZXing; QR con `uqr` |
| Repositorio | npm workspaces: `apps/tiendas`, `apps/consola` y `packages/compartido` |
| Despliegue | Vercel, un proyecto por app (`vercel.json` de cada app redirige todas las rutas a `index.html`) |

La lógica sensible vive en la base de datos y el frontend solo la consume:
- permisos;
- alcance por empresa, zona, sucursal o departamento;
- folios;
- movimientos de inventario;
- tareas automáticas.

## Puesta en marcha (desarrollo)

Requisitos: Node 20 o superior y un proyecto de Supabase.

```bash
npm install             # en la raíz: instala las dos apps y el paquete compartido
cp .env.example .env    # y llena las variables (las dos apps leen este .env)
npm run dev             # tiendas: http://localhost:5173
npm run dev:consola     # Consola: http://localhost:5174
```

Variables de `.env`, que también se configuran en Vercel → Settings → Environment Variables:

| Variable | App | Qué es |
|---|---|---|
| `VITE_SUPABASE_URL` | Las dos | URL del proyecto (Supabase → Project Settings → API) |
| `VITE_SUPABASE_ANON_KEY` | Las dos | Llave pública (*publishable/anon*). **Nunca** la `service_role`. |
| `VITE_TIENDAS_URL` | Consola | Dominio de la app de tiendas (`https://…`), para armar el link `/e/<código>` y su QR. Sin ella la Consola avisa que el link no sirve |
| `VITE_CONSOLA_URL` | Tiendas | Dominio de la Consola (`https://…`). Lo usan el aviso de `/plataforma` y el link «Consola Operalia» del menú del superadmin. Sin ella el aviso no trae link |

| Comando (en la raíz) | Para qué |
|---|---|
| `npm run dev` / `npm run dev:consola` | Servidor de desarrollo de tiendas / Consola |
| `npm run lint` | ESLint de todo el repo |
| `npm run build` | Compila las dos apps (`apps/tiendas/dist` y `apps/consola/dist`) |
| `npm run build:tiendas` / `npm run build:consola` | Compila solo una |

### Repositorio

```
apps/
  tiendas/       la app de los empleados (PWA)
  consola/       Consola Operalia: login con correo, solo superadmins
packages/
  compartido/    lo que usan las dos: componentes ui y gráficas, cliente y
                 servicios de Supabase (lib/), config/env, tema y marca
                 (theme/, branding/), hooks, utils y estilos
supabase/        una sola vez, en la raíz: migraciones, semillas y pruebas
```

- **Importar del paquete compartido:** `import Button from '@operalia/compartido/components/ui/Button.jsx'`, con la extensión.
- **Qué va en `compartido`:** algo que usen las dos apps. Lo que solo usa una app se queda en esa app.
- **Páginas de plataforma:** viven solo en `apps/consola/src/pages`. La app de tiendas ya no las tiene. En `/plataforma/*` muestra el aviso «La plataforma se movió a la Consola», con el link a la misma página en la Consola (`/plataforma/soporte/123` → `<consola>/soporte/123`).

### Despliegue en Vercel (dos proyectos)

Las dos apps salen del **mismo repositorio** de GitHub; en Vercel son dos proyectos:

| | Proyecto tiendas | Proyecto Consola |
|---|---|---|
| Import | Este repo | Este mismo repo, otra vez («Add New → Project») |
| **Root Directory** | `apps/tiendas` | `apps/consola` |
| Framework preset | Vite | Vite |
| Build / Output | Los de Vite (`vite build`, `dist`) | Igual |
| Variables | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, más `VITE_CONSOLA_URL` | Las mismas dos, con los mismos valores, más `VITE_TIENDAS_URL` |

1. **Proyecto existente (tiendas):** en Settings → Build and Deployment, cambia **Root Directory** a `apps/tiendas` **antes** de hacer merge de este cambio. Si no, el siguiente deploy de `main` no encuentra `index.html` en la raíz y falla.
2. **Proyecto nuevo (Consola):**
   - **Root Directory:** `apps/consola`.
   - **Variables:** copia `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` del proyecto de tiendas y agrega `VITE_TIENDAS_URL` con el dominio de tiendas.
3. **Instalación:**
   - **Normal:** Vercel detecta los npm workspaces por el `package-lock.json` de la raíz e instala desde ahí. Deja activada la opción «Include files outside of the Root Directory», que viene así por defecto, porque las apps usan `packages/compartido`.
   - **Si el build no encuentra `@operalia/compartido`:** pon como Install Command `cd ../.. && npm install`.
4. **Supabase:** en Authentication → URL Configuration, agrega el dominio de la Consola a «Redirect URLs», junto al de tiendas.

## Arquitectura multiempresa

Operalia es **una sola base y una sola app para varias empresas cliente** (tabla `companies`). Cada empresa tiene sus sucursales, empleados, roles y datos.

- **Cada fila sabe de qué empresa es.** Casi todas las tablas tienen `company_id`. Las que no lo tienen, como respuestas de checklist o renglones de pedido, cuelgan de una tabla que sí lo tiene.
- **El aislamiento lo hace la base, no el frontend.** Toda tabla tiene Row Level Security (RLS). Sus políticas comparan contra funciones que dicen quién llama:
  - `auth_company_id()`, `auth_employee_id()`, `auth_role_scope()`, `has_permission()`;
  - `can_access_branch()` y `can_access_department()`, que además cubren el alcance por zona, sucursal o departamento.

  Aunque alguien llame a la API directamente, solo ve y toca lo de su empresa y su alcance.
- **Las vistas `v_*`** tienen `security_invoker`: respetan el RLS de quien consulta.
- **Storage (bucket `evidence`):** la primera carpeta de cada archivo es el id de la empresa. Solo se lee y se sube en la propia carpeta, y solo se borra lo propio.
- **Storage (bucket `company-branding`, logos):** es público para leer, porque el logo sale en el login. Solo el propietario de esa empresa o un superadmin sube y borra en `{company_id}/`.
- **Funciones SECURITY DEFINER** (las que saltan RLS):
  - toda función que la API puede llamar valida empresa, usuario o superadmin;
  - las internas, como `generate_checklist_runs` o `seed_company_base`, están revocadas para la API;
  - `anon` (sin sesión) solo ejecuta las dos funciones del login: `request_password_reset` (0026) y `get_company_branding` (0028). Esta última solo devuelve nombre, nombre visible, logo y color de una empresa activa.
- **Empresa suspendida** (`companies.status = 'suspended'`): las funciones `auth_*` devuelven null, así que sus empleados no ven nada. Los procesos de pg_cron se la saltan. No se borra ningún dato.
- **Superadmin de la plataforma** (`platform_admins`): no abre el RLS de otras empresas. Ve otras empresas solo por las funciones `platform_*`, que exigen `is_platform_admin()` y devuelven agregados (o tickets de soporte, para atenderlos).

La prueba [supabase/pruebas/aislamiento.sql](supabase/pruebas/aislamiento.sql) comprueba todo esto (ver más abajo).

## Inicio de sesión

Cada empresa tiene un **código** (por ejemplo `gatopelon`). En el login, el empleado escribe:

| Campo | Ejemplo | Nota |
|---|---|---|
| Empresa | `gatopelon` | Se recuerda en el dispositivo. Con el **link de la empresa** no se escribe nunca |
| Usuario | `cajero` | Único dentro de su empresa (otra empresa puede tener su propio `cajero`) |
| Contraseña | — | La primera es temporal y se cambia al entrar |

- **Link de la empresa:** `https://<dominio>/e/<código>` (por ejemplo `/e/gatopelon`). Al abrirlo, o al escanear su QR, el dispositivo recuerda la empresa y aplica su marca. Después, el login solo pide usuario y contraseña y muestra el logo y el nombre de la empresa, con «¿No es tu empresa? Cambiar». Un código que no existe, o de una empresa suspendida, solo dice «Empresa no encontrada». El superadmin copia el link e imprime el QR en la **Consola → Empresas** (botón QR de cada fila) o en **Consola → Marca**.
- **App instalada (PWA):** el manifest usa `start_url: "."`. La app instalada abre en la raíz del sitio y usa la empresa que el link dejó recordada.
- **Correo de Auth:** internamente Supabase Auth usa el correo `usuario@<código>.operalia.local` (`cajero@gatopelon.operalia.local`). Ese correo no existe; nadie lo escribe.
- **Correo real:** si alguien tiene uno registrado (como el propietario), puede entrar con él sin escribir la empresa.
- **Altas de personal:** las cuentas las crea un administrador o gerente desde **Configuración → Empleados** («Contraseña inicial» o «Crear cuenta»), con `admin_set_password`. El registro público de Supabase debe estar **desactivado**: Authentication → Sign In / Providers → «Allow new users to sign up».
- **Contraseña olvidada:** «¿Olvidaste tu contraseña?» pide usuario (y empresa, si el dispositivo no la recuerda) y avisa a su gerente y al administrador de esa empresa. Responde igual exista o no el usuario.

## Marca de cada empresa

Cada empresa puede tener su **nombre visible**, su **color** y su **logo** (migración 0028). Los editan:
- **el propietario**, en Configuración → Mi empresa;
- **un superadmin**, en la **Consola → Marca**, para cualquier empresa. La Consola lee la marca con `platform_get_company_branding` (0029), incluso de empresas suspendidas.

El editor es el mismo componente en las dos apps: `packages/compartido/src/branding/BrandEditor.jsx`.

| Dónde se ve | Cómo |
|---|---|
| Inicio de sesión | Al escribir el código de empresa, la pantalla toma su logo, su nombre y su color (`get_company_branding`) |
| Toda la app de tiendas | Botones, menú activo, enlaces e insignias usan su color: `theme/brand.js` (paquete compartido) escribe `--primary`, `--primary-dark`, `--primary-light` y `--primary-deep` en `:root` |
| Menú lateral | Su logo y su nombre visible. El superadmin ve el de Operalia |

- **Contraste:** si el color elegido no tiene contraste AA (4.5:1) con texto blanco, se oscurece solo hasta tenerlo; la página lo avisa.
- **Sin parpadeo:** la última marca se guarda en el dispositivo y se aplica antes del primer render.
- **Logo:** PNG, SVG o WebP de hasta 500 KB, en el bucket público `company-branding`, carpeta `{company_id}/`.

## Cuentas: empleados, propietario y plataforma

| Cuenta | Qué es | Cómo se crea |
|---|---|---|
| **Empleado** | Ve lo que su rol y su alcance (empresa, zona, sucursal, departamento o solo lo suyo) permiten, dentro de su empresa | Configuración → Empleados |
| **Propietario** | Uno por empresa (`employees.is_owner`), rol Administrador. Es el único que entra a **Roles** y **Permisos** y edita los datos de la empresa. Un administrador que no es propietario no cambia permisos. | Al dar de alta la empresa (Consola → Nueva empresa) o en el SQL Editor |
| **Superadmin** | Equipo de Operalia (tabla `platform_admins`). Trabaja en la **Consola Operalia**. En la app de tiendas es un empleado más de su empresa, por ejemplo `gatopelon` en Gato Pelón, y solo ve esa empresa; su menú trae además el link a la Consola. | Solo en el SQL Editor (abajo) |

**Consola Operalia** (`apps/consola`, solo superadmins):
- **Entrada:** su propio login con correo y contraseña. Después pide `get_my_profile()`: si la cuenta no es superadmin (`is_platform_admin`), ve «Sin acceso» y nada más.
- **Seguridad:** la de verdad está en la base. Cada función `platform_*` valida superadmin por su cuenta.
- **Correo:** el superadmin necesita un correo registrado en su cuenta de Auth. Si solo tiene el interno, entra con él: `usuario@<código>.operalia.local`.
- **Páginas:** Empresas, Rendimiento, Marca, Prospectos, Nueva empresa y Soporte de tiendas.

**Páginas de la Consola:**
- **Empresas:** estado, salud de la cuenta (verde, amarillo o rojo), avance de arranque, y suspender o reactivar. Desde cada fila: link de acceso con QR y Marca.
- **Marca** (Consola): nombre visible, color y logo de cualquier empresa, con su link y QR.
- **Rendimiento:** indicadores por empresa y sucursal, ranking, tendencia diaria y mapa de calor de checklists. Usa las definiciones de Estadísticas y solo devuelve agregados.
- **Prospectos:** cadenas interesadas y su estado.
- **Nueva empresa.**
- **Soporte de tiendas:** tickets de todas las empresas. Las respuestas llegan firmadas «Soporte Operalia».

**Rendimiento en cascada:** el mismo tablero de métricas en cada nivel, cada quien con lo que le toca. Las métricas son las mismas en todos los niveles (migración 0027).

| Quién | Dónde | Qué ve |
|---|---|---|
| Superadmin (Operalia) | Consola → Rendimiento | Todas las empresas; con un clic en una empresa, sus sucursales |
| Propietario y administradores de una tienda | Análisis → Rendimiento de sucursales | Todas las sucursales de su empresa |
| Jefe de zona | Igual | Las sucursales de sus zonas |
| Gerente | Igual | Su sucursal |

Para el detalle de una sucursal (por departamento, checklist o producto) está **Estadísticas**.

**Superadmin en la app de tiendas:** ve el menú de su empresa como cualquier empleado. Abajo trae «Plataforma → Consola Operalia», que abre la Consola en otra pestaña. La plataforma ya no está en la app de tiendas.

Para agregar o quitar un superadmin, en el SQL Editor; la persona necesita un empleado con cuenta:
```sql
insert into public.platform_admins (user_id)
select e.user_id from public.employees e join public.companies c on c.id = e.company_id
where c.code = 'gatopelon' and e.username = 'USUARIO' and e.user_id is not null
on conflict do nothing;
-- quitar: delete from public.platform_admins where user_id = '…';
```

## Cómo se da de alta una tienda

1. **Prospecto** (opcional): regístralo en **Consola → Prospectos** (cadena, contacto, sucursales y giro) y avanza su estado: nuevo → demo → negociación → ganado.
2. **Alta:**
   - **Desde un prospecto ganado:** «Dar de alta» abre **Nueva empresa** con nombre, código sugerido y propietario llenos.
   - **Sin prospecto:** entra directo a Consola → Nueva empresa.
3. **Llena el formulario:**
   - empresa: nombre, razón social, RFC, **código** y zona horaria;
   - primera sucursal;
   - propietario: nombre, usuario y contraseña temporal, que se sugiere sola.

   Al guardar, `provision_company` lo hace todo en una transacción:
   - crea la empresa y su sucursal;
   - corre `seed_company_base`;
   - crea al propietario con su cuenta, que pedirá cambiar la contraseña;
   - registra el alta en auditoría.
4. **Comparte los datos de acceso:** la tarjeta final trae la URL de la app, el código de empresa, el usuario y la contraseña temporal para copiar. Para los empleados, en **Consola → Empresas** está el link `/e/<código>` y su QR para imprimir y pegar en la tienda.
5. **Acompaña el arranque:** en Consola → Empresas, el **avance de arranque** marca 5 pasos:
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
| `migrations/` | Esquema: tablas, funciones, triggers, vistas, RLS, Storage y pg_cron (0001 → 0029) |
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

App de tiendas (`apps/tiendas/src`); lo marcado con * está en `packages/compartido/src`:

```
src/
  app/         router (rutas protegidas por permiso) y guards
  config/      permissions.js (códigos de permiso) y navigation.js (menú)
  contexts/    AuthProvider: sesión, perfil, permisos, alcance y sucursal activa
  services/    un archivo por módulo; único lugar que habla con Supabase
  features/    una carpeta por pantalla o módulo
  components/  domain/, layout/   (* ui/ y charts/)
  * hooks/ lib/ utils/ constants/status.js styles/ theme/ branding/ rendimiento/
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
   - el servicio en `src/services/` y la pantalla en `src/features/`;
   - si es de superadmin, va en la Consola (`apps/consola/src/pages`, su ruta en `router.jsx` y su opción en `layout/ConsolaLayout.jsx`);
   - lo que usen las dos apps va en `packages/compartido`.
4. **Instaladores y verificación:**
   - `node supabase/build-pendiente.mjs` regenera los dos instaladores;
   - agrega sus comprobaciones a `supabase/verificar.sql`.
5. **Revisión:**
   - `npm run lint` y `npm run build` en la raíz (compila las dos apps);
   - en el ambiente de pruebas, `supabase/pruebas/aislamiento.sql` sin ❌.
6. **Diario:** escribe el cambio en [docs/diario-de-cambios/](docs/diario-de-cambios/).

Los `.sql` se guardan con saltos de línea LF (lo fuerza `.gitattributes`). Algunas migraciones parchean funciones existentes buscando texto exacto.
