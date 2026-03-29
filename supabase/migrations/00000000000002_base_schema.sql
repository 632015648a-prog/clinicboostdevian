-- ============================================================================
-- ClinicBoost — Esquema Base Completo
-- Migración: 00000000000002_base_schema.sql
-- Descripción: Todas las tablas de negocio con RLS, índices críticos y comentarios.
--
-- Tablas incluidas:
--   · tenants               — Clínicas registradas (sin RLS — acceso por app)
--   · tenant_users          — Usuarios de cada clínica (staff, admin)
--   · patients              — Pacientes por tenant (E.164, único por tenant)
--   · patient_consents      — Consentimientos RGPD por paciente y versión
--   · calendar_connections  — Integraciones de calendario (iCal / Google / Outlook)
--   · appointments          — Citas de pacientes con trazabilidad de origen
--   · appointment_events    — Eventos del ciclo de vida de una cita (log inmutable)
--   · conversations         — Conversaciones WhatsApp / voz por paciente
--   · messages              — Mensajes individuales dentro de una conversación
--   · waitlist_entries      — Lista de espera por tenant
--   · rule_configs          — Configuración de reglas de automatización por tenant
--   · revenue_events        — Ingresos recuperados / generados por el sistema
--   · automation_runs       — Ejecuciones de flows de automatización (trazabilidad)
--   · webhook_events        — Webhooks recibidos de Twilio / externos (raw)
--   · processed_events      — Tabla de idempotencia: event_type + event_id únicos
--   · audit_logs            — Auditoría de operaciones sensibles (append-only)
--
-- Convenciones:
--   · UUID v4 con gen_random_uuid() como PK en todas las tablas
--   · Todas las tablas de negocio llevan tenant_id UUID NOT NULL + FK a tenants
--   · Timestamps siempre TIMESTAMPTZ (UTC); la app convierte a local con TimeZoneInfo
--   · Enums persistidos como TEXT con CHECK constraints (legibilidad + flexibilidad)
--   · snake_case en todos los nombres (convención PostgreSQL)
--   · RLS habilitado + FORCE en todas las tablas de negocio
--   · app_user es el rol de la aplicación: NO puede bypass RLS
--   · El rol de migraciones (postgres / superuser) NO corre queries de negocio
-- ============================================================================

-- ──────────────────────────────────────────────────────────────────────────────
-- EXTENSIONES
-- ──────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- uuid_generate_v4() (compatibilidad)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- gen_random_uuid(), crypt()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- índices trigram para búsquedas de nombre

-- ──────────────────────────────────────────────────────────────────────────────
-- ROL DE APLICACIÓN
-- El usuario de la app nunca tiene BYPASSRLS. Las migraciones corren
-- con el superuser (postgres) que sí puede hacer DDL.
-- ──────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'app_user_password';
    END IF;
END
$$;

-- ──────────────────────────────────────────────────────────────────────────────
-- HELPER: función para obtener el tenant actual desde la sesión
-- Se llama con: SET LOCAL app.current_tenant_id = '<uuid>';
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting('app.current_tenant_id', true)::uuid;
$$;

COMMENT ON FUNCTION current_tenant_id() IS
    'Devuelve el tenant_id activo en la sesión actual. '
    'Establecido por TenantMiddleware vía SET LOCAL app.current_tenant_id.';

-- ──────────────────────────────────────────────────────────────────────────────
-- HELPER: trigger genérico para updated_at automático
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION set_updated_at() IS
    'Trigger function: actualiza updated_at al valor actual en cada UPDATE.';

-- ──────────────────────────────────────────────────────────────────────────────
-- HELPER: crear trigger solo si no existe (idempotencia)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_updated_at_trigger(p_table TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trg_' || p_table || '_updated_at'
          AND tgrelid = p_table::regclass
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at
             BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
            p_table, p_table
        );
    END IF;
END;
$$;

-- ──────────────────────────────────────────────────────────────────────────────
-- HELPER: crear política RLS solo si no existe (idempotencia)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_rls_policy(
    p_table TEXT,
    p_policy TEXT,
    p_cmd TEXT,       -- 'ALL', 'SELECT', 'INSERT', 'UPDATE', 'DELETE'
    p_using TEXT DEFAULT NULL,
    p_check TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = p_table AND policyname = p_policy
    ) THEN
        RETURN;  -- ya existe, no hacer nada
    END IF;

    v_sql := format('CREATE POLICY %I ON %I FOR %s', p_policy, p_table, p_cmd);
    IF p_using IS NOT NULL THEN
        v_sql := v_sql || ' USING (' || p_using || ')';
    END IF;
    IF p_check IS NOT NULL THEN
        v_sql := v_sql || ' WITH CHECK (' || p_check || ')';
    END IF;
    EXECUTE v_sql;
END;
$$;


-- ============================================================================
-- 1. TENANTS
-- Propósito: Representa cada clínica de fisioterapia registrada en ClinicBoost.
--            Es el nodo raíz del modelo multi-tenant. No hereda tenant_id.
--            Sin RLS directo: el acceso se controla por la app (solo lectura propia).
-- ============================================================================
CREATE TABLE IF NOT EXISTS tenants (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identidad
    name                    VARCHAR(200) NOT NULL,
    slug                    VARCHAR(100) NOT NULL,          -- identificador URL único
    timezone                VARCHAR(50)  NOT NULL DEFAULT 'Europe/Madrid',  -- IANA timezone

    -- Contacto
    phone                   VARCHAR(20),                    -- E.164 formato
    email                   VARCHAR(200),
    twilio_phone_number     VARCHAR(20),                    -- número Twilio asignado a esta clínica

    -- Negocio
    standard_session_price  NUMERIC(10,2) NOT NULL DEFAULT 0,
    inactivity_threshold_days INT         NOT NULL DEFAULT 60,
    business_hours_start    TIME          NOT NULL DEFAULT '09:00',
    business_hours_end      TIME          NOT NULL DEFAULT '20:00',

    -- Suscripción
    subscription_tier       TEXT         NOT NULL DEFAULT 'Free'
                                CHECK (subscription_tier IN ('Free','Starter','Growth','Scale')),
    subscription_status     TEXT         NOT NULL DEFAULT 'Trial'
                                CHECK (subscription_status IN ('Trial','Active','PastDue','Cancelled','Suspended')),
    stripe_customer_id      VARCHAR(100),                   -- ID de cliente en Stripe
    stripe_subscription_id  VARCHAR(100),                   -- ID de suscripción en Stripe

    -- iCal (integración legada antes de calendar_connections)
    ical_feed_url           TEXT,
    ical_last_synced_at     TIMESTAMPTZ,

    -- Estado
    is_active               BOOLEAN      NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ
);

-- ── Migración incremental: añadir columnas nuevas si la tabla ya existía ──────
-- (Idempotente: DO NOTHING si la columna ya existe)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='twilio_phone_number') THEN
        ALTER TABLE tenants ADD COLUMN twilio_phone_number VARCHAR(20);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='standard_session_price') THEN
        ALTER TABLE tenants ADD COLUMN standard_session_price NUMERIC(10,2) NOT NULL DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='inactivity_threshold_days') THEN
        ALTER TABLE tenants ADD COLUMN inactivity_threshold_days INT NOT NULL DEFAULT 60;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='business_hours_start') THEN
        ALTER TABLE tenants ADD COLUMN business_hours_start TIME NOT NULL DEFAULT '09:00';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='business_hours_end') THEN
        ALTER TABLE tenants ADD COLUMN business_hours_end TIME NOT NULL DEFAULT '20:00';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='tenants' AND column_name='stripe_subscription_id') THEN
        ALTER TABLE tenants ADD COLUMN stripe_subscription_id VARCHAR(100);
    END IF;
    -- Actualizar CHECK de subscription_tier si difiere (DROP + ADD)
    IF NOT EXISTS (SELECT 1 FROM information_schema.check_constraints
                   WHERE constraint_name LIKE '%tenants%subscription_tier%'
                     AND check_clause LIKE '%Growth%') THEN
        ALTER TABLE tenants DROP CONSTRAINT IF EXISTS tenants_subscription_tier_check;
        ALTER TABLE tenants ADD CONSTRAINT tenants_subscription_tier_check
            CHECK (subscription_tier IN ('Free','Starter','Growth','Scale'));
    END IF;
