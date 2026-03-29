-- ============================================================================
-- ClinicBoost — Migración inicial
-- ============================================================================
-- Este archivo será reemplazado por las migraciones reales de EF Core
-- cuando se conecte Supabase en el Bloque 1.
--
-- Convenciones:
--   - Todas las tablas de negocio llevan tenant_id (UUID NOT NULL)
--   - RLS activado en todas las tablas de negocio
--   - Timestamps en UTC (timestamptz)
--   - IDs son UUID con gen_random_uuid()
-- ============================================================================

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Tabla de tenants (sin RLS — acceso controlado por la app) ──────────────
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    timezone VARCHAR(50) NOT NULL DEFAULT 'Europe/Madrid',
    phone VARCHAR(20),
    email VARCHAR(200),
    subscription_tier VARCHAR(20) NOT NULL DEFAULT 'Trial',
    subscription_status VARCHAR(20) NOT NULL DEFAULT 'Trialing',
    stripe_customer_id VARCHAR(100),
    ical_feed_url TEXT,
    ical_last_synced_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Usuarios de aplicación ─────────────────────────────────────────────────
-- Separar usuario de migraciones del usuario de aplicación
-- El app_user NO puede bypass RLS
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_user_password';
    END IF;
END
$$;

-- Placeholder: las tablas de negocio se crean via EF Core migrations
-- Ver apps/api/Domain/Entities/ para la definición de entidades
