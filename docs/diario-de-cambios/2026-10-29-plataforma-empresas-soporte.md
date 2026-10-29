# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
29 de octubre de 2026

## 🧩 Cambio registrado
**Sección Plataforma para superadmins: alta de empresas cliente en un paso, suspender y reactivar empresas, y soporte de todas las tiendas firmado como «Soporte Operalia».**

---

# 🗄️ Base de datos

## Migración `0024_plataforma_empresas_soporte.sql`

Todas las funciones son `security definer` y fallan si `not is_platform_admin()`. Desde el SQL Editor (sin usuario) también fallan, porque ahí no hay superadmin.

### A. Empresas

**`provision_company(p_name, p_legal_name, p_rfc, p_code, p_timezone, p_branch_code, p_branch_name, p_owner_username, p_owner_full_name, p_owner_password, p_with_demo default false)`**

Todo ocurre en la misma transacción: si algo falla, no queda nada a medias. En orden:
1. **Valida los datos:**
   - código de 2 a 30 caracteres `[a-z0-9-]`, sin guion al inicio ni al final, y que no exista;
   - zona horaria válida;
   - usuario de 3 a 40 caracteres;
   - contraseña de 8 caracteres o más;
   - si se piden datos demo, que `demo/` esté instalado.
2. **Crea la empresa:** con `status = 'active'` y el RFC en mayúsculas.
3. **Crea la primera sucursal:** va **antes** de la semilla para que reciba sus puntos QR y los checklists del día.
4. **Siembra lo base:** `seed_company_base(empresa)`.
5. **Crea al propietario:**
   - rol `admin`, departamento `ADM`, puesto «Propietario» y `is_owner = true`;
   - su cuenta la crea **`admin_set_password`**, sin duplicar su lógica: correo `usuario@<code>.operalia.local`, confirmado y con `must_change_password = true`.
6. **Datos demo:** si `p_with_demo`, corre `seed_company_demo(empresa)`.
7. **Auditoría:** registro en `audit_logs` (`evento = 'empresa_provisionada'`).
8. **Devuelve** `{ id, code, branch_id, owner_employee_id, owner_username }`.

**`platform_list_companies()`** devuelve, por empresa:
- nombre, razón social, RFC, código, estado, plan y zona horaria;
- sucursales activas y empleados activos;
- propietario;
- último inicio de sesión de cualquiera de sus empleados (`auth.users.last_sign_in_at`);
- fecha de alta.

**`platform_set_company_status(p_company_id, p_status)`** acepta `'active'` o `'suspended'`:
- registra el cambio en `audit_logs`;
- **no deja suspender la empresa de un superadmin**, porque él mismo se quedaría fuera de la plataforma.

### B. Soporte Operalia
- **RLS sin cambios:** las políticas de `support_tickets` y `support_ticket_messages` **no se abrieron** a otras empresas. Por consulta directa, el superadmin sigue viendo solo los tickets de Gato Pelón. A los de las demás empresas llega por las funciones de plataforma.
- **Mensajes de la plataforma:** se agregó la columna `support_ticket_messages.is_platform`. Un mensaje de la plataforma no tiene autor (`author_id` null) y la vista `v_support_ticket_messages` lo firma como **«Soporte Operalia»** (puesto «Plataforma»).
  - `tg_ticket_message_before` solo acepta `is_platform` en modo sistema. Si alguien de una tienda intenta marcarlo desde la API, recibe un error.
- **`platform_list_tickets(p_company_id, p_status, p_search, p_limit)`**:
  - filtra por empresa, por estado (también `'active'`, `'done'` u `'overdue'`) y por texto (folio, asunto o descripción);
  - indica si Soporte Operalia ya respondió.
- **`platform_get_ticket(id)`** devuelve el ticket con su empresa y la conversación completa. Las notas internas de la tienda vienen marcadas.
- **`platform_reply_ticket(id, mensaje, p_status default null)`**:
  - responde y, si se indica, cambia el estado. Primero aplica el estado y luego el mensaje, así que también sirve para reabrir y responder en un solo paso;
  - en un ticket cerrado no responde, salvo que se reabra en la misma llamada.
- **Avisos a quien levantó el ticket:** siguen saliendo de los triggers de 0003 («Respuesta en TCK-…», «esperando tu respuesta», «resuelto»). Además se marca la primera respuesta y el ticket abierto pasa a «en atención».
- **Avisos nuevos para el superadmin**, con liga a `/plataforma/soporte/<id>`:
  - **Ticket nuevo de otra empresa:** los de su propia empresa ya le llegaban.
  - **El solicitante respondió** en un ticket que atiende Soporte Operalia.

# 💻 Frontend

