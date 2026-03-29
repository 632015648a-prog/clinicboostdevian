using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class WaitlistEntry : TenantEntity
{
    public Guid PatientId { get; set; }
    public DateOnly RequestedDate { get; set; }
    public int Priority { get; set; }
    public WaitlistStatus Status { get; set; } = WaitlistStatus.Pending;
}
