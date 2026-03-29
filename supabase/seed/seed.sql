-- ============================================================================
-- ClinicBoost — Seed data para desarrollo
-- ============================================================================
-- Ejecutar después de las migraciones para tener datos de prueba.
-- NO ejecutar en producción.
-- ============================================================================

-- Tenant de prueba: Clínica FisioNavarra
INSERT INTO tenants (id, name, slug, timezone, phone, email, subscription_tier, subscription_status)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'Clínica FisioNavarra',
    'fisionavarra',
    'Europe/Madrid',
    '+34948000001',
    'admin@fisionavarra.es',
    'Professional',
    'Active'
) ON CONFLICT (slug) DO NOTHING;

-- Tenant de prueba: Centro Rehabilitación Pamplona
INSERT INTO tenants (id, name, slug, timezone, phone, email, subscription_tier, subscription_status)
VALUES (
    'a0000000-0000-0000-0000-000000000002',
    'Centro Rehabilitación Pamplona',
    'rehab-pamplona',
    'Europe/Madrid',
    '+34948000002',
    'admin@rehabpamplona.es',
    'Starter',
    'Active'
) ON CONFLICT (slug) DO NOTHING;
