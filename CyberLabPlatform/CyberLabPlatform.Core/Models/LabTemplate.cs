using CyberLabPlatform.Core.Enums;

namespace CyberLabPlatform.Core.Models;

public class LabTemplate
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string GitCommitHash { get; set; } = string.Empty;
    public DifficultyLevel DifficultyLevel { get; set; }
    public int EstimatedDurationMinutes { get; set; }
    public string VmDefinitions { get; set; } = string.Empty;
    public string NetworkTopology { get; set; } = string.Empty;
    public string Objectives { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}
