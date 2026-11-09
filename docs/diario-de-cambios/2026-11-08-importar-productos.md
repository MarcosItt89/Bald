# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
8 de noviembre de 2026

## 🧩 Cambio registrado
**Importación de productos por CSV (Inventario → Importar productos) para el propietario o un administrador de la empresa.**

> La migración es **0030**, no 0029 como decía la solicitud: 0029 ya existía (`0029_consola_marca.sql`, Consola).

---

# 🗄️ Migración `0030_importar_productos.sql` (re-ejecutable)

## `import_products(p_branch_id, p_rows, p_mode)`
- **SECURITY INVOKER:** cada escritura pasa por el RLS que ya existía:
  - `products_write` y `barcodes_write`: `manage_inventory` y su empresa;
  - `inventory_insert` y `inventory_update`: su sucursal;
  - `movements_insert`: su sucursal y `manage_inventory`.

  Además revisa explícitamente, antes de tocar nada:
  - sesión de empleado (`auth_company_id`);
  - **rol de alcance empresa** con `manage_inventory`: el propietario o un administrador. Un gerente de sucursal recibe error;
  - que **la sucursal sea de su empresa** y pueda acceder a ella;
  - modo válido (`crear`, `actualizar` o `ambos`) y máximo 1000 filas por llamada.
- **Por fila** (cada una en su propio bloque: un error no deshace las demás):
  - **Producto:** upsert por `(company_id, sku)`.
    - `crear` con un SKU que ya existe da error, y también `actualizar` con un SKU que no existe.
    - **Nombre:** obligatorio solo para productos nuevos.
    - **Celdas vacías:** al actualizar, el dato no cambia.
    - **Precio:** si cambia, se guardan `previous_price` y `price_updated_at`.
  - **Validaciones:**
    - números con punto decimal y no negativos;
    - unidad entre `pz, kg, g, l, ml, caja, paquete`;
    - caducidad como sí o no;
    - departamento por **código o nombre**, siempre de la empresa.
  - **Código de barras** (`product_barcodes`):
    - error si ya es de **otro** producto de la empresa;
    - si el producto no tiene ninguno, el nuevo es el principal.
  - **Inventario:**
    - asegura el renglón del producto en la sucursal;
    - `minimo` actualiza `min_stock`.
  - **Existencia:**
    - **Carga:** movimiento `adjustment_in` con motivo **«Carga inicial»** (`reference_type = 'import'`); el trigger de siempre mueve el stock, así que el kardex cuadra.
    - **Una sola vez:** solo si el producto **no tiene movimientos** en esa sucursal. Repetir la importación no duplica existencias; la fila lo indica con «existencia no aplicada».
  - **Resultado:** devuelve `{ fila, sku, estado: creado | actualizado | error, motivo, producto_id }`. Si nada cambió, el motivo dice «sin cambios en el producto».
- **Funciones auxiliares** (sin SECURITY DEFINER), solo para `authenticated`:
  - `import_parse_num`: número de una celda;
  - `import_parse_bool`: sí o no de una celda.

## Pruebas SQL
- **`verificar.sql`:** fila nueva de 0030. La función existe, es invoker y `anon` no la ejecuta.
- **`pruebas/aislamiento.sql`, grupo nuevo «4 importar»:**
  - **Sucursal de otra empresa:** nadie importa a una sucursal de Gato Pelón (sucursal, `self`, propietario, `anon` y admin: error).
  - **Datos de otra empresa:** una importación del propietario o del admin a su propia sucursal con el **mismo SKU y el mismo código de barras** que un producto de Gato Pelón no crea ni cambia nada de Gato Pelón (prueba a ciegas, contando como postgres).
  - **Control positivo:** propietario y admin sí importan a su sucursal; el empleado de sucursal y `self` reciben error.
- **Instaladores:** regenerados (39 y 32 archivos).

