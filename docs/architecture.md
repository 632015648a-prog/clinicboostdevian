# ClinicBoost — Arquitectura

## Producto

**Revenue Recovery Layer** para clínicas de fisioterapia privadas en España.
NO es un sistema de gestión clínica — es una capa de automatización sobre el software existente.

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Backend | .NET 10 Minimal API |
| Arquitectura | Vertical Slice (sin Clean Architecture) |
| Base de datos | PostgreSQL via Supabase |
| Multi-tenant | `tenant_id` + RLS + EF Core Global Filters |
| Frontend | React 18 + Vite + TypeScript + Tailwind CSS |
| Auth | JWT en cookies httpOnly (NUNCA localStorage) |
| Mensajería | Twilio (WhatsApp Business + Voice) |
| Scheduler | Hangfire |
| IA | Claude/OpenAI con Function Calling |
| Validación | FluentValidation |
| Resiliencia | Polly (circuit breaker, retry, timeout) |
| Teléfonos | libphonenumber-csharp |
| API docs | Swagger/OpenAPI |

## Estructura del Monorepo

```
clinicboost/
├── apps/
│   ├── api/           # .NET 10 Minimal API (Vertical Slice)
│   │   ├── Domain/    # Entidades + Enums
│   │   ├── Features/  # Vertical Slices (Endpoint.cs, Handler.cs, Request.cs)
│   │   └── Infrastructure/  # Middleware, Persistence, Services
│   └── web/           # React + Vite + TypeScript + Tailwind
│       └── src/
├── supabase/
│   ├── config.toml    # Configuración Supabase CLI
│   ├── migrations/    # SQL migrations (RLS, tablas)
│   └── seed/          # Datos de prueba
├── docs/              # Documentación del proyecto
├── docker/
│   └── nginx/         # Configuración Nginx
├── .github/
│   └── workflows/     # CI/CD
└── docker-compose.yml
```

## Vertical Slice Architecture

Cada feature es autocontenida en su propia carpeta:

```
Features/
├── Appointments/
│   ├── BookSlot/
│   │   ├── Endpoint.cs    # Minimal API endpoint
│   │   ├── Request.cs     # DTO de entrada
│   │   └── Handler.cs     # Lógica de negocio
│   └── GetAvailableSlots/
│       └── Endpoint.cs
├── Auth/Login/
├── Health/
├── Tenants/Register/
└── Webhooks/
    ├── Voice/
    └── WhatsApp/
```

**Reglas:**
- NO usar MediatR ni AutoMapper
- NO repositorios genéricos
- Cada slice accede directamente a `AppDbContext`
- Validación con FluentValidation en cada slice

## Multi-Tenant

- Todas las tablas de negocio llevan `tenant_id` (UUID NOT NULL)
- EF Core aplica filtro global: `.HasQueryFilter(e => e.TenantId == _tenantId)`
- `SaveChangesAsync` asigna `tenant_id` automáticamente a entidades nuevas
- `TenantMiddleware` extrae `TenantId` del JWT y ejecuta `SET LOCAL app.current_tenant_id`
- PostgreSQL RLS refuerza aislamiento a nivel de base de datos
- Usuario de migraciones ≠ usuario de aplicación (app_user NO bypass RLS)

## Seguridad

| Capa | Mecanismo |
|------|-----------|
| Auth | JWT en httpOnly cookies, refresh token con rotación |
| Tenant | RLS + EF Core filters + middleware |
| Descuentos | DiscountGuard con CHECK constraints en DB |
| Webhooks | Validación criptográfica (HMAC-SHA1 Twilio) |
| Timezone | UTC storage + `TimeZoneInfo` (nunca `AddHours`) |
| Idempotencia | Tabla `processed_events` (event_type + event_id) |
| Resiliencia | Circuit breaker + retry + timeout por proveedor |
| CSP | Content Security Policy estricta en Nginx |

## 7+1 Core Flows

| Flow | Nombre | Descripción |
|------|--------|-------------|
| 00 | Onboarding | Consentimiento RGPD + configuración inicial |
| 01 | Llamadas Perdidas | WhatsApp automático tras llamada no contestada |
| 02 | Yield Management | Detección y relleno de huecos de agenda |
| 03 | No-Shows | Reagendado automático de citas no asistidas |
| 04 | Fuera de Horario | Captura de leads fuera del horario |
| 05 | NPS | Encuestas de satisfacción post-sesión |
| 06 | Reactivación | Campañas para pacientes inactivos |
| 07 | Reagendado | Gestión de cambios de cita |

## Reglas de la IA

- La IA **propone**, el backend **ejecuta**
- La IA **NUNCA** confirma citas directamente
- Todas las acciones de IA se auditan en `audit_log`
- Function calling para acciones estructuradas
