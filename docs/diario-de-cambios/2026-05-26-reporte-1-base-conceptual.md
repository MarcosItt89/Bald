# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
26 de mayo de 2026

## 🧩 Cambio registrado
Definición oficial del nombre del proyecto, organización conceptual de la aplicación, identificación del problema principal, comparación contra soluciones existentes y definición preliminar de herramientas, objetivos y diferenciadores.

---

# 🚀 Nombre oficial del proyecto

## **Operalia**

### Frase conceptual

> **Operalia es una plataforma operativa modular para empresas con sucursales, inventario, empleados, proveedores, checklists, evidencias y procesos internos que necesitan control, trazabilidad y orden diario.**

---

# 👥 Creadores del proyecto

Este proyecto es desarrollado inicialmente por:

- **Ramírez Guerra Marcos Yerán**
- **Arámbula García Sarahy**

---

# 🧠 Idea principal

Operalia nace como una aplicación web pensada para ayudar a empresas que necesitan controlar su operación diaria desde un solo sistema.

La idea inicial surge al observar cómo empresas con múltiples sucursales, como supermercados, utilizan aplicaciones internas para controlar actividades por departamento, registrar bitácoras, escanear productos, consultar precios, dar entrada a proveedores, registrar mercancía recibida, revisar inventarios, controlar cambios de precio y generar evidencias de cumplimiento.

Operalia busca tomar esa lógica operativa y convertirla en una plataforma flexible que pueda adaptarse a diferentes empresas, giros y formas de trabajo.

---

# 🏢 Tipo de aplicación

Operalia no debe entenderse únicamente como un sistema de inventario.

Debe entenderse como una:

## **Plataforma de operación empresarial**

Que combina:

- 📦 Inventario
- 🧾 Recibo de mercancía
- 🏪 Sucursales
- 👥 Empleados
- 🧑‍💼 Roles y permisos
- ✅ Checklists
- 📋 Bitácoras
- 📸 Evidencias fotográficas
- 🚚 Proveedores
- 🛒 Pedidos internos
- 🏷️ Cambios de precio
- 🪧 Cenefas
- 📊 Reportes
- 🧭 Supervisión operativa
- 🔐 Control de accesos

---

# 🧩 Problema que se busca resolver

Muchas empresas operan con procesos diarios que se repiten todos los días, pero que no siempre quedan correctamente documentados.

En negocios con sucursales, departamentos y varios empleados, suelen existir problemas como:

- ❌ Inventarios desactualizados.
- ❌ Falta de evidencia de actividades realizadas.
- ❌ Bitácoras en papel o sistemas separados.
- ❌ Pedidos internos hechos por WhatsApp o verbalmente.
- ❌ Falta de control sobre proveedores.
- ❌ Procesos diferentes entre sucursales.
- ❌ Cambios de precio sin trazabilidad.
- ❌ Cenefas no colocadas o no verificadas.
- ❌ Supervisores sin visibilidad en tiempo real.
- ❌ Empleados viendo información que no les corresponde.
- ❌ Reportes difíciles de auditar.
- ❌ Falta de historial sobre quién hizo qué, cuándo y dónde.
- ❌ Dificultad para saber si una tarea realmente se cumplió.

---

# 🎯 Objetivo general

Crear una aplicación web modular que permita a empresas organizar, controlar y supervisar su operación diaria desde una sola plataforma, adaptando la información visible según el rol, sucursal, departamento y permisos del empleado.

---

# 🎯 Objetivos específicos

## 1. Centralizar la operación diaria

Unificar en una sola plataforma actividades como inventario, checklists, bitácoras, recibo de mercancía, pedidos internos, evidencias y reportes.

---

## 2. Controlar accesos por empleado

Permitir que cada usuario vea únicamente los módulos y datos que le corresponden según:

- Empresa
- Sucursal
- Departamento
- Puesto
- Rol
- Permisos

---

## 3. Mejorar la trazabilidad

Registrar quién hizo cada actividad, en qué momento, desde qué sucursal, en qué departamento y con qué evidencia.

---

## 4. Reducir errores operativos

Disminuir errores relacionados con inventario, entrada de mercancía, precios, pedidos internos, cambios de cenefas y cumplimiento de tareas.

---

## 5. Digitalizar checklists y bitácoras

