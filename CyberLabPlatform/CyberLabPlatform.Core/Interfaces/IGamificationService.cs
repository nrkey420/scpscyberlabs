namespace CyberLabPlatform.Core.Interfaces;

public class LeaderboardEntry
{
    public string StudentId { get; set; } = string.Empty;
    public string StudentName { get; set; } = string.Empty;
    public int TotalPoints { get; set; }
    public int ObjectivesCompleted { get; set; }
    public List<string> Badges { get; set; } = new();
}

public class FlagSubmissionResult
{
    public bool IsCorrect { get; set; }
    public int PointsAwarded { get; set; }
    public List<string> NewBadges { get; set; } = new();
    public string Message { get; set; } = string.Empty;
}

public interface IGamificationService
{
    Task<FlagSubmissionResult> SubmitFlagAsync(Guid sessionId, string studentId, Guid objectiveId, string flagValue);
    Task AwardPointsAsync(Guid sessionId, string studentId, Guid objectiveId, int points);
    Task<List<LeaderboardEntry>> GetClassLeaderboardAsync(Guid sessionId);
}
