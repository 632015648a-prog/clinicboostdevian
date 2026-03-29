using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class DashboardTask : TenantEntity
{
    public string? PatientPhone { get; set; }
    public string Message { get; set; } = string.Empty;
    public DashboardTaskType TaskType { get; set; }
    public DashboardTaskPriority Priority { get; set; } = DashboardTaskPriority.Normal;
    public DateTime? DueDate { get; set; }
    public bool IsCompleted { get; set; }
    public DateTime? CompletedAt { get; set; }
}
