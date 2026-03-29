# ClinicBoost

**Revenue Recovery Layer** para clínicas de fisioterapia privadas en España.

ClinicBoost automatiza la recuperación de ingresos perdidos: llamadas no contestadas, huecos de agenda, no-shows, pacientes inactivos y más. No es un software de gestión clínica — es una capa que se conecta al sistema existente de la clínica.

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Backend | .NET 10 Minimal APIs + Vertical Slice Architecture |
| Frontend | React 18 + Vite + TypeScript + Tailwind CSS |
| Base de datos | PostgreSQL (Supabase) con Row Level Security |
| ORM | EF Core 10 con filtros globales multi-tenant |
| Mensajería | Twilio (WhatsApp Business API + Voice) |
| Scheduler | Hangfire |
| IA | OpenAI / Claude con Function Calling |
| Auth | JWT en cookies httpOnly (nunca localStorage) |

## Requisitos

- [.NET 10 SDK](https://dotnet.microsoft.com/download) (>= 10.0.201)
- [Node.js](https://nodejs.org/) (>= 22.x)
- [Docker](https://www.docker.com/) y Docker Compose
- PostgreSQL 16+ (o usar Docker Compose)

## Inicio Rápido

### 1. Clonar y configurar variables de entorno

```bash
git clone https://github.com/632015648a-prog/clinicboost.git
cd clinicboost
cp .env.example .env
# Editar .env con tus valores
```

### 2. Con Docker Compose (recomendado)

```bash
docker compose up -d
```

Esto levanta: PostgreSQL, API (.NET), Frontend (React) y Nginx.

- Frontend: http://localhost
- API: http://localhost:5000
- Swagger: http://localhost:5000/swagger
- Health: http://localhost/health

### 3. Sin Docker (desarrollo local)

```bash
# Backend
cd src/ClinicBoost.Api
dotnet restore
dotnet run

# Frontend (en otra terminal)
cd src/ClinicBoost.Web
npm install
npm run dev
```

- API: http://localhost:5000
- Frontend: http://localhost:5173

## Estructura del Proyecto

```
clinicboost/
├── src/
│   ├── ClinicBoost.Api/           # Backend .NET 10
│   │   ├── Domain/
│   │   │   ├── Entities/          # Entidades del dominio
│   │   │   └── Enums/             # Enumeraciones
│   │   ├── Features/              # Vertical Slices (endpoint por feature)
│   │   │   ├── Appointments/
│   │   │   ├── Auth/
│   │   │   ├── Health/
│   │   │   ├── Tenants/
│   │   │   └── Webhooks/
│   │   └── Infrastructure/
│   │       ├── Middleware/         # TenantMiddleware, TwilioSignatureMiddleware
│   │       ├── Persistence/       # AppDbContext con filtros globales
│   │       └── Services/          # Timezone, Idempotency, Messaging
│   └── ClinicBoost.Web/           # Frontend React + Vite + Tailwind
├── docker/
│   └── nginx/                     # Configuración Nginx
├── docker-compose.yml
├── .env.example
├── global.json                    # Pinning de versión .NET
└── ClinicBoost.sln
```

## Arquitectura

- **Vertical Slice Architecture**: cada feature es autocontenida (Endpoint + Request + Handler)
- **Multi-tenant**: todas las tablas de negocio llevan `tenant_id`, EF Core filtra automáticamente
- **RLS**: PostgreSQL Row Level Security como última línea de defensa
- **Idempotencia**: tabla `processed_events` para deduplicación de webhooks
- **Timezone**: siempre UTC en DB, conversión con `TimeZoneInfo` (nunca `AddHours`)
- **Seguridad**: JWT en cookies httpOnly, firma HMAC-SHA1 en webhooks de Twilio

## Reglas Arquitectónicas

- No usar MediatR ni AutoMapper salvo instrucción explícita
- No guardar tokens en localStorage
- No permitir bypass de RLS desde el runtime de la app
- No usar `AddHours` manual para timezones
- Toda integración externa debe tener timeout, retry y circuit breaker
- Todo webhook debe ser idempotente y validado criptográficamente
- La IA nunca confirma citas por sí misma; el backend ejecuta

## Roadmap

| Bloque | Descripción | Estado |
|--------|------------|--------|
| 0 | Scaffolding + entidades + middleware | **Actual** |
| 1 | Multi-tenant + Auth + RLS | Pendiente |
| 2 | Webhooks Twilio (voz + WhatsApp) | Pendiente |
| 3 | Motor de citas + iCal | Pendiente |
| 4 | Flow 01 — Llamadas perdidas | Pendiente |
| 5-17 | Flows adicionales + dashboard + deploy | Pendiente |

## Licencia

Propietario. Todos los derechos reservados.
