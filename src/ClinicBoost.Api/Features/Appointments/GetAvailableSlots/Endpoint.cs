namespace ClinicBoost.Api.Features.Appointments.GetAvailableSlots;

/// <summary>
/// GET /api/appointments/slots — Obtener huecos disponibles para una fecha.
/// Implementación completa en Bloque 4 (Flow 01).
/// </summary>
public static class Endpoint
{
    public static void MapGetAvailableSlotsEndpoint(this WebApplication app)
    {
        app.MapGet("/api/appointments/slots", () =>
        {
            return Results.Json(new
            {
                type = "https://tools.ietf.org/html/rfc7807",
                title = "Not Implemented",
                status = 501,
                detail = "GetAvailableSlots endpoint — implementación en Bloque 4"
            }, statusCode: StatusCodes.Status501NotImplemented);
        })
        .WithTags("Appointments")
        .RequireAuthorization();
    }
}
