using ClinicBoost.Api.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace ClinicBoost.Api.Features.Health;

/// <summary>
/// Health checks separados: liveness (la app responde), readiness (dependencias listas).
/// No golpear servicios externos en liveness para evitar falsos negativos.
/// </summary>
public static class HealthEndpoint
{
    public static void MapHealthEndpoints(this WebApplication app)
    {
        // Liveness: la aplicación está viva y puede responder
        app.MapGet("/health", () => Results.Ok(new
        {
            status = "healthy",
            version = "0.1.0",
            timestamp = DateTime.UtcNow
        }))
        .WithTags("Health")
        .AllowAnonymous();

        // Readiness: la aplicación y sus dependencias críticas están listas
        app.MapGet("/health/ready", async (AppDbContext db) =>
        {
            var checks = new Dictionary<string, string>();

            try
            {
                // Verificar conexión a PostgreSQL/Supabase
                var canConnect = await db.Database.CanConnectAsync();
                checks["database"] = canConnect ? "ok" : "failed";
            }
            catch (Exception ex)
            {
                checks["database"] = $"failed: {ex.Message}";
            }

            var allHealthy = checks.Values.All(v => v == "ok");

            return allHealthy
                ? Results.Ok(new { status = "ready", checks, timestamp = DateTime.UtcNow })
                : Results.Json(
                    new { status = "degraded", checks, timestamp = DateTime.UtcNow },
                    statusCode: StatusCodes.Status503ServiceUnavailable);
        })
        .WithTags("Health")
        .AllowAnonymous();
    }
}
