# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
8 de noviembre de 2026

## 🧩 Cambio registrado
**Link de cada empresa (`/e/<código>`) y su QR: el empleado ya no escribe la empresa al iniciar sesión.**

Sin cambios en la base de datos: usa `get_company_branding` (0028). El correo interno sigue igual: `usuario@<código>.operalia.local`.

---

# 🔗 Ruta pública `/e/:codigo`
- **Archivo:** `src/features/auth/CompanyLinkPage.jsx`, registrada en `src/app/router.jsx`, fuera de la sesión.
- **Normaliza el código:** `/e/MercadoSol` encuentra `mercadosol`.
- **Si la empresa existe y está activa:**
  - la recuerda en el dispositivo (`rememberCompany`);
  - guarda y aplica su marca (`saveBrand` y `applyBrand`);
  - redirige a `/login`.
- **Si no existe o está suspendida:** solo dice **«Empresa no encontrada»**, con un enlace al inicio de sesión. No dice si existió ni si está suspendida.
- **Sin conexión:** «No se pudo abrir el link» con «Reintentar». No se confunde con una empresa inexistente.
- **Con sesión iniciada:** no cambia nada y manda al inicio.
- **En Vercel** funciona con la regla actual de `vercel.json`, que manda todo a `index.html`. **En la PWA** funciona con el `navigateFallback` del service worker.

# 🔐 Inicio de sesión
- **Con empresa recordada** (por el link o por un inicio anterior):
  - se oculta el campo **Empresa**;
  - el encabezado muestra el logo y el nombre de la empresa, y «Inicia sesión con tu usuario y contraseña»;
  - el enlace pequeño **«¿No es tu empresa? Cambiar»** vuelve a mostrar el campo vacío y la marca de Operalia. La empresa recordada solo cambia al entrar con otra.
- **Sin empresa recordada:** el campo se ve como antes.
- **Correo real (con @):** igual que antes. No necesita empresa y no la sobrescribe.
- **«¿Olvidaste tu contraseña?»:** con empresa recordada solo pide el usuario. Muestra «Empresa: Gato Pelón» con su propio «Cambiar».

# 📱 PWA
- **Manifest:** `start_url` y `scope` pasan de `/` a `.` (relativos). El manifest se sirve en `/manifest.webmanifest`, así que `.` es la raíz del sitio donde esté publicado.
- **Al instalarla:** la app instalada desde `/e/gatopelon` abre en la raíz → `/login` y lee la empresa recordada del mismo origen.
- **iPhone:** al instalar desde Safari, la app instalada tiene su propio almacenamiento. Si ahí no aparece la empresa, se escribe una vez o se abre de nuevo el link dentro de la app.

# 🏢 Plataforma → Empresas
- Cada fila muestra `/e/<código>` y un botón **QR**. El botón abre «Link de acceso»:
  - **link completo** `https://<dominio>/e/<código>`, con el dominio desde el que se abre el panel, y el botón **Copiar**;
  - **QR** generado en el navegador con `uqr`, la misma librería de los puntos de control, sin servicios externos;
  - **Imprimir QR:** hoja con el nombre de la empresa, el QR grande, el link e instrucciones para pegarla en la tienda (`printCompanyLink.js`);
  - si la empresa está suspendida, avisa que el link dirá «Empresa no encontrada».
- **Nueva empresa:** la tarjeta final de datos de acceso ahora trae el link de la empresa en lugar de solo la URL de la app.

# 🧪 Pruebas en el navegador
Supabase simulado, a 1280 y 360 px, sin errores ni scroll horizontal.

| Caso | Resultado |
|---|---|
| `/e/gatopelon` | Va a `/login` sin campo Empresa, con el título «Gato Pelón» y la empresa recordada. «Olvidé» manda `p_company_code: gatopelon` sin pedirla |
| `/e/MercadoSol` | Va a `/login` con el logo y el verde ajustado (`#0b825a`). Entrar usa `cajero@mercadosol.operalia.local` |
| `/e/noexiste` | «Empresa no encontrada». No recuerda nada y deja la marca de Operalia |
| `/login` sin link | Muestra el campo Empresa como antes |
| «Cambiar» | Vuelve el campo y la marca de Operalia |
| Correo real | Entra con `chee@ejemplo.com` sin empresa |
| Plataforma | Copia `http://localhost:4173/e/mercadosol`, el QR se ve y la hoja de impresión se abre |

`npm run lint` y `npm run build` pasan.