END
$$;

COMMENT ON TABLE tenants IS
    'Clínicas de fisioterapia registradas en ClinicBoost. '
    'Nodo raíz del modelo multi-tenant. Sin RLS propio: el acceso se controla '
    'a nivel de app (cada tenant solo lee su propio registro).';
COMMENT ON COLUMN tenants.slug            IS 'Identificador URL único de la clínica (p.ej. "fisionavarra").';
COMMENT ON COLUMN tenants.timezone        IS 'IANA timezone (p.ej. "Europe/Madrid"). Todo en DB es UTC.';
COMMENT ON COLUMN tenants.twilio_phone_number IS 'Número de teléfono Twilio asignado (E.164).';
COMMENT ON COLUMN tenants.standard_session_price IS 'Precio base de sesión. Usado en cálculo de revenue recuperado.';
COMMENT ON COLUMN tenants.inactivity_threshold_days IS 'Días sin cita para considerar paciente inactivo (flow 06).';
COMMENT ON COLUMN tenants.stripe_customer_id IS 'ID del cliente en Stripe para facturación.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_tenants_slug
    ON tenants (slug);

CREATE INDEX IF NOT EXISTS idx_tenants_subscription_status
    ON tenants (subscription_status)
    WHERE is_active = true;

SELECT create_updated_at_trigger('tenants');


-- ============================================================================
-- 2. TENANT_USERS
-- Propósito: Usuarios humanos (fisioterapeutas, recepcionistas, admin) que
--            pertenecen a una clínica. Cada usuario pertenece exactamente a
--            un tenant. El campo auth_user_id enlaza con el sistema de auth
--            (Supabase Auth / JWT personalizado).
-- ============================================================================
CREATE TABLE IF NOT EXISTS tenant_users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,

    -- Identidad
    email           VARCHAR(200) NOT NULL,
    full_name       VARCHAR(200) NOT NULL,
    phone           VARCHAR(20),                    -- E.164, opcional

    -- Vínculo con el sistema de autenticación
    auth_user_id    UUID        UNIQUE,             -- referencia a auth.users (Supabase Auth)

    -- Rol dentro de la clínica
    role            TEXT        NOT NULL DEFAULT 'Staff'
                        CHECK (role IN ('Owner','Admin','Staff','ReadOnly')),

    -- Estado
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ
);

COMMENT ON TABLE tenant_users IS
    'Usuarios humanos (staff, admin, propietario) de cada clínica. '
    'Un usuario pertenece a un único tenant. auth_user_id vincula con el '
    'proveedor de autenticación (Supabase Auth / JWT).';
COMMENT ON COLUMN tenant_users.auth_user_id IS 'UUID del usuario en el sistema de auth externo (Supabase Auth).';
COMMENT ON COLUMN tenant_users.role         IS 'Rol: Owner (propietario), Admin, Staff, ReadOnly.';

-- Índice principal de acceso: usuario dentro de un tenant
CREATE UNIQUE INDEX IF NOT EXISTS uq_tenant_users_tenant_email
    ON tenant_users (tenant_id, email);

CREATE INDEX IF NOT EXISTS idx_tenant_users_tenant_id
    ON tenant_users (tenant_id);

CREATE INDEX IF NOT EXISTS idx_tenant_users_auth_user_id
    ON tenant_users (auth_user_id)
    WHERE auth_user_id IS NOT NULL;

