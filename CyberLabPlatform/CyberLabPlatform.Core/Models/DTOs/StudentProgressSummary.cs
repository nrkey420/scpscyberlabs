namespace CyberLabPlatform.Core.Models.DTOs;

public class StudentProgressSummary
{
    public string StudentId { get; set; } = string.Empty;
    public string StudentName { get; set; } = string.Empty;
    public int TotalPoints { get; set; }
    public List<CompletedObjectiveInfo> CompletedObjectives { get; set; } = new();
    public int TotalConnectionTimeSeconds { get; set; }
}

public class CompletedObjectiveInfo
{
    public string Title { get; set; } = string.Empty;
    public DateTime CompletedAt { get; set; }
}
