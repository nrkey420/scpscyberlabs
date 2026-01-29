using CyberLabPlatform.Core.Enums;

namespace CyberLabPlatform.Core.Models.DTOs;

public class LabSessionSummary
{
    public Guid Id { get; set; }
    public string TemplateName { get; set; } = string.Empty;
    public string ClassName { get; set; } = string.Empty;
    public LabStatus Status { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime ScheduledEndTime { get; set; }
    public int StudentCount { get; set; }
    public int VmCount { get; set; }
}
