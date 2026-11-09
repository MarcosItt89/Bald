# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
9 de noviembre de 2026

## 🧩 Cambio registrado
**Recibo de mercancía a partir del XML de la factura CFDI 4.0 del proveedor, con emparejamiento de claves del proveedor que se recuerda.**

---

# 🗄️ Migración `0031_recepcion_cfdi.sql` (re-ejecutable)

## Tabla nueva `supplier_product_codes`
| Columna | Para qué |
|---|---|
| `company_id`, `supplier_id` | Empresa y proveedor |
| `supplier_code` | La clave del proveedor (`NoIdentificacion`; si no viene, `desc:` + descripción) |
| `product_id` | El producto de la empresa |
| `created_by`, `created_at`, `updated_at` | Quién la emparejó (trigger `trg_actor`) y cuándo |

- **Unicidad:** `(company_id, supplier_id, supplier_code)`.
- **RLS por empresa:**
  - **Leer:** toda la empresa.
  - **Escribir:** la empresa, con `receive_products`, `manage_suppliers` o `manage_inventory`.
  - **`anon`:** sin acceso.
- **Trigger `trg_supplier_product_codes_company`:** el proveedor y el producto deben ser **de la misma empresa** que la fila. El RLS solo revisa `company_id`; sin el trigger alguien podría ligar ids de otra empresa a la suya.

## Recibos
- **`receiving_orders`:**
  - `cfdi_uuid` (formato UUID en mayúsculas), `invoice_date`, `invoice_total`, `invoice_currency`;
  - `source` (`manual` o `cfdi`);
  - **índice único** `(company_id, cfdi_uuid)` en recibos no cancelados: una factura no entra dos veces.
- **`receiving_items`:** `supplier_code`, `supplier_description`, `supplier_unit` y `unit_cost` (el `ValorUnitario`).
- **Vistas:** se recrearon `v_receiving_orders` y `v_receiving_items` con la misma definición, porque usan `r.*` y `ri.*` y solo así traen las columnas nuevas.

## `create_receiving_from_cfdi(sucursal, proveedor, factura, partidas, notas)`
- **SECURITY INVOKER:** pasa por el RLS de recibos, partidas y claves.
- **Antes de crear nada, revisa:**
  - `receive_products`;
  - que la sucursal y el proveedor sean de su empresa;
  - el UUID;
  - las partidas (1 a 1000, cantidad mayor que 0 y producto de su empresa).
- **Crea el recibo `in_progress` (en captura):**
  - **Factura:** `invoice_number` = serie-folio.
  - **Partidas:** esperado = cantidad de la factura y recibido = 0.
  - **Existencias:** **no se mueven**; eso sigue pasando solo al cerrar (`tg_receiving_after_complete`).
- **Recuerda las claves** marcadas con `recordar`. Si la clave ya existía con otro producto, la actualiza.
- **Factura repetida:** si ya está en un recibo no cancelado, dice en cuál («Esta factura ya está en el recibo REC-…»). Si ese recibo es de una sucursal que quien llama no ve, dice que ya se registró en otro recibo de la empresa.

## Evidencia
- **Bucket `evidence`:** ahora acepta `application/xml` y `text/xml`.
- **Quién adjunta:** quien tiene `receive_products` ya puede adjuntar archivos **a recibos**. Los cambios están en la política `evidence_insert` y en `evidence_objects_insert` de Storage, en la carpeta `{empresa}/receiving_order/…`. Antes solo podía `upload_evidence`; el resto de las condiciones no cambió.

## Pruebas SQL
- **`verificar.sql`:** 2 filas nuevas de 0031.
- **`pruebas/aislamiento.sql`:**
  - **Barrido por tabla:** `supplier_product_codes` entra con una clave de Gato Pelón creada como fixture, para que haya qué leer, cambiar y borrar.
  - **Grupo nuevo «5 cfdi»:**
    - nadie liga un proveedor o producto de Gato Pelón en su empresa (directo a la tabla);
    - nadie crea un recibo desde CFDI en una sucursal de Gato Pelón ni con su proveedor o producto;
    - control positivo: el propietario y el admin sí, en su sucursal.
  - **Mensaje del trigger:** «deben ser de la misma empresa» se agregó a los mensajes de seguridad, para que esos bloqueos salgan ✅ y no ⚠️.
  - **Resultado:** **0 ❌** en 460 pruebas. Los 9 ⚠️ son los de siempre.

