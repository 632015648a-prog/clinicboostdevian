namespace ClinicBoost.Api.Features.Webhooks.Voice;

/// <summary>
/// POST /api/webhooks/voice — Recibe webhooks de Twilio para llamadas de voz.
/// La firma HMAC-SHA1 se valida en TwilioSignatureMiddleware antes de llegar aquí.
/// Implementación completa en Bloque 2.
/// </summary>
public static class Endpoint
{
    public static void MapVoiceWebhookEndpoint(this WebApplication app)
    {
        app.MapPost("/api/webhooks/voice", (HttpContext context, ILogger<Program> logger) =>
        {
            logger.LogInformation("Voice webhook received — stub (Bloque 2)");

            // Retornar TwiML vacío válido (Twilio requiere respuesta rápida)
            context.Response.ContentType = "application/xml";
            return Results.Content(
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>",
                "application/xml");
        })
        .WithTags("Webhooks")
        .AllowAnonymous();
    }
}
