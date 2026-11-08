# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
8 de noviembre de 2026

## 🧩 Cambio registrado
**La app de tiendas ya no tiene la plataforma de superadmin: vive solo en la Consola Operalia. En `/plataforma` queda un aviso con el link.**

Sin cambios en la base de datos.

---

# 🏪 App de tiendas (`apps/tiendas`)
- **Rutas:**
  - se quitaron las 7 rutas de `/plataforma`: Empresas, Nueva empresa, Rendimiento, Prospectos, Soporte, Ticket y Marca;
  - se quitaron sus imports de `@operalia/consola` y el `PlatformBaseContext`;
  - tiendas ya no depende del paquete `@operalia/consola`.
- **Archivos de `features/platform`:** ya no existían en tiendas. Se movieron a `apps/consola/src/pages` en el cambio anterior, así que aquí no queda ninguno.
- **`navigation.js`:** se quitó el grupo **Plataforma** y sus íconos.
- **Aviso en `/plataforma/*`** (`features/errors/PlatformMovedPage.jsx`):
  - es una ruta pública: sirve con o sin sesión y para enlaces guardados;
  - dice **«La plataforma se movió a la Consola»** con el botón «Ir a la Consola»;
  - el botón lleva a la misma página en la Consola: `/plataforma/soporte/123?empresa=…` → `<consola>/soporte/123?empresa=…`;
  - si no está definida `VITE_CONSOLA_URL`, en lugar del botón pide el link al equipo de Operalia.
- **Superadmin en tiendas:**
  - entra al Dashboard como cualquiera, ya no a `/plataforma/rendimiento`;
  - ve el menú y la marca de su empresa; se quitó la sección plegable «Operación de…»;
  - al final del menú tiene «Plataforma → Consola Operalia», que abre la Consola en otra pestaña (solo si `VITE_CONSOLA_URL` está definida);
  - conserva todos sus permisos.
- **Variable nueva** `VITE_CONSOLA_URL`, solo para tiendas: va en `config/env.js` (paquete compartido), `.env.example` y el README.
- **Estilos:** se borraron los de `.nav-section` en `global.css`, porque ya no se usan.

# 🖥️ Consola (`apps/consola`)
- **Rutas internas:** ya no se montan bajo `/plataforma`, así que se quitó `paths.js` (`usePlatformPath`). Las páginas usan rutas directas: `/nueva`, `/soporte/:id`, `/marca?empresa=…`.
- **`package.json`:** se quitó el `exports`, porque nadie la importa ya.

# 🧪 Pruebas
- `npm run lint` en verde y `npm run build` compila las dos apps. El lint detectó que «Rendimiento de sucursales» usa el ícono `Activity`: el build pasaba, pero el menú habría fallado al cargar.
- **Navegador** (Supabase simulado, 1280 y 360 px, sin errores):

  | Caso | Resultado |
  |---|---|
  | `/plataforma` sin sesión | Aviso con el link `http://localhost:4174/` |
  | `/plataforma/soporte/t1?empresa=c1` | Link `…:4174/soporte/t1?empresa=c1` |
  | Superadmin en tiendas | Entra a `/dashboard`. El menú no tiene Empresas, Prospectos ni Nueva empresa; tiene «Consola Operalia». La marca es la de Gato Pelón |
  | `/plataforma/rendimiento` con sesión | El mismo aviso, con el link a `/rendimiento` |
  | Empleado normal | Entra a `/dashboard`, sin link a la Consola |
  | Consola | Nueva empresa → `/nueva` y Cancelar → `/`. Marca → `/marca?empresa=c1` y el ticket → `/soporte/t1` |

# ▶️ En Vercel
- **Proyecto de tiendas:** agregar `VITE_CONSOLA_URL` con el dominio de la Consola y volver a desplegar.
- **Sin la variable:** el aviso sale igual, pero sin botón, y el menú del superadmin no muestra el link.
