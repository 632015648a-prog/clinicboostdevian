using System.Security.Cryptography;
using System.Text;

namespace ClinicBoost.Api.Infrastructure.Middleware;

/// <summary>
/// Middleware que valida la firma HMAC-SHA1 de los webhooks de Twilio.
/// Solo se aplica a rutas que comienzan con /api/webhooks/.
/// Un endpoint sin esta validación es equivalente a un endpoint público
/// que cualquiera puede llamar con datos falsos.
/// </summary>
public class TwilioSignatureMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<TwilioSignatureMiddleware> _logger;

    public TwilioSignatureMiddleware(RequestDelegate next, ILogger<TwilioSignatureMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? string.Empty;

        // Solo aplicar a rutas de webhooks
        if (!path.StartsWith("/api/webhooks", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        var twilioAuthToken = context.RequestServices.GetRequiredService<IConfiguration>()["TWILIO_AUTH_TOKEN"];
        if (string.IsNullOrEmpty(twilioAuthToken))
        {
            _logger.LogError("TWILIO_AUTH_TOKEN not configured — rejecting webhook");
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            return;
        }

        var signature = context.Request.Headers["X-Twilio-Signature"].FirstOrDefault();
        if (string.IsNullOrEmpty(signature))
        {
            _logger.LogWarning("Webhook request without X-Twilio-Signature header from {IP}",
                context.Connection.RemoteIpAddress);
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }

        // Habilitar buffering para poder leer el body múltiples veces
        context.Request.EnableBuffering();

        // Construir la URL completa del request
        var url = $"{context.Request.Scheme}://{context.Request.Host}{context.Request.Path}{context.Request.QueryString}";

        // Leer y ordenar los parámetros del body (form-encoded)
        var form = await context.Request.ReadFormAsync();
        var sortedParams = form.OrderBy(kvp => kvp.Key).ToList();

        // Construir el string para validar: URL + params concatenados
        var dataToSign = new StringBuilder(url);
        foreach (var param in sortedParams)
        {
            dataToSign.Append(param.Key);
            dataToSign.Append(param.Value.ToString());
        }

        // Calcular HMAC-SHA1
        using var hmac = new HMACSHA1(Encoding.UTF8.GetBytes(twilioAuthToken));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(dataToSign.ToString()));
        var expectedSignature = Convert.ToBase64String(hash);

        // Comparación de tiempo constante para prevenir timing attacks
        var expectedBytes = Encoding.UTF8.GetBytes(expectedSignature);
        var receivedBytes = Encoding.UTF8.GetBytes(signature);

        if (expectedBytes.Length != receivedBytes.Length ||
            !CryptographicOperations.FixedTimeEquals(expectedBytes, receivedBytes))
        {
            _logger.LogWarning("Invalid Twilio signature for {Path} from {IP}",
                path, context.Connection.RemoteIpAddress);
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }

        // Resetear la posición del body para que el handler lo pueda leer
        context.Request.Body.Position = 0;

        await _next(context);
    }
}
