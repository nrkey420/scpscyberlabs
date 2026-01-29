using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;

namespace CyberLabPlatform.Web.Services;

public class ActivityLoggingService(
    CyberLabDbContext context,
    ILogger<ActivityLoggingService> logger) : IActivityLoggingService
{
    public async Task LogEventAsync(Guid sessionId, string studentId, Guid? vmId, string eventType, string eventDetails, string? ipAddress = null)
    {
        try
        {
            var log = new ActivityLog
            {
                SessionId = sessionId,
                StudentId = studentId,
                VmId = vmId,
                Timestamp = DateTime.UtcNow,
                EventType = eventType,
                EventDetails = eventDetails,
                IpAddress = ipAddress ?? string.Empty
            };

            context.ActivityLogs.Add(log);
            await context.SaveChangesAsync();

            logger.LogDebug("Activity logged: {EventType} for session {SessionId}, student {StudentId}", eventType, sessionId, studentId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to log activity event {EventType} for session {SessionId}", eventType, sessionId);
        }
    }
}
