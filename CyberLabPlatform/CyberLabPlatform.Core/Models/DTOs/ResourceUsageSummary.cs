namespace CyberLabPlatform.Core.Models.DTOs;

public class ResourceUsageSummary
{
    public int TotalRamGb { get; set; }
    public int UsedRamGb { get; set; }
    public int TotalVcpu { get; set; }
    public int UsedVcpu { get; set; }
    public int RunningVms { get; set; }
    public int ActiveSessions { get; set; }
}