Permitir que actividades recurrentes, como apertura, cierre, limpieza, recibo, revisión de áreas o supervisión diaria, puedan registrarse digitalmente.

---

## 6. Usar evidencia fotográfica

Solicitar fotos cuando una actividad lo requiera, para validar visualmente que una tarea fue realizada correctamente.

---

## 7. Preparar reportes operativos

Generar información útil para gerentes, supervisores y administradores.

---

# 🧑‍💼 Usuarios principales

Operalia está pensada para diferentes tipos de usuarios dentro de una empresa.

| Usuario | Uso principal |
|---|---|
| Admin general | Configura empresa, sucursales, roles, permisos y módulos |
| Gerente de sucursal | Supervisa toda la operación de una tienda o unidad |
| Supervisor | Revisa tareas, checklists y evidencias por departamento |
| Empleado de departamento | Llena checklists, consulta inventario y registra actividades |
| Caja | Consulta precios y reporta incidencias relacionadas |
| Recibo | Registra proveedores, mercancía, cantidades, peso y diferencias |
| Almacén | Controla entradas, salidas y existencias |
| Carnicería | Registra actividades específicas de su área |
| Pescadería | Registra procesos propios de su departamento |
| Abarrotes | Consulta productos, pedidos y existencias |
| Juguetería | Controla inventario y tareas de temporada |

---

# 🧱 Módulos planeados

## 📊 1. Dashboard

Panel principal donde cada usuario verá información personalizada según su rol.

Puede incluir:

- Tareas pendientes
- Checklists del día
- Evidencias pendientes
- Productos con bajo stock
- Pedidos pendientes
- Recibos recientes
- Cambios de precio pendientes
- Alertas por departamento
- Actividad reciente

---

## 📦 2. Inventario

Módulo para consultar y controlar productos.

Campos contemplados:

- SKU
- Código de barras
- Nombre del producto
- Categoría
- Departamento
- Existencia actual
- Stock mínimo
- Stock máximo
- Precio actual
- Sucursal
- Estado
- Última actualización

Estados posibles:

- Normal
- Bajo stock
- Crítico
- Sin existencia
- Pendiente de revisión

---

## 🔎 3. Consulta de precios

Módulo para que empleados puedan consultar precios rápidamente.

Funciones contempladas:

- Buscar por nombre
- Buscar por SKU
- Buscar por código de barras
- Escanear producto
- Ver precio actual
- Ver precio anterior
- Ver fecha de último cambio
- Ver si requiere cenefa nueva

Este módulo puede ser útil para caja, piso de venta, abarrotes, departamentos y personal de atención al cliente.

---

## 🚚 4. Proveedores

Módulo para administrar proveedores y sus movimientos.

Campos contemplados:

- Código de proveedor
- Nombre del proveedor
- Razón social
- Tipo de mercancía
- Contacto
- Teléfono
- Correo
- Estatus
- Historial de visitas
- Documentos asociados

---

## 📥 5. Recibo de mercancía

Módulo clave para registrar entrada de producto.

Funciones contempladas:

- Registrar llegada de proveedor
- Validar código de proveedor
- Registrar hora de entrada
- Registrar hora de salida
- Registrar factura o remisión
- Registrar productos recibidos
- Registrar cantidades
- Registrar peso
- Registrar diferencias
- Registrar producto dañado
- Subir evidencia
- Generar resumen de recibo

---

## 🧾 6. Resumen de mercancía recibida

Módulo para concentrar lo que entró a la empresa o sucursal.

Puede incluir:

- Proveedor
- Fecha
- Hora
- Productos recibidos
- Cantidades
- Pesos
- Diferencias
- Evidencias
- Usuario responsable
- Estado del recibo

---

## ✅ 7. Checklists

Módulo para formularios operativos por horario, sucursal o departamento.

Ejemplos:

- Checklist de apertura
- Checklist de cierre
- Checklist de limpieza
- Checklist de recibo
- Checklist de caja
- Checklist de refrigeración
- Checklist de seguridad
- Checklist de anaqueles
- Checklist de producto dañado

Tipos de respuesta:

- Sí / No
- Texto
- Número
- Selección múltiple
- Foto obligatoria
- Foto opcional
- Comentario
- Firma o confirmación

---

## 📋 8. Bitácoras

Módulo para registrar actividades diarias.

Ejemplo:

