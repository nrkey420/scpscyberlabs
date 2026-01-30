namespace CyberLabPlatform.Core.Models.DTOs;

public class LeaderboardEntry
{
    public string StudentId { get; set; } = string.Empty;
    public string StudentName { get; set; } = string.Empty;
    public string StudentEmail { get; set; } = string.Empty;
    public int TotalPoints { get; set; }
    public int ObjectivesCompleted { get; set; }
    public int Rank { get; set; }
}
