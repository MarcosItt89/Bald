# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
7 de noviembre de 2026

## 🧩 Cambio registrado
**Marca por empresa: nombre visible, color principal y logo. Se aplican en el inicio de sesión y en toda la app, y los edita el propietario (o un superadmin) en Configuración → Mi empresa.**

---

# 🗄️ Migración `0028_marca_empresa.sql` (re-ejecutable)

## Columnas en `companies`
| Columna | Tipo | Regla |
|---|---|---|
| `brand_color` | `text not null default '#2563eb'` | `check (brand_color ~ '^#[0-9a-fA-F]{6}$')` |
| `display_name` | `text` | 1 a 60 caracteres, o null (se usa `name`) |
| `logo_url` | ya existía | Solo URLs del bucket `company-branding` de esa empresa (lo valida `set_company_branding`) |

## Quién cambia la marca
- **Trigger `trg_company_branding_guard`:**
  - si cambian `logo_url`, `brand_color` o `display_name`, exige superadmin (`is_platform_admin()`) o el propietario de **esa** empresa (`auth_is_owner()` y `id = auth_company_id()`);
  - aplica también a quien escriba directo en la tabla por la API.
- **`set_company_branding(empresa, nombre visible, color, logo)`** (SECURITY DEFINER):
  - **Permisos:** el propietario guarda la de su empresa y el superadmin, la de cualquiera.
  - **Validaciones:** color `#RRGGBB` y nombre de hasta 60 caracteres. El logo tiene que estar en `company-branding/{empresa}/`.
  - **Registro:** se anota en `audit_logs` como `marca_actualizada`.

## Bucket `company-branding`
- **Configuración:** público, 500 KB (512 000 bytes), solo `image/png`, `image/svg+xml` e `image/webp`.
- **Políticas en `storage.objects`:**
  - **Lectura:** pública. El logo sale en el login, sin sesión.
  - **Subir, reemplazar y borrar:** solo en la carpeta `{company_id}/` y solo si `can_manage_branding_folder()` lo permite: el propietario de esa empresa o un superadmin.
- **SVG:** la app solo lo muestra con `<img>`, y ahí el navegador no ejecuta scripts. Si algún día se abriera como documento, convendría quitar SVG de los tipos permitidos.

## `get_company_branding(p_code)`
- **Para qué es:** la pantalla de login, sin sesión.
- **Quién la ejecuta:** `anon` y `authenticated`.
- **Qué devuelve:** solo `name`, `display_name`, `logo_url` y `brand_color`, y solo de una empresa **activa**; si está suspendida o no existe, no devuelve nada. Normaliza el código: `'  SuperLuna '` encuentra `superluna`.

## Otros cambios
- **`get_my_profile()`:** agrega `company_display_name`, `company_logo_url` y `company_brand_color`.
- **0026:** el barrido que quita EXECUTE a `anon` ahora respeta también `get_company_branding`. Si se vuelve a correr la 0026, el login no pierde la marca.
- **`verificar.sql`:** 3 filas nuevas de 0028. La fila de `anon` ahora acepta las dos funciones del login.

# 💻 Frontend

## `src/theme/brand.js`
- **`applyBrand(color)`:** escribe en `:root` cuatro variables:
  - `--primary`;
  - `--primary-dark`, para el hover de botones (18 % más oscuro);
  - `--primary-light`, para fondos suaves (85 % hacia blanco);
  - `--primary-deep`, para el menú activo, el degradado del login y los filtros (32 % más oscuro).

  Con el azul de Operalia o un color inválido, quita las variables y queda el CSS original intacto.
- **Contraste AA:** si el color no llega a 4.5:1 con texto blanco, porque los botones llevan texto blanco, se oscurece en pasos de 5 % hasta llegar.

  | Color elegido | Color de los botones | Contraste con blanco |
  |---|---|---|
  | Amarillo `#facc15` | `#8a700c` | 4.8:1 |
  | Verde `#10b981` | `#0b825a` | 4.8:1 |
  | Morado `#7c3aed` | Sin cambio | 5.7:1 |
  | Azul de Operalia | Sin cambio | 5.2:1 |
- **Guardado en el dispositivo:** `saveBrand` y `readSavedBrand` usan `localStorage` (`operalia.brand`). `bootBrand()` corre en `main.jsx` **antes** de `createRoot`, así no parpadea el azul.
- **`--primary-deep` (nuevo):** antes eran `#1e40af` fijos en el CSS: `--sidebar-active-bg`, el degradado del login, `.filter-chip` y `.waste-reason-active`. Su valor por defecto es el mismo `#1e40af`, así que sin marca todo se ve igual que antes. Los azules de «información» (`--info`, `badge-info`, `permission-tag`) se dejaron fijos porque son de estado, no de marca.

## Dónde se aplica
- **Al iniciar sesión:** `AuthProvider`, al cargar el perfil, aplica y guarda la marca de la empresa del empleado.
- **Login:** con el código de empresa escrito, tras 300 ms, pide `get_company_branding` y muestra el logo, el nombre visible y el color.
  - Al abrir la página usa la última marca guardada si es de la misma empresa.
  - Con el campo vacío o una empresa inexistente, vuelve a Operalia.
- **Menú lateral:**
  - muestra el logo y el nombre visible de la empresa;
  - el superadmin sigue viendo Operalia y «Plataforma», porque trabaja como plataforma.
- **Configuración → Mi empresa** (`/company`; solo propietario o superadmin, `canEditBranding`), sección **Marca**:
  - **Nombre visible.**
  - **Color:** selector y campo hexadecimal, con el botón «Original». Dice el contraste o el color ajustado.
  - **Logo:** subir, cambiar o quitar, con validación de tipo y peso antes de subir.
  - **Vista previa** del menú, de los botones, las insignias y los enlaces, y del login.
  - **Al guardar:**
    - sube el logo y llama a `set_company_branding`;
    - borra el logo anterior del bucket;
    - recarga el perfil, así el color nuevo se aplica al instante;
    - si falla, borra el logo recién subido.

# 🧪 Pruebas
- **Prueba de aislamiento** (`pruebas/aislamiento.sql`), grupo nuevo **marca**:
  - Nadie (empleado de sucursal, `self`, propietario, admin no propietario ni `anon`) puede cambiar la marca de **otra** empresa: ni con `set_company_branding`, ni con un `update` directo, ni subiendo un logo a su carpeta.
  - **En su propia empresa:**
    - el propietario sí puede: control positivo;
    - el admin que no es propietario y el gerente, no.
  - `anon` sí obtiene la marca pública del login.
  - Resultado: **0 ❌** en 441 pruebas. Los 9 ⚠️ son los mismos de antes.
- **Funcionales (PGlite):**
  - el perfil trae la marca;
  - se rechazan un logo de otra carpeta, el color «morado» (el RPC y el check de la tabla) y una empresa suspendida en el login;
  - el superadmin cambia la marca de otra empresa;
  - `audit_logs` registra los cambios.
- **`verificar.sql`:** 99 filas, todas en verde salvo pg_cron, que la copia local no tiene.
- **Pantallas** (Supabase simulado, 1280 y 360 px, sin scroll horizontal):
  - el login con la marca de «superluna»;
  - Mi empresa con un color ajustado;
  - al recargar, `--primary` ya es el de la empresa desde el primer render.
- `npm run lint` y `npm run build` pasan.

# ▶️ Qué correr en Supabase
1. `migrations/0028_marca_empresa.sql`.
2. `verificar.sql`: las 3 filas de 0028 deben salir ✅.
3. En el ambiente de pruebas, `pruebas/aislamiento.sql`: debe dar **0 con ❌**.
