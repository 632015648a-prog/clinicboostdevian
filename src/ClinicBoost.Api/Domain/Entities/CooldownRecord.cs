namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Registra el último mensaje proactivo enviado a un paciente por tenant.
/// Cooldown de 30 días entre mensajes proactivos para evitar bloqueo de Meta.
/// </summary>
public class CooldownRecord : TenantEntity
{
    public string PatientPhone { get; set; } = string.Empty;
    public DateTime LastProactiveMessageAt { get; set; } = DateTime.UtcNow;
}
