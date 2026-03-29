namespace ClinicBoost.Api.Domain.Entities;

/// <summary>
/// Configuración de reglas de descuento por tenant.
/// Los límites min/max están protegidos por CHECK constraints en PostgreSQL (DiscountGuard).
/// </summary>
public class TenantRuleConfig : TenantEntity
{
    public string RuleType { get; set; } = string.Empty; // LastMinuteDiscount, LoyaltyDiscount, etc.
    public decimal MinDiscountPct { get; set; }
    public decimal MaxDiscountPct { get; set; } = 30;
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Parámetros adicionales de la regla en formato JSON.
    /// </summary>
    public string? ConfigJson { get; set; }
}
