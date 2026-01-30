using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Web.Data;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.BackgroundJobs;

public class HealthCheckJob(
    CyberLabDbContext context,
    IPowerShellExecutor powerShell,
    ILogger<HealthCheckJob> logger)
{
    public async Task RunHealthCheckAsync()
    {
        logger.LogDebug("Running system health check");

        try
        {
            // Check disk space
            await CheckDiskSpaceAsync();

            // Check memory
            await CheckMemoryAsync();

            // Check for failed VMs
            await CheckFailedVMsAsync();

            logger.LogDebug("System health check completed");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error during system health check");
        }
    }

    private async Task CheckDiskSpaceAsync()
    {
        try
        {
            var result = await powerShell.ExecuteAsync("Get-LabDiskSpace", new Dictionary<string, object?>());

            if (result.Success && result.Data.TryGetValue("FreeSpaceGb", out var freeSpace) && freeSpace is int freeGb)
            {
                if (freeGb < 50)
                    logger.LogWarning("Low disk space: {FreeGb}GB remaining", freeGb);
                else
                    logger.LogDebug("Disk space OK: {FreeGb}GB free", freeGb);
            }
            else
            {
                logger.LogWarning("Unable to determine disk space: {Error}", result.Error);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error checking disk space");
        }
    }

    private async Task CheckMemoryAsync()
    {
        try
        {
            var result = await powerShell.ExecuteAsync("Get-LabMemoryUsage", new Dictionary<string, object?>());

            if (result.Success && result.Data.TryGetValue("FreeMemoryGb", out var freeMem) && freeMem is int freeGb)
            {
                if (freeGb < 8)
                    logger.LogWarning("Low memory: {FreeGb}GB remaining", freeGb);
                else
                    logger.LogDebug("Memory OK: {FreeGb}GB free", freeGb);
            }
            else
            {
                logger.LogWarning("Unable to determine memory usage: {Error}", result.Error);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error checking memory");
        }
    }

    private async Task CheckFailedVMsAsync()
    {
        try
        {
            var failedVms = await context.VmInstances
                .Where(v => v.Status == VMStatus.Error)
                .Include(v => v.Session)
                .ToListAsync();

            if (failedVms.Count > 0)
            {
                logger.LogWarning("Found {Count} VMs in error state", failedVms.Count);
                foreach (var vm in failedVms)
                {
                    logger.LogWarning("Failed VM: {VmName} in session {SessionId} (Status: {Status})",
                        vm.VmName, vm.SessionId, vm.Status);
                }
            }
            else
            {
                logger.LogDebug("No failed VMs found");
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error checking failed VMs");
        }
    }
}
