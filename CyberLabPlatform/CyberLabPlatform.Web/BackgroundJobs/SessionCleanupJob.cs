using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Web.Data;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.BackgroundJobs;

public class SessionCleanupJob(
    CyberLabDbContext context,
    ILabOrchestrationService labOrchestration,
    IReportingService reportingService,
    ILogger<SessionCleanupJob> logger)
{
    public async Task CleanupExpiredSessionsAsync()
    {
        logger.LogDebug("Running expired session cleanup");

        try
        {
            var expiredSessions = await context.LabSessions
                .Where(s => (s.Status == LabStatus.Active || s.Status == LabStatus.Provisioning)
                    && s.ScheduledEndTime < DateTime.UtcNow)
                .ToListAsync();

            if (expiredSessions.Count == 0)
            {
                logger.LogDebug("No expired sessions found");
                return;
            }

            logger.LogInformation("Found {Count} expired sessions to clean up", expiredSessions.Count);

            foreach (var session in expiredSessions)
            {
                try
                {
                    logger.LogInformation("Cleaning up expired session {SessionId} ({ClassName})", session.Id, session.ClassName);

                    // Generate report before terminating
                    try
                    {
                        var pdfReport = await reportingService.GenerateSessionReportAsync(session.Id, ReportFormat.PDF);
                        logger.LogInformation("Generated cleanup report for session {SessionId}, size: {Size} bytes", session.Id, pdfReport.Length);
                    }
                    catch (Exception ex)
                    {
                        logger.LogWarning(ex, "Failed to generate report for session {SessionId} during cleanup", session.Id);
                    }

                    // Terminate the session
                    await labOrchestration.TerminateLabAsync(session.Id);
                    logger.LogInformation("Session {SessionId} terminated successfully during cleanup", session.Id);
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error cleaning up session {SessionId}", session.Id);
                }
            }

            logger.LogDebug("Expired session cleanup completed");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error during session cleanup job");
        }
    }
}
