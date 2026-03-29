namespace ClinicBoost.Api.Features.Webhooks.WhatsApp;

/// <summary>
/// POST /api/webhooks/whatsapp — Recibe webhooks de Twilio para mensajes WhatsApp.
/// La firma HMAC-SHA1 se valida en TwilioSignatureMiddleware antes de llegar aquí.
/// Implementación completa en Bloque 2.
/// </summary>
public static class Endpoint
{
    public static void MapWhatsAppWebhookEndpoint(this WebApplication app)
    {
        app.MapPost("/api/webhooks/whatsapp", (HttpContext context, ILogger<Program> logger) =>
        {
            logger.LogInformation("WhatsApp webhook received — stub (Bloque 2)");
            return Results.Ok();
        })
        .WithTags("Webhooks")
        .AllowAnonymous();
    }
}
