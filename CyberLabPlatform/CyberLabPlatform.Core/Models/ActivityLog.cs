namespace CyberLabPlatform.Core.Models;

public class ActivityLog
{
    public long Id { get; set; }
    public Guid SessionId { get; set; }
    public LabSession Session { get; set; } = null!;
    public string StudentId { get; set; } = string.Empty;
    public Guid? VmId { get; set; }
    public VMInstance? VmInstance { get; set; }
    public DateTime Timestamp { get; set; }
    public string EventType { get; set; } = string.Empty;
    public string EventDetails { get; set; } = string.Empty;
    public string IpAddress { get; set; } = string.Empty;
}