# 💻 Frontend (app de tiendas)
- **`features/receiving/cfdi/parseCfdi.js`:** lee el XML con `DOMParser`, que no ejecuta scripts ni carga entidades externas.
  - **Acepta** CFDI 4.0 (y 3.3).
  - **Rechaza** con un mensaje claro: XML inválido, XML que no es CFDI, CFDI que no es de ingreso (por ejemplo una nota de crédito) y facturas sin timbre (UUID).
- **`ReceivingCfdiPage.jsx`** (`/receiving/cfdi`; botón «Desde factura XML» en Recibo):
  - **Datos de la factura:** emisor, RFC, serie-folio, fecha, total, UUID y número de conceptos.
  - **Factura repetida:** aviso con link al recibo existente; no deja crear otro.
  - **Proveedor por RFC:**
    - si hay varios con ese RFC, se elige;
    - si está inactivo, avisa;
    - si no existe, «Dar de alta» con nombre, razón social y RFC de la factura (requiere `manage_suppliers`).
  - **Partidas:** cada concepto con clave, descripción, cantidad, unidad y valor unitario.
    - **Emparejamiento automático:** «Recordado» si la clave ya estaba guardada, o «Sugerido» si coincide con un código de barras o un SKU.
    - **A mano:** se elige con el buscador de productos o se omite (fletes, servicios).
    - **Pendientes:** salen en amarillo; mientras haya alguna, no se puede crear el recibo.
  - **Al crear:**
    - llama a `create_receiving_from_cfdi` y guarda el XML como evidencia;
    - abre el recibo en captura;
    - si el XML no se pudo guardar, avisa pero el recibo queda creado.
- **`ReceivingDetailPage.jsx`:**
  - **Encabezado:** muestra la factura CFDI (UUID, fecha y total).
  - **Partidas:** traen la clave y la unidad del proveedor y la columna «Costo factura».
  - **Botón «Contar» por partida** (resaltado si aún no se cuenta): recibido, dañado, peso, lote y caducidad. Antes solo se podían agregar partidas ya contadas.
- **`evidenceService`:** si el navegador no pone tipo al `.xml`, usa `application/xml`.
- **`EvidenceGallery`:** muestra el XML como documento.

# 🧪 Pruebas
- **PGlite (la base real, sin simular):**
  - **Al crear:** el recibo queda en captura con 3 partidas (esperado 10, 11 y 12, recibido 0, clave, costo y unidad). El encabezado lleva el UUID, serie-folio, fecha y total, y lo firma quien lo creó.
  - **Existencias:** **no cambian** en el borrador. Al contar y cerrar suben exactamente lo recibido (45 → 55, 6 → 17 y 49 → 61), con 3 movimientos `receiving`.
  - **Claves:** se guardan 3 claves firmadas. Volver a emparejar una clave con otro producto actualiza la memoria.
  - **Rechazos:** misma factura, UUID inválido, sin partidas, cantidad 0 (sin dejar un recibo a medias) y empleado sin `receive_products`.
  - **Cancelación:** después de cancelar un recibo, la misma factura se puede volver a registrar.
- **Navegador** (Supabase simulado, 1280 y 360 px, sin errores ni scroll horizontal), con facturas CFDI 4.0 de prueba (namespaces del SAT, impuestos, timbre y `&amp;` en una descripción):
  - **Rechazos:** la nota de crédito y el XML roto se rechazan con su mensaje.
  - **Factura 1, proveedor nuevo:**
    - el proveedor se da de alta desde la factura;
    - el arroz se sugiere por código de barras, el aceite y el frijol se eligen con el buscador y el flete se omite;
    - el recibo se crea con 3 partidas y el XML queda como evidencia;
    - «Contar» guarda recibido = 24.
  - **Factura 2, mismo proveedor:** las 3 partidas salen «Recordado» y se puede crear sin tocar nada.
  - **Factura 1 otra vez:** aviso «ya está en el recibo REC-…» y botón deshabilitado.
- `npm run lint` y `npm run build` en verde.

# ▶️ Qué correr en Supabase
1. `migrations/0031_recepcion_cfdi.sql`.
2. `verificar.sql`: las 2 filas de 0031 deben salir ✅.
3. En el ambiente de pruebas, `pruebas/aislamiento.sql`: debe dar **0 con ❌**.
