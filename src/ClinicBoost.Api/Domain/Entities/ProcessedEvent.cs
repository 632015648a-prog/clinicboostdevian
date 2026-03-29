namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Servicio de idempotencia unificado. Registra eventos ya procesados
/// para evitar procesamiento duplicado en webhooks y jobs.
/// </summary>
public class ProcessedEvent
{
    public Guid Id { get; set; }
    public string EventType { get; set; } = string.Empty; // VoiceWebhook, WhatsAppWebhook, etc.
    public string EventId { get; set; } = string.Empty; // CallSid, MessageSid, etc.
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
}