# 💻 Frontend (app de tiendas)
- **Ruta:** `/inventory/import`, con `manage_inventory` y alcance de empresa (`when: 'isCompanyScope'`).
- **Acceso:** opción «Importar productos» en el menú Inventario y botón «Importar» en Inventario.
- **`features/inventory/import/productCsv.js`** (funciones puras):
  - **Codificación:** UTF-8, o Latin-1 (windows-1252) si el archivo no es UTF-8 válido. Quita el BOM.
  - **Separador:** coma, punto y coma o tabulador, el más frecuente en el encabezado y fuera de comillas.
  - **CSV:** maneja comillas, `""` y saltos de línea dentro de comillas.
  - **Encabezados:** sin acentos ni mayúsculas, con alias como «Código de barras», «EAN», «Stock» o «Descripción».
  - **Coma decimal:** se detecta en todo el archivo. Entiende `1.234,50`, `1,234.50`, `12,5` y `$ 99.90`.
  - **Unidades:** acepta alias como «pieza», «kilo» o «litros».
  - **Validación por fila:** las mismas reglas que la base, más SKU o código repetido en el archivo (con las filas), código de otro producto y código de barras en notación científica (Excel convierte `7501055300001` en `7.50105E+12`).
- **`ImportProductsPage.jsx`:**
  1. **Archivo:** se elige sucursal y modo, y se sube el archivo. Un `.xlsx` se rechaza con la indicación de guardarlo como CSV; el máximo es 10 MB y 20,000 filas.
  2. **Archivo leído:** dice el separador, la codificación y si usa coma decimal, y cuántos productos son nuevos, se actualizan o tienen errores.
  3. **Vista previa:** de 100 en 100 filas, con filtro (todas, con errores, nuevos o se actualizan). Las filas con error salen en rojo con sus motivos.
  4. **Con errores el botón Importar está deshabilitado.** «Quitar N filas con error» las saca de la importación.
  5. **Importación:**
     - bloques de **500** con barra de progreso;
     - la pestaña avisa si se intenta cerrar a media importación;
     - si un bloque falla completo, se marca y sigue el siguiente.
  6. **Resumen:** creados, actualizados y errores; **«Descargar resumen»** en CSV (fila, SKU, nombre, estado y motivo).
- **Antes de validar**, el catálogo (SKU y dueño de cada código) se descarga en páginas de 1000, porque Supabase limita cada consulta a 1000 filas.

# 🧪 Pruebas
- **CSV generados de 2,000 filas:**
  - **UTF-8 con coma**, con nombres que llevan comas entre comillas y «ñ»: 0 errores.
  - **Latin-1 con punto y coma y coma decimal** (como lo guarda Excel en español), con 6 errores sembrados que marcan 8 filas: precio «doce», unidad «litros_x», código repetido (2 filas), SKU repetido (2 filas), código de otro producto y departamento «Juguetería». El lector los detecta todos en unos 70 ms.
- **PGlite (la base real, sin simular):**
  - **Primera importación**, 2,000 filas en 4 bloques de 500, de unos 2 s por bloque en PGlite: 2,000 creados y 2,000 códigos. Hubo 1,933 movimientos «Carga inicial», porque 67 filas traían existencia 0, y su suma (28,900) es igual al stock.
  - **La misma importación otra vez:** 2,000 «actualizado» con «sin cambios», y el kardex queda **idéntico**.
  - **Actualizar precio y mínimo:** guarda `previous_price`, mantiene el nombre si la celda viene vacía y cambia `min_stock`.
  - **Errores por fila:** precio «12,5» (la app ya lo convierte antes de enviarlo), unidad, código ajeno, departamento, existencia negativa, sin SKU, sin nombre y caducidad «quizá». Ninguna fila con error se creó.
  - **Seguridad:** sucursal de otra empresa, gerente de sucursal y modo inválido dan error.
  - **Aislamiento: 0 ❌** en 449 pruebas. `verificar.sql` sale en verde salvo pg_cron.
  - **Bug encontrado y corregido:** `texto[] || 'nota'` tomaba la nota como arreglo («malformed array literal»), así que repetir una importación habría marcado todo como error. Ahora se usa `array_append`.
- **Navegador** (Supabase simulado, 1280 y 360 px, sin errores ni scroll horizontal):
  - el botón Importar de Inventario abre la página y la plantilla se descarga;
  - el CSV de Excel muestra 8 filas en rojo y el botón Importar queda deshabilitado; «Quitar 8 filas con error» deja 1,992;
  - la importación manda bloques de 500, 500, 500 y 492 con barra de progreso;
  - el resumen da 1,991 creados y 1 error simulado, y se descarga en CSV con «ñ» correcta;
  - el CSV UTF-8 deja listas las 2,000 filas.
- `npm run lint` y `npm run build` en verde.
