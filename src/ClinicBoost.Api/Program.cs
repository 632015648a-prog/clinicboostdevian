using System.Text;
using ClinicBoost.Api.Features.Appointments.BookSlot;
using ClinicBoost.Api.Features.Appointments.GetAvailableSlots;
using ClinicBoost.Api.Features.Auth.Login;
using ClinicBoost.Api.Features.Health;
using ClinicBoost.Api.Features.Tenants.Register;
using ClinicBoost.Api.Features.Webhooks.Voice;
using ClinicBoost.Api.Features.Webhooks.WhatsApp;
using ClinicBoost.Api.Infrastructure.Middleware;
using ClinicBoost.Api.Infrastructure.Persistence;
using ClinicBoost.Api.Infrastructure.Services.Idempotency;
using ClinicBoost.Api.Infrastructure.Services.Messaging;
using ClinicBoost.Api.Infrastructure.Services.Timezone;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// ─── Configuración desde variables de entorno ───────────────────────────────
builder.Configuration.AddEnvironmentVariables();

// ─── PostgreSQL / Supabase ──────────────────────────────────────────────────
var connectionString = builder.Configuration["DATABASE_URL"]
    ?? "Host=localhost;Database=clinicboost;Username=postgres;Password=postgres";

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(connectionString));

// ─── Autenticación JWT (cookies httpOnly — NUNCA localStorage) ──────────────
var jwtSecret = builder.Configuration["JWT_SECRET"] ?? "dev-secret-key-min-32-chars-long!!";
var jwtIssuer = builder.Configuration["JWT_ISSUER"] ?? "https://clinicboost.io";
var jwtAudience = builder.Configuration["JWT_AUDIENCE"] ?? "clinicboost-dashboard";

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtAudience,
            ClockSkew = TimeSpan.FromSeconds(30)
        };

        // Leer JWT de cookie httpOnly si no viene en Authorization header
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                if (context.Request.Cookies.TryGetValue("clinicboost_auth", out var token))
                {
                    context.Token = token;
                }
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();

// ─── CORS (origen desde configuración) ──────────────────────────────────────
var corsOrigins = builder.Configuration["CORS_ALLOWED_ORIGINS"] ?? "http://localhost:5173";
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins(corsOrigins.Split(','))
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials(); // Necesario para cookies httpOnly
    });
});

// ─── Servicios de infraestructura ───────────────────────────────────────────
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<ITimezoneService, TimezoneService>();
builder.Services.AddScoped<IIdempotencyService, IdempotencyService>();
builder.Services.AddScoped<ISMSService, TwilioSMSService>();

// ─── Swagger/OpenAPI ────────────────────────────────────────────────────────
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title = "ClinicBoost API",
        Version = "v0.1.0",
        Description = "Motor de ingresos automatizado para clínicas de fisioterapia — Revenue Recovery Layer"
    });
});

var app = builder.Build();

// ─── Middleware pipeline ────────────────────────────────────────────────────
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();

// Validación de firma Twilio ANTES de cualquier procesamiento de webhooks
app.UseMiddleware<TwilioSignatureMiddleware>();

// Autenticación y autorización
app.UseAuthentication();
app.UseAuthorization();

// Tenant middleware: extrae TenantId del JWT y activa RLS
app.UseMiddleware<TenantMiddleware>();

// ─── Registrar todos los endpoints (Vertical Slice) ─────────────────────────
app.MapHealthEndpoints();
app.MapVoiceWebhookEndpoint();
app.MapWhatsAppWebhookEndpoint();
app.MapLoginEndpoint();
app.MapTenantRegisterEndpoint();
app.MapGetAvailableSlotsEndpoint();
app.MapBookSlotEndpoint();

app.Run();

// Necesario para tests de integración con WebApplicationFactory
public partial class Program { }
