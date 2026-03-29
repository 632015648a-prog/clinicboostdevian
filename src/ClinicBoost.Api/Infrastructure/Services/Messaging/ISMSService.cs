namespace ClinicBoost.Api.Infrastructure.Services.Messaging;

/// <summary>
/// Interfaz de abstracción de mensajería para WhatsApp/SMS.
/// Permite cambiar de proveedor (Twilio, 360dialog, Infobip) sin modificar el código de negocio.
/// </summary>
public interface ISMSService
{
    /// <summary>
    /// Enviar mensaje de WhatsApp a un número de teléfono.
    /// </summary>
    Task<SendResult> SendWhatsAppAsync(string toPhone, string message, Guid tenantId, CancellationToken ct = default);

    /// <summary>
    /// Enviar mensaje a múltiples destinatarios (para campañas de reactivación).
    /// </summary>
    Task<BulkSendResult> SendBulkWhatsAppAsync(
        IEnumerable<(string phone, string message)> messages,
        Guid tenantId,
        CancellationToken ct = default);

    /// <summary>
    /// Verificar si un número tiene WhatsApp activo.
    /// </summary>
    Task<bool> IsWhatsAppActiveAsync(string phone, CancellationToken ct = default);
}

public record SendResult(bool Success, string? MessageSid, int? ErrorCode, string? ErrorMessage);

public record BulkSendResult(int TotalSent, int TotalFailed, IReadOnlyList<SendResult> Results);
