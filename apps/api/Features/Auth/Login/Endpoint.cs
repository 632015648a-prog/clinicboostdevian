namespace ClinicBoost.Api.Features.Auth.Login;

/// <summary>
/// POST /api/auth/login — Autenticación de usuarios.
/// Implementación completa en Bloque 1 (Multi-Tenant + Auth).
/// </summary>
public static class Endpoint
{
    public static void MapLoginEndpoint(this WebApplication app)
    {
        app.MapPost("/api/auth/login", () =>
        {
            return Results.Json(new
            {
                type = "https://tools.ietf.org/html/rfc7807",
                title = "Not Implemented",
                status = 501,
                detail = "Login endpoint — implementación en Bloque 1"
            }, statusCode: StatusCodes.Status501NotImplemented);
        })
        .WithTags("Auth")
        .AllowAnonymous();
    }
}
