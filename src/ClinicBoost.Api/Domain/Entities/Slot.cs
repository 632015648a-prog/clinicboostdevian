using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class Slot : TenantEntity
{
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public bool IsAvailable { get; set; } = true;
    public Guid? TherapistId { get; set; }

    /// <summary>
    /// ID externo del evento en el software de la clínica (vía iCal).
    /// </summary>
    public string? ExternalId { get; set; }

    public SlotSource Source { get; set; } = SlotSource.Manual;
}
