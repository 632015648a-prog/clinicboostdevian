using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Registra cada cita generada o recuperada por el sistema.
/// Es la fuente de verdad del Revenue Tracker en el dashboard.
/// </summary>
public class RecoveredRevenueEvent : TenantEntity
{
    public Guid AppointmentId { get; set; }
    public Guid PatientId { get; set; }
    public decimal Amount { get; set; }
    public SourceFlow SourceFlow { get; set; }
    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
}
