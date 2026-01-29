using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Services;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace CyberLabPlatform.Tests.Unit;

public class GamificationServiceTests : IDisposable
{
    private readonly CyberLabDbContext _dbContext;
    private readonly GamificationService _sut;
    private readonly Mock<IActivityLoggingService> _activityLoggingMock;
    private readonly Mock<ILogger<GamificationService>> _loggerMock;

    public GamificationServiceTests()
    {
        var options = new DbContextOptionsBuilder<CyberLabDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        _dbContext = new CyberLabDbContext(options);
        _activityLoggingMock = new Mock<IActivityLoggingService>();
        _loggerMock = new Mock<ILogger<GamificationService>>();

        _sut = new GamificationService(_dbContext, _activityLoggingMock.Object, _loggerMock.Object);
    }

    private (LabTemplate template, LabSession session, LabObjective objective) SeedBasicLabData(
        string flagValue = "CTF{correct_flag}", int points = 100)
    {
        var template = new LabTemplate
        {
            Id = Guid.NewGuid(),
            Name = "Test Lab",
            Description = "A test lab template",
            Version = "1.0",
            GitCommitHash = "abc123",
            DifficultyLevel = DifficultyLevel.Intermediate,
            EstimatedDurationMinutes = 60,
            VmDefinitions = "{}",
            NetworkTopology = "{}",
            Objectives = "[]",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatedBy = "admin",
            IsActive = true
        };
        _dbContext.LabTemplates.Add(template);

        var session = new LabSession
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            InstructorId = "instructor-1",
            ClassName = "CyberSec 101",
            StartTime = DateTime.UtcNow,
            ScheduledEndTime = DateTime.UtcNow.AddHours(2),
            Status = LabStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.LabSessions.Add(session);

        var objective = new LabObjective
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            ObjectiveOrder = 1,
            Title = "Find the hidden flag",
            Description = "Locate and submit the hidden flag",
            FlagValue = flagValue,
            Points = points,
            Hint = "Look in /etc",
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.LabObjectives.Add(objective);

        _dbContext.SaveChanges();
        return (template, session, objective);
    }

    [Fact]
    public async Task AwardPoints_FirstCompletion_AwardsPoints()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(points: 50);
        var studentId = "student-1";

        // Act
        await _sut.AwardPointsAsync(session.Id, studentId, objective.Id, objective.Points);

        // Assert
        var progress = await _dbContext.StudentProgress
            .FirstOrDefaultAsync(p => p.StudentId == studentId && p.ObjectiveId == objective.Id);

