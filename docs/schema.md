# ClinicBoost — Esquema de Base de Datos

**Migración:** `supabase/migrations/00000000000002_base_schema.sql`  
**Motor:** PostgreSQL 15+ (Supabase)  
**Validado:** ✅ 0 errores en PostgreSQL 15.16

---

## Resumen de tablas

| # | Tabla | tenant_id | RLS | Append-only | Propósito |
|---|-------|-----------|-----|-------------|-----------|
| 1 | `tenants` | — (ES el tenant) | ❌ | ❌ | Clínicas registradas. Nodo raíz multi-tenant |
| 2 | `tenant_users` | ✅ NOT NULL | ✅ | ❌ | Staff y administradores de cada clínica |
| 3 | `patients` | ✅ NOT NULL | ✅ | ❌ | Pacientes. Phone E.164 único por tenant |
| 4 | `patient_consents` | ✅ NOT NULL | ✅ | ✅ | Historial inmutable de consentimientos RGPD |
| 5 | `calendar_connections` | ✅ NOT NULL | ✅ | ❌ | Integraciones iCal / Google / Outlook |
| 6 | `appointments` | ✅ NOT NULL | ✅ | ❌ | Citas con trazabilidad de flow y canal |
| 7 | `appointment_events` | ✅ NOT NULL | ✅ | ✅ | Log inmutable del ciclo de vida de citas |
| 8 | `conversations` | ✅ NOT NULL | ✅ | ❌ | Hilos de conversación WhatsApp / voz |
| 9 | `messages` | ✅ NOT NULL | ✅ | ✅ | Mensajes individuales por conversación |
| 10 | `waitlist_entries` | ✅ NOT NULL | ✅ | ❌ | Lista de espera con TTL de respuesta |
| 11 | `rule_configs` | ✅ NOT NULL | ✅ | ❌ | Reglas de automatización con DiscountGuard |
| 12 | `revenue_events` | ✅ NOT NULL | ✅ | ✅ | Revenue Tracker: ingresos recuperados |
| 13 | `automation_runs` | ✅ NOT NULL | ✅ | parcial | Ejecuciones de flows (Hangfire jobs) |
| 14 | `webhook_events` | nullable | ✅ | parcial | Webhooks raw "store first, process later" |
| 15 | `processed_events` | nullable | ❌ | ✅ | Idempotencia global (event_type + event_id) |
| 16 | `audit_logs` | nullable | ❌ | ✅ | Auditoría de operaciones sensibles |

---

## Convenciones

| Aspecto | Convención |
|---------|-----------|
| PKs | `UUID` con `gen_random_uuid()` en todas las tablas |
| Timestamps | `TIMESTAMPTZ` (siempre UTC). La app convierte a local con `TimeZoneInfo` |
| Enums | `TEXT` + `CHECK constraint` (legibilidad en DB, fácil extensión) |
| Nombres | `snake_case` (convención PostgreSQL) |
| Multi-tenant | `tenant_id UUID NOT NULL` + FK a `tenants` + RLS |
| Teléfonos | Formato E.164 (validado por `libphonenumber-csharp` en la app) |

---

## Seguridad multi-capa

```
Request HTTP
    │
    ▼
TenantMiddleware (.NET)
    │  extrae TenantId del JWT
    │  ejecuta: SET LOCAL app.current_tenant_id = '<uuid>'
    ▼
EF Core Global Filters
    │  .HasQueryFilter(e => e.TenantId == _currentTenantId)
    ▼
PostgreSQL RLS (última línea de defensa)
    │  tenant_id = current_tenant_id()
    ▼
app_user (sin BYPASSRLS)
```

---

## Índices críticos

### Por tabla

#### `tenants`
| Índice | Columnas | Tipo | Propósito |
|--------|----------|------|-----------|
| `uq_tenants_slug` | `slug` | UNIQUE | Lookup por URL slug |
| `idx_tenants_subscription_status` | `subscription_status` WHERE `is_active` | BTREE | Billing activo |

