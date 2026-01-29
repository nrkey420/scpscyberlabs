using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Services;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace CyberLabPlatform.Tests.Unit;

public class ReportingServiceTests : IDisposable
{
    private readonly CyberLabDbContext _dbContext;
    private readonly ReportingService _sut;
    private readonly Guid _sessionId;

    public ReportingServiceTests()
    {
        var options = new DbContextOptionsBuilder<CyberLabDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        _dbContext = new CyberLabDbContext(options);
        var loggerMock = new Mock<ILogger<ReportingService>>();

        _sut = new ReportingService(_dbContext, loggerMock.Object);
        _sessionId = SeedData();
    }

    private Guid SeedData()
    {
        var template = new LabTemplate
        {
            Id = Guid.NewGuid(),
            Name = "Reporting Test Lab",
            Description = "Lab used for reporting tests",
            Version = "2.0",
            GitCommitHash = "rep789",
            DifficultyLevel = DifficultyLevel.Advanced,
            EstimatedDurationMinutes = 180,
            VmDefinitions = "[]",
            NetworkTopology = "{}",
            Objectives = "[]",
            CreatedAt = DateTime.UtcNow.AddDays(-7),
            UpdatedAt = DateTime.UtcNow.AddDays(-7),
            CreatedBy = "admin",
            IsActive = true
        };
        _dbContext.LabTemplates.Add(template);

        var session = new LabSession
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            InstructorId = "instructor-1",
            ClassName = "Advanced Pen Testing",
            StartTime = DateTime.UtcNow.AddHours(-3),
            ScheduledEndTime = DateTime.UtcNow.AddHours(-1),
            ActualEndTime = DateTime.UtcNow.AddHours(-1),
            Status = LabStatus.Terminated,
            CreatedAt = DateTime.UtcNow.AddHours(-3)
        };
        _dbContext.LabSessions.Add(session);

        var objective1 = new LabObjective
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            ObjectiveOrder = 1,
            Title = "Exploit SQL Injection",
            Description = "Find and exploit the SQL injection vulnerability",
            FlagValue = "CTF{sqli_found}",
            Points = 50,
            Hint = "Check user input fields",
            CreatedAt = DateTime.UtcNow.AddDays(-7)
        };
        var objective2 = new LabObjective
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            ObjectiveOrder = 2,
            Title = "Privilege Escalation",
            Description = "Escalate to root",
            FlagValue = "CTF{root_obtained}",
            Points = 100,
            Hint = "Check SUID binaries",
            CreatedAt = DateTime.UtcNow.AddDays(-7)
        };
        _dbContext.LabObjectives.AddRange(objective1, objective2);

        // Student assignments
        _dbContext.StudentLabAssignments.AddRange(
            new StudentLabAssignment
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-1",
                StudentEmail = "alice@university.edu",
                StudentName = "Alice Johnson",
                EnrolledAt = DateTime.UtcNow.AddHours(-3),
                FirstAccess = DateTime.UtcNow.AddHours(-2.9),
                TotalConnectionTimeSeconds = 6000
            },
            new StudentLabAssignment
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-2",
                StudentEmail = "bob@university.edu",
                StudentName = "Bob Smith",
                EnrolledAt = DateTime.UtcNow.AddHours(-3),
                FirstAccess = DateTime.UtcNow.AddHours(-2.8),
                TotalConnectionTimeSeconds = 5400
            });

        // Student progress
        _dbContext.StudentProgress.AddRange(
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-1",
                ObjectiveId = objective1.Id,
                CompletedAt = DateTime.UtcNow.AddHours(-2),
                FlagSubmitted = "CTF{sqli_found}",
                PointsAwarded = 50,
                AttemptNumber = 1
            },
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-1",
                ObjectiveId = objective2.Id,
                CompletedAt = DateTime.UtcNow.AddHours(-1.5),
                FlagSubmitted = "CTF{root_obtained}",
                PointsAwarded = 100,
                AttemptNumber = 2
            },
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-2",
                ObjectiveId = objective1.Id,
                CompletedAt = DateTime.UtcNow.AddHours(-1.8),
                FlagSubmitted = "CTF{sqli_found}",
                PointsAwarded = 50,
                AttemptNumber = 1
            });

        // Activity logs
        _dbContext.ActivityLogs.AddRange(
            new ActivityLog
            {
                SessionId = session.Id,
                StudentId = "student-1",
                Timestamp = DateTime.UtcNow.AddHours(-2.9),
                EventType = "SessionJoined",
                EventDetails = "Student joined the lab session",
                IpAddress = "192.168.1.100"
            },
            new ActivityLog
            {
                SessionId = session.Id,
                StudentId = "student-1",
                Timestamp = DateTime.UtcNow.AddHours(-2),
                EventType = "FlagSubmitted",
                EventDetails = "Submitted flag for objective 1 - Correct",
                IpAddress = "192.168.1.100"
            },
            new ActivityLog
            {
                SessionId = session.Id,
                StudentId = "student-2",
                Timestamp = DateTime.UtcNow.AddHours(-2.8),
                EventType = "SessionJoined",
                EventDetails = "Student joined the lab session",
                IpAddress = "192.168.1.101"
            },
            new ActivityLog
            {
                SessionId = session.Id,
                StudentId = "student-2",
                Timestamp = DateTime.UtcNow.AddHours(-1.8),
                EventType = "FlagSubmitted",
                EventDetails = "Submitted flag for objective 1 - Correct",
                IpAddress = "192.168.1.101"
            });

        _dbContext.SaveChanges();
        return session.Id;
    }

    [Fact]
    public async Task GenerateReport_PDF_ReturnsBytes()
    {
        // Arrange
        var format = ReportFormat.PDF;

        // Act
        var result = await _sut.GenerateSessionReportAsync(_sessionId, format);

        // Assert
        result.Should().NotBeNull();
        result.Should().NotBeEmpty("a PDF report should contain data");
        result.Length.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task GenerateReport_CSV_ReturnsBytes()
    {
        // Arrange
        var format = ReportFormat.CSV;

        // Act
        var result = await _sut.GenerateSessionReportAsync(_sessionId, format);

        // Assert
        result.Should().NotBeNull();
        result.Should().NotBeEmpty("a CSV report should contain data");

        // CSV should be parseable as text
        var csvContent = System.Text.Encoding.UTF8.GetString(result);
        csvContent.Should().NotBeNullOrEmpty();
        csvContent.Should().Contain(",", "CSV output should contain comma delimiters");
    }

    [Fact]
    public async Task ExportActivityLog_ReturnsStream()
    {
        // Arrange & Act
        var result = await _sut.ExportActivityLogAsync(_sessionId);

        // Assert
        result.Should().NotBeNull();
        result.Should().NotBeEmpty("activity log export should contain data");
        result.Length.Should().BeGreaterThan(0);

        // Verify the export contains activity data
        var content = System.Text.Encoding.UTF8.GetString(result);
        content.Should().Contain("SessionJoined").Or.Subject.Should().Contain("FlagSubmitted",
            "the export should include activity events from the seeded data");
    }

    public void Dispose()
    {
        _dbContext.Dispose();
    }
}
