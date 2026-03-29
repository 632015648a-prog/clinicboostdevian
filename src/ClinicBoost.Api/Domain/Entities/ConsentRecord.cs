using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class ConsentRecord : TenantEntity
{
    public string PatientPhone { get; set; } = string.Empty;
    public ConsentStatus ConsentStatus { get; set; } = ConsentStatus.Pending;
    public string ConsentTextVersion { get; set; } = "1.0";
    public DateTime? GrantedAt { get; set; }
    public string? IpAddress { get; set; }

    /// <summary>
    /// Canal por el que se obtuvo el consentimiento.
    /// </summary>
    public BookingChannel Channel { get; set; } = BookingChannel.WhatsApp;
}
