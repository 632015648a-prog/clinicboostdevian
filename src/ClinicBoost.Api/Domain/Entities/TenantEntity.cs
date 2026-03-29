namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Entidad base de la que heredan todas las entidades multi-tenant.
/// Garantiza que todas las tablas de negocio tienen tenant_id.
/// </summary>
public abstract class TenantEntity
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
}
