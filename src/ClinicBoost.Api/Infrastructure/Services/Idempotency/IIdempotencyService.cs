namespace ClinicBoost.Api.Infrastructure.Services.Idempotency;

/// <summary>
/// Servicio de idempotencia unificado. Registra eventos ya procesados
/// en la tabla processed_events para evitar procesamiento duplicado.
/// </summary>
public interface IIdempotencyService
{
    /// <summary>
    /// Verifica si un evento ya fue procesado.
    /// </summary>
    Task<bool> IsAlreadyProcessedAsync(string eventType, string eventId, CancellationToken ct = default);

    /// <summary>
    /// Marca un evento como procesado. Retorna false si ya existía (race condition).
    /// </summary>
    Task<bool> MarkAsProcessedAsync(string eventType, string eventId, CancellationToken ct = default);
}
