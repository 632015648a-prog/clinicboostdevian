using System.IdentityModel.Tokens.Jwt;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace ClinicBoost.Api.Infrastructure.Middleware;

/// <summary>
/// Middleware que extrae el TenantId del JWT (cookie httpOnly) y lo inyecta
/// en HttpContext.Items para que AppDbContext lo use en los filtros globales.
/// También ejecuta SET LOCAL app.current_tenant_id en PostgreSQL para activar RLS.
/// </summary>
public class TenantMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<TenantMiddleware> _logger;

    // Rutas excluidas del middleware de tenant
    private static readonly string[] ExcludedPaths =
    [
        "/api/webhooks",
        "/api/auth",
        "/health",
        "/swagger"
    ];

    public TenantMiddleware(RequestDelegate next, ILogger<TenantMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? string.Empty;

        // No aplicar a rutas excluidas
        if (ExcludedPaths.Any(excluded => path.StartsWith(excluded, StringComparison.OrdinalIgnoreCase)))
        {
            await _next(context);
            return;
        }

        // Extraer JWT de la cookie o del header Authorization
        var token = context.Request.Cookies["clinicboost_auth"]
                    ?? ExtractBearerToken(context.Request.Headers.Authorization.ToString());

        if (string.IsNullOrEmpty(token))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await WriteUnauthorizedResponse(context, "Token no proporcionado");
            return;
        }

        var jwtSecret = context.RequestServices.GetRequiredService<IConfiguration>()["JWT_SECRET"];
        if (string.IsNullOrEmpty(jwtSecret))
        {
            _logger.LogError("JWT_SECRET not configured");
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            return;
        }

        try
        {
            var tokenHandler = new JwtSecurityTokenHandler();
            var key = Encoding.UTF8.GetBytes(jwtSecret);
            tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = context.RequestServices.GetRequiredService<IConfiguration>()["JWT_ISSUER"],
                ValidateAudience = true,
                ValidAudience = context.RequestServices.GetRequiredService<IConfiguration>()["JWT_AUDIENCE"],
                ClockSkew = TimeSpan.FromSeconds(30)
            }, out var validatedToken);

            var jwtToken = (JwtSecurityToken)validatedToken;
            var tenantIdClaim = jwtToken.Claims.FirstOrDefault(c => c.Type == "tenant_id")?.Value;

            if (string.IsNullOrEmpty(tenantIdClaim) || !Guid.TryParse(tenantIdClaim, out var tenantId))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await WriteUnauthorizedResponse(context, "Claim tenant_id inválido");
                return;
            }

            // Inyectar TenantId en el contexto para AppDbContext
            context.Items["TenantId"] = tenantId;

            // TODO (Bloque 1): Ejecutar SET LOCAL app.current_tenant_id para activar RLS en PostgreSQL
            // Esto se implementará cuando se configure la conexión con Supabase

            _logger.LogDebug("Tenant {TenantId} authenticated for {Path}", tenantId, path);
        }
        catch (SecurityTokenException ex)
        {
            _logger.LogWarning("Invalid JWT token: {Message}", ex.Message);
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await WriteUnauthorizedResponse(context, "Token inválido o expirado");
            return;
        }

        await _next(context);
    }

    private static string? ExtractBearerToken(string authHeader)
    {
        if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return null;
        return authHeader["Bearer ".Length..].Trim();
    }

    private static async Task WriteUnauthorizedResponse(HttpContext context, string detail)
    {
        context.Response.ContentType = "application/problem+json";
        await context.Response.WriteAsJsonAsync(new
        {
            type = "https://tools.ietf.org/html/rfc7807",
            title = "Unauthorized",
            status = 401,
            detail
        });
    }
}
