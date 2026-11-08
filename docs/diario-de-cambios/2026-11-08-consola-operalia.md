# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
8 de noviembre de 2026

## 🧩 Cambio registrado
**La plataforma de superadmin se separa en una segunda app, «Consola Operalia», dentro del mismo repo y con la misma base de Supabase.**

La app de tiendas sigue igual para los empleados, y `/plataforma` sigue funcionando en ella por ahora.

---

# 🗂️ Estructura (npm workspaces)

```
apps/tiendas         la app actual (PWA): src/, public/, index.html, vite.config.js, vercel.json
apps/consola         Consola Operalia (nueva)
packages/compartido  @operalia/compartido: lo que usan las dos
supabase/            sin moverse, una sola vez en la raíz
```

- **Raíz:** su `package.json` declara los workspaces y los comandos:
  - `dev` y `dev:consola`;
  - `build`, que compila las dos apps, y `build:tiendas` / `build:consola`;
  - `lint`, que revisa todo el repo.

  ESLint se queda en la raíz e ignora `**/dist`.
- **Variables:** las dos apps leen el `.env` de la raíz (`envDir: '../..'`).
- **Cómo se movieron los archivos:**
  - con un script, usando `git mv` para que git conserve la historia de cada archivo;
  - el script reescribió cada import relativo al paquete correcto, por ejemplo `@operalia/compartido/components/ui/Button.jsx`, siempre con la extensión;
  - solo 6 imports necesitaron arreglo a mano.

## Qué hay en `packages/compartido/src`
| Carpeta | Contenido |
|---|---|
| `components/ui`, `components/charts` | Botones, tablas, modales, gráficas |
| `lib/` | Cliente de Supabase (`supabaseClient.js`) y `queryHelpers.js` |
| `config/env.js` | Variables `VITE_*`, código de empresa y link `/e/<código>` |
| `theme/brand.js` | Paleta y contraste AA de la marca |
| `branding/` | `brandingService.js` (logo, color y nombre), `BrandEditor.jsx`, `CompanyLink.jsx` (link + QR), `printCompanyLink.js` |
| `rendimiento/` | `PerformanceView.jsx` y `platformMetrics.js`. El tablero recibe de dónde salen los datos (`source`), así lo usan la Consola (plataforma) y tiendas (Rendimiento de sucursales) |
| `hooks/`, `contexts/` | `useAsync`, `useToast`, `useAuth` y `AuthContext` (cada app pone su propio proveedor de sesión), `ToastProvider` |
| `utils/`, `constants/status.js`, `styles/` | Formato, CSV, QR (`qr.js`), contraseñas temporales (`passwords.js`), estados y estilos globales |
| `reports/`, `support/` | `reportFormat.js` (periodos y formato), `reportUi.jsx`, `supportUi.jsx` |

**Archivos de tiendas que se dividieron y quedan como puente** (lo que ya importaba tiendas sigue funcionando):
- `organizationService.js` reexporta lo de marca;
- `reportFilters.js` reexporta periodos y formato;
- `reportService.js` reexporta `daysBetween`;
- `employeeService.js` reexporta `generateTempPassword`;
- `printCheckpoints.js` usa `utils/qr.js`.

# 🖥️ Consola Operalia (`apps/consola`)
- **Páginas movidas desde `src/features/platform`:**
  - Empresas, Nueva empresa, Rendimiento, Prospectos, Soporte de tiendas y Ticket;
  - su servicio `platformService.js`.
- **Login propio** con correo y contraseña:
  - **Al entrar:** pide `get_my_profile()`. Si la cuenta no es `is_platform_admin` ve **«Sin acceso»**, con su correo y el botón «Cerrar sesión», y no se llama a ninguna función de plataforma.
  - **Si falla la consulta del perfil:** dice «No se pudo verificar tu cuenta» con «Reintentar».
  - **Seguridad:** la real sigue en la base, porque cada `platform_*` valida superadmin.