> De 6:00 AM a 8:00 AM, el empleado debe confirmar que revisó su área, validar limpieza, verificar productos críticos, tomar evidencia y registrar incidencias.

Las bitácoras permiten crear disciplina operativa y documentar tareas repetitivas.

---

## 📸 9. Evidencias

Módulo para subir y revisar fotografías o archivos.

Las evidencias pueden relacionarse con:

- Checklist
- Bitácora
- Producto
- Pedido
- Recibo
- Proveedor
- Cambio de precio
- Cenefa
- Tarea
- Incidencia

Estados posibles:

- Pendiente
- Aprobada
- Rechazada
- Requiere corrección

---

## 🛒 10. Pedidos internos

Módulo para solicitar mercancía o insumos.

Campos contemplados:

- Producto
- SKU
- Cantidad solicitada
- Departamento solicitante
- Sucursal
- Solicitado por
- Aprobado por
- Estado
- Comentarios
- Evidencia opcional

Estados posibles:

- Solicitado
- En revisión
- Aprobado
- Rechazado
- Enviado
- Recibido
- Cerrado

---

## 🏷️ 11. Cambios de precio

Módulo para controlar actualizaciones de precios.

Campos contemplados:

- Producto
- SKU
- Precio anterior
- Precio nuevo
- Fecha efectiva
- Usuario responsable
- Departamento responsable
- Requiere cenefa
- Estado del cambio

---

## 🪧 12. Cenefas

Módulo para controlar etiquetas o señalización de precio en tienda.

Estados posibles:

- Pendiente
- Impresa
- Colocada
- Validada
- Rechazada

La cenefa puede requerir evidencia fotográfica para confirmar que fue colocada correctamente.

---

## 🧭 13. Tareas operativas

Módulo para asignar y dar seguimiento a tareas.

Campos contemplados:

- Título de la tarea
- Descripción
- Departamento
- Responsable
- Sucursal
- Fecha límite
- Evidencia requerida
- Estado
- Comentarios

---

## 📊 14. Reportes

Módulo futuro para análisis operativo.

Reportes posibles:

- Cumplimiento por sucursal
- Cumplimiento por departamento
- Checklists completados
- Checklists pendientes
- Evidencias rechazadas
- Productos con bajo stock
- Pedidos por estado
- Recibos por proveedor
- Cambios de precio pendientes
- Cenefas no validadas
- Actividad por empleado

---

# 🛠️ Herramientas que se usarán en el proyecto

## Frontend

| Herramienta | Uso |
|---|---|
| React | Construcción de la interfaz |
| Vite | Entorno de desarrollo rápido para React |
| JavaScript | Lenguaje principal del frontend |
| CSS | Estilos iniciales |
| React Router DOM | Navegación entre páginas |
| Lucide React | Íconos modernos para interfaz |

React recomienda usar una herramienta de build como Vite para crear aplicaciones modernas desde cero, y Vite ofrece plantillas oficiales para iniciar proyectos, incluyendo React con JavaScript. :contentReference[oaicite:0]{index=0}

---

## Backend y base de datos

| Herramienta | Uso |
|---|---|
| Supabase | Backend, base de datos, autenticación y storage |
| PostgreSQL | Base de datos relacional |
| Supabase Auth | Login y usuarios |
| Supabase Storage | Fotos y evidencias |
| Row Level Security | Seguridad por usuario, empresa, sucursal y departamento |
| SQL Triggers | Automatizaciones internas de base de datos |

Supabase se define como una plataforma de desarrollo basada en PostgreSQL que incluye base de datos, autenticación, APIs instantáneas, funciones, realtime y storage. :contentReference[oaicite:1]{index=1}

---

## Desarrollo y control de versiones

| Herramienta | Uso |
|---|---|
| Visual Studio Code | Editor de código |
| Claude Code | Asistencia en desarrollo |
| Skills.sh | Skills de apoyo para Claude |
| Git | Control de versiones |
| GitHub | Repositorio del proyecto |
| Markdown | Documentación técnica y diario de cambios |

---

# 🗃️ Base de datos contemplada

Operalia utilizará una base de datos relacional porque la información estará conectada entre múltiples entidades.

Ejemplo:

> Un empleado pertenece a una empresa, trabaja en una sucursal, pertenece a un departamento, tiene un rol, cuenta con permisos, puede llenar checklists, subir evidencias, solicitar mercancía y registrar actividades.

