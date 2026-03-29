using ClinicBoost.Api.Domain.Enums;

namespace ClinicBoost.Api.Domain.Entities;

public class Appointment : TenantEntity
{
    public Guid PatientId { get; set; }
    public Guid SlotId { get; set; }
    public AppointmentStatus Status { get; set; } = AppointmentStatus.Pending;

    /// <summary>
    /// true si esta cita fue generada/recuperada por el bot; false si fue agendada manualmente.
    /// </summary>
    public bool IsRecovered { get; set; }

    public SourceFlow SourceFlow { get; set; } = SourceFlow.Manual;
    public BookingChannel BookingChannel { get; set; } = BookingChannel.Manual;

    /// <summary>
    /// Minutos entre el momento de la reserva y el inicio del hueco.
    /// Se recoge desde el MVP para entrenar el futuro modelo ML.
    /// </summary>
    public int MinsBetweenBookAndSlot { get; set; }

    public int RescheduledCount { get; set; }
    public DateTime? ReminderSentAt { get; set; }
}
