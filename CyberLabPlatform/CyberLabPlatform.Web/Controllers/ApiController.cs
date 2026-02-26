using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.Controllers;

[ApiController]
[Route("api")]
[Authorize]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public class ApiController(
    CyberLabDbContext context,
    ILabOrchestrationService labOrchestration,
    IResourceManagerService resourceManager,
    IGamificationService gamification,
    IReportingService reportingService,
    IActivityLoggingService activityLogging,
    ILogger<ApiController> logger) : ControllerBase
{
    // ========================================================================
    // Templates
    // ========================================================================

    [HttpGet("templates")]
    public async Task<ActionResult<List<LabTemplate>>> GetTemplates()
    {
        var templates = await context.LabTemplates
            .Where(t => t.IsActive)
            .OrderBy(t => t.Name)
            .ToListAsync();
        return Ok(templates);
    }

    [HttpGet("templates/{id:guid}")]
    public async Task<ActionResult<LabTemplate>> GetTemplate(Guid id)
    {
        var template = await context.LabTemplates.FindAsync(id);
        if (template == null) return NotFound();

        var objectives = await context.LabObjectives
            .Where(o => o.TemplateId == id)
            .OrderBy(o => o.ObjectiveOrder)
            .ToListAsync();

        return Ok(new { template, objectives });
    }

    // ========================================================================
    // Lab Sessions
    // ========================================================================

    [HttpPost("labs/deploy")]
    [Authorize(Policy = "Instructor")]
    public async Task<ActionResult<LabSession>> DeployLab([FromBody] DeployLabRequest request)
    {
        if (request.TemplateId == Guid.Empty)
            return BadRequest("Template ID is required");
        if (string.IsNullOrWhiteSpace(request.ClassName))
            return BadRequest("Class name is required");
        if (request.StudentIds.Count == 0)
            return BadRequest("At least one student is required");

        try
        {
            request.InstructorId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";
            var session = await labOrchestration.DeployLabAsync(request);
            return CreatedAtAction(nameof(GetSessionDetail), new { sessionId = session.Id }, session);
        }
        catch (InvalidOperationException ex)
        {
            logger.LogWarning(ex, "Lab deployment rejected");
            return BadRequest(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error deploying lab");
            return StatusCode(500, "An error occurred while deploying the lab");
        }
    }

    [HttpPost("labs/{sessionId:guid}/terminate")]
    [Authorize(Policy = "Instructor")]
    public async Task<ActionResult> TerminateLab(Guid sessionId)
    {
        try
        {
            await labOrchestration.TerminateLabAsync(sessionId);
            return Ok(new { message = "Lab session terminated successfully" });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error terminating lab session {SessionId}", sessionId);
            return StatusCode(500, "An error occurred while terminating the lab");
        }
    }

    [HttpGet("labs/active")]
    public async Task<ActionResult> GetActiveSessions()
    {
        var sessions = await context.LabSessions
            .Include(s => s.Template)
            .Include(s => s.StudentAssignments)
            .Where(s => s.Status == LabStatus.Active || s.Status == LabStatus.Provisioning)
            .OrderByDescending(s => s.StartTime)
            .ToListAsync();

        var result = sessions.Select(s => new
        {
            id = s.Id,
            templateName = s.Template?.Name ?? "Unknown",
            status = s.Status.ToString(),
            studentCount = s.StudentAssignments.Count,
            startedAt = s.StartTime,
            endsAt = s.ScheduledEndTime,
            averageProgress = 0,
        });

        return Ok(result);
    }

    [HttpGet("labs/{sessionId:guid}")]
    public async Task<ActionResult> GetSessionDetail(Guid sessionId)
    {
        var session = await context.LabSessions
            .Include(s => s.Template)
            .Include(s => s.VmInstances)
            .Include(s => s.StudentAssignments)
            .FirstOrDefaultAsync(s => s.Id == sessionId);

        if (session == null) return NotFound();
        return Ok(session);
    }

    // ========================================================================
    // VM Management
    // ========================================================================

    [HttpPost("vms/{vmId:guid}/pause")]
    public async Task<ActionResult> PauseVM(Guid vmId)
    {
        try
        {
            await labOrchestration.PauseVMAsync(vmId);
            return Ok(new { message = "VM paused successfully" });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error pausing VM {VmId}", vmId);
            return StatusCode(500, "An error occurred while pausing the VM");
        }
    }

    [HttpPost("vms/{vmId:guid}/resume")]
    public async Task<ActionResult> ResumeVM(Guid vmId)
    {
        try
        {
            await labOrchestration.ResumeVMAsync(vmId);
            return Ok(new { message = "VM resumed successfully" });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error resuming VM {VmId}", vmId);
            return StatusCode(500, "An error occurred while resuming the VM");
        }
    }

    [HttpPost("vms/{vmId:guid}/reset")]
    public async Task<ActionResult> ResetVM(Guid vmId)
    {
        try
        {
            await labOrchestration.ResetVMAsync(vmId);
            return Ok(new { message = "VM reset initiated" });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error resetting VM {VmId}", vmId);
            return StatusCode(500, "An error occurred while resetting the VM");
        }
    }

    [HttpGet("vms/{vmId:guid}/console")]
    public async Task<ActionResult> GetConsoleUrl(Guid vmId)
    {
        try
        {
            var url = await labOrchestration.GetVMConsoleUrlAsync(vmId);
            return Ok(new { consoleUrl = url });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting console URL for VM {VmId}", vmId);
            return StatusCode(500, "An error occurred while generating the console URL");
        }
    }

    [HttpPost("vms/{vmId:guid}/snapshot")]
    [Authorize(Policy = "Instructor")]
    public async Task<ActionResult> CreateSnapshot(Guid vmId, [FromBody] CreateSnapshotRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.SnapshotName))
            return BadRequest("Snapshot name is required");

        try
        {
            await labOrchestration.CreateSnapshotAsync(vmId, request.SnapshotName);
            return Ok(new { message = "Snapshot created successfully" });
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error creating snapshot for VM {VmId}", vmId);
            return StatusCode(500, "An error occurred while creating the snapshot");
        }
    }

    // ========================================================================
    // Gamification / Objectives
    // ========================================================================

    [HttpPost("objectives/{objectiveId:guid}/submit")]
    [Authorize(Policy = "Student")]
    public async Task<ActionResult<FlagSubmissionResult>> SubmitFlag(Guid objectiveId, [FromBody] FlagSubmitRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.FlagValue))
            return BadRequest("Flag value is required");
        if (request.SessionId == Guid.Empty)
            return BadRequest("Session ID is required");

        try
        {
            var studentId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";
            var result = await gamification.SubmitFlagAsync(request.SessionId, studentId, objectiveId, request.FlagValue);

            await activityLogging.LogEventAsync(request.SessionId, studentId, null, "flag_submission",
                $"Objective: {objectiveId}, Correct: {result.IsCorrect}",
                HttpContext.Connection.RemoteIpAddress?.ToString());

            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing flag submission for objective {ObjectiveId}", objectiveId);
            return StatusCode(500, "An error occurred while processing the flag submission");
        }
    }

    [HttpGet("sessions/{sessionId:guid}/leaderboard")]
    public async Task<ActionResult<List<LeaderboardEntry>>> GetLeaderboard(Guid sessionId)
    {
        try
        {
            var leaderboard = await gamification.GetClassLeaderboardAsync(sessionId);
            return Ok(leaderboard);
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching leaderboard for session {SessionId}", sessionId);
            return StatusCode(500, "An error occurred while fetching the leaderboard");
        }
    }

    [HttpGet("sessions/{sessionId:guid}/progress")]
    public async Task<ActionResult> GetAllStudentProgress(Guid sessionId)
    {
        var progress = await context.StudentProgress
            .Include(p => p.Objective)
            .Where(p => p.SessionId == sessionId && p.PointsAwarded > 0)
            .OrderBy(p => p.StudentId)
            .ThenBy(p => p.CompletedAt)
            .ToListAsync();
        return Ok(progress);
    }

    // ========================================================================
    // Student-specific endpoints
    // ========================================================================

    [HttpGet("student/sessions")]
    [Authorize(Policy = "Student")]
    public async Task<ActionResult> GetStudentSessions()
    {
        var studentId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";

        var assignments = await context.StudentLabAssignments
            .Include(a => a.Session).ThenInclude(s => s.Template)
            .Where(a => a.StudentId == studentId)
            .OrderByDescending(a => a.EnrolledAt)
            .ToListAsync();

        return Ok(assignments);
    }

    [HttpGet("student/sessions/{sessionId:guid}")]
    [Authorize(Policy = "Student")]
    public async Task<ActionResult> GetStudentSessionDetail(Guid sessionId)
    {
        var studentId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";

        var assignment = await context.StudentLabAssignments
            .Include(a => a.Session).ThenInclude(s => s.Template)
            .FirstOrDefaultAsync(a => a.SessionId == sessionId && a.StudentId == studentId);

        if (assignment == null) return NotFound();

        var vms = await context.VmInstances
            .Where(v => v.SessionId == sessionId && (v.StudentId == studentId || v.IsShared))
            .ToListAsync();

        var objectives = await context.LabObjectives
            .Where(o => o.TemplateId == assignment.Session.TemplateId)
            .OrderBy(o => o.ObjectiveOrder)
            .ToListAsync();

        var progress = await context.StudentProgress
            .Where(p => p.SessionId == sessionId && p.StudentId == studentId && p.PointsAwarded > 0)
            .ToListAsync();

        return Ok(new { assignment, vms, objectives, progress });
    }

    [HttpGet("student/sessions/{sessionId:guid}/progress")]
    [Authorize(Policy = "Student")]
    public async Task<ActionResult> GetStudentOwnProgress(Guid sessionId)
    {
        var studentId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";

        var progress = await context.StudentProgress
            .Include(p => p.Objective)
            .Where(p => p.SessionId == sessionId && p.StudentId == studentId)
            .OrderBy(p => p.CompletedAt)
            .ToListAsync();

        return Ok(progress);
    }

    // ========================================================================
    // Reports
    // ========================================================================

    [HttpGet("reports/{sessionId:guid}")]
    [Authorize(Policy = "Instructor")]
    public async Task<ActionResult> GenerateReport(Guid sessionId, [FromQuery] string format = "pdf")
    {
        try
        {
            var reportFormat = format.Equals("csv", StringComparison.OrdinalIgnoreCase) ? ReportFormat.CSV : ReportFormat.PDF;
            var reportBytes = await reportingService.GenerateSessionReportAsync(sessionId, reportFormat);

            var contentType = reportFormat == ReportFormat.PDF ? "application/pdf" : "text/csv";
            var extension = reportFormat == ReportFormat.PDF ? "pdf" : "csv";
            return File(reportBytes, contentType, $"session-report-{sessionId}.{extension}");
        }
        catch (InvalidOperationException ex)
        {
            return NotFound(ex.Message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating report for session {SessionId}", sessionId);
            return StatusCode(500, "An error occurred while generating the report");
        }
    }

    [HttpGet("reports/{sessionId:guid}/activity")]
    [Authorize(Policy = "Instructor")]
    public async Task<ActionResult> ExportActivityLog(Guid sessionId)
    {
        try
        {
            var csvBytes = await reportingService.ExportActivityLogAsync(sessionId);
            return File(csvBytes, "text/csv", $"activity-log-{sessionId}.csv");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting activity log for session {SessionId}", sessionId);
            return StatusCode(500, "An error occurred while exporting the activity log");
        }
    }

    // ========================================================================
    // Resources (Admin)
    // ========================================================================

    [HttpGet("resources/usage")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult> GetResourceUsage()
    {
        try
        {
            var usage = await resourceManager.GetCurrentUsageAsync();
            return Ok(usage);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching resource usage");
            return StatusCode(500, "An error occurred while fetching resource usage");
        }
    }

    [HttpGet("resources/quotas")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult<List<ResourceQuota>>> GetResourceQuotas()
    {
        var quotas = await context.ResourceQuotas.ToListAsync();
        return Ok(quotas);
    }

    // ========================================================================
    // Admin Configuration
    // ========================================================================

    [HttpGet("admin/config")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult<List<SystemConfig>>> GetSystemConfig()
    {
        var configs = await context.SystemConfigs.OrderBy(c => c.Key).ToListAsync();
        return Ok(configs);
    }

    [HttpPut("admin/config/{key}")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult> UpdateSystemConfig(string key, [FromBody] UpdateConfigRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Value))
            return BadRequest("Value is required");

        var config = await context.SystemConfigs.FindAsync(key);
        if (config == null) return NotFound($"Configuration key '{key}' not found");

        config.Value = request.Value;
        config.UpdatedAt = DateTime.UtcNow;
        config.UpdatedBy = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";

        await context.SaveChangesAsync();
        return Ok(config);
    }

    [HttpGet("admin/health")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult> GetSystemHealth()
    {
        try
        {
            var usage = await resourceManager.GetCurrentUsageAsync();
            var failedVms = await context.VmInstances.CountAsync(v => v.Status == VMStatus.Error);
            var activeSessions = await context.LabSessions.CountAsync(s => s.Status == LabStatus.Active);

            return Ok(new
            {
                status = "Healthy",
                timestamp = DateTime.UtcNow,
                resources = usage,
                failedVms,
                activeSessions,
                databaseConnected = true
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching system health");
            return Ok(new
            {
                status = "Degraded",
                timestamp = DateTime.UtcNow,
                error = ex.Message
            });
        }
    }

    // ========================================================================
    // Users
    // ========================================================================

    [HttpGet("users")]
    [Authorize(Policy = "SystemAdministrator")]
    public async Task<ActionResult> GetAllUsers()
    {
        // Pull users who have appeared in the system from the database.
        // Roles are managed via Entra ID group membership; this endpoint
        // reflects what is stored locally from lab activity.
        var students = await context.StudentLabAssignments
            .Select(a => new { id = a.StudentId, name = a.StudentName, email = a.StudentEmail, role = "Student" })
            .Distinct()
            .ToListAsync();

        var instructorIds = await context.LabSessions
            .Select(s => s.InstructorId)
            .Distinct()
            .ToListAsync();

        var instructors = instructorIds
            .Select(id => new { id, name = id, email = string.Empty, role = "Instructor" })
            .ToList();

        // Always include the currently authenticated user so the admin sees
        // themselves even before any lab sessions have been created.
        var currentId = User.FindFirst("oid")?.Value ?? string.Empty;
        var currentName = User.FindFirst("name")?.Value ?? User.Identity?.Name ?? "Admin";
        var currentEmail = User.FindFirst("preferred_username")?.Value ?? string.Empty;

        var allUsers = students
            .Cast<object>()
            .Concat(instructors.Cast<object>())
            .Concat(new[] { (object)new { id = currentId, name = currentName, email = currentEmail, role = "Admin" } })
            .GroupBy(u => ((dynamic)u).id)
            .Select(g => g.First())
            .ToList();

        return Ok(allUsers);
    }

    [HttpPut("users/{userId}/role")]
    [Authorize(Policy = "SystemAdministrator")]
    public ActionResult UpdateUserRole(string userId, [FromBody] UpdateUserRoleRequest request)
    {
        // Roles are assigned via Entra ID group membership (CyberLab-Admins,
        // CyberLab-Teachers, CyberLab-Students). To change a user's role,
        // move them to the appropriate group in the Azure portal.
        logger.LogInformation("Role change requested for user {UserId} to {Role} — manage via Entra ID groups", userId, request.Role);
        return Ok(new { message = "Role changes are managed via Entra ID group membership. Move the user to the appropriate group in the Azure portal." });
    }

    // ========================================================================
    // Student Progress Summary
    // ========================================================================

    [HttpGet("student/progress")]
    [Authorize(Policy = "Student")]
    public async Task<ActionResult> GetStudentProgressSummary()
    {
        var studentId = User.FindFirst("oid")?.Value ?? User.Identity?.Name ?? "unknown";

        var progressItems = await context.StudentProgress
            .Where(p => p.StudentId == studentId)
            .ToListAsync();

        var assignmentCount = await context.StudentLabAssignments
            .CountAsync(a => a.StudentId == studentId);

        return Ok(new
        {
            totalSessions = assignmentCount,
            completedSessions = 0,
            totalPointsEarned = progressItems.Sum(p => p.PointsAwarded),
            totalObjectivesCompleted = progressItems.Count(p => p.PointsAwarded > 0),
            badges = Array.Empty<object>(),
            recentActivity = Array.Empty<object>(),
        });
    }
}

// ========================================================================
// Request DTOs
// ========================================================================

public class CreateSnapshotRequest
{
    public string SnapshotName { get; set; } = string.Empty;
}

public class FlagSubmitRequest
{
    public Guid SessionId { get; set; }
    public string FlagValue { get; set; } = string.Empty;
}

public class UpdateConfigRequest
{
    public string Value { get; set; } = string.Empty;
}

public class UpdateUserRoleRequest
{
    public string Role { get; set; } = string.Empty;
}
