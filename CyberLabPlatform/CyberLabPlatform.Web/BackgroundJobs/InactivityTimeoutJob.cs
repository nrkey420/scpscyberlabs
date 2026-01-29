using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.BackgroundJobs;

public class InactivityTimeoutJob(
    CyberLabDbContext context,
    IPowerShellExecutor powerShell,
    IHubContext<LabActivityHub> hubContext,
    ILogger<InactivityTimeoutJob> logger)
{
    public async Task CheckInactiveVMsAsync()
    {
        logger.LogDebug("Running inactivity timeout check");

        try
        {
            var activeSessions = await context.LabSessions
                .Where(s => s.Status == LabStatus.Active)
                .Include(s => s.VmInstances)
                .ToListAsync();

            foreach (var session in activeSessions)
            {
                var inactivityTimeout = TimeSpan.FromMinutes(session.InactivityTimeoutMinutes);

                var inactiveVms = session.VmInstances
                    .Where(vm => vm.Status == VMStatus.Running
                        && vm.LastActivity.HasValue
                        && (DateTime.UtcNow - vm.LastActivity.Value) > inactivityTimeout)
                    .ToList();

                foreach (var vm in inactiveVms)
                {
                    logger.LogInformation(
                        "VM {VmName} in session {SessionId} inactive for {Minutes} minutes, saving state",
                        vm.VmName, session.Id, (DateTime.UtcNow - vm.LastActivity!.Value).TotalMinutes);

                    try
                    {
                        var result = await powerShell.ExecuteAsync("Save-LabVM", new Dictionary<string, object?>
                        {
                            ["VMName"] = vm.VmName
                        });

                        if (result.Success)
                        {
                            vm.Status = VMStatus.Paused;
                            vm.LastActivity = DateTime.UtcNow;

                            await hubContext.Clients.Group($"session-{session.Id}").SendAsync("VMStatusChanged", new
                            {
                                vmId = vm.Id,
                                vmName = vm.VmName,
                                status = "Paused",
                                reason = "Inactivity timeout"
                            });
                        }
                        else
                        {
                            logger.LogWarning("Failed to save VM {VmName}: {Error}", vm.VmName, result.Error);
                        }
                    }
                    catch (Exception ex)
                    {
                        logger.LogError(ex, "Error saving inactive VM {VmName}", vm.VmName);
                    }
                }
            }

            await context.SaveChangesAsync();
            logger.LogDebug("Inactivity timeout check completed");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error during inactivity timeout check");
        }
    }
}
