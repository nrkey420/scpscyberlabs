namespace CyberLabPlatform.Core.Models;

public class SystemConfig
{
    public string Key { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public DateTime UpdatedAt { get; set; }
    public string UpdatedBy { get; set; } = string.Empty;
}
