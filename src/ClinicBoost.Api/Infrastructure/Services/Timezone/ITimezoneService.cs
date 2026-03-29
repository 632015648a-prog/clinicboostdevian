namespace ClinicBoost.Api.Infrastructure.Services.Timezone;

/// <summary>
/// Servicio de conversión de timezone. Todo se persiste en UTC y se convierte
/// por tenant usando su timezone configurada (IANA, ej: "Europe/Madrid").
/// NUNCA usar AddHours manual.
/// </summary>
public interface ITimezoneService
{
    /// <summary>
    /// Convierte un DateTime UTC a la hora local del tenant.
    /// </summary>
    DateTime ConvertToTenantLocal(DateTime utcDateTime, string ianaTimezone);

    /// <summary>
    /// Convierte un DateTime local del tenant a UTC.
    /// </summary>
    DateTime ConvertToUtc(DateTime localDateTime, string ianaTimezone);

    /// <summary>
    /// Obtiene la hora actual en la timezone del tenant.
    /// </summary>
    DateTime GetCurrentTimeForTenant(string ianaTimezone);

    /// <summary>
    /// Obtiene solo la hora actual (TimeOnly) en la timezone del tenant.
    /// Útil para verificar si estamos dentro del horario de atención.
    /// </summary>
    TimeOnly GetCurrentTimeOnlyForTenant(string ianaTimezone);

    /// <summary>
    /// Verifica si la hora actual del tenant está dentro de un rango horario.
    /// </summary>
    bool IsWithinBusinessHours(string ianaTimezone, TimeOnly start, TimeOnly end);

    /// <summary>
    /// Verifica si hoy es fin de semana en la timezone del tenant.
    /// </summary>
    bool IsWeekend(string ianaTimezone);
}
