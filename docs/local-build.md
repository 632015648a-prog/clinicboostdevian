# Plan de Compilación Local

## Requisitos

| Herramienta | Versión |
|-------------|---------|
| .NET SDK | 10.0.x |
| Node.js | 22.x |
| npm | 10.x |
| Docker + Docker Compose | Latest |
| PostgreSQL | 16 (via Docker) |

## Opción 1: Docker Compose (recomendado)

```bash
# Levantar todos los servicios
docker compose up --build

# Servicios disponibles:
# - http://localhost      → Nginx (proxy)
# - http://localhost:5000 → API (.NET)
# - http://localhost:5173 → Frontend (React)
# - localhost:5432        → PostgreSQL
```

## Opción 2: Desarrollo Local

### 1. Base de datos

```bash
# Solo PostgreSQL via Docker
docker compose up db -d

# Verificar conexión
docker compose exec db pg_isready -U postgres
```

### 2. Backend (.NET API)

```bash
cd apps/api

# Restaurar dependencias
dotnet restore

# Compilar
dotnet build

# Ejecutar en modo desarrollo
dotnet run

# API disponible en http://localhost:5000
# Swagger en http://localhost:5000/swagger
```

### 3. Frontend (React + Vite)

```bash
cd apps/web

# Instalar dependencias
npm install

# Desarrollo con hot reload
npm run dev

# Frontend disponible en http://localhost:5173
# Proxy a API configurado automáticamente
```

### 4. Compilar para producción

```bash
# Backend
cd apps/api && dotnet publish -c Release -o ./publish

# Frontend
cd apps/web && npm run build
# Output en apps/web/dist/
```

## Variables de Entorno

Copiar `.env.example` a `.env` y configurar:

```bash
cp .env.example .env
```

Variables mínimas para desarrollo local:
- `DATABASE_URL` — ya configurada para Docker local
- `JWT_SECRET` — cambiar a un string seguro de 32+ caracteres
- Las demás variables (Twilio, OpenAI, Stripe, Supabase) se configuran cuando se necesiten

## Lint y Verificación

```bash
# Frontend lint
cd apps/web && npm run lint

# Backend build (incluye análisis estático)
cd apps/api && dotnet build --warnaserrors
```