#### `patients`
| Índice | Columnas | Tipo | Propósito |
|--------|----------|------|-----------|
| `uq_patients_tenant_phone` | `(tenant_id, phone)` | UNIQUE | Lookup de webhook Twilio |
| `idx_patients_last_visit` | `(tenant_id, last_visit_date)` WHERE activo | BTREE | Flow 06 Reactivación |
| `idx_patients_name_trgm` | `name` | GIN/trigram | Búsqueda por nombre parcial |

#### `appointments`
| Índice | Columnas | Tipo | Propósito |
|--------|----------|------|-----------|
| `idx_appointments_tenant_date` | `(tenant_id, starts_at)` WHERE no cancelada | BTREE | Consultas de agenda |
| `idx_appointments_reminder` | `(tenant_id, starts_at)` WHERE Confirmed+sin_reminder | BTREE | Job de recordatorios |
| `idx_appointments_noshows` | `(tenant_id, starts_at)` WHERE NoShow | BTREE | Flow 03 No-Shows |
| `idx_appointments_recovered` | `(tenant_id, source_flow)` WHERE recovered | BTREE | Revenue Tracker |

#### `processed_events`
| Índice | Columnas | Tipo | Propósito |
|--------|----------|------|-----------|
| `uq_processed_events_type_id` | `(event_type, event_id)` | UNIQUE | **Idempotencia** |

#### `rule_configs`
| Índice | Columnas | Tipo | Propósito |
|--------|----------|------|-----------|
| `uq_rule_configs_tenant_type` | `(tenant_id, rule_type)` WHERE activo | UNIQUE | Una regla activa por tipo |

---

## Patrones especiales

### Append-only (tablas inmutables)
Las siguientes tablas tienen `CREATE POLICY ... FOR UPDATE USING (false)` y `FOR DELETE USING (false)`:
- `patient_consents` — evidencia RGPD
- `appointment_events` — log de ciclo de vida
- `revenue_events` — registro financiero
- `audit_logs` — auditoría legal
- `processed_events` — registro de idempotencia
- `messages` — historial de conversación

### DiscountGuard
`rule_configs` tiene dos niveles de protección:
1. `CHECK (min_discount_pct >= 0 AND min_discount_pct <= 50)`
2. `CHECK (max_discount_pct >= 0 AND max_discount_pct <= 50)`
3. `CHECK (min_discount_pct <= max_discount_pct)` — impide rangos invertidos

### Idempotencia
`IdempotencyService` verifica `processed_events` antes de procesar cualquier webhook:
```sql
INSERT INTO processed_events (event_type, event_id)
VALUES ('VoiceWebhook', 'CAxxxxx')
ON CONFLICT (event_type, event_id) DO NOTHING
RETURNING id;
-- Si 0 rows: ya procesado, descartar silenciosamente
```

### Store-first webhooks
`webhook_events` almacena el payload raw antes de cualquier lógica:
1. Webhook llega → INSERT inmediato en `webhook_events`
2. Hangfire job lee `processed = false` → procesa → UPDATE `processed = true`
3. Permite reprocessing manual desde el dashboard

---

## Relación con los 7+1 Flows

| Flow | Tablas principales |
|------|-------------------|
| Flow 00 — Onboarding | `tenants`, `tenant_users`, `patient_consents` |
| Flow 01 — Llamadas Perdidas | `webhook_events`, `patients`, `conversations`, `messages`, `appointments` |
| Flow 02 — Yield Management | `appointments`, `waitlist_entries`, `messages` |
| Flow 03 — No-Shows | `appointments`, `appointment_events`, `waitlist_entries` |
| Flow 04 — Fuera de Horario | `webhook_events`, `conversations`, `messages`, `appointments` |
| Flow 05 — NPS | `appointments`, `messages`, `audit_logs` |
| Flow 06 — Reactivación | `patients` (last_visit_date), `rule_configs`, `messages` |
| Flow 07 — Reagendado | `appointments`, `appointment_events`, `conversations` |
| Todos | `automation_runs`, `revenue_events`, `audit_logs`, `processed_events` |
