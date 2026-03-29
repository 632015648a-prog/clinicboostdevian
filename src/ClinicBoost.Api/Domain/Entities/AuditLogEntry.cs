namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Registro de auditoría para cambios críticos y operaciones sensibles.
/// Separado de los application logs.
/// </summary>
public class AuditLogEntry
{
    public Guid Id { get; set; }
    public Guid? TenantId { get; set; }
    public Guid? UserId { get; set; }
    public string Action { get; set; } = string.Empty; // Login, ConfigChange, PatientDelete, etc.
    public string EntityType { get; set; } = string.Empty;
    public string? EntityId { get; set; }
    public string? OldValues { get; set; }
    public string? NewValues { get; set; }
    public string? IpAddress { get; set; }
    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
}
