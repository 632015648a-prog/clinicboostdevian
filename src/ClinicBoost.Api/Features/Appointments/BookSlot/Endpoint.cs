namespace ClinicBoost.Api.Features.Appointments.BookSlot;

/// <summary>
/// POST /api/appointments/book — Reservar un hueco.
/// La IA NUNCA confirma citas directamente; el backend (AppointmentEngine) ejecuta.
/// Implementación completa en Bloque 4 (Flow 01).
/// </summary>
public static class Endpoint
{
    public static void MapBookSlotEndpoint(this WebApplication app)
    {
        app.MapPost("/api/appointments/book", () =>
        {
            return Results.Json(new
            {
                type = "https://tools.ietf.org/html/rfc7807",
                title = "Not Implemented",
                status = 501,
                detail = "BookSlot endpoint — implementación en Bloque 4"
            }, statusCode: StatusCodes.Status501NotImplemented);
        })
        .WithTags("Appointments")
        .RequireAuthorization();
    }
}
