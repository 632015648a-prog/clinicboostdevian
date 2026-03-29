using ClinicBoost.Api.Domain.Entities;
using ClinicBoost.Api.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace ClinicBoost.Api.Infrastructure.Services.Idempotency;

public class IdempotencyService : IIdempotencyService
{
    private readonly AppDbContext _db;
    private readonly ILogger<IdempotencyService> _logger;

    public IdempotencyService(AppDbContext db, ILogger<IdempotencyService> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task<bool> IsAlreadyProcessedAsync(string eventType, string eventId, CancellationToken ct = default)
    {
        return await _db.ProcessedEvents
            .AnyAsync(pe => pe.EventType == eventType && pe.EventId == eventId, ct);
    }

    public async Task<bool> MarkAsProcessedAsync(string eventType, string eventId, CancellationToken ct = default)
    {
        try
        {
            _db.ProcessedEvents.Add(new ProcessedEvent
            {
                Id = Guid.NewGuid(),
                EventType = eventType,
                EventId = eventId,
                ProcessedAt = DateTime.UtcNow
            });
            await _db.SaveChangesAsync(ct);
            return true;
        }
        catch (DbUpdateException)
        {
            // Unique constraint violation — ya fue procesado (race condition controlada)
            _logger.LogDebug("Event {EventType}:{EventId} already processed (concurrent)", eventType, eventId);
            return false;
        }
    }
}