-- RLS
ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('tenant_users', 'tenant_users_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('tenant_users', 'tenant_users_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_users TO app_user;

SELECT create_updated_at_trigger('tenant_users');


-- ============================================================================
-- 3. PATIENTS
-- Propósito: Pacientes de la clínica. El teléfono (E.164) es único por tenant
--            y es el identificador principal para las comunicaciones Twilio.
--            Almacena estado de consentimiento RGPD activo y canal preferido.
-- ============================================================================
CREATE TABLE IF NOT EXISTS patients (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,

    -- Datos básicos
    name                VARCHAR(200) NOT NULL,
    phone               VARCHAR(20)  NOT NULL,       -- E.164 validado por libphonenumber
    email               VARCHAR(200),
    notes               TEXT,                        -- notas clínicas libres (sin PHI estructurada)

    -- Historial clínico agregado
    last_visit_date     TIMESTAMPTZ,
    total_sessions      INT          NOT NULL DEFAULT 0,
    average_rating      NUMERIC(3,2) NOT NULL DEFAULT 0
                            CHECK (average_rating >= 0 AND average_rating <= 5),

    -- Consentimiento activo (snapshot desnormalizado para consultas rápidas)
    consent_granted         BOOLEAN      NOT NULL DEFAULT false,
    consent_granted_at      TIMESTAMPTZ,
    consent_text_version    VARCHAR(20),             -- versión del texto legal aceptado

    -- Preferencias
    preferred_channel   TEXT         NOT NULL DEFAULT 'WhatsApp'
                            CHECK (preferred_channel IN ('Manual','WhatsApp','Web','Phone')),

    -- Estado
    is_active           BOOLEAN      NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ
);

COMMENT ON TABLE patients IS
    'Pacientes de la clínica. Teléfono único por tenant (E.164). '
    'Identificador principal para comunicaciones Twilio. '
    'consent_granted es snapshot para lecturas rápidas; la fuente de verdad '
    'es patient_consents. Sin PHI estructurada (nombre, teléfono y notas libres).';
COMMENT ON COLUMN patients.phone               IS 'Teléfono en formato E.164. Validado por libphonenumber-csharp.';
COMMENT ON COLUMN patients.consent_granted     IS 'Snapshot del consentimiento RGPD activo. Fuente de verdad: patient_consents.';
COMMENT ON COLUMN patients.consent_text_version IS 'Versión del texto RGPD aceptado por el paciente.';
COMMENT ON COLUMN patients.average_rating      IS 'Media NPS/rating de sesiones. Calculado por el sistema.';
COMMENT ON COLUMN patients.total_sessions      IS 'Contador de sesiones asistidas. Actualizado por automation.';

-- CRÍTICO: unicidad teléfono por tenant (búsquedas de webhook Twilio)
CREATE UNIQUE INDEX IF NOT EXISTS uq_patients_tenant_phone
    ON patients (tenant_id, phone);

-- Búsqueda por tenant (consultas de dashboard y listados)
CREATE INDEX IF NOT EXISTS idx_patients_tenant_id
    ON patients (tenant_id);

-- Búsqueda de pacientes inactivos (Flow 06 — Reactivación)
CREATE INDEX IF NOT EXISTS idx_patients_last_visit
    ON patients (tenant_id, last_visit_date)
    WHERE is_active = true;

-- Búsqueda por nombre (trigram para coincidencias parciales)
CREATE INDEX IF NOT EXISTS idx_patients_name_trgm
    ON patients USING gin (name gin_trgm_ops);

-- RLS
ALTER TABLE patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE patients FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('patients', 'patients_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('patients', 'patients_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON patients TO app_user;

SELECT create_updated_at_trigger('patients');


-- ============================================================================
-- 4. PATIENT_CONSENTS
-- Propósito: Registro inmutable de consentimientos RGPD por paciente.
--            Cada fila es un evento de consentimiento (Granted / Denied / Revoked).
--            Permite trazabilidad completa de versiones y canales. La tabla
--            patients.consent_granted es el snapshot activo para lecturas rápidas.
-- ============================================================================
CREATE TABLE IF NOT EXISTS patient_consents (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    patient_id          UUID        NOT NULL REFERENCES patients (id) ON DELETE CASCADE,

    -- Detalles del evento de consentimiento
    consent_status      TEXT        NOT NULL
                            CHECK (consent_status IN ('Pending','Granted','Denied','Revoked')),
    consent_text_version VARCHAR(20) NOT NULL DEFAULT '1.0',  -- versión del texto legal mostrado
    channel             TEXT        NOT NULL DEFAULT 'WhatsApp'
                            CHECK (channel IN ('Manual','WhatsApp','Web','Phone')),

    -- Evidencia
    ip_address          INET,                       -- IP del consentimiento web (nullable si WhatsApp)
    user_agent          TEXT,                       -- User-agent del consentimiento web
    twilio_message_sid  VARCHAR(100),               -- SID del mensaje de WhatsApp con el opt-in

    -- Timestamps (append-only: nunca se actualiza este registro)
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE patient_consents IS
    'Registro inmutable de eventos de consentimiento RGPD. '
    'Append-only: cada cambio de estado genera una nueva fila. '
    'Permite auditoría completa para cumplimiento RGPD / LOPDGDD. '
    'El estado activo se desnormaliza en patients.consent_granted.';
COMMENT ON COLUMN patient_consents.consent_text_version IS 'Versión del texto legal mostrado al paciente en el momento del consentimiento.';
COMMENT ON COLUMN patient_consents.twilio_message_sid   IS 'SID del mensaje Twilio con el opt-in explícito.';
COMMENT ON COLUMN patient_consents.occurred_at          IS 'Momento exacto del evento de consentimiento (UTC).';

-- Historial de consentimientos de un paciente (orden cronológico)
CREATE INDEX IF NOT EXISTS idx_patient_consents_patient_id
    ON patient_consents (patient_id, occurred_at DESC);

-- Búsqueda por tenant para auditorías RGPD
CREATE INDEX IF NOT EXISTS idx_patient_consents_tenant_id
    ON patient_consents (tenant_id, occurred_at DESC);

-- Búsqueda de pacientes con consentimiento activo por tenant
CREATE INDEX IF NOT EXISTS idx_patient_consents_status
    ON patient_consents (tenant_id, consent_status)
    WHERE consent_status = 'Granted';

-- RLS
ALTER TABLE patient_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_consents FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('patient_consents', 'patient_consents_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('patient_consents', 'patient_consents_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

-- Append-only: prohibir UPDATE y DELETE en consentimientos (solo INSERT)
SELECT create_rls_policy('patient_consents', 'patient_consents_no_update', 'UPDATE', 'false');

SELECT create_rls_policy('patient_consents', 'patient_consents_no_delete', 'DELETE', 'false');

GRANT SELECT, INSERT ON patient_consents TO app_user;


-- ============================================================================
-- 5. CALENDAR_CONNECTIONS
-- Propósito: Conexiones a calendarios externos (iCal, Google Calendar, Outlook)
--            por tenant. Cada fila representa una integración activa con su
--            URL/credenciales y estado de sincronización. Un tenant puede tener
--            múltiples calendarios (por terapeuta).
-- ============================================================================
CREATE TABLE IF NOT EXISTS calendar_connections (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,

    -- Identificación
    display_name        VARCHAR(200) NOT NULL,               -- nombre descriptivo (ej: "Agenda Dr. García")
    provider            TEXT        NOT NULL DEFAULT 'ICal'
                            CHECK (provider IN ('ICal','GoogleCalendar','OutlookCalendar','Manual')),

    -- Credenciales / configuración (según proveedor)
    ical_url            TEXT,                                -- URL pública del feed iCal
    oauth_access_token  TEXT,                                -- token OAuth (cifrado en tránsito)
    oauth_refresh_token TEXT,                                -- refresh token OAuth
    oauth_token_expires_at TIMESTAMPTZ,
    external_calendar_id TEXT,                              -- ID del calendario en Google/Outlook

    -- Estado de sincronización
    last_synced_at      TIMESTAMPTZ,
    last_sync_error     TEXT,                               -- último error de sincronización
    sync_frequency_mins INT         NOT NULL DEFAULT 15,    -- frecuencia de sync en minutos
    is_active           BOOLEAN     NOT NULL DEFAULT true,

    -- Asociación opcional a terapeuta
    therapist_user_id   UUID REFERENCES tenant_users (id) ON DELETE SET NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ
);

COMMENT ON TABLE calendar_connections IS
    'Integraciones con calendarios externos (iCal, Google, Outlook) por tenant. '
    'Un tenant puede tener múltiples conexiones (una por terapeuta). '
    'Las credenciales OAuth se almacenan cifradas. '
    'La sincronización la ejecuta Hangfire según sync_frequency_mins.';
COMMENT ON COLUMN calendar_connections.ical_url            IS 'URL del feed iCal público (sin OAuth).';
COMMENT ON COLUMN calendar_connections.oauth_access_token  IS 'Access token OAuth. Cifrar en reposo con pgcrypto.';
COMMENT ON COLUMN calendar_connections.last_sync_error     IS 'Último mensaje de error de sincronización para diagnóstico.';
COMMENT ON COLUMN calendar_connections.sync_frequency_mins IS 'Minutos entre sincronizaciones automáticas (Hangfire).';

CREATE INDEX IF NOT EXISTS idx_calendar_connections_tenant_id
    ON calendar_connections (tenant_id)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_calendar_connections_sync
    ON calendar_connections (last_synced_at, sync_frequency_mins)
    WHERE is_active = true;

-- RLS
ALTER TABLE calendar_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_connections FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('calendar_connections', 'calendar_connections_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('calendar_connections', 'calendar_connections_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON calendar_connections TO app_user;

SELECT create_updated_at_trigger('calendar_connections');


-- ============================================================================
-- 6. APPOINTMENTS
-- Propósito: Citas de pacientes. Corazón del modelo de negocio de ClinicBoost.
--            Trazabilidad completa: qué flow la generó, por qué canal se reservó,
--            si fue recuperada por el bot, y métricas para el modelo ML futuro.
--            El ciclo de vida se audita en appointment_events.
-- ============================================================================
CREATE TABLE IF NOT EXISTS appointments (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    patient_id              UUID        NOT NULL REFERENCES patients (id) ON DELETE RESTRICT,

    -- Slot de tiempo
    starts_at               TIMESTAMPTZ NOT NULL,           -- UTC
    ends_at                 TIMESTAMPTZ NOT NULL,           -- UTC
    duration_mins           INT         NOT NULL
                                CHECK (duration_mins > 0 AND duration_mins <= 480),
    therapist_user_id       UUID REFERENCES tenant_users (id) ON DELETE SET NULL,

    -- Referencia a evento de calendario externo
    calendar_connection_id  UUID REFERENCES calendar_connections (id) ON DELETE SET NULL,
    external_event_id       VARCHAR(500),                   -- ID del evento en el software externo

    -- Estado
    status                  TEXT        NOT NULL DEFAULT 'Pending'
                                CHECK (status IN ('Pending','Confirmed','Attended','NoShow','Cancelled','Rescheduled')),
    cancellation_reason     TEXT,                           -- motivo de cancelación / no-show

    -- Trazabilidad de origen (fundamental para el Revenue Tracker)
    is_recovered            BOOLEAN     NOT NULL DEFAULT false,  -- ¿fue recuperada por el bot?
    source_flow             TEXT        NOT NULL DEFAULT 'Manual'
                                CHECK (source_flow IN ('Manual','MissedCall','LastMinute','NoShowWaitlist',
                                                       'OutOfHours','PostSession','Reactivation','Reschedule')),
    booking_channel         TEXT        NOT NULL DEFAULT 'Manual'
                                CHECK (booking_channel IN ('Manual','WhatsApp','Web','Phone')),

    -- Métricas para ML (recopilar desde el MVP)
    mins_between_book_and_slot INT       NOT NULL DEFAULT 0, -- lead time de reserva
    rescheduled_count          INT       NOT NULL DEFAULT 0, -- número de reagendados

    -- Acciones de recordatorio
    reminder_sent_at        TIMESTAMPTZ,
    nps_sent_at             TIMESTAMPTZ,                    -- cuándo se envió encuesta post-sesión

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ
);

COMMENT ON TABLE appointments IS
    'Citas de pacientes. Fuente de verdad del modelo de negocio. '
    'source_flow y is_recovered permiten calcular el revenue recuperado por el sistema. '
    'mins_between_book_and_slot y rescheduled_count se acumulan para el modelo ML futuro. '
    'El ciclo de vida completo (cambios de estado) se registra en appointment_events.';
COMMENT ON COLUMN appointments.starts_at             IS 'Inicio de la cita en UTC. Conversión a local con TimeZoneInfo.';
COMMENT ON COLUMN appointments.is_recovered          IS 'true si la cita fue generada/recuperada por el bot de ClinicBoost.';
COMMENT ON COLUMN appointments.source_flow           IS 'Flow de automatización que originó la cita (para analytics).';
COMMENT ON COLUMN appointments.mins_between_book_and_slot IS 'Lead time entre reserva e inicio. Dataset para modelo ML de yield.';
COMMENT ON COLUMN appointments.external_event_id    IS 'ID del evento en el software de gestión de la clínica (iCal UID).';

-- CRÍTICO: consultas de agenda (slots disponibles, próximas citas)
CREATE INDEX IF NOT EXISTS idx_appointments_tenant_date
    ON appointments (tenant_id, starts_at)
    WHERE status NOT IN ('Cancelled');

-- Agenda de un paciente específico
CREATE INDEX IF NOT EXISTS idx_appointments_patient
    ON appointments (tenant_id, patient_id, starts_at DESC);

-- Citas pendientes de recordatorio (Hangfire job)
CREATE INDEX IF NOT EXISTS idx_appointments_reminder
    ON appointments (tenant_id, starts_at)
    WHERE status = 'Confirmed' AND reminder_sent_at IS NULL;

-- No-shows a procesar (Flow 03)
CREATE INDEX IF NOT EXISTS idx_appointments_noshows
    ON appointments (tenant_id, starts_at)
    WHERE status = 'NoShow';

-- Citas recuperadas para el Revenue Tracker
CREATE INDEX IF NOT EXISTS idx_appointments_recovered
    ON appointments (tenant_id, source_flow)
    WHERE is_recovered = true;

-- Búsqueda por evento externo (sincronización iCal)
CREATE INDEX IF NOT EXISTS idx_appointments_external_event
    ON appointments (tenant_id, external_event_id)
    WHERE external_event_id IS NOT NULL;

-- RLS
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('appointments', 'appointments_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('appointments', 'appointments_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON appointments TO app_user;

SELECT create_updated_at_trigger('appointments');


-- ============================================================================
-- 7. APPOINTMENT_EVENTS
-- Propósito: Log inmutable del ciclo de vida de cada cita. Cada transición de
--            estado, recordatorio enviado o acción del sistema genera una fila.
--            Append-only: nunca se modifica ni elimina. Base para trazabilidad,
--            debugging y futuro event sourcing.
-- ============================================================================
CREATE TABLE IF NOT EXISTS appointment_events (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    appointment_id      UUID        NOT NULL REFERENCES appointments (id) ON DELETE CASCADE,

    -- Evento
    event_type          TEXT        NOT NULL
                            CHECK (event_type IN (
                                'Created','Confirmed','Attended','NoShow','Cancelled',
                                'Rescheduled','ReminderSent','NpsSent','RecoveryAttempted',
                                'WaitlistNotified','ManualOverride'
                            )),
    previous_status     TEXT,                               -- estado anterior (nullable en Created)
    new_status          TEXT,                               -- estado resultante del evento

    -- Contexto
    actor_type          TEXT        NOT NULL DEFAULT 'System'
                            CHECK (actor_type IN ('System','User','Patient','Automation','Webhook')),
    actor_id            UUID,                               -- tenant_user_id o null si es el sistema
    source_flow         TEXT,                               -- flow que originó el evento
    notes               TEXT,                               -- descripción libre del evento
    metadata            JSONB,                              -- datos adicionales (p.ej. SID de Twilio)

    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No updated_at: append-only
);

COMMENT ON TABLE appointment_events IS
    'Log inmutable del ciclo de vida de cada cita. Append-only. '
    'Cada cambio de estado, reminder, NPS o acción del sistema genera una fila. '
    'Base para debugging, trazabilidad de automations y futuro event sourcing. '
    'Nunca se hace UPDATE ni DELETE en esta tabla.';
COMMENT ON COLUMN appointment_events.event_type    IS 'Tipo de evento (Created, Confirmed, NoShow, ReminderSent...).';
COMMENT ON COLUMN appointment_events.actor_type    IS 'Quién ejecutó el evento: System, User humano, Patient, Automation o Webhook externo.';
COMMENT ON COLUMN appointment_events.metadata      IS 'Datos adicionales en JSONB (p.ej. {twilio_sid: "SM...", duration_ms: 450}).';

-- Historial de eventos de una cita (más común: ordenado cronológicamente)
CREATE INDEX IF NOT EXISTS idx_appointment_events_appointment
    ON appointment_events (tenant_id, appointment_id, occurred_at);

-- Búsqueda de eventos por tipo (analytics, debugging)
CREATE INDEX IF NOT EXISTS idx_appointment_events_type
    ON appointment_events (tenant_id, event_type, occurred_at DESC);

-- RLS
ALTER TABLE appointment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_events FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('appointment_events', 'appointment_events_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('appointment_events', 'appointment_events_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('appointment_events', 'appointment_events_no_update', 'UPDATE', 'false');

SELECT create_rls_policy('appointment_events', 'appointment_events_no_delete', 'DELETE', 'false');

GRANT SELECT, INSERT ON appointment_events TO app_user;


-- ============================================================================
-- 8. CONVERSATIONS
-- Propósito: Hilo de conversación entre la clínica y un paciente, iniciado
--            por cualquier canal (WhatsApp, voz). Una conversación agrupa
--            todos los messages. Tiene estado propio y se asocia al flow
--            de automatización que la inició.
-- ============================================================================
CREATE TABLE IF NOT EXISTS conversations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    patient_id          UUID        NOT NULL REFERENCES patients (id) ON DELETE RESTRICT,

    -- Origen
    channel             TEXT        NOT NULL DEFAULT 'WhatsApp'
                            CHECK (channel IN ('WhatsApp','Voice','SMS','Web')),
    source_flow         TEXT        NOT NULL DEFAULT 'Manual'
                            CHECK (source_flow IN ('Manual','MissedCall','LastMinute','NoShowWaitlist',
                                                   'OutOfHours','PostSession','Reactivation','Reschedule')),

    -- Referencia a la cita relacionada (opcional)
    appointment_id      UUID REFERENCES appointments (id) ON DELETE SET NULL,

    -- Estado de la conversación
    status              TEXT        NOT NULL DEFAULT 'Open'
                            CHECK (status IN ('Open','WaitingPatient','WaitingStaff','Closed','Expired')),

    -- Contexto IA (para continuidad de conversación)
    ai_context          JSONB,                              -- estado del agente IA (function calls, intenciones)

    -- Twilio
    twilio_conversation_sid VARCHAR(100),                   -- SID de Twilio Conversations (si aplica)

    opened_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at           TIMESTAMPTZ,
    last_message_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ
);

COMMENT ON TABLE conversations IS
    'Hilo de conversación entre la clínica y un paciente. '
    'Agrupa todos los messages de un contexto (WhatsApp, voz). '
    'ai_context guarda el estado del agente IA para continuidad entre turnos. '
    'Un tenant puede tener múltiples conversaciones abiertas simultáneamente.';
COMMENT ON COLUMN conversations.ai_context IS 'Estado del agente IA: últimos mensajes, intención detectada, function calls pendientes.';
COMMENT ON COLUMN conversations.twilio_conversation_sid IS 'SID de Twilio Conversations API para hilo estructurado.';

-- Conversaciones abiertas de un tenant (dashboard en tiempo real)
CREATE INDEX IF NOT EXISTS idx_conversations_tenant_open
    ON conversations (tenant_id, last_message_at DESC)
    WHERE status IN ('Open','WaitingPatient','WaitingStaff');

-- Conversaciones de un paciente
CREATE INDEX IF NOT EXISTS idx_conversations_patient
    ON conversations (tenant_id, patient_id, opened_at DESC);

-- Lookup por SID de Twilio (webhooks entrantes)
CREATE INDEX IF NOT EXISTS idx_conversations_twilio_sid
    ON conversations (twilio_conversation_sid)
    WHERE twilio_conversation_sid IS NOT NULL;

-- RLS
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('conversations', 'conversations_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('conversations', 'conversations_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON conversations TO app_user;

SELECT create_updated_at_trigger('conversations');


-- ============================================================================
-- 9. MESSAGES
-- Propósito: Mensajes individuales dentro de una conversación. Cada fila es
--            un mensaje entrante o saliente (texto, audio, plantilla Twilio).
--            Append-only por naturaleza. Almacena el SID de Twilio para
--            trazabilidad y el estado de entrega.
-- ============================================================================
CREATE TABLE IF NOT EXISTS messages (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    conversation_id     UUID        NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,

    -- Dirección y origen
    direction           TEXT        NOT NULL
                            CHECK (direction IN ('Inbound','Outbound')),
    sender_type         TEXT        NOT NULL DEFAULT 'System'
                            CHECK (sender_type IN ('Patient','System','AI','Staff')),

    -- Contenido
    body                TEXT,                               -- cuerpo del mensaje (nullable si solo media)
    media_url           TEXT,                               -- URL de media adjunta (audio nota de voz, imagen)
    template_name       TEXT,                               -- nombre de plantilla Twilio (si aplica)
    template_variables  JSONB,                              -- variables de la plantilla

    -- Trazabilidad Twilio
    twilio_message_sid  VARCHAR(100),                       -- MessageSid / CallSid de Twilio
    twilio_status       TEXT,                               -- queued, sent, delivered, read, failed
    twilio_error_code   VARCHAR(20),                        -- código de error Twilio si failed
    twilio_price        NUMERIC(10,6),                      -- coste del mensaje en USD

    -- Metadatos IA
    ai_model            VARCHAR(100),                       -- modelo usado (gpt-4o, claude-3-5-sonnet, etc.)
    ai_tokens_used      INT,                                -- tokens consumidos (para cost tracking)
    ai_function_calls   JSONB,                              -- function calls ejecutadas por el agente

    sent_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    read_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No updated_at: los mensajes son inmutables una vez creados
);

COMMENT ON TABLE messages IS
    'Mensajes individuales de cada conversación. Append-only por naturaleza. '
    'Cubre WhatsApp, SMS y transcripciones de voz. '
    'twilio_message_sid es la clave de idempotencia para webhooks de estado. '
    'ai_tokens_used permite tracking de coste de IA por tenant.';
COMMENT ON COLUMN messages.template_name     IS 'Nombre de la plantilla aprobada por Meta/Twilio (mensajes proactivos).';
COMMENT ON COLUMN messages.twilio_price      IS 'Coste del mensaje según tarifa Twilio. Para tracking de COGS.';
COMMENT ON COLUMN messages.ai_function_calls IS 'Function calls que el agente IA ejecutó al generar este mensaje.';

-- Historial de mensajes de una conversación (paginación)
CREATE INDEX IF NOT EXISTS idx_messages_conversation
    ON messages (tenant_id, conversation_id, created_at);

-- Lookup por SID de Twilio (webhooks de estado: delivered, read, failed)
CREATE INDEX IF NOT EXISTS idx_messages_twilio_sid
    ON messages (twilio_message_sid)
    WHERE twilio_message_sid IS NOT NULL;

-- RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('messages', 'messages_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('messages', 'messages_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT ON messages TO app_user;


-- ============================================================================
-- 10. WAITLIST_ENTRIES
-- Propósito: Lista de espera por tenant. Pacientes que quieren una cita pero
--            no hay slot disponible en su fecha preferida. El sistema los
--            notifica automáticamente (Flow 02/03) cuando se libera un hueco.
--            Estado propio para controlar el flujo de notificación.
-- ============================================================================
CREATE TABLE IF NOT EXISTS waitlist_entries (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    patient_id          UUID        NOT NULL REFERENCES patients (id) ON DELETE CASCADE,

    -- Preferencias del paciente
    requested_date      DATE        NOT NULL,                -- fecha preferida (en local del tenant)
    requested_time_start TIME,                               -- ventana horaria inicio (opcional)
    requested_time_end  TIME,                                -- ventana horaria fin (opcional)
    therapist_user_id   UUID REFERENCES tenant_users (id) ON DELETE SET NULL,

    -- Estado del proceso de notificación
    status              TEXT        NOT NULL DEFAULT 'Pending'
                            CHECK (status IN ('Pending','Contacted','Accepted','Expired','Cancelled')),
    priority            INT         NOT NULL DEFAULT 0,      -- menor número = mayor prioridad
    notified_at         TIMESTAMPTZ,                         -- cuándo se envió la notificación
    response_deadline   TIMESTAMPTZ,                         -- hasta cuándo puede responder el paciente

    -- Resultado
    assigned_appointment_id UUID REFERENCES appointments (id) ON DELETE SET NULL,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ
);

COMMENT ON TABLE waitlist_entries IS
    'Lista de espera de pacientes por tenant. '
    'Usada en Flow 02 (Yield Management) y Flow 03 (No-Shows) para rellenar huecos. '
    'priority controla el orden de notificación (0 = máxima prioridad). '
    'response_deadline evita bloquear huecos indefinidamente.';
COMMENT ON COLUMN waitlist_entries.requested_date  IS 'Fecha preferida del paciente (en timezone del tenant).';
COMMENT ON COLUMN waitlist_entries.priority        IS 'Orden de notificación. 0 = mayor prioridad. Actualizable por staff.';
COMMENT ON COLUMN waitlist_entries.response_deadline IS 'TTL de la oferta de hueco. Si expira, se contacta al siguiente.';

-- CRÍTICO: búsqueda de la cola por tenant (notificación por orden de prioridad)
CREATE INDEX IF NOT EXISTS idx_waitlist_tenant_pending
    ON waitlist_entries (tenant_id, requested_date, priority)
    WHERE status = 'Pending';

-- Entradas activas de un paciente (evitar duplicados)
CREATE INDEX IF NOT EXISTS idx_waitlist_patient
    ON waitlist_entries (tenant_id, patient_id)
    WHERE status IN ('Pending', 'Contacted');

-- RLS
ALTER TABLE waitlist_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE waitlist_entries FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('waitlist_entries', 'waitlist_entries_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('waitlist_entries', 'waitlist_entries_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON waitlist_entries TO app_user;

SELECT create_updated_at_trigger('waitlist_entries');


-- ============================================================================
-- 11. RULE_CONFIGS
-- Propósito: Configuración de reglas de automatización por tenant. Cada fila
--            define un tipo de regla (descuento, flow trigger, cooldown, etc.)
--            con sus parámetros. Los CHECK constraints actúan como DiscountGuard
--            a nivel de BD, impidiendo descuentos fuera de rango.
-- ============================================================================
CREATE TABLE IF NOT EXISTS rule_configs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,

    -- Identificación de la regla
    rule_type           TEXT        NOT NULL
                            CHECK (rule_type IN (
                                'LastMinuteDiscount',
                                'LoyaltyDiscount',
                                'NoShowPenalty',
                                'ReactivationDiscount',
                                'ProactiveMessageCooldown',
                                'WaitlistExpiry',
                                'ReminderTiming',
                                'BusinessHoursOverride',
                                'FlowTrigger'
                            )),
    display_name        VARCHAR(200),                        -- nombre descriptivo para el dashboard

    -- DiscountGuard: CHECK garantiza que los descuentos están en rango seguro
    min_discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 0
                            CHECK (min_discount_pct >= 0 AND min_discount_pct <= 50),
    max_discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 30
                            CHECK (max_discount_pct >= 0 AND max_discount_pct <= 50),

    -- Parámetros específicos de la regla en JSON
    config_json         JSONB        NOT NULL DEFAULT '{}',  -- parámetros libre según rule_type

    -- Estado
    is_active           BOOLEAN      NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ,

    -- Una sola configuración activa por tipo de regla por tenant
    CONSTRAINT chk_discount_range CHECK (min_discount_pct <= max_discount_pct)
);

COMMENT ON TABLE rule_configs IS
    'Configuración de reglas de automatización por tenant. '
    'Cada regla define parámetros para un flow específico (descuentos, timings, cooldowns). '
    'DiscountGuard: CHECK constraints en min/max_discount_pct previenen '
    'descuentos abusivos a nivel de BD (segunda línea de defensa tras la app). '
    'config_json almacena parámetros adicionales específicos de cada rule_type.';
COMMENT ON COLUMN rule_configs.rule_type        IS 'Tipo de regla. Una configuración activa por tipo por tenant.';
COMMENT ON COLUMN rule_configs.min_discount_pct IS 'Descuento mínimo aplicable (%). CHECK 0-50.';
COMMENT ON COLUMN rule_configs.max_discount_pct IS 'Descuento máximo aplicable (%). CHECK 0-50. DiscountGuard.';
COMMENT ON COLUMN rule_configs.config_json      IS 'Parámetros adicionales en JSONB (p.ej. {reminder_hours: 24, cooldown_days: 30}).';

-- CRÍTICO: una sola regla activa por tipo por tenant
CREATE UNIQUE INDEX IF NOT EXISTS uq_rule_configs_tenant_type
    ON rule_configs (tenant_id, rule_type)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_rule_configs_tenant
    ON rule_configs (tenant_id)
    WHERE is_active = true;

-- RLS
ALTER TABLE rule_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE rule_configs FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('rule_configs', 'rule_configs_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('rule_configs', 'rule_configs_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE, DELETE ON rule_configs TO app_user;

SELECT create_updated_at_trigger('rule_configs');


-- ============================================================================
-- 12. REVENUE_EVENTS
-- Propósito: Registro de cada ingreso generado o recuperado por el sistema.
--            Es la fuente de verdad del Revenue Tracker en el dashboard.
--            Cada cita recuperada genera un revenue_event con el importe y
--            el flow que la originó. Inmutable una vez creado.
-- ============================================================================
CREATE TABLE IF NOT EXISTS revenue_events (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,
    appointment_id      UUID        NOT NULL REFERENCES appointments (id) ON DELETE RESTRICT,
    patient_id          UUID        NOT NULL REFERENCES patients (id) ON DELETE RESTRICT,

    -- Clasificación del ingreso
    event_type          TEXT        NOT NULL DEFAULT 'RecoveredSession'
                            CHECK (event_type IN (
                                'RecoveredSession',   -- cita recuperada por el bot
                                'NewSession',         -- cita nueva captada por el bot (out-of-hours)
                                'SuccessFee',         -- comisión de éxito cobrada a la clínica
                                'Subscription'        -- ingreso de suscripción mensual
                            )),
    source_flow         TEXT        NOT NULL
                            CHECK (source_flow IN ('Manual','MissedCall','LastMinute','NoShowWaitlist',
                                                   'OutOfHours','PostSession','Reactivation','Reschedule')),

    -- Importe
    amount              NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    currency            CHAR(3)     NOT NULL DEFAULT 'EUR',
    discount_applied_pct NUMERIC(5,2) DEFAULT 0
                            CHECK (discount_applied_pct >= 0 AND discount_applied_pct <= 50),

    -- Facturación (para SuccessFee y Subscription)
    stripe_invoice_id   VARCHAR(100),
    billing_period      VARCHAR(20),                        -- YYYY-MM para agregación mensual

    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
    -- Append-only: sin updated_at
);

COMMENT ON TABLE revenue_events IS
    'Fuente de verdad del Revenue Tracker en el dashboard. '
    'Cada cita recuperada/generada por ClinicBoost genera una fila. '
    'También registra los SuccessFee cobrados a la clínica. '
    'Append-only: nunca se modifica un revenue_event creado.';
COMMENT ON COLUMN revenue_events.event_type           IS 'Clasificación: sesión recuperada, nueva, comisión de éxito o suscripción.';
COMMENT ON COLUMN revenue_events.discount_applied_pct IS 'Descuento aplicado a la sesión (para calcular revenue neto).';
COMMENT ON COLUMN revenue_events.billing_period       IS 'Período de facturación YYYY-MM para agregación en dashboard.';

-- CRÍTICO: dashboard de revenue (suma por tenant y período)
CREATE INDEX IF NOT EXISTS idx_revenue_events_tenant_period
    ON revenue_events (tenant_id, billing_period, event_type);

-- Revenue por flow (analytics de qué flow genera más valor)
CREATE INDEX IF NOT EXISTS idx_revenue_events_flow
    ON revenue_events (tenant_id, source_flow, occurred_at DESC);

-- Historial de ingresos de una cita
CREATE INDEX IF NOT EXISTS idx_revenue_events_appointment
    ON revenue_events (appointment_id);

-- RLS
ALTER TABLE revenue_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_events FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('revenue_events', 'revenue_events_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('revenue_events', 'revenue_events_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('revenue_events', 'revenue_events_no_update', 'UPDATE', 'false');

SELECT create_rls_policy('revenue_events', 'revenue_events_no_delete', 'DELETE', 'false');

GRANT SELECT, INSERT ON revenue_events TO app_user;


-- ============================================================================
-- 13. AUTOMATION_RUNS
-- Propósito: Registro de cada ejecución de un flow de automatización.
--            Permite depuración, monitorización de fallos y trazabilidad
--            completa de qué hizo el sistema y cuándo. Cada job de Hangfire
--            que ejecuta un flow crea un automation_run.
-- ============================================================================
CREATE TABLE IF NOT EXISTS automation_runs (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL REFERENCES tenants (id) ON DELETE CASCADE,

    -- Identificación del flow
    flow_name           TEXT        NOT NULL
                            CHECK (flow_name IN (
                                'Flow00_Onboarding',
                                'Flow01_MissedCall',
                                'Flow02_YieldManagement',
                                'Flow03_NoShow',
                                'Flow04_OutOfHours',
                                'Flow05_NPS',
                                'Flow06_Reactivation',
                                'Flow07_Reschedule',
                                'Sync_Calendar',
                                'Job_Reminders',
                                'Job_Expiry'
                            )),

    -- Entidades relacionadas
    patient_id          UUID REFERENCES patients (id) ON DELETE SET NULL,
    appointment_id      UUID REFERENCES appointments (id) ON DELETE SET NULL,
    conversation_id     UUID REFERENCES conversations (id) ON DELETE SET NULL,

    -- Estado de la ejecución
    status              TEXT        NOT NULL DEFAULT 'Running'
                            CHECK (status IN ('Running','Completed','Failed','Skipped')),
    skip_reason         TEXT,                               -- motivo si status = Skipped
    error_message       TEXT,                               -- mensaje de error si status = Failed
    error_stack_trace   TEXT,                               -- stack trace completo (solo Failed)

    -- Hangfire
    hangfire_job_id     VARCHAR(100),                       -- ID del job en Hangfire
    trigger_type        TEXT        NOT NULL DEFAULT 'Scheduled'
                            CHECK (trigger_type IN ('Scheduled','Webhook','Manual','Retry')),

    -- Métricas
    duration_ms         INT,                                -- duración total de la ejecución
    steps_completed     INT         NOT NULL DEFAULT 0,
    messages_sent       INT         NOT NULL DEFAULT 0,
    ai_calls_made       INT         NOT NULL DEFAULT 0,

    -- Contexto de entrada y salida
    input_context       JSONB,                              -- datos de entrada del flow
    output_context      JSONB,                              -- resultado estructurado del flow

    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE automation_runs IS
    'Registro de cada ejecución de flow de automatización (Hangfire jobs). '
    'Permite depuración y monitorización de fallos en el dashboard. '
    'La combinación flow_name + patient_id + started_at permite detectar '
    'ejecuciones duplicadas. Incluye métricas de mensajes enviados y llamadas IA.';
COMMENT ON COLUMN automation_runs.flow_name     IS 'Nombre del flow de ClinicBoost ejecutado.';
COMMENT ON COLUMN automation_runs.skip_reason   IS 'Motivo de omisión (p.ej. "cooldown_activo", "sin_consentimiento").';
COMMENT ON COLUMN automation_runs.hangfire_job_id IS 'ID del job en Hangfire para correlación de logs.';
COMMENT ON COLUMN automation_runs.input_context IS 'Snapshot del contexto de entrada al iniciar el flow.';

-- Runs fallidos a reintentar / alertar (dashboard de operaciones)
CREATE INDEX IF NOT EXISTS idx_automation_runs_failed
    ON automation_runs (tenant_id, started_at DESC)
    WHERE status = 'Failed';

-- Historial de runs por flow (analytics de rendimiento)
CREATE INDEX IF NOT EXISTS idx_automation_runs_flow
    ON automation_runs (tenant_id, flow_name, started_at DESC);

-- Runs de un paciente específico
CREATE INDEX IF NOT EXISTS idx_automation_runs_patient
    ON automation_runs (tenant_id, patient_id, started_at DESC)
    WHERE patient_id IS NOT NULL;

-- Correlación con Hangfire
CREATE INDEX IF NOT EXISTS idx_automation_runs_hangfire
    ON automation_runs (hangfire_job_id)
    WHERE hangfire_job_id IS NOT NULL;

-- RLS
ALTER TABLE automation_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_runs FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('automation_runs', 'automation_runs_isolation', 'ALL', 'tenant_id = current_tenant_id()');

SELECT create_rls_policy('automation_runs', 'automation_runs_insert', 'INSERT', NULL, 'tenant_id = current_tenant_id()');

GRANT SELECT, INSERT, UPDATE ON automation_runs TO app_user;


-- ============================================================================
-- 14. WEBHOOK_EVENTS
-- Propósito: Almacén de webhooks entrantes en crudo (raw) antes de procesar.
--            Patrón "store first, process later": recibir el webhook, persistir
--            inmediatamente (sin lógica de negocio) y encolar para procesamiento
--            asíncrono. Permite reprocessing y auditoría de lo que llegó.
-- ============================================================================
CREATE TABLE IF NOT EXISTS webhook_events (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        REFERENCES tenants (id) ON DELETE SET NULL,  -- puede ser NULL si no se identificó el tenant aún

    -- Origen del webhook
    provider            TEXT        NOT NULL
                            CHECK (provider IN ('Twilio','Stripe','Google','Outlook','Manual')),
    event_type          TEXT        NOT NULL,                -- tipo de evento del proveedor (p.ej. "voice.incoming")
    external_event_id   VARCHAR(500),                        -- ID del evento en el proveedor (CallSid, MessageSid, etc.)

    -- Validación criptográfica
    signature_header    TEXT,                                -- valor del header X-Twilio-Signature
    signature_valid     BOOLEAN,                             -- resultado de la validación HMAC-SHA1
    validation_error    TEXT,                                -- motivo de fallo de validación

    -- Payload completo (raw)
    headers             JSONB,                               -- headers HTTP recibidos
    payload             JSONB       NOT NULL,                -- body del webhook parseado

    -- Estado de procesamiento
    processed           BOOLEAN     NOT NULL DEFAULT false,
    processed_at        TIMESTAMPTZ,
    processing_error    TEXT,                                -- error durante el procesamiento
    automation_run_id   UUID REFERENCES automation_runs (id) ON DELETE SET NULL,

    -- Metadata de red
    source_ip           INET,
    http_method         CHAR(6)     NOT NULL DEFAULT 'POST',

    received_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE webhook_events IS
    'Almacén de webhooks entrantes en crudo. Patrón "store first, process later". '
    'Recibir → persistir inmediatamente → procesar de forma asíncrona (Hangfire). '
    'signature_valid registra si pasó la validación HMAC-SHA1 de Twilio. '
    'Permite reprocessing manual de webhooks fallidos desde el dashboard.';
COMMENT ON COLUMN webhook_events.external_event_id IS 'ID único del evento en el proveedor (CallSid, MessageSid, Stripe event ID).';
COMMENT ON COLUMN webhook_events.signature_valid   IS 'Resultado de la validación criptográfica del webhook.';
COMMENT ON COLUMN webhook_events.payload           IS 'Body completo del webhook en JSONB para reprocessing.';

-- Webhooks pendientes de procesar (Hangfire polling)
CREATE INDEX IF NOT EXISTS idx_webhook_events_pending
    ON webhook_events (received_at)
    WHERE processed = false;

-- Búsqueda por ID externo (correlación con Twilio/Stripe)
CREATE INDEX IF NOT EXISTS idx_webhook_events_external_id
    ON webhook_events (provider, external_event_id)
    WHERE external_event_id IS NOT NULL;

-- Webhooks de un tenant (debugging)
CREATE INDEX IF NOT EXISTS idx_webhook_events_tenant
    ON webhook_events (tenant_id, received_at DESC)
    WHERE tenant_id IS NOT NULL;

-- Webhooks con firma inválida (alertas de seguridad)
CREATE INDEX IF NOT EXISTS idx_webhook_events_invalid_sig
    ON webhook_events (received_at DESC)
    WHERE signature_valid = false;

-- RLS: webhook_events tiene tenant_id nullable (el tenant puede no estar resuelto aún)
-- Se aplica RLS solo cuando tenant_id no es NULL
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events FORCE ROW LEVEL SECURITY;

SELECT create_rls_policy('webhook_events', 'webhook_events_isolation', 'ALL', 'tenant_id = current_tenant_id() OR tenant_id IS NULL');

SELECT create_rls_policy('webhook_events', 'webhook_events_insert', 'INSERT', NULL, 'true');   -- cualquier request puede insertar (se valida después)

GRANT SELECT, INSERT, UPDATE ON webhook_events TO app_user;


-- ============================================================================
-- 15. PROCESSED_EVENTS
-- Propósito: Tabla de idempotencia unificada. Registra eventos ya procesados
--            por event_type + event_id. Antes de procesar cualquier webhook
--            o job, se verifica que no existe en esta tabla. Si existe, se
--            descarta silenciosamente. Sin tenant_id: la idempotencia es global.
-- ============================================================================
CREATE TABLE IF NOT EXISTS processed_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Clave de idempotencia
    event_type      TEXT        NOT NULL,       -- VoiceWebhook, WhatsAppWebhook, StripeEvent, HangfireJob...
    event_id        TEXT        NOT NULL,       -- CallSid, MessageSid, evt_xxx, job-uuid...

    -- Contexto del procesamiento
    tenant_id       UUID REFERENCES tenants (id) ON DELETE SET NULL,  -- opcional para correlación
    result          TEXT,                       -- resultado del procesamiento (Success, Skipped, Error)
    notes           TEXT,                       -- información adicional (útil para debugging)

    processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    -- Append-only: nunca se actualiza
);

COMMENT ON TABLE processed_events IS
    'Tabla de idempotencia global. Registra eventos ya procesados por event_type + event_id. '
    'IdempotencyService verifica esta tabla antes de procesar cualquier webhook o job. '
    'Si el par (event_type, event_id) ya existe → descartar silenciosamente. '
    'Sin RLS: la idempotencia debe ser global (no por tenant). Append-only.';
COMMENT ON COLUMN processed_events.event_type IS 'Tipo de evento: VoiceWebhook, WhatsAppWebhook, StripeEvent, HangfireJob...';
COMMENT ON COLUMN processed_events.event_id   IS 'Identificador único del evento en el sistema origen (CallSid, MessageSid, etc.).';

-- CRÍTICO: clave de idempotencia (la verificación más frecuente del sistema)
CREATE UNIQUE INDEX IF NOT EXISTS uq_processed_events_type_id
    ON processed_events (event_type, event_id);

-- Lookup por tenant para auditorías
CREATE INDEX IF NOT EXISTS idx_processed_events_tenant
    ON processed_events (tenant_id, processed_at DESC)
    WHERE tenant_id IS NOT NULL;

-- Limpieza de registros antiguos (retención 90 días)
CREATE INDEX IF NOT EXISTS idx_processed_events_cleanup
    ON processed_events (processed_at);

GRANT SELECT, INSERT ON processed_events TO app_user;
-- Sin RLS: acceso controlado exclusivamente por la app (IdempotencyService)


-- ============================================================================
-- 16. AUDIT_LOGS
-- Propósito: Auditoría de operaciones sensibles del sistema. Append-only e
--            inmutable. Registra acciones de usuarios humanos y del sistema
--            sobre entidades críticas (cambios de config, borrados, logins,
--            operaciones de IA). Separado de los application logs.
--            Sin tenant_id obligatorio: algunas acciones son de sistema global.
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Contexto del actor
    tenant_id       UUID REFERENCES tenants (id) ON DELETE SET NULL,
    user_id         UUID REFERENCES tenant_users (id) ON DELETE SET NULL,
    actor_type      TEXT        NOT NULL DEFAULT 'System'
                        CHECK (actor_type IN ('User','System','AI','Webhook','Migration')),

    -- Acción auditada
    action          TEXT        NOT NULL,       -- Login, Logout, ConfigChange, PatientDelete, ConsentRevoke,
                                                -- AppointmentOverride, DiscountApplied, AIDecision, etc.
    entity_type     TEXT,                       -- nombre de la tabla/entidad afectada
    entity_id       TEXT,                       -- PK de la entidad afectada (como TEXT para flexibilidad)

    -- Diff de cambios (para ConfigChange, PatientUpdate, etc.)
    old_values      JSONB,                      -- estado anterior de la entidad
    new_values      JSONB,                      -- estado nuevo de la entidad

    -- Contexto de red y request
    ip_address      INET,
    user_agent      TEXT,
    request_id      UUID,                       -- correlation ID del HTTP request

    -- Severidad
    severity        TEXT        NOT NULL DEFAULT 'Info'
                        CHECK (severity IN ('Debug','Info','Warning','Critical')),

    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
    -- Append-only: sin updated_at, sin DELETE
);

COMMENT ON TABLE audit_logs IS
    'Registro inmutable de auditoría de operaciones sensibles. Append-only. '
    'Cubre: logins, cambios de configuración, borrados de datos, anulaciones manuales, '
    'decisiones de IA y cualquier operación que requiera trazabilidad para RGPD/cumplimiento. '
    'old_values y new_values permiten reconstruir el estado de cualquier entidad. '
    'Nunca se hace UPDATE ni DELETE: es evidencia legal.';
COMMENT ON COLUMN audit_logs.action      IS 'Acción auditada: Login, ConfigChange, PatientDelete, ConsentRevoke, AIDecision...';
COMMENT ON COLUMN audit_logs.old_values  IS 'Estado anterior de la entidad (JSONB). Nulo si es creación.';
COMMENT ON COLUMN audit_logs.new_values  IS 'Estado nuevo de la entidad (JSONB). Nulo si es borrado.';
COMMENT ON COLUMN audit_logs.request_id  IS 'Correlation ID del HTTP request (para correlación con application logs).';
COMMENT ON COLUMN audit_logs.severity    IS 'Severidad: Debug (verbose), Info (normal), Warning, Critical (alerta inmediata).';

-- Búsqueda por tenant y fecha (panel de auditoría)
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant
    ON audit_logs (tenant_id, occurred_at DESC)
    WHERE tenant_id IS NOT NULL;

-- Auditoría de un usuario específico
CREATE INDEX IF NOT EXISTS idx_audit_logs_user
    ON audit_logs (user_id, occurred_at DESC)
    WHERE user_id IS NOT NULL;

-- Acciones críticas (alertas de seguridad)
CREATE INDEX IF NOT EXISTS idx_audit_logs_critical
    ON audit_logs (occurred_at DESC)
    WHERE severity = 'Critical';

-- Búsqueda por entidad específica (historial de cambios de un registro)
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
    ON audit_logs (entity_type, entity_id, occurred_at DESC)
    WHERE entity_type IS NOT NULL;

-- Retención: auditoría de los últimos N días (limpieza programada)
CREATE INDEX IF NOT EXISTS idx_audit_logs_cleanup
    ON audit_logs (occurred_at);

GRANT SELECT, INSERT ON audit_logs TO app_user;
-- Sin RLS en audit_logs: el sistema escribe desde cualquier contexto.
-- El acceso de lectura se controla en la capa de app (solo Owner/Admin).
-- La escritura es libre para el app_user (registro desde cualquier contexto).
-- Para máxima seguridad, considerar un rol audit_writer separado con solo INSERT.


-- ============================================================================
-- GRANTS FINALES
-- ============================================================================

-- Acceso de lectura a la tabla de tenants para el app_user
-- (el tenant solo puede leer su propio registro; la app filtra por ID del JWT)
GRANT SELECT ON tenants TO app_user;
GRANT UPDATE ON tenants TO app_user;  -- para updated_at y configuración


-- ============================================================================
-- RESUMEN DE TABLAS Y SU RELACIÓN CON RLS
-- ============================================================================
--
-- Tabla                | tenant_id | RLS habilitado | Append-only | Notas
-- ---------------------|-----------|----------------|-------------|------
-- tenants              | N/A (ES el tenant) | NO    | NO          | Acceso por JWT en app
-- tenant_users         | NOT NULL  | SÍ             | NO          | Staff de la clínica
-- patients             | NOT NULL  | SÍ             | NO          | E.164 único por tenant
-- patient_consents     | NOT NULL  | SÍ             | SÍ          | RGPD append-only
-- calendar_connections | NOT NULL  | SÍ             | NO          | iCal / OAuth
-- appointments         | NOT NULL  | SÍ             | NO          | Citas
-- appointment_events   | NOT NULL  | SÍ             | SÍ          | Ciclo de vida citas
-- conversations        | NOT NULL  | SÍ             | NO          | Hilos WhatsApp/voz
-- messages             | NOT NULL  | SÍ             | SÍ          | Mensajes individuales
-- waitlist_entries     | NOT NULL  | SÍ             | NO          | Lista de espera
-- rule_configs         | NOT NULL  | SÍ             | NO          | Reglas y descuentos
-- revenue_events       | NOT NULL  | SÍ             | SÍ          | Revenue Tracker
-- automation_runs      | NOT NULL  | SÍ             | parcial     | Ejecuciones de flows
-- webhook_events       | NULLABLE  | SÍ (flexible)  | parcial     | Webhooks raw entrantes
-- processed_events     | NULLABLE  | NO             | SÍ          | Idempotencia global
-- audit_logs           | NULLABLE  | NO             | SÍ          | Auditoría global
--
-- ============================================================================
