using CyberLabPlatform.Core.Enums;

namespace CyberLabPlatform.Core.Models;

public class LabSession
{
    public Guid Id { get; set; }
    public Guid TemplateId { get; set; }
    public LabTemplate Template { get; set; } = null!;
    public string InstructorId { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public DateTime StartTime { get; set; }
    public DateTime ScheduledEndTime { get; set; }
    public DateTime? ActualEndTime { get; set; }
    public LabStatus Status { get; set; }
    public int TimeoutMinutes { get; set; } = 120;
    public int MaxDurationMinutes { get; set; } = 480;
    public int InactivityTimeoutMinutes { get; set; } = 30;
    public DateTime CreatedAt { get; set; }

    public List<VMInstance> VmInstances { get; set; } = new();
    public List<StudentLabAssignment> StudentAssignments { get; set; } = new();
}
