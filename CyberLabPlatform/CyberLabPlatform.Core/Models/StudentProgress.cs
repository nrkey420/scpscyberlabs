namespace CyberLabPlatform.Core.Models;

public class StudentProgress
{
    public Guid Id { get; set; }
    public Guid SessionId { get; set; }
    public LabSession Session { get; set; } = null!;
    public string StudentId { get; set; } = string.Empty;
    public Guid ObjectiveId { get; set; }
    public LabObjective Objective { get; set; } = null!;
    public DateTime CompletedAt { get; set; }
    public string FlagSubmitted { get; set; } = string.Empty;
    public int PointsAwarded { get; set; }
    public int AttemptNumber { get; set; } = 1;
}
