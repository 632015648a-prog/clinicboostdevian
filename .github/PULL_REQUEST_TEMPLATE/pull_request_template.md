## Descripción

<!-- Breve descripción de los cambios -->

## Bloque

<!-- ¿A qué bloque del roadmap pertenece? -->
- [ ] Bloque 0 — Scaffolding
- [ ] Bloque 1 — Multi-tenant + Auth + RLS
- [ ] Bloque 2-17 — Otro

## Checklist

- [ ] `dotnet build` pasa sin errores
- [ ] `npm run build` pasa sin errores
- [ ] `npm run lint` pasa sin errores
- [ ] No hay secrets hardcodeados
- [ ] Todas las entidades de negocio llevan `tenant_id`
- [ ] No se usa MediatR, AutoMapper ni repositorios genéricos
- [ ] JWT en cookies httpOnly (no localStorage)
- [ ] Timezone via servicio (no AddHours)
