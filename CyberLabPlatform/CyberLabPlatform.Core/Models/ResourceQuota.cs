namespace CyberLabPlatform.Core.Models;

public class ResourceQuota
{
    public Guid Id { get; set; }
    public string Role { get; set; } = string.Empty;
    public int MaxConcurrentVms { get; set; }
    public int MaxRamGb { get; set; }
    public int MaxVcpu { get; set; }
    public int MaxSessionDurationMinutes { get; set; }
}
