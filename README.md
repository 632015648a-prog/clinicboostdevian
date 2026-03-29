# ClinicBoost

**Revenue Recovery Layer** para clínicas de fisioterapia privadas en España.

> Automatiza llamadas perdidas, huecos de agenda, no-shows y reactivación de pacientes.

## Stack

| Capa | Tecnología |
|------|-----------|
| Backend | .NET 10 Minimal API — Vertical Slice Architecture |
| Frontend | React 18 + Vite + TypeScript + Tailwind CSS 4 |
| Base de datos | PostgreSQL 16 via Supabase |
| Multi-tenant | `tenant_id` + RLS + EF Core Global Filters |
| Auth | JWT en cookies httpOnly |
| Mensajería | Twilio (WhatsApp + Voice) |
| IA | Claude/OpenAI Function Calling |

## Estructura del Monorepo

```
clinicboost/
├── apps/
│   ├── api/             # .NET 10 Minimal API
│   │   ├── Domain/      # Entidades + Enums
│   │   ├── Features/    # Vertical Slices
│   │   └── Infrastructure/
│   └── web/             # React + Vite + TypeScript + Tailwind
├── supabase/
│   ├── config.toml      # Configuración Supabase CLI
│   ├── migrations/      # Migraciones SQL + RLS
│   └── seed/            # Datos de desarrollo
├── docs/                # Documentación
├── docker/nginx/        # Configuración Nginx
├── .github/workflows/   # CI/CD
└── docker-compose.yml
```

## Quick Start

### Docker Compose (recomendado)

```bash
cp .env.example .env
docker compose up --build
```

| Servicio | URL |
|----------|-----|
| Frontend | http://localhost:5173 |
| API | http://localhost:5000 |
| Swagger | http://localhost:5000/swagger |
| Nginx | http://localhost |
| PostgreSQL | localhost:5432 |

### Desarrollo Local

```bash
# Backend
cd apps/api && dotnet restore && dotnet run

# Frontend (en otra terminal)
cd apps/web && npm install && npm run dev
```

## Reglas Arquitectónicas

- **Vertical Slice Architecture** — cada feature autocontenida, sin capas horizontales
- **Multi-tenant** — todas las tablas llevan `tenant_id`, RLS en PostgreSQL
- **Sin MediatR** — sin AutoMapper — sin repositorios genéricos
- **JWT en cookies httpOnly** — NUNCA en localStorage
- **Timezone** — UTC storage + `TimezoneService` (nunca `AddHours`)
- **IA propone, backend ejecuta** — la IA nunca confirma citas directamente
- **Resiliencia** — circuit breaker + retry + timeout en toda integración externa
- **Idempotencia** — tabla `processed_events` para webhooks
- **Webhooks** — validación criptográfica (HMAC-SHA1 Twilio)

## Roadmap

| Bloque | Descripción | Estado |
|--------|-------------|--------|
| 0 | Scaffolding + estructura | ✓ |
| 1 | Multi-tenant + Auth + RLS | Pendiente |
| 2 | Twilio + WhatsApp | Pendiente |
| 3 | iCal + Yield Management | Pendiente |
| 4 | Flow 01 — Llamadas Perdidas | Pendiente |
| 5-17 | Flows restantes + Dashboard + Deploy | Pendiente |

Ver [docs/architecture.md](docs/architecture.md) para documentación completa.
