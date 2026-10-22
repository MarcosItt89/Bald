# [Nombre pendiente del proyecto]

> Aplicación web adaptable para gestión operativa, inventario, bitácoras, checklists, evidencias y permisos por rol en empresas con sucursales, áreas operativas y personal distribuido.

---

## Estado del proyecto

Este repositorio contiene la base inicial de una aplicación web pensada para empresas que necesitan controlar inventario, operaciones diarias, pedidos internos, tareas por área, evidencias fotográficas y seguimiento de cumplimiento operativo.

El proyecto se encuentra en etapa inicial de planeación y desarrollo.

Por ahora, el nombre comercial del sistema queda abierto para definirse más adelante.

---

## Posibles nombres del proyecto

| Nombre | Enfoque |
|---|---|
| Gestor Operativo 360 | Control general de operación |
| Sucursal 360 | Empresas con varias tiendas o sucursales |
| OperaFlow | Flujo operativo y seguimiento |
| RetailOps | Operación para retail y supermercados |
| Bitácora Pro | Checklists, evidencias y cumplimiento |
| Inventario+ | Inventario con módulos adicionales |
| ControlStore | Control interno para tiendas |
| StoreFlow | Flujo operativo de tienda |
| CheckOps | Checklists y operación diaria |
| SucursalPro | Gestión profesional por sucursal |
| PuntoControl | Supervisión, inventario y evidencias |
| Operalia | Plataforma operativa adaptable |
| TaskStock | Tareas + inventario |
| BranchOps | Operación por sucursal |
| EvidenceOps | Operación con evidencias |

---

## Idea general de la aplicación

La aplicación busca funcionar como una plataforma interna adaptable para empresas que manejan inventario, personal, áreas operativas, procesos diarios y sucursales.

La idea nace a partir de observar cómo en empresas grandes, como supermercados, existen sistemas internos donde los trabajadores deben registrar actividades diarias, contestar formularios, confirmar procedimientos, escanear áreas o productos, subir evidencias y consultar información relacionada con su puesto.

El objetivo no es crear solamente un sistema de inventario, sino una plataforma operativa modular que pueda adaptarse a diferentes empresas según sus necesidades.

---

## Problema que busca resolver

Muchas empresas tienen operación diaria distribuida en varias áreas, sucursales o departamentos. Esto genera problemas como:

- Falta de trazabilidad en tareas diarias.
- Inventarios desactualizados.
- Pedidos internos hechos por WhatsApp, papel o de forma informal.
- Bitácoras manuales difíciles de revisar.
- Falta de evidencia de que una actividad realmente se realizó.
- Supervisión limitada por parte de gerentes o encargados.
- Personal con acceso a información que no le corresponde.
- Procesos diferentes entre sucursales.
- Dificultad para auditar cumplimiento operativo.
- Pérdida de información entre turnos.
- Falta de control sobre áreas específicas como caja, recibo, carnicería, pescadería, abarrotes, juguetería, almacén, etc.

---

## Solución propuesta

Crear una aplicación web que permita a cada trabajador acceder únicamente a la información, módulos y tareas que corresponden a su puesto, sucursal y área de trabajo.

La aplicación deberá permitir:

- Consultar inventario.
- Registrar pedidos internos.
- Contestar bitácoras o checklists diarios.
- Subir evidencias fotográficas.
- Ver tareas pendientes.
- Revisar alertas operativas.
- Controlar permisos por rol.
- Filtrar información por empresa, sucursal, área, puesto o empleado.
- Dar seguimiento a procedimientos internos.
- Centralizar información operativa en un solo lugar.

---

## Concepto del sistema

El sistema se plantea como una plataforma adaptable por empresa.

Cada empresa podrá tener:

- Sus propias sucursales.
- Sus propias áreas.
- Sus propios puestos.
- Sus propios formularios.
- Sus propios horarios de bitácora.
- Sus propios permisos.
- Sus propios productos.
- Sus propios flujos de aprobación.
- Sus propios tipos de evidencia.

Esto permite que el sistema pueda venderse o adaptarse a diferentes giros, no solamente supermercados.

---

## Empresas o giros donde podría aplicarse

Aunque la idea inicial surge del contexto de supermercados, el sistema puede adaptarse a diferentes industrias:

| Giro | Uso posible |
|---|---|
| Supermercados | Inventario, bitácoras, pedidos, áreas y evidencias |
| Tiendas de conveniencia | Control por sucursal, turnos y productos |
| Farmacias | Inventario, caducidades, pedidos y cumplimiento |
| Restaurantes | Insumos, apertura, cierre, limpieza y pedidos |
| Ferreterías | Stock, productos, sucursales y pedidos |
| Almacenes | Entradas, salidas, recibo y evidencia |
| CEDIS | Control de mercancía, recibo, embarques y auditorías |
| Maquiladoras | Checklists, procesos, evidencias y control operativo |
| Refaccionarias | Inventario, pedidos internos y sucursales |
| Empresas de servicios | Tareas, evidencias y cumplimiento operativo |

---

## Módulos principales planeados

### 1. Dashboard general

Panel principal donde el usuario puede ver información resumida según su rol.

Ejemplos:

- Inventario general.
- Productos en bajo stock.
- Tareas pendientes.
- Checklists del día.
- Evidencias pendientes.
- Pedidos internos.
- Alertas operativas.
- Estado de sucursales.
- Actividades recientes.

---

### 2. Inventario

Módulo para visualizar y administrar productos.

Campos iniciales:

- SKU.
- Nombre del producto.
- Categoría.
- Stock actual.
- Stock mínimo.
- Unidad de medida.
- Sucursal.
- Área responsable.
- Estado del producto.
- Última actualización.

Estados posibles:

- Normal.
- Bajo.
- Crítico.
- Sin stock.
- Pendiente de revisión.

---

### 3. Bitácoras y checklists

Módulo para registrar actividades diarias o por turno.

Ejemplo:

Checklist de apertura de 6:00 AM a 8:00 AM.

Preguntas posibles:

- ¿Se revisó el área asignada?
- ¿Se verificó limpieza?
- ¿Se validó inventario crítico?
- ¿Se reportaron productos dañados?
- ¿Se tomaron fotografías de evidencia?
- ¿Se revisaron temperaturas?
- ¿Se confirmó acomodo de mercancía?
- ¿Se detectaron faltantes?
- ¿Se realizó cierre de turno?

Tipos de respuesta:

- Sí / No.
- Comentario.
- Foto obligatoria.
- Foto opcional.
- Selección múltiple.
- Campo numérico.
- Firma digital.
- Escaneo de código.
- Confirmación de lectura.

---

### 4. Evidencias

Módulo para subir, revisar y consultar fotografías o archivos relacionados con una actividad.

Las evidencias pueden estar ligadas a:

- Una pregunta de checklist.
- Un producto.
- Una sucursal.
- Un área.
- Un pedido.
- Una incidencia.
- Una auditoría.
- Un empleado.
- Un turno.

Las fotos son importantes porque permiten comprobar visualmente que una tarea fue realizada. En empresas operativas, la evidencia ayuda a reducir respuestas falsas, validar condiciones reales, documentar problemas, auditar procesos y dar seguimiento a incidencias.

Ejemplos de evidencia:

- Foto de anaquel.
- Foto de producto dañado.
- Foto de área limpia.
- Foto de refrigerador o vitrina.
- Foto de mercancía recibida.
- Foto de ticket, documento o etiqueta.
- Foto de cierre de caja.
- Foto de inventario físico.
- Foto de área antes y después.

---

### 5. Sucursales

Módulo para administrar diferentes tiendas o ubicaciones.

Campos iniciales:

- Número de tienda.
- Nombre de sucursal.
- Tipo de sucursal.
- Ciudad.
- Estado.
- Dirección.
- Responsable.
- Estatus.
- Horario de operación.

Tipos de sucursal ejemplo:

- Ley.
- Súper Ley.
- Ley Express.
- Tienda grande.
- Tienda mediana.
- Tienda express.
- Almacén.
- CEDIS.
- Restaurante.
- Farmacia.
- Otro.

---

### 6. Empleados

Módulo para administrar trabajadores y su acceso al sistema.

Campos iniciales:

- Código de empleado.
- Nombre.
- Apellido.
- Puesto.
- Área.
- Sucursal.
- Rol del sistema.
- Estado.
- Correo.
- Teléfono.
- Fecha de alta.

La aplicación puede personalizar el acceso del trabajador usando su código de empleado o cuenta de usuario.

---

### 7. Roles y permisos

El sistema debe permitir que cada usuario vea únicamente lo que le corresponde.

Roles iniciales:

