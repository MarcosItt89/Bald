# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
5 de noviembre de 2026

## 🧩 Cambio registrado
**Rendimiento en cascada: el superadmin ve las tiendas, cada tienda ve sus sucursales y cada gerente ve la suya. El menú del superadmin pone Plataforma primero.**

---

# 🐞 Error en producción: «Could not find the function public.platform_list_companies»
- **Causa:** en la base de producción **no se había corrido la migración 0024**.
  - Estaban aplicadas 0022, 0023, 0025 y 0026, pero no existía ninguna función de 0024 (`platform_list_companies`, `provision_company`, `platform_set_company_status` y el soporte de plataforma).
  - Se comprobó llamando a la API con la llave pública: las funciones de 0025 respondían «permission denied» (existen) y las de 0024, «not found».
- **Solución:** correr `0024`, después `0026` otra vez (re-ejecutable: quita a `anon` las funciones nuevas) y luego `0027`.
- **Cómo detectarlo:** `verificar.sql` marca ❌ en las filas de la migración que falte.

# 🗄️ Migración `0027_rendimiento_en_cascada.sql`
El mismo tablero de 0025 en cada nivel, sin duplicar el cálculo:

| Función | Para quién | Alcance |
|---|---|---|
| `perf_kpis`, `perf_trend`, `perf_heatmap` | Internas: la API no puede llamarlas | Son el cálculo de 0025, copiado tal cual, con dos parámetros: empresa y lista de sucursales |
| `platform_company_kpis`, `platform_company_trend`, `platform_checklist_heatmap` | Superadmin | Todas las empresas (misma firma y resultado que en 0025) |
| `branch_kpis`, `branch_trend`, `branch_checklist_heatmap` | Cualquier empleado con `view_reports` | Su empresa y solo las sucursales que puede ver (`can_access_branch`) |

**Comprobado con los usuarios demo:**

| Usuario | Qué devuelve `branch_kpis` |
|---|---|
| Propietaria de Súper La Luna | Sus 4 sucursales y el total |
| Gerente de La Luna Centro | Solo su sucursal. Si pide la tendencia de otra, recibe «Sucursal no permitida» |
| Jefe de zona de Gato Pelón | Las 2 sucursales de sus zonas |
| Cajero | Error: no tiene `view_reports` |

- **Plataforma:** devuelve los mismos números que antes.
- **Prueba de aislamiento:** suma dos comprobaciones de cascada:
  - `branch_kpis` nunca devuelve filas de otra empresa;
  - nunca devuelve sucursales fuera del alcance de quien consulta.

  Sigue en **0 ❌**.

# 💻 Frontend
- **Inicio según el rol:**
  - el superadmin entra a **Plataforma → Rendimiento**; los demás, al Dashboard;
  - «Ir al inicio», el login y el cambio de contraseña llevan a `/`, que decide a dónde ir.
- **Menú del superadmin:**
  - Plataforma va primero;
  - la operación de su empresa (Dashboard, Inventario, etc.) queda en **«Operación de Gato Pelón»**, una sección plegable cerrada por defecto. Se recuerda en el dispositivo y se abre sola si la página actual está ahí;
  - conserva todos sus permisos; solo no los ve hasta que los busca;
  - el encabezado dice «Plataforma» y el pie, «Superadmin · Administrador».
- **Plataforma → Rendimiento** tiene ahora selector de tienda arriba.
  - Clic en una empresa del ranking → `?empresa=…`: los totales, el ranking, la tendencia y el mapa de calor pasan a ser de esa empresa y sus sucursales.
  - La «✕» del filtro regresa a toda la plataforma.
- **Análisis → Rendimiento de sucursales** (`/reports/sucursales`, permiso `view_reports`):
  - es el mismo tablero con las sucursales de la propia empresa y selector de sucursal;
  - cada nivel ve lo suyo: el propietario y los administradores, todas las sucursales; el jefe de zona, las de su zona; el gerente, la suya;
  - para bajar al detalle de una sucursal (por departamento, checklist o producto) sigue Estadísticas.
- **Código:** `PerformancePage` recibe `scope` (`platform` o `company`). El servicio de la empresa vive en `reportService` (`getBranchKpis`, `getBranchTrend`, `getBranchHeatmap`).

# ✅ Pruebas
- **Instalador completo:** corre dos veces sin errores.
- **Prueba de aislamiento:** 0 ❌, con 435 pruebas.
- **Cascada:** se probó por usuario (tabla de arriba).
- **Pantallas:** se revisaron con Supabase simulado:
  - el inicio del superadmin y el menú plegado y abierto;
  - el clic en una empresa del ranking;
  - Rendimiento de sucursales.
- `npm run lint` y `npm run build` pasan.

# ▶️ Qué correr en Supabase (en este orden)
1. `migrations/0024_plataforma_empresas_soporte.sql`: la que faltaba.
2. `migrations/0026_aislamiento_empresas.sql`, otra vez.
3. `migrations/0027_rendimiento_en_cascada.sql`.
4. `verificar.sql`: todas las filas de 0024 a 0027 deben salir ✅.
