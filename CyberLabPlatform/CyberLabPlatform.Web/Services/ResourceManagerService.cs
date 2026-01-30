using System.Text.Json;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models.DTOs;
using CyberLabPlatform.Web.Data;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.Services;

public class ResourceManagerService(
    CyberLabDbContext context,
    IPowerShellExecutor powerShell,
    IConfiguration configuration,
    ILogger<ResourceManagerService> logger) : IResourceManagerService
{
    public async Task<ResourceUsageSummary> GetCurrentUsageAsync()
    {
        logger.LogDebug("Fetching current resource usage");

        try
        {
            // Call PowerShell to get live resource usage from Hyper-V host
            var result = await powerShell.ExecuteAsync("Get-LabResourceUsage", new Dictionary<string, object?>());

            var maxRamGb = configuration.GetValue<int>("ResourceLimits:MaxTotalRamGb", 115);
            var maxVcpu = configuration.GetValue<int>("ResourceLimits:MaxTotalVcpu", 22);

            var summary = new ResourceUsageSummary
            {
                TotalRamGb = maxRamGb,
                TotalVcpu = maxVcpu
            };

            if (result.Success)
            {
                if (result.Data.TryGetValue("UsedRamGb", out var usedRam) && usedRam is int ramVal)
                    summary.UsedRamGb = ramVal;
                if (result.Data.TryGetValue("UsedVcpu", out var usedVcpu) && usedVcpu is int vcpuVal)
                    summary.UsedVcpu = vcpuVal;
                if (result.Data.TryGetValue("RunningVms", out var runningVms) && runningVms is int vmVal)
                    summary.RunningVms = vmVal;
            }
            else
            {
                logger.LogWarning("PowerShell resource check failed, using database counts: {Error}", result.Error);

                // Fallback: count from database
                var runningVmCount = await context.VmInstances
                    .CountAsync(v => v.Status == Core.Enums.VMStatus.Running);
                summary.RunningVms = runningVmCount;
            }

            summary.ActiveSessions = await context.LabSessions
                .CountAsync(s => s.Status == Core.Enums.LabStatus.Active || s.Status == Core.Enums.LabStatus.Provisioning);

            return summary;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching resource usage");
            throw;
        }
    }

    public async Task<bool> CanDeployAsync(Guid templateId, int studentCount)
    {
        logger.LogInformation("Checking deployment feasibility for template {TemplateId} with {StudentCount} students", templateId, studentCount);

        try
        {
            var template = await context.LabTemplates.FindAsync(templateId);
            if (template == null)
            {
                logger.LogWarning("Template {TemplateId} not found", templateId);
                return false;
            }

            // Parse VM definitions to calculate required resources
            var vmDefinitions = JsonSerializer.Deserialize<JsonElement[]>(template.VmDefinitions) ?? [];

            var requiredRamMb = 0;
            var requiredVcpu = 0;

            foreach (var vmDef in vmDefinitions)
            {
                var ramMb = vmDef.TryGetProperty("ram_mb", out var ramProp) ? ramProp.GetInt32() : 2048;
                var vcpu = vmDef.TryGetProperty("vcpu", out var vcpuProp) ? vcpuProp.GetInt32() : 2;

                // Each student gets their own set of VMs (unless shared)
                requiredRamMb += ramMb * studentCount;
                requiredVcpu += vcpu * studentCount;
            }

            // Apply overhead percentage
            var overheadPct = configuration.GetValue<int>("ResourceLimits:OverheadPercent", 10);
            var overheadMultiplier = 1.0 + (overheadPct / 100.0);

            var totalRequiredRamGb = (int)Math.Ceiling(requiredRamMb * overheadMultiplier / 1024.0);
            var totalRequiredVcpu = (int)Math.Ceiling(requiredVcpu * overheadMultiplier);

            // Get current usage
            var currentUsage = await GetCurrentUsageAsync();

            var availableRamGb = currentUsage.TotalRamGb - currentUsage.UsedRamGb;
            var availableVcpu = currentUsage.TotalVcpu - currentUsage.UsedVcpu;

            // Check quotas from database
            var instructorQuota = await context.ResourceQuotas.FirstOrDefaultAsync(q => q.Role == "instructor");
            if (instructorQuota != null)
            {
                var currentInstructorSessions = await context.LabSessions
                    .CountAsync(s => s.Status == Core.Enums.LabStatus.Active || s.Status == Core.Enums.LabStatus.Provisioning);

                if (currentInstructorSessions >= instructorQuota.MaxConcurrentVms)
                {
                    logger.LogWarning("Instructor concurrent session quota exceeded");
                    return false;
                }
            }

            var canDeploy = totalRequiredRamGb <= availableRamGb && totalRequiredVcpu <= availableVcpu;

            logger.LogInformation(
                "Deployment check: Required RAM={RequiredRam}GB, Available={AvailableRam}GB, Required vCPU={RequiredVcpu}, Available={AvailableVcpu}, CanDeploy={CanDeploy}",
                totalRequiredRamGb, availableRamGb, totalRequiredVcpu, availableVcpu, canDeploy);

            return canDeploy;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error checking deployment feasibility");
            return false;
        }
    }
}
