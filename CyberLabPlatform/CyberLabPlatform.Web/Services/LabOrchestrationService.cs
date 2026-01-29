using System.Text.Json;
using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.Services;

public class LabOrchestrationService(
    CyberLabDbContext context,
    IPowerShellExecutor powerShell,
    IResourceManagerService resourceManager,
    IHubContext<LabActivityHub> hubContext,
    IConfiguration configuration,
    ILogger<LabOrchestrationService> logger) : ILabOrchestrationService
{
    public async Task<LabSession> DeployLabAsync(DeployLabRequest request)
    {
        logger.LogInformation("Deploying lab for template {TemplateId}, class {ClassName}", request.TemplateId, request.ClassName);

        // Load template
        var template = await context.LabTemplates.FindAsync(request.TemplateId)
            ?? throw new InvalidOperationException($"Template {request.TemplateId} not found");

        if (!template.IsActive)
            throw new InvalidOperationException("Template is not active");

        // Check resources
        var canDeploy = await resourceManager.CanDeployAsync(request.TemplateId, request.StudentIds.Count);
        if (!canDeploy)
            throw new InvalidOperationException("Insufficient resources to deploy this lab");

        // Create session
        var session = new LabSession
        {
            Id = Guid.NewGuid(),
            TemplateId = request.TemplateId,
            InstructorId = request.InstructorId,
            ClassName = request.ClassName,
            StartTime = DateTime.UtcNow,
            ScheduledEndTime = DateTime.UtcNow.AddMinutes(request.DurationMinutes),
            Status = LabStatus.Provisioning,
            TimeoutMinutes = request.DurationMinutes,
            InactivityTimeoutMinutes = request.InactivityTimeoutMinutes,
            CreatedAt = DateTime.UtcNow
        };

        context.LabSessions.Add(session);
        await context.SaveChangesAsync();

        try
        {
            // Parse VM definitions from template
            var vmDefinitions = JsonSerializer.Deserialize<JsonElement[]>(template.VmDefinitions) ?? [];

            // Call PowerShell to deploy lab environment
            var deployResult = await powerShell.ExecuteAsync("Deploy-LabEnvironment", new Dictionary<string, object?>
            {
                ["SessionId"] = session.Id.ToString(),
                ["TemplateName"] = template.Name,
                ["VmDefinitions"] = template.VmDefinitions,
                ["NetworkTopology"] = template.NetworkTopology,
                ["StoragePath"] = configuration["HyperV:VmStoragePath"],
                ["TemplatePath"] = configuration["HyperV:TemplateStoragePath"]
            });

            if (!deployResult.Success)
            {
                logger.LogError("PowerShell deployment failed: {Error}", deployResult.Error);
                session.Status = LabStatus.Error;
                await context.SaveChangesAsync();
                throw new InvalidOperationException($"Lab deployment failed: {deployResult.Error}");
            }

            // Create VM records from deployment results
            foreach (var vmDef in vmDefinitions)
            {
                var vmName = vmDef.GetProperty("name").GetString() ?? "unknown";
                var vmInstance = new VMInstance
                {
                    Id = Guid.NewGuid(),
                    SessionId = session.Id,
                    VmName = $"{session.Id:N}-{vmName}",
                    VmType = vmDef.GetProperty("os").GetString() ?? "Unknown",
                    Status = VMStatus.Starting,
                    CreatedAt = DateTime.UtcNow
                };

                // Try to get HyperV VM ID from deployment result
                if (deployResult.Data.TryGetValue($"vm_{vmName}_id", out var hyperVId) && hyperVId is string idStr)
                {
                    if (Guid.TryParse(idStr, out var parsedId))
                        vmInstance.HyperVVMId = parsedId;
                }

                if (deployResult.Data.TryGetValue($"vm_{vmName}_ip", out var ip) && ip is string ipStr)
                    vmInstance.IpAddress = ipStr;

                context.VmInstances.Add(vmInstance);
            }

            // Create student assignments
            for (var i = 0; i < request.StudentIds.Count; i++)
            {
                var assignment = new StudentLabAssignment
                {
                    Id = Guid.NewGuid(),
                    SessionId = session.Id,
                    StudentId = request.StudentIds[i],
                    StudentEmail = i < request.StudentEmails.Count ? request.StudentEmails[i] : string.Empty,
                    StudentName = i < request.StudentNames.Count ? request.StudentNames[i] : string.Empty,
                    EnrolledAt = DateTime.UtcNow
                };
                context.StudentLabAssignments.Add(assignment);
            }

            session.Status = LabStatus.Active;
            await context.SaveChangesAsync();

            // Notify via SignalR
            await hubContext.Clients.Group($"session-{session.Id}").SendAsync("VMStatusChanged", new
            {
                sessionId = session.Id,
                status = "Active",
                message = "Lab environment deployed successfully"
            });

            logger.LogInformation("Lab session {SessionId} deployed successfully", session.Id);
            return session;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to deploy lab session {SessionId}", session.Id);
            session.Status = LabStatus.Error;
            await context.SaveChangesAsync();
            throw;
        }
    }

    public async Task TerminateLabAsync(Guid sessionId)
    {
        logger.LogInformation("Terminating lab session {SessionId}", sessionId);

        var session = await context.LabSessions
            .Include(s => s.VmInstances)
            .FirstOrDefaultAsync(s => s.Id == sessionId)
            ?? throw new InvalidOperationException($"Session {sessionId} not found");

        // Notify clients that session is terminating
        await hubContext.Clients.Group($"session-{sessionId}").SendAsync("SessionTerminating", new
        {
            sessionId,
            message = "Lab session is being terminated"
        });

        try
        {
            // Call PowerShell to tear down environment
            var result = await powerShell.ExecuteAsync("Remove-LabEnvironment", new Dictionary<string, object?>
            {
                ["SessionId"] = sessionId.ToString(),
                ["VmNames"] = JsonSerializer.Serialize(session.VmInstances.Select(v => v.VmName).ToList())
            });

            if (!result.Success)
                logger.LogWarning("PowerShell teardown returned errors: {Error}", result.Error);

            // Update VM statuses
            foreach (var vm in session.VmInstances)
                vm.Status = VMStatus.Stopped;

            session.Status = LabStatus.Terminated;
            session.ActualEndTime = DateTime.UtcNow;
            await context.SaveChangesAsync();

            logger.LogInformation("Lab session {SessionId} terminated successfully", sessionId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error terminating lab session {SessionId}", sessionId);
            session.Status = LabStatus.Error;
            await context.SaveChangesAsync();
            throw;
        }
    }

    public async Task PauseVMAsync(Guid vmId)
    {
        logger.LogInformation("Pausing VM {VmId}", vmId);

        var vm = await context.VmInstances.FindAsync(vmId)
            ?? throw new InvalidOperationException($"VM {vmId} not found");

        var result = await powerShell.ExecuteAsync("Save-LabVM", new Dictionary<string, object?>
        {
            ["VMName"] = vm.VmName
        });

        if (!result.Success)
            throw new InvalidOperationException($"Failed to pause VM: {result.Error}");

        vm.Status = VMStatus.Paused;
        vm.LastActivity = DateTime.UtcNow;
        await context.SaveChangesAsync();

        await hubContext.Clients.Group($"session-{vm.SessionId}").SendAsync("VMStatusChanged", new
        {
            vmId,
            status = "Paused",
            vmName = vm.VmName
        });
    }

    public async Task ResumeVMAsync(Guid vmId)
    {
        logger.LogInformation("Resuming VM {VmId}", vmId);

        var vm = await context.VmInstances.FindAsync(vmId)
            ?? throw new InvalidOperationException($"VM {vmId} not found");

        var result = await powerShell.ExecuteAsync("Start-LabVM", new Dictionary<string, object?>
        {
            ["VMName"] = vm.VmName
        });

        if (!result.Success)
            throw new InvalidOperationException($"Failed to resume VM: {result.Error}");

        vm.Status = VMStatus.Running;
        vm.LastActivity = DateTime.UtcNow;
        await context.SaveChangesAsync();

        await hubContext.Clients.Group($"session-{vm.SessionId}").SendAsync("VMStatusChanged", new
        {
            vmId,
            status = "Running",
            vmName = vm.VmName
        });
    }

    public async Task ResetVMAsync(Guid vmId)
    {
        logger.LogInformation("Resetting VM {VmId}", vmId);

        var vm = await context.VmInstances.FindAsync(vmId)
            ?? throw new InvalidOperationException($"VM {vmId} not found");

        var result = await powerShell.ExecuteAsync("Reset-LabVM", new Dictionary<string, object?>
        {
            ["VMName"] = vm.VmName
        });

        if (!result.Success)
            throw new InvalidOperationException($"Failed to reset VM: {result.Error}");

        vm.Status = VMStatus.Starting;
        vm.LastActivity = DateTime.UtcNow;
        await context.SaveChangesAsync();

        await hubContext.Clients.Group($"session-{vm.SessionId}").SendAsync("VMStatusChanged", new
        {
            vmId,
            status = "Starting",
            vmName = vm.VmName
        });
    }

    public async Task<string> GetVMConsoleUrlAsync(Guid vmId)
    {
        logger.LogInformation("Generating console URL for VM {VmId}", vmId);

        var vm = await context.VmInstances.FindAsync(vmId)
            ?? throw new InvalidOperationException($"VM {vmId} not found");

        var guacBaseUrl = configuration["Guacamole:BaseUrl"]
            ?? throw new InvalidOperationException("Guacamole base URL not configured");
        var secretKey = configuration["Guacamole:SecretKey"]
            ?? throw new InvalidOperationException("Guacamole secret key not configured");
        var expirationMinutes = int.Parse(configuration["Guacamole:TokenExpirationMinutes"] ?? "60");

        // Generate a time-limited token for Guacamole access
        var tokenPayload = new
        {
            vmId = vm.Id,
            vmName = vm.VmName,
            ip = vm.IpAddress,
            expires = DateTime.UtcNow.AddMinutes(expirationMinutes).ToString("o")
        };

        var tokenJson = JsonSerializer.Serialize(tokenPayload);
        var tokenBytes = System.Text.Encoding.UTF8.GetBytes(tokenJson);
        var token = Convert.ToBase64String(tokenBytes);

        var consoleUrl = $"{guacBaseUrl}/#/client/{Uri.EscapeDataString(vm.VmName)}?token={Uri.EscapeDataString(token)}";

        return consoleUrl;
    }

    public async Task CreateSnapshotAsync(Guid vmId, string snapshotName)
    {
        logger.LogInformation("Creating snapshot '{SnapshotName}' for VM {VmId}", snapshotName, vmId);

        var vm = await context.VmInstances.FindAsync(vmId)
            ?? throw new InvalidOperationException($"VM {vmId} not found");

        var result = await powerShell.ExecuteAsync("Checkpoint-LabVM", new Dictionary<string, object?>
        {
            ["VMName"] = vm.VmName,
            ["SnapshotName"] = snapshotName
        });

        if (!result.Success)
            throw new InvalidOperationException($"Failed to create snapshot: {result.Error}");

        logger.LogInformation("Snapshot '{SnapshotName}' created for VM {VmId}", snapshotName, vmId);
    }
}
