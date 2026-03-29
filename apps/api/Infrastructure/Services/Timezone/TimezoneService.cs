namespace ClinicBoost.Api.Infrastructure.Services.Timezone;

public class TimezoneService : ITimezoneService
{
    public DateTime ConvertToTenantLocal(DateTime utcDateTime, string ianaTimezone)
    {
        var tz = GetTimezoneInfo(ianaTimezone);
        return TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcDateTime, DateTimeKind.Utc), tz);
    }

    public DateTime ConvertToUtc(DateTime localDateTime, string ianaTimezone)
    {
        var tz = GetTimezoneInfo(ianaTimezone);
        return TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(localDateTime, DateTimeKind.Unspecified), tz);
    }

    public DateTime GetCurrentTimeForTenant(string ianaTimezone)
    {
        return ConvertToTenantLocal(DateTime.UtcNow, ianaTimezone);
    }

    public TimeOnly GetCurrentTimeOnlyForTenant(string ianaTimezone)
    {
        var localTime = GetCurrentTimeForTenant(ianaTimezone);
        return TimeOnly.FromDateTime(localTime);
    }

    public bool IsWithinBusinessHours(string ianaTimezone, TimeOnly start, TimeOnly end)
    {
        var currentTime = GetCurrentTimeOnlyForTenant(ianaTimezone);
        return currentTime >= start && currentTime <= end;
    }

    public bool IsWeekend(string ianaTimezone)
    {
        var localTime = GetCurrentTimeForTenant(ianaTimezone);
        return localTime.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;
    }

    /// <summary>
    /// Resuelve una IANA timezone string a TimeZoneInfo.
    /// Funciona tanto en Linux (IANA nativo) como en Windows (conversión automática).
    /// </summary>
    private static TimeZoneInfo GetTimezoneInfo(string ianaTimezone)
    {
        return TimeZoneInfo.FindSystemTimeZoneById(ianaTimezone);
    }
}
