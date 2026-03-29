namespace ClinicBoost.Api.Domain.Entities;

public class BillingEvent : TenantEntity
{
    public decimal Amount { get; set; }
    public string BillingType { get; set; } = string.Empty; // SuccessFee, Subscription
    public string Period { get; set; } = string.Empty;
    public string? StripeInvoiceId { get; set; }
}