## Plataforma (solo superadmins)
- **Acceso:**
  - Las rutas `/plataforma`, `/plataforma/nueva`, `/plataforma/soporte` y `/plataforma/soporte/:id` exigen `when: 'isPlatformAdmin'`. Con el menú o con la URL, cualquier otro recibe la pantalla 403.
  - El menú y las rutas usan la misma regla, `canAccess`.
- **Grupo «Plataforma»** en `navigation.js`: Empresas, Nueva empresa y Soporte de tiendas.
- **Servicio nuevo:** `src/services/platformService.js`, al estilo de los demás (`unwrap` + `rpc`).

| Pantalla | Qué hace |
|---|---|
| **Empresas** | Tabla con lo que devuelve `platform_list_companies`. Para cada empresa: botón para ver sus tickets y «Suspender» / «Reactivar», con confirmación. |
| **Nueva empresa** | Formulario con todos los campos de `provision_company`. El código se sugiere a partir del nombre. Trae una contraseña temporal sugerida de 10 caracteres, que se puede regenerar. Al terminar muestra una tarjeta para copiar: URL de la app, código de empresa, usuario y contraseña temporal. |
| **Soporte de tiendas** | Bandeja de todas las empresas con pestañas (Abiertos, Vencidos, Esperando usuario, Cerrados, Todos), búsqueda y filtro por empresa. |
| **Ticket** | Conversación completa, respuesta como «Soporte Operalia» con cambio de estado opcional, «Marcar resuelto» y «Reabrir». |

- **En la tienda:** el ticket muestra «Atiende: Soporte Operalia» cuando la plataforma ya respondió y nadie de la tienda lo tiene asignado.
- **Límites conocidos:** el superadmin no ve las **fotos adjuntas** de otra empresa, porque Storage respeta el RLS de cada empresa. Tampoco recibe la conversación **en vivo**, porque Realtime también lo respeta; en su lugar hay un botón para actualizar.

# 🔐 Cómo agregar otro superadmin
Desde el SQL Editor. La persona necesita un empleado con cuenta en alguna empresa:
```sql
insert into public.platform_admins (user_id)
select e.user_id from public.employees e join public.companies c on c.id = e.company_id
where c.code = 'gatopelon' and e.username = 'USUARIO' and e.user_id is not null
on conflict do nothing;
```
Para quitarlo: `delete from public.platform_admins where user_id = '…';`.

# ✅ Pruebas (PGlite)
- **Instaladores:**
  - `pendiente.sql` corre dos veces sin errores;
  - `verificar.sql`, con 88 filas, sale en verde salvo pg_cron, que no existe en la copia local;
  - `instalacion-limpia.sql` sigue dejando solo a `chee` y `marcos.yeran.guerra`.
- **Actualización:** sobre una base con el instalador anterior, aplicar 0022, 0023, 0024 y `seed/` no duplica plantillas ni preguntas.
- **`provision_company`:**
  - Rechaza a un no superadmin, al SQL Editor, un código inválido, un código repetido y una contraseña de 7 caracteres.
  - Si se piden datos demo y no están instalados, falla sin dejar la empresa creada.
  - **Sin demo:** 14 roles, 12 plantillas, 2 puntos QR y los checklists del día. La propietaria tiene rol admin/ADM y su cuenta está confirmada con `must_change_password`. Al entrar ve su empresa, es propietaria y tiene `manage_roles`.
  - **Con demo:** además 14 productos y 21 plantillas.
- **`platform_set_company_status`:**
  - Al suspender, el perfil de sus empleados queda vacío; al reactivar, vuelve.
  - Rechaza suspender Gato Pelón y rechaza un estado inválido.
  - La propietaria no puede cambiar el estado, ni con la función ni con `update`.
- **Soporte:**
  - **Ticket nuevo:** el superadmin recibe el aviso y por RLS ve 0 tickets de esa empresa.
  - **Bandeja:** la lista y la búsqueda funcionan.
  - **Respuesta de la plataforma:** la tienda la ve firmada «Soporte Operalia» y recibe «esperando tu respuesta» y «Respuesta en …».
  - **Suplantación:** la tienda no puede escribir como plataforma.
  - **Respuesta de la tienda:** el superadmin recibe el aviso.
  - **Estados:** cerrar sin mensaje funciona; responder un ticket cerrado se rechaza; reabrir y responder en un solo paso funciona.
  - **Mensajes internos de una empresa:** siguen firmados por el empleado.
- **Pantallas** (Supabase simulado, a 1280 px y 360 px): las cuatro pantallas se ven bien y sin scroll horizontal. Un no superadmin no ve el grupo y recibe 403 en `/plataforma`.
- `npm run lint` y `npm run build` pasan.

# ▶️ Qué correr en Supabase
1. `migrations/0024_plataforma_empresas_soporte.sql`, después de 0022 y 0023.
2. `verificar.sql`: las filas de 0024 deben salir ✅.
3. Publica el frontend nuevo.