Por eso, la base de datos debe estar bien organizada desde el inicio.

---

## Tablas principales contempladas

| Tabla | Propósito |
|---|---|
| companies | Empresas que usan Operalia |
| branches | Sucursales o unidades de negocio |
| departments | Departamentos o áreas internas |
| employees | Empleados registrados |
| roles | Roles del sistema |
| permissions | Permisos disponibles |
| role_permissions | Relación entre roles y permisos |
| employee_permissions | Permisos especiales por empleado |
| products | Catálogo de productos |
| product_barcodes | Códigos de barras por producto |
| inventory | Existencias por sucursal y departamento |
| inventory_movements | Historial de entradas y salidas |
| suppliers | Proveedores |
| supplier_visits | Entrada y salida de proveedores |
| receiving_orders | Recibos de mercancía |
| receiving_items | Productos recibidos |
| price_changes | Cambios de precio |
| shelf_tags | Cenefas |
| checklists | Formularios operativos |
| checklist_questions | Preguntas de formularios |
| checklist_answers | Respuestas de empleados |
| evidence_files | Fotos y archivos de evidencia |
| orders | Pedidos internos |
| order_items | Productos solicitados |
| tasks | Tareas operativas |
| audit_logs | Historial de acciones |

---

# ⚙️ Triggers contemplados

Los triggers ayudarán a automatizar procesos dentro de la base de datos.

## Triggers futuros

| Trigger | Función |
|---|---|
| updated_at automático | Actualiza fecha de modificación |
| movimiento de inventario | Registra entradas y salidas |
| bajo stock | Marca producto como bajo o crítico |
| recibo completado | Genera resumen de mercancía recibida |
| cambio de precio | Marca cenefa como pendiente |
| checklist completado | Cambia estado al responder todas las preguntas |
| evidencia obligatoria | Evita cerrar si falta foto requerida |
| audit log | Registra acciones importantes |

---

# 🔐 Políticas de seguridad contempladas

Operalia deberá usar políticas de seguridad para que cada usuario vea solamente lo que le corresponde.

## Reglas base

| Usuario | Acceso esperado |
|---|---|
| Admin general | Toda la empresa |
| Gerente | Toda su sucursal |
| Supervisor | Departamentos asignados |
| Empleado | Solo su departamento |
| Caja | Consulta de precios y tareas propias |
| Recibo | Proveedores y recibo de mercancía |
| Almacén | Inventario y movimientos |
| Auditor | Reportes y evidencias autorizadas |

## Criterios de filtrado

La información deberá filtrarse por:

- company_id
- branch_id
- department_id
- employee_id
- role_id
- permissions

---

# 🧠 Diferenciador de Operalia

Operalia no busca competir únicamente como checklist, inventario o app de tareas.

Su diferencia es integrar operación diaria real en una sola plataforma modular.

---

## Comparación conceptual

| Sistema / enfoque | Qué resuelve | Limitación observada | Cómo se diferencia Operalia |
|---|---|---|---|
| Checklist digital | Controla tareas y formularios | Puede quedarse solo en cumplimiento | Operalia conecta checklist con inventario, evidencia, empleados, sucursales y reportes |
| Inventario tradicional | Controla existencias | No siempre controla tareas ni evidencias | Operalia conecta inventario con pedidos, recibo, proveedores, precios y departamentos |
| App de tareas | Asigna pendientes | No necesariamente valida cumplimiento operativo | Operalia puede exigir evidencia, horario, responsable y sucursal |
| Sistema de recibo | Registra mercancía | Puede estar separado de inventario y proveedores | Operalia integra proveedor, entrada, producto, cantidad, peso, evidencia e inventario |
| Plataforma tipo Jarboss Work | Checklists, rondines, actividades y reportes | Su enfoque principal está en checklists, inspecciones y reportes | Operalia busca integrar además inventario, precios, recibo, proveedores, cenefas y operación por departamento |
| Plataforma tipo Binnacle | Control operativo y procesos por sucursal | Se enfoca en centralizar y digitalizar procesos operativos | Operalia se enfocará en operación interna adaptable con inventario, precios, proveedores y módulos departamentales |

Jarboss Work se presenta como una herramienta para checklists, actividades, rondines, reportes automáticos e inspecciones. :contentReference[oaicite:2]{index=2}  
Binnacle se describe como una plataforma digital para empresas con múltiples sucursales que centraliza, digitaliza y mejora procesos operativos con visibilidad en tiempo real. :contentReference[oaicite:3]{index=3}