        progress.Should().NotBeNull();
        progress!.PointsAwarded.Should().Be(50);
        progress.SessionId.Should().Be(session.Id);
        progress.ObjectiveId.Should().Be(objective.Id);
    }

    [Fact]
    public async Task AwardPoints_DuplicateCompletion_ReturnsExistingPoints()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(points: 75);
        var studentId = "student-1";

        var existingProgress = new StudentProgress
        {
            Id = Guid.NewGuid(),
            SessionId = session.Id,
            StudentId = studentId,
            ObjectiveId = objective.Id,
            CompletedAt = DateTime.UtcNow.AddMinutes(-10),
            FlagSubmitted = "CTF{correct_flag}",
            PointsAwarded = 75,
            AttemptNumber = 1
        };
        _dbContext.StudentProgress.Add(existingProgress);
        await _dbContext.SaveChangesAsync();

        // Act
        await _sut.AwardPointsAsync(session.Id, studentId, objective.Id, objective.Points);

        // Assert
        var progressRecords = await _dbContext.StudentProgress
            .Where(p => p.StudentId == studentId && p.ObjectiveId == objective.Id)
            .ToListAsync();

        progressRecords.Should().HaveCount(1, "duplicate completions should not create new records");
        progressRecords[0].PointsAwarded.Should().Be(75);
    }

    [Fact]
    public async Task SubmitFlag_CorrectFlag_ReturnsTrue()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(flagValue: "CTF{secret_value}", points: 100);
        var studentId = "student-1";

        // Act
        var result = await _sut.SubmitFlagAsync(session.Id, studentId, objective.Id, "CTF{secret_value}");

        // Assert
        result.Should().NotBeNull();
        result.IsCorrect.Should().BeTrue();
        result.PointsAwarded.Should().Be(100);
    }

    [Fact]
    public async Task SubmitFlag_IncorrectFlag_ReturnsFalse()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(flagValue: "CTF{secret_value}", points: 100);
        var studentId = "student-1";

        // Act
        var result = await _sut.SubmitFlagAsync(session.Id, studentId, objective.Id, "CTF{wrong_flag}");

        // Assert
        result.Should().NotBeNull();
        result.IsCorrect.Should().BeFalse();
        result.PointsAwarded.Should().Be(0);
    }

    [Fact]
    public async Task GetLeaderboard_ReturnsOrderedByPoints()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(points: 100);

        var objective2 = new LabObjective
        {
            Id = Guid.NewGuid(),
            TemplateId = session.TemplateId,
            ObjectiveOrder = 2,
            Title = "Second objective",
            Description = "Another objective",
            FlagValue = "CTF{second}",
            Points = 50,
            Hint = "Try harder",
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.LabObjectives.Add(objective2);

        // Student A: 150 points (completed both objectives)
        _dbContext.StudentProgress.AddRange(
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-a",
                ObjectiveId = objective.Id,
                CompletedAt = DateTime.UtcNow.AddMinutes(-20),
                FlagSubmitted = "CTF{correct_flag}",
                PointsAwarded = 100,
                AttemptNumber = 1
            },
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-a",
                ObjectiveId = objective2.Id,
                CompletedAt = DateTime.UtcNow.AddMinutes(-10),
                FlagSubmitted = "CTF{second}",
                PointsAwarded = 50,
                AttemptNumber = 1
            });

        // Student B: 100 points (completed one objective)
        _dbContext.StudentProgress.Add(new StudentProgress
        {
            Id = Guid.NewGuid(),
            SessionId = session.Id,
            StudentId = "student-b",
            ObjectiveId = objective.Id,
            CompletedAt = DateTime.UtcNow.AddMinutes(-5),
            FlagSubmitted = "CTF{correct_flag}",
            PointsAwarded = 100,
            AttemptNumber = 1
        });

        // Student C: 50 points
        _dbContext.StudentProgress.Add(new StudentProgress
        {
            Id = Guid.NewGuid(),
            SessionId = session.Id,
            StudentId = "student-c",
            ObjectiveId = objective2.Id,
            CompletedAt = DateTime.UtcNow,
            FlagSubmitted = "CTF{second}",
            PointsAwarded = 50,
            AttemptNumber = 1
        });

        await _dbContext.SaveChangesAsync();

        // Act
        var leaderboard = await _sut.GetClassLeaderboardAsync(session.Id);

        // Assert
        leaderboard.Should().NotBeNull();
        leaderboard.Should().HaveCountGreaterOrEqualTo(3);
        leaderboard[0].TotalPoints.Should().BeGreaterOrEqualTo(leaderboard[1].TotalPoints);
        leaderboard[1].TotalPoints.Should().BeGreaterOrEqualTo(leaderboard[2].TotalPoints);
        leaderboard[0].StudentId.Should().Be("student-a");
        leaderboard[0].TotalPoints.Should().Be(150);
    }

    [Fact]
    public async Task GetBadges_FirstBlood_AwardedToFirstCompleter()
    {
        // Arrange
        var (_, session, objective) = SeedBasicLabData(flagValue: "CTF{first_blood}", points: 100);

        // First student completes the objective (should get first blood)
        var firstStudentId = "student-first";
        var firstResult = await _sut.SubmitFlagAsync(session.Id, firstStudentId, objective.Id, "CTF{first_blood}");

        // Second student completes the same objective (should not get first blood)
        var secondStudentId = "student-second";
        var secondResult = await _sut.SubmitFlagAsync(session.Id, secondStudentId, objective.Id, "CTF{first_blood}");

        // Assert
        firstResult.IsCorrect.Should().BeTrue();
        firstResult.NewBadges.Should().Contain(b => b.Contains("First Blood", StringComparison.OrdinalIgnoreCase),
            "the first completer should receive the First Blood badge");

        secondResult.IsCorrect.Should().BeTrue();
        secondResult.NewBadges.Should().NotContain(b => b.Contains("First Blood", StringComparison.OrdinalIgnoreCase),
            "subsequent completers should not receive the First Blood badge");
    }

    public void Dispose()
    {
        _dbContext.Dispose();
    }
}
