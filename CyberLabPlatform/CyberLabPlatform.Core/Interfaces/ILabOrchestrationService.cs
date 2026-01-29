using CyberLabPlatform.Core.Models;

namespace CyberLabPlatform.Core.Interfaces;

public class DeployLabRequest
{
    public Guid TemplateId { get; set; }
    public string ClassName { get; set; } = string.Empty;
    public string InstructorId { get; set; } = string.Empty;
    public List<string> StudentIds { get; set; } = new();
    public List<string> StudentEmails { get; set; } = new();
    public List<string> StudentNames { get; set; } = new();
    public int DurationMinutes { get; set; } = 240;
    public int InactivityTimeoutMinutes { get; set; } = 30;
}

public interface ILabOrchestrationService
{
    Task<LabSession> DeployLabAsync(DeployLabRequest request);
    Task TerminateLabAsync(Guid sessionId);
    Task PauseVMAsync(Guid vmId);
    Task ResumeVMAsync(Guid vmId);
    Task ResetVMAsync(Guid vmId);
    Task<string> GetVMConsoleUrlAsync(Guid vmId);
    Task CreateSnapshotAsync(Guid vmId, string snapshotName);
}