| Rol | Alcance |
|---|---|
| Admin general | Puede ver toda la empresa |
| Gerente de sucursal | Puede ver toda su sucursal |
| Supervisor | Puede ver áreas asignadas |
| Empleado de área | Solo ve sus tareas y área |
| Caja | Acceso a caja y procesos relacionados |
| Recibo | Acceso a mercancía recibida |
| Carnicería | Acceso a procesos de carnicería |
| Pescadería | Acceso a procesos de pescadería |
| Abarrotes | Acceso a inventario y tareas de abarrotes |
| Juguetería | Acceso a inventario y tareas de juguetería |

Ejemplo de permisos:

- Un empleado de carnicería no debería ver información de caja.
- Un trabajador de una sucursal no debería ver información de otra sucursal.
- Un gerente debe poder ver todo lo relacionado con su tienda.
- Un administrador general debe poder ver todas las sucursales.
- Un supervisor puede revisar evidencias y checklists de su área.
- Un empleado puede llenar formularios, pero no necesariamente editarlos.

---

### 8. Pedidos internos

Módulo para solicitar mercancía o insumos.

Campos iniciales:

- Producto.
- SKU.
- Cantidad solicitada.
- Área solicitante.
- Sucursal.
- Solicitado por.
- Fecha de solicitud.
- Estado.
- Comentarios.
- Evidencia opcional.

Estados posibles:

- Solicitado.
- En revisión.
- Aprobado.
- Rechazado.
- Enviado.
- Recibido.
- Cerrado.

---

### 9. Procedimientos

Módulo futuro para controlar procedimientos internos por área.

Ejemplos:

- Procedimiento de apertura.
- Procedimiento de cierre.
- Procedimiento de recibo.
- Procedimiento de caja.
- Procedimiento de limpieza.
- Procedimiento de inventario.
- Procedimiento de merma.
- Procedimiento de producto dañado.
- Procedimiento de refrigeración.
- Procedimiento de seguridad.

---

### 10. Reportes

Módulo futuro para generar reportes operativos.

Reportes posibles:

- Checklists completados.
- Checklists pendientes.
- Evidencias faltantes.
- Productos en bajo stock.
- Pedidos por sucursal.
- Incidencias por área.
- Cumplimiento por empleado.
- Cumplimiento por sucursal.
- Actividades por turno.
- Historial de inventario.

---

## Flujo general de uso

### Ejemplo: empleado de área

1. El empleado inicia sesión.
2. El sistema identifica su código de empleado.
3. El sistema detecta su sucursal, área y rol.
4. El empleado ve únicamente sus módulos permitidos.
5. El empleado revisa tareas pendientes.
6. Contesta checklist del día.
7. Sube evidencia si la pregunta lo requiere.
8. Revisa inventario de su área.
9. Solicita mercancía si es necesario.
10. Finaliza sus actividades del turno.

---

### Ejemplo: gerente de sucursal

1. El gerente inicia sesión.
2. El sistema identifica su sucursal.
3. El gerente ve todas las áreas de su tienda.
4. Revisa checklists pendientes.
5. Revisa evidencias subidas por empleados.
6. Consulta productos críticos.
7. Aprueba o revisa pedidos internos.
8. Da seguimiento a incidencias.
9. Supervisa cumplimiento diario.

---

### Ejemplo: administrador general

1. El administrador inicia sesión.
2. Puede ver todas las sucursales.
3. Compara cumplimiento entre tiendas.
4. Revisa reportes generales.
5. Configura usuarios, roles y permisos.
6. Crea checklists.
7. Administra productos y catálogos.
8. Da seguimiento global a la operación.

---

## Arquitectura inicial del proyecto

El proyecto se desarrollará inicialmente con:

- React.
- Vite.
- JavaScript.
- CSS modular o global inicial.
- React Router.
- Datos mock para prototipo.
- Supabase preparado para futura conexión.

---

## Estructura inicial sugerida

```text
src/
  app/
    App.jsx
    routes.jsx

  assets/

  components/
    layout/
      Sidebar.jsx
      Topbar.jsx
      MainLayout.jsx

    ui/
      Card.jsx
      Button.jsx
      Badge.jsx
      Table.jsx

  features/
    auth/
      LoginPage.jsx

    dashboard/
      DashboardPage.jsx

    inventory/
      InventoryPage.jsx
      ProductList.jsx
      ProductCard.jsx

    checklists/
      ChecklistsPage.jsx
      ChecklistCard.jsx
      ChecklistForm.jsx

    branches/
      BranchesPage.jsx

    employees/
      EmployeesPage.jsx

    orders/
      OrdersPage.jsx

    evidence/
      EvidencePage.jsx

    roles/
      RolesPage.jsx

  data/
    mockData.js

  lib/
    supabaseClient.js

  styles/
    global.css

  main.jsx
