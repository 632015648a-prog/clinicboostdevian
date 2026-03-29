using ClinicBoost.Api.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace ClinicBoost.Api.Infrastructure.Persistence;

/// <summary>
/// Único AppDbContext del proyecto. Filtros globales por TenantId
/// garantizan aislamiento multi-tenant a nivel de EF Core.
/// PostgreSQL RLS actúa como última línea de defensa a nivel de DB.
/// </summary>
public class AppDbContext : DbContext
{
    private readonly Guid _currentTenantId;

    public AppDbContext(DbContextOptions<AppDbContext> options, IHttpContextAccessor httpContextAccessor)
        : base(options)
    {
        if (httpContextAccessor.HttpContext?.Items.TryGetValue("TenantId", out var tenantIdObj) == true
            && tenantIdObj is Guid tenantId)
        {
            _currentTenantId = tenantId;
        }
    }

    // Tablas de negocio multi-tenant
    public DbSet<Patient> Patients => Set<Patient>();
    public DbSet<Appointment> Appointments => Set<Appointment>();
    public DbSet<Slot> Slots => Set<Slot>();
    public DbSet<ConsentRecord> ConsentRecords => Set<ConsentRecord>();
    public DbSet<RecoveredRevenueEvent> RecoveredRevenueEvents => Set<RecoveredRevenueEvent>();
    public DbSet<WaitlistEntry> WaitlistEntries => Set<WaitlistEntry>();
    public DbSet<CooldownRecord> CooldownRecords => Set<CooldownRecord>();
    public DbSet<BillingEvent> BillingEvents => Set<BillingEvent>();
    public DbSet<TenantRuleConfig> TenantRuleConfigs => Set<TenantRuleConfig>();
    public DbSet<DashboardTask> DashboardTasks => Set<DashboardTask>();

    // Tablas sin tenant_id
    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<ProcessedEvent> ProcessedEvents => Set<ProcessedEvent>();
    public DbSet<AuditLogEntry> AuditLogEntries => Set<AuditLogEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Filtros globales multi-tenant: todas las queries filtran por tenant automáticamente
        modelBuilder.Entity<Patient>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<Appointment>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<Slot>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<ConsentRecord>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<RecoveredRevenueEvent>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<WaitlistEntry>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<CooldownRecord>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<BillingEvent>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<TenantRuleConfig>().HasQueryFilter(e => e.TenantId == _currentTenantId);
        modelBuilder.Entity<DashboardTask>().HasQueryFilter(e => e.TenantId == _currentTenantId);

        // Índice único: teléfono del paciente por tenant
        modelBuilder.Entity<Patient>()
            .HasIndex(p => new { p.TenantId, p.Phone })
            .IsUnique();

        // Índice para idempotencia: event_type + event_id
        modelBuilder.Entity<ProcessedEvent>()
            .HasIndex(pe => new { pe.EventType, pe.EventId })
            .IsUnique();

        // Índice para cooldown: tenant + phone
        modelBuilder.Entity<CooldownRecord>()
            .HasIndex(c => new { c.TenantId, c.PatientPhone })
            .IsUnique();

        // DiscountGuard CHECK constraint (migración SQL se genera en Bloque 1)
        // Los CHECK constraints viven en PostgreSQL, no en EF Core.

        // Configuración de enums como strings para legibilidad en DB
        ConfigureEnumConversions(modelBuilder);

        // Configuración de nombres de tablas en snake_case para PostgreSQL
        ConfigureTableNames(modelBuilder);
    }

    public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
    {
        // Segunda línea de defensa: asignar TenantId a entidades nuevas que no lo tengan
        foreach (var entry in ChangeTracker.Entries<TenantEntity>())
        {
            if (entry.State == EntityState.Added && entry.Entity.TenantId == Guid.Empty)
            {
                entry.Entity.TenantId = _currentTenantId;
            }

            if (entry.State == EntityState.Modified)
            {
                entry.Entity.UpdatedAt = DateTime.UtcNow;
            }
        }

        return await base.SaveChangesAsync(cancellationToken);
    }

    private static void ConfigureEnumConversions(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Patient>()
            .Property(p => p.PreferredChannel).HasConversion<string>();
        modelBuilder.Entity<Appointment>()
            .Property(a => a.Status).HasConversion<string>();
        modelBuilder.Entity<Appointment>()
            .Property(a => a.SourceFlow).HasConversion<string>();
        modelBuilder.Entity<Appointment>()
            .Property(a => a.BookingChannel).HasConversion<string>();
        modelBuilder.Entity<Slot>()
            .Property(s => s.Source).HasConversion<string>();
        modelBuilder.Entity<ConsentRecord>()
            .Property(c => c.ConsentStatus).HasConversion<string>();
        modelBuilder.Entity<ConsentRecord>()
            .Property(c => c.Channel).HasConversion<string>();
        modelBuilder.Entity<RecoveredRevenueEvent>()
            .Property(r => r.SourceFlow).HasConversion<string>();
        modelBuilder.Entity<WaitlistEntry>()
            .Property(w => w.Status).HasConversion<string>();
        modelBuilder.Entity<DashboardTask>()
            .Property(d => d.TaskType).HasConversion<string>();
        modelBuilder.Entity<DashboardTask>()
            .Property(d => d.Priority).HasConversion<string>();
        modelBuilder.Entity<Tenant>()
            .Property(t => t.SubscriptionTier).HasConversion<string>();
        modelBuilder.Entity<Tenant>()
            .Property(t => t.SubscriptionStatus).HasConversion<string>();
    }

    private static void ConfigureTableNames(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Tenant>().ToTable("tenants");
        modelBuilder.Entity<Patient>().ToTable("patients");
        modelBuilder.Entity<Appointment>().ToTable("appointments");
        modelBuilder.Entity<Slot>().ToTable("slots");
        modelBuilder.Entity<ConsentRecord>().ToTable("consent_records");
        modelBuilder.Entity<RecoveredRevenueEvent>().ToTable("recovered_revenue_events");
        modelBuilder.Entity<WaitlistEntry>().ToTable("waitlist_entries");
        modelBuilder.Entity<CooldownRecord>().ToTable("cooldown_records");
        modelBuilder.Entity<BillingEvent>().ToTable("billing_events");
        modelBuilder.Entity<TenantRuleConfig>().ToTable("tenant_rule_configs");
        modelBuilder.Entity<DashboardTask>().ToTable("dashboard_tasks");
        modelBuilder.Entity<ProcessedEvent>().ToTable("processed_events");
        modelBuilder.Entity<AuditLogEntry>().ToTable("audit_log_entries");
    }
}