- **Menú:** Empresas, Rendimiento, Marca, Prospectos, Nueva empresa y Soporte de tiendas. Usa los mismos estilos que tiendas, con el menú plegable en celular.
- **Marca** (nueva, `/marca?empresa=<id>`):
  - el superadmin elige una empresa, incluso suspendida, y edita su nombre visible, color y logo con el mismo `BrandEditor` del propietario;
  - debajo están su **link de acceso y QR**: copiar e imprimir;
  - desde Empresas, cada fila trae los botones QR y Marca.
- **La Consola no se pinta con la marca de ninguna empresa:** siempre usa el azul de Operalia.
- **Link `/e/<código>`:** la ruta vive en la app de tiendas. La Consola arma el link con **`VITE_TIENDAS_URL`**; si falta, el panel lo avisa en lugar de dar un link roto.

# 🏪 App de tiendas
- **`/plataforma/*` sigue igual.** Importa las páginas de `@operalia/consola` y las envuelve con `PlatformBaseContext` (`/plataforma`).
  - Así los botones internos (Nueva empresa, Tickets, Cancelar…) siguen llevando a `/plataforma/...`; en la Consola llevan a `/nueva`, `/soporte`…
  - Se agregó `/plataforma/marca`, el mismo editor.
- **Mi empresa** usa el `BrandEditor` compartido.
- **Rendimiento de sucursales** usa el `PerformanceView` compartido.

# 🗄️ Migración `0029_consola_marca.sql`
- **Para qué:** RLS de `companies` solo deja leer la empresa propia, así que la Consola no podía leer la marca de las demás.
- **Qué agrega:** `platform_get_company_branding(empresa)`, SECURITY DEFINER y solo para superadmin. Devuelve id, nombre, código, estado y la marca, incluso de empresas suspendidas.
- **Permisos:** revoca `public` y `anon`; da `authenticated`.
- **Guardar:** sigue siendo con `set_company_branding` (0028), que ya aceptaba superadmin.
- **Revisiones:** fila nueva en `verificar.sql`, función agregada a la lista revisada de `pruebas/aislamiento.sql` e instaladores regenerados (38 y 31 archivos).

# 🧪 Pruebas
- **Lint y build:** `npm run lint` en verde y `npm run build` compila las dos apps.
- **PGlite:**
  - la instalación corre dos veces sin errores;
  - `verificar.sql`: 100 filas, todas en verde salvo pg_cron, que la copia local no tiene;
  - aislamiento: **0 ❌** en 446 pruebas;
  - `platform_get_company_branding`: el superadmin lee Mercado Sol suspendida; la propietaria de La Luna recibe error y `anon` no tiene permiso.
- **Navegador** (Supabase simulado, 1280 y 360 px, sin errores ni scroll horizontal):

  | App | Caso | Resultado |
  |---|---|---|
  | Consola | `/marca` sin sesión | Va a `/login`. Al entrar con correo vuelve a `/marca` |
  | Consola | Empresas | 3 filas. El QR copia `http://localhost:4173/e/mercadosol`, con el dominio de tiendas |
  | Consola | Marca de Mercado Sol | Guarda con `set_company_branding` (`#facc15`, «Sol del Norte»). El `--primary` de la Consola no cambia |
  | Consola | Empresa suspendida | El panel del link lo avisa |
  | Consola | Rendimiento | 8 indicadores |
  | Consola | Nueva empresa → Cancelar | Vuelve a `/` |
  | Consola | Cerrar sesión | Va a `/login` |
  | Consola | Cuenta que no es superadmin | «Sin acceso», sin llamadas `platform_*` |
  | Tiendas | `/plataforma` | 3 empresas. «Nueva empresa» lleva a `/plataforma/nueva` |
  | Tiendas | Otras páginas | `/plataforma/marca`, `/reports/sucursales` y `/company` funcionan |
  | Tiendas | Prueba del link `/e/…` | Repetida, sigue igual |

# ▶️ Pendiente fuera del código
1. **Vercel, proyecto actual:** cambiar **Root Directory** a `apps/tiendas` antes del merge.
2. **Vercel, proyecto nuevo** con Root Directory `apps/consola`:
   - las mismas `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`;
   - `VITE_TIENDAS_URL` con el dominio de tiendas.
3. **Supabase:** correr `migrations/0029_consola_marca.sql` y `verificar.sql`, y agregar el dominio de la Consola en Auth → Redirect URLs.
