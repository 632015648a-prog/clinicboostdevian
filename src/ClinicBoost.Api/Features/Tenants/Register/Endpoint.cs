namespace ClinicBoost.Api.Features.Tenants.Register;

/// <summary>
/// POST /api/tenants/register — Alta de una nueva clínica.
/// Implementación completa en Bloque 1 (Multi-Tenant + Auth).
/// </summary>
public static class Endpoint
{
    public static void MapTenantRegisterEndpoint(this WebApplication app)
    {
        app.MapPost("/api/tenants/register", () =>
        {
            return Results.Json(new
            {
                type = "https://tools.ietf.org/html/rfc7807",
                title = "Not Implemented",
                status = 501,
                detail = "Tenant registration endpoint — implementación en Bloque 1"
            }, statusCode: StatusCodes.Status501NotImplemented);
        })
        .WithTags("Tenants")
        .AllowAnonymous();
    }
}
