using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class Patient : TenantEntity
{
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Teléfono en formato E.164 (ej: +34612345678). Único por tenant.
    /// Validado con libphonenumber antes de persistir.
    /// </summary>
    public string Phone { get; set; } = string.Empty;

    public string? Email { get; set; }
    public DateTime? LastVisitDate { get; set; }
    public int TotalSessions { get; set; }
    public decimal AverageRating { get; set; }
    public bool IsActive { get; set; } = true;
    public bool ConsentGranted { get; set; }
    public DateTime? ConsentGrantedAt { get; set; }
    public BookingChannel PreferredChannel { get; set; } = BookingChannel.WhatsApp;
}
