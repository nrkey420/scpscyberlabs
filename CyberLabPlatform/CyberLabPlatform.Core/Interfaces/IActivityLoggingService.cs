namespace CyberLabPlatform.Core.Interfaces;

public interface IActivityLoggingService
{
    Task LogEventAsync(Guid sessionId, string studentId, Guid? vmId, string eventType, string eventDetails, string? ipAddress = null);
}
