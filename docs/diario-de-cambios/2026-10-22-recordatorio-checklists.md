# 📘 Diario de Cambios — Operalia

## 🗓️ Fecha
22 de octubre de 2026

## 🧩 Cambio registrado
**Recordatorio 30 minutos antes de que venza un checklist** que sigue sin completarse. Es la función 1 de 5 del último encargo (0017 en adelante).

---

# 🗄️ Base de datos

## Migración `0017_recordatorio_checklists.sql`
- **`checklist_runs.reminded_at`**: el aviso se manda una sola vez por corrida; en los checklists que se repiten, una vez por ronda.
- **`send_checklist_reminders(empresa, minutos = 30)`**:
  - Busca las corridas de hoy en `pending`, `in_progress` o `reopened` que ya empezaron y vencen en 30 minutos o menos, con la hora de la empresa.
  - Las marca como avisadas y notifica:
    - al **departamento** del checklist en esa sucursal (notificación de departamento de la 0008, llega en vivo);
    - a **quien lo inició**, si no es de ese departamento (p. ej. un gerente que inició un checklist de Cajas);
    - a los **gerentes** de la sucursal, si el checklist no tiene departamento.
  - Mensaje: «Checklist por vencer: <título> (ronda X de Y)» · «Vence a las 17:11 y aún no se inicia / completa».
- **pg_cron**: nuevo job `operalia-recordatorios` cada 5 minutos. El job de la 0012 corre cada hora, demasiado espaciado para avisar con 30 minutos de anticipación.
- **Sin pg_cron**: `run_daily_maintenance` también envía los recordatorios, así que funcionan cada vez que alguien abre Checklists.

---

# ✅ Verificación
- `pendiente.sql` regenerado (24 archivos) y ejecutado dos veces en PGlite sin errores.
- `verificar.sql`: 4 comprobaciones nuevas, en verde. Solo faltan los dos jobs de pg_cron, que no existen en PGlite.
- Prueba en PGlite:

| Caso | Resultado |
|---|---|
| Limpieza de cajas, vence en 20 min, sin iniciar | Aviso al departamento Cajas ✅ |
| Revisión de tarimas, vence en 50 min | Sin aviso ✅ |
| Recolección de carritos, aún no empieza | Sin aviso ✅ |
| Cierre · Seguridad (Gerencia), en progreso, iniciado por el supervisor | Aviso a Gerencia y directo al supervisor ✅ |
| Segunda ejecución | 0 avisos, no se repiten ✅ |
| `cajero` | Ve el aviso de su departamento ✅ |

- `npm run lint` y `npm run build` sin errores. No hubo cambios de frontend: la campana ya muestra los avisos de departamento en vivo.

# 📌 Para aplicar
1. En el SQL Editor: `migrations/0017_recordatorio_checklists.sql`.
2. Para que los avisos lleguen aunque nadie abra la app, **activa pg_cron** (Database → Extensions) y vuelve a ejecutar el archivo.
