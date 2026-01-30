using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace CyberLabPlatform.Web.Services;

public class GamificationService(
    CyberLabDbContext context,
    IHubContext<LabActivityHub> hubContext,
    ILogger<GamificationService> logger) : IGamificationService
{
    public async Task<FlagSubmissionResult> SubmitFlagAsync(Guid sessionId, string studentId, Guid objectiveId, string flagValue)
    {
        logger.LogInformation("Flag submission for session {SessionId}, student {StudentId}, objective {ObjectiveId}", sessionId, studentId, objectiveId);

        try
        {
            var objective = await context.LabObjectives.FindAsync(objectiveId)
                ?? throw new InvalidOperationException($"Objective {objectiveId} not found");

            // Check if already completed
            var existingProgress = await context.StudentProgress
                .FirstOrDefaultAsync(p => p.SessionId == sessionId && p.StudentId == studentId && p.ObjectiveId == objectiveId && p.PointsAwarded > 0);

            if (existingProgress != null)
            {
                return new FlagSubmissionResult
                {
                    IsCorrect = true,
                    PointsAwarded = 0,
                    Message = "Objective already completed"
                };
            }

            // Validate flag
            var isCorrect = string.Equals(flagValue.Trim(), objective.FlagValue.Trim(), StringComparison.Ordinal);

            // Record attempt
            var attemptCount = await context.StudentProgress
                .CountAsync(p => p.SessionId == sessionId && p.StudentId == studentId && p.ObjectiveId == objectiveId);

            if (!isCorrect)
            {
                var failedAttempt = new StudentProgress
                {
                    Id = Guid.NewGuid(),
                    SessionId = sessionId,
                    StudentId = studentId,
                    ObjectiveId = objectiveId,
                    CompletedAt = DateTime.UtcNow,
                    FlagSubmitted = flagValue,
                    PointsAwarded = 0,
                    AttemptNumber = attemptCount + 1
                };
                context.StudentProgress.Add(failedAttempt);
                await context.SaveChangesAsync();

                return new FlagSubmissionResult
                {
                    IsCorrect = false,
                    PointsAwarded = 0,
                    Message = "Incorrect flag value"
                };
            }

            // Award points
            await AwardPointsAsync(sessionId, studentId, objectiveId, objective.Points);

            // Check for badges
            var newBadges = await CheckBadgesAsync(sessionId, studentId, objectiveId);

            // Notify via SignalR
            await hubContext.Clients.Group($"session-{sessionId}").SendAsync("ObjectiveCompleted", new
            {
                studentId,
                objectiveId,
                objectiveTitle = objective.Title,
                points = objective.Points,
                badges = newBadges
            });

            return new FlagSubmissionResult
            {
                IsCorrect = true,
                PointsAwarded = objective.Points,
                NewBadges = newBadges,
                Message = "Flag accepted! Points awarded."
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error processing flag submission");
            throw;
        }
    }

    public async Task AwardPointsAsync(Guid sessionId, string studentId, Guid objectiveId, int points)
    {
        // Check if already awarded
        var existing = await context.StudentProgress
            .FirstOrDefaultAsync(p => p.SessionId == sessionId && p.StudentId == studentId && p.ObjectiveId == objectiveId && p.PointsAwarded > 0);

        if (existing != null)
        {
            logger.LogDebug("Points already awarded for objective {ObjectiveId} to student {StudentId}", objectiveId, studentId);
            return;
        }

        var attemptCount = await context.StudentProgress
            .CountAsync(p => p.SessionId == sessionId && p.StudentId == studentId && p.ObjectiveId == objectiveId);

        var progress = new StudentProgress
        {
            Id = Guid.NewGuid(),
            SessionId = sessionId,
            StudentId = studentId,
            ObjectiveId = objectiveId,
            CompletedAt = DateTime.UtcNow,
            FlagSubmitted = string.Empty,
            PointsAwarded = points,
            AttemptNumber = attemptCount + 1
        };

        context.StudentProgress.Add(progress);
        await context.SaveChangesAsync();

        logger.LogInformation("Awarded {Points} points to student {StudentId} for objective {ObjectiveId}", points, studentId, objectiveId);
    }

    public async Task<List<LeaderboardEntry>> GetClassLeaderboardAsync(Guid sessionId)
    {
        logger.LogDebug("Fetching leaderboard for session {SessionId}", sessionId);

        try
        {
            var session = await context.LabSessions
                .Include(s => s.StudentAssignments)
                .FirstOrDefaultAsync(s => s.Id == sessionId)
                ?? throw new InvalidOperationException($"Session {sessionId} not found");

            var leaderboard = new List<LeaderboardEntry>();

            foreach (var assignment in session.StudentAssignments)
            {
                var progressEntries = await context.StudentProgress
                    .Where(p => p.SessionId == sessionId && p.StudentId == assignment.StudentId && p.PointsAwarded > 0)
                    .ToListAsync();

                var totalPoints = progressEntries.Sum(p => p.PointsAwarded);
                var objectivesCompleted = progressEntries.Count;

                leaderboard.Add(new LeaderboardEntry
                {
                    StudentId = assignment.StudentId,
                    StudentName = assignment.StudentName,
                    TotalPoints = totalPoints,
                    ObjectivesCompleted = objectivesCompleted,
                    Badges = await GetStudentBadgesAsync(sessionId, assignment.StudentId)
                });
            }

            return leaderboard.OrderByDescending(e => e.TotalPoints).ThenBy(e => e.StudentName).ToList();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching leaderboard for session {SessionId}", sessionId);
            throw;
        }
    }

    private async Task<List<string>> CheckBadgesAsync(Guid sessionId, string studentId, Guid objectiveId)
    {
        var badges = new List<string>();

        try
        {
            // "First Blood" - first student to complete any objective in this session
            var anyOtherCompletion = await context.StudentProgress
                .AnyAsync(p => p.SessionId == sessionId && p.ObjectiveId == objectiveId && p.PointsAwarded > 0 && p.StudentId != studentId);

            if (!anyOtherCompletion)
                badges.Add("First Blood");

            // "Completionist" - completed all objectives for the template
            var session = await context.LabSessions.FindAsync(sessionId);
            if (session != null)
            {
                var totalObjectives = await context.LabObjectives
                    .CountAsync(o => o.TemplateId == session.TemplateId);

                var studentCompleted = await context.StudentProgress
                    .Where(p => p.SessionId == sessionId && p.StudentId == studentId && p.PointsAwarded > 0)
                    .Select(p => p.ObjectiveId)
                    .Distinct()
                    .CountAsync();

                if (studentCompleted >= totalObjectives && totalObjectives > 0)
                    badges.Add("Completionist");

                // "Speed Demon" - completed all objectives within 30 minutes of session start
                if (studentCompleted >= totalObjectives && totalObjectives > 0)
                {
                    var elapsed = DateTime.UtcNow - session.StartTime;
                    if (elapsed.TotalMinutes <= 30)
                        badges.Add("Speed Demon");
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Error checking badges for student {StudentId}", studentId);
        }

        return badges;
    }

    private async Task<List<string>> GetStudentBadgesAsync(Guid sessionId, string studentId)
    {
        // Recompute badges for display (in production, these would be stored)
        var badges = new List<string>();

        try
        {
            var completedObjectives = await context.StudentProgress
                .Where(p => p.SessionId == sessionId && p.StudentId == studentId && p.PointsAwarded > 0)
                .ToListAsync();

            if (!completedObjectives.Any())
                return badges;

            // Check First Blood for each objective
            foreach (var progress in completedObjectives)
            {
                var wasFirst = !await context.StudentProgress
                    .AnyAsync(p => p.SessionId == sessionId && p.ObjectiveId == progress.ObjectiveId
                        && p.PointsAwarded > 0 && p.StudentId != studentId && p.CompletedAt < progress.CompletedAt);

                if (wasFirst)
                {
                    badges.Add("First Blood");
                    break;
                }
            }

            // Check Completionist
            var session = await context.LabSessions.FindAsync(sessionId);
            if (session != null)
            {
                var totalObjectives = await context.LabObjectives.CountAsync(o => o.TemplateId == session.TemplateId);
                var uniqueCompleted = completedObjectives.Select(p => p.ObjectiveId).Distinct().Count();

                if (uniqueCompleted >= totalObjectives && totalObjectives > 0)
                {
                    badges.Add("Completionist");

                    var lastCompletion = completedObjectives.Max(p => p.CompletedAt);
                    if ((lastCompletion - session.StartTime).TotalMinutes <= 30)
                        badges.Add("Speed Demon");
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Error getting badges for student {StudentId}", studentId);
        }

        return badges.Distinct().ToList();
    }
}
