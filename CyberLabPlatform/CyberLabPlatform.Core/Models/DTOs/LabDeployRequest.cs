namespace CyberLabPlatform.Core.Models.DTOs;

public class LabDeployRequest
{
    public Guid TemplateId { get; set; }
    public List<string> StudentIds { get; set; } = new();
    public int TimeoutMinutes { get; set; }
    public int MaxDurationMinutes { get; set; }
    public string ClassName { get; set; } = string.Empty;
}