---

# 🧩 Qué atacamos diferente

Operalia busca atacar un problema más amplio:

## No solo cumplimiento

No basta con decir:

> “La tarea se hizo.”

Operalia busca saber:

- Quién la hizo.
- A qué hora.
- En qué sucursal.
- En qué departamento.
- Con qué evidencia.
- Qué producto afectó.
- Si generó un pedido.
- Si cambió el inventario.
- Si requiere aprobación.
- Si impacta un reporte.
- Si hay seguimiento pendiente.

---

## No solo inventario

Un producto no es solamente una cantidad.

También puede tener:

- Precio
- Código de barras
- Proveedor
- Departamento
- Stock mínimo
- Última entrada
- Último cambio de precio
- Cenefa pendiente
- Evidencia relacionada
- Historial de movimientos
- Pedido interno
- Incidencias

---

## No solo empleados

Un empleado no es solamente un usuario.

También tiene:

- Código de empleado
- Sucursal
- Departamento
- Puesto
- Rol
- Permisos
- Tareas asignadas
- Checklists pendientes
- Historial de actividad
- Evidencias subidas
- Restricciones de acceso

---

# 📌 Principios del proyecto

## 1. Modularidad

El sistema debe crecer por módulos.

Una empresa puede necesitar solo inventario y checklists, mientras otra puede necesitar proveedores, recibo, precios, evidencias y reportes.

---

## 2. Adaptabilidad

Operalia debe poder adaptarse a diferentes giros:

- Supermercados
- Tiendas
- Farmacias
- Ferreterías
- Restaurantes
- Almacenes
- CEDIS
- Maquiladoras
- Refaccionarias
- Empresas de servicios

---

## 3. Trazabilidad

Toda acción importante debe dejar registro.

---

## 4. Evidencia

Cuando una tarea requiere prueba visual, el sistema debe permitir o exigir fotografía.

---

## 5. Seguridad por rol

Cada empleado debe ver solo lo que necesita para trabajar.

---

## 6. Escalabilidad

La estructura debe permitir crecer de una empresa pequeña a una empresa con varias sucursales.

---

# 🧭 Alcance inicial del proyecto

En esta etapa no se construirá toda la aplicación final.

El objetivo inicial es crear:

- Estructura limpia del proyecto
- Rutas principales
- Dashboard base
- Módulos placeholder
- Datos mock
- Preparación para Supabase
- Documentación del concepto
- Base para desarrollo incremental

---

# ✅ Cambios realizados o definidos en esta etapa

- ✅ Se definió el nombre oficial del proyecto: **Operalia**
- ✅ Se definió el enfoque principal como plataforma operativa modular
- ✅ Se identificaron módulos principales
- ✅ Se identificó problemática empresarial
- ✅ Se definieron usuarios principales
- ✅ Se contempló arquitectura por sucursal, departamento y rol
- ✅ Se definieron herramientas iniciales
- ✅ Se contempló Supabase como backend principal
- ✅ Se documentaron tablas futuras
- ✅ Se documentaron triggers futuros
- ✅ Se documentaron políticas de seguridad futuras
- ✅ Se comparó conceptualmente contra soluciones existentes
- ✅ Se definió el diferenciador de Operalia

---

# 🚧 Pendientes inmediatos

- [ ] Confirmar estructura final de carpetas en React
- [ ] Crear rutas principales
- [ ] Crear páginas placeholder por módulo
- [ ] Crear layout base con sidebar y topbar
- [ ] Crear mockData inicial
- [ ] Configurar conexión segura con Supabase usando `.env`
- [ ] Crear primeras tablas reales en Supabase
- [ ] Definir si el primer prototipo será enfocado en supermercado o multiempresa
- [ ] Definir colores e identidad visual
- [ ] Crear README principal del repositorio
- [ ] Crear carpeta de documentación técnica

---

# 🗂️ Estructura documental sugerida

```text
docs/
  diario-de-cambios/
    2026-05-26-operalia-base-conceptual.md

  arquitectura/
    estructura-frontend.md
    modelo-base-datos.md
    roles-y-permisos.md

  producto/
    problematica.md
    propuesta-de-valor.md
    roadmap.md
