using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Representa una clínica de fisioterapia registrada en el sistema.
/// No hereda de TenantEntity porque ES el tenant.
/// </summary>
public class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string? TwilioPhoneNumber { get; set; }
    public string? ICalFeedUrl { get; set; }
    public TimeOnly BusinessHoursStart { get; set; } = new(9, 0);
    public TimeOnly BusinessHoursEnd { get; set; } = new(20, 0);
    public decimal StandardSessionPrice { get; set; }
    public int InactivityThresholdDays { get; set; } = 60;

    /// <summary>
    /// IANA timezone del tenant (ej: "Europe/Madrid"). Todo se persiste en UTC
    /// y se convierte con TimeZoneInfo para presentación.
    /// </summary>
    public string Timezone { get; set; } = "Europe/Madrid";

    public SubscriptionTier SubscriptionTier { get; set; } = SubscriptionTier.Free;
    public SubscriptionStatus SubscriptionStatus { get; set; } = SubscriptionStatus.Trial;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
}
