# Checklist de Validación — Bloque 0

## Estructura de Carpetas

- [x] `apps/api/` — .NET 10 Minimal API con VSA
- [x] `apps/web/` — React + Vite + TypeScript + Tailwind
- [x] `supabase/` — Config + migrations + seed
- [x] `docs/` — Documentación del proyecto
- [x] `.github/` — CI workflows + PR templates
- [x] `docker/` — Nginx config

## Backend (apps/api)

- [x] `Program.cs` con pipeline completo (CORS, JWT, Swagger, Middleware)
- [x] 13 entidades del dominio con `TenantEntity` base
- [x] 10 enums (AppointmentStatus, SourceFlow, BookingChannel, etc.)
- [x] `AppDbContext` con filtros globales multi-tenant
- [x] `SaveChangesAsync` override para asignar `tenant_id`
- [x] `TenantMiddleware` (JWT cookie → RLS SET LOCAL)
- [x] `TwilioSignatureMiddleware` (HMAC-SHA1)
- [x] `TimezoneService` (UTC + Europe/Madrid, sin AddHours)
- [x] `IdempotencyService` (processed_events)
- [x] `TwilioSMSService` (stub)
- [x] Health checks (/health, /health/ready)
- [x] Feature stubs (Auth, Tenants, Appointments, Webhooks)
- [x] Dockerfile multi-stage

## Frontend (apps/web)

- [x] React 18 + Vite + TypeScript
- [x] Tailwind CSS 4 via `@tailwindcss/vite`
- [x] Dashboard scaffold con estado del API
- [x] Grid de flows (01-06)
- [x] Proxy a API configurado en `vite.config.ts`
- [x] ESLint configurado
- [x] Dockerfile

## Infraestructura

- [x] `docker-compose.yml` (db, api, web, nginx)
- [x] Nginx con security headers + CSP
- [x] `.env.example` con todas las variables
- [x] `.gitignore` completo
- [x] `.editorconfig`
- [x] `global.json` (.NET 10 pinned)

## Supabase

- [x] `config.toml` para Supabase CLI
- [x] Migración inicial con extensiones + tabla tenants
- [x] Políticas RLS (plantilla)
- [x] Datos seed para desarrollo

## Compilación

- [x] `dotnet build` sin errores
- [x] `npm run build` sin errores
- [x] `npm run lint` sin errores

## Reglas Arquitectónicas

- [x] Sin MediatR
- [x] Sin AutoMapper
- [x] Sin repositorios genéricos
- [x] JWT en cookies httpOnly (no localStorage)
- [x] Timezone via servicio (no AddHours)
- [x] Vertical Slice Architecture
- [x] Multi-tenant con tenant_id en todas las entidades
