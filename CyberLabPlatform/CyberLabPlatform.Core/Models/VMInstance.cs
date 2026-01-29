using CyberLabPlatform.Core.Enums;

namespace CyberLabPlatform.Core.Models;

public class VMInstance
{
    public Guid Id { get; set; }
    public Guid SessionId { get; set; }
    public LabSession Session { get; set; } = null!;
    public string StudentId { get; set; } = string.Empty;
    public string VmName { get; set; } = string.Empty;
    public Guid HyperVVMId { get; set; }
    public string IpAddress { get; set; } = string.Empty;
    public string Credentials { get; set; } = string.Empty;
    public string VmType { get; set; } = string.Empty;
    public VMStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastActivity { get; set; }
    public bool IsShared { get; set; }
}
