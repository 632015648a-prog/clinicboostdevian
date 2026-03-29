namespace ClinicBoost.Api.Infrastructure.Services.Messaging;

/// <summary>
/// Implementación de ISMSService usando Twilio.
/// Se configurará completamente en el Bloque 2 (Webhooks de Twilio).
/// </summary>
public class TwilioSMSService : ISMSService
{
    private readonly IConfiguration _config;
    private readonly ILogger<TwilioSMSService> _logger;

    public TwilioSMSService(IConfiguration config, ILogger<TwilioSMSService> logger)
    {
        _config = config;
        _logger = logger;
    }

    public Task<SendResult> SendWhatsAppAsync(string toPhone, string message, Guid tenantId, CancellationToken ct = default)
    {
        // TODO (Bloque 2): Implementar con Twilio SDK + circuit breaker + retry
        _logger.LogInformation("SendWhatsApp stub called for tenant {TenantId}", tenantId);
        return Task.FromResult(new SendResult(false, null, null, "Not implemented yet — Bloque 2"));
    }

    public Task<BulkSendResult> SendBulkWhatsAppAsync(
        IEnumerable<(string phone, string message)> messages,
        Guid tenantId,
        CancellationToken ct = default)
    {
        _logger.LogInformation("SendBulkWhatsApp stub called for tenant {TenantId}", tenantId);
        return Task.FromResult(new BulkSendResult(0, 0, []));
    }

    public Task<bool> IsWhatsAppActiveAsync(string phone, CancellationToken ct = default)
    {
        return Task.FromResult(false);
    }
}
