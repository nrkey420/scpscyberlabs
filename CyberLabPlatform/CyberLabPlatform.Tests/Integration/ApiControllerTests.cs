using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Core.Models.DTOs;
using CyberLabPlatform.Web.Data;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Xunit;

namespace CyberLabPlatform.Tests.Integration;

#region Test Authentication Handler

public class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string SchemeName = "TestScheme";
    public const string UserIdHeader = "X-Test-UserId";
    public const string RoleHeader = "X-Test-Role";
    public const string NameHeader = "X-Test-Name";
    public const string EmailHeader = "X-Test-Email";

    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder) { }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.ContainsKey(UserIdHeader))
            return Task.FromResult(AuthenticateResult.Fail("Missing test auth header"));

        var userId = Request.Headers[UserIdHeader].ToString();
        var role = Request.Headers.ContainsKey(RoleHeader) ? Request.Headers[RoleHeader].ToString() : "Student";
        var name = Request.Headers.ContainsKey(NameHeader) ? Request.Headers[NameHeader].ToString() : "Test User";
        var email = Request.Headers.ContainsKey(EmailHeader) ? Request.Headers[EmailHeader].ToString() : "test@test.com";

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Name, name),
            new Claim(ClaimTypes.Email, email),
            new Claim(ClaimTypes.Role, role)
        };

        var identity = new ClaimsIdentity(claims, SchemeName);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SchemeName);

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}

#endregion

public class ApiControllerTests : IClassFixture<WebApplicationFactory<Program>>, IDisposable
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;

    public ApiControllerTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");

            builder.ConfigureTestServices(services =>
            {
                // Remove existing DbContext registration
                var descriptor = services.SingleOrDefault(
                    d => d.ServiceType == typeof(DbContextOptions<CyberLabDbContext>));
                if (descriptor != null)
                    services.Remove(descriptor);

                // Use InMemory database for tests
                services.AddDbContext<CyberLabDbContext>(options =>
                    options.UseInMemoryDatabase("IntegrationTestDb_" + Guid.NewGuid()));

                // Configure test authentication
                services.AddAuthentication(options =>
                    {
                        options.DefaultAuthenticateScheme = TestAuthHandler.SchemeName;
                        options.DefaultChallengeScheme = TestAuthHandler.SchemeName;
                    })
                    .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            });
        });

        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    private void SetAuthHeaders(HttpRequestMessage request, string userId, string role,
        string name = "Test User", string email = "test@test.com")
    {
        request.Headers.Add(TestAuthHandler.UserIdHeader, userId);
        request.Headers.Add(TestAuthHandler.RoleHeader, role);
        request.Headers.Add(TestAuthHandler.NameHeader, name);
        request.Headers.Add(TestAuthHandler.EmailHeader, email);
    }

    private async Task SeedTestData()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CyberLabDbContext>();

        var template = new LabTemplate
        {
            Id = Guid.Parse("11111111-1111-1111-1111-111111111111"),
            Name = "Web Application Security",
            Description = "Learn OWASP Top 10 vulnerabilities",
            Version = "3.0",
            GitCommitHash = "seed123",
            DifficultyLevel = DifficultyLevel.Intermediate,
            EstimatedDurationMinutes = 90,
            VmDefinitions = "[{\"name\":\"kali\",\"ram_gb\":4,\"vcpu\":2,\"template\":\"kali-2024\"}]",
            NetworkTopology = "{\"subnet\":\"10.0.0.0/24\"}",
            Objectives = "[]",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatedBy = "admin",
            IsActive = true
        };
        db.LabTemplates.Add(template);

        var inactiveTemplate = new LabTemplate
        {
            Id = Guid.Parse("22222222-2222-2222-2222-222222222222"),
            Name = "Deprecated Lab",
            Description = "This lab is no longer active",
            Version = "1.0",
            GitCommitHash = "old999",
            DifficultyLevel = DifficultyLevel.Beginner,
            EstimatedDurationMinutes = 30,
            VmDefinitions = "[]",
            NetworkTopology = "{}",
            Objectives = "[]",
            CreatedAt = DateTime.UtcNow.AddMonths(-6),
            UpdatedAt = DateTime.UtcNow.AddMonths(-1),
            CreatedBy = "admin",
            IsActive = false
        };
        db.LabTemplates.Add(inactiveTemplate);

        var objective = new LabObjective
        {
            Id = Guid.Parse("33333333-3333-3333-3333-333333333333"),
            TemplateId = template.Id,
            ObjectiveOrder = 1,
            Title = "Find XSS Vulnerability",
            Description = "Discover and exploit the stored XSS",
            FlagValue = "CTF{xss_found_2024}",
            Points = 75,
            Hint = "Check the comment section",
            CreatedAt = DateTime.UtcNow
        };
        db.LabObjectives.Add(objective);

        var session = new LabSession
        {
            Id = Guid.Parse("44444444-4444-4444-4444-444444444444"),
            TemplateId = template.Id,
            InstructorId = "instructor-1",
            ClassName = "WebSec 301",
            StartTime = DateTime.UtcNow,
            ScheduledEndTime = DateTime.UtcNow.AddHours(2),
            Status = LabStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
        db.LabSessions.Add(session);

        db.StudentLabAssignments.Add(new StudentLabAssignment
        {
            Id = Guid.NewGuid(),
            SessionId = session.Id,
            StudentId = "student-1",
            StudentEmail = "student@test.com",
            StudentName = "Test Student",
            EnrolledAt = DateTime.UtcNow
        });

        // Seed leaderboard data
        db.StudentProgress.AddRange(
            new StudentProgress
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = "student-top",
                ObjectiveId = objective.Id,
                CompletedAt = DateTime.UtcNow.AddMinutes(-30),
                FlagSubmitted = "CTF{xss_found_2024}",
                PointsAwarded = 75,
                AttemptNumber = 1
            });

        await db.SaveChangesAsync();
    }

    [Fact]
    public async Task GetTemplates_ReturnsAllActive()
    {
        // Arrange
        await SeedTestData();
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/templates");
        SetAuthHeaders(request, "instructor-1", "Instructor");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var content = await response.Content.ReadAsStringAsync();
        content.Should().NotBeNullOrEmpty();

        var templates = JsonSerializer.Deserialize<List<LabTemplate>>(content,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        templates.Should().NotBeNull();
        templates!.Should().OnlyContain(t => t.IsActive,
            "only active templates should be returned");
        templates.Should().Contain(t => t.Name == "Web Application Security");
        templates.Should().NotContain(t => t.Name == "Deprecated Lab");
    }

    [Fact]
    public async Task DeployLab_AsInstructor_ReturnsCreated()
    {
        // Arrange
        await SeedTestData();
        var deployRequest = new LabDeployRequest
        {
            TemplateId = Guid.Parse("11111111-1111-1111-1111-111111111111"),
            StudentIds = new List<string> { "student-1", "student-2" },
            TimeoutMinutes = 120,
            MaxDurationMinutes = 240,
            ClassName = "Instructor Deploy Test"
        };

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/labs/deploy")
        {
            Content = JsonContent.Create(deployRequest)
        };
        SetAuthHeaders(request, "instructor-1", "Instructor", "Prof. Smith", "smith@university.edu");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().BeOneOf(HttpStatusCode.Created, HttpStatusCode.OK);
    }

    [Fact]
    public async Task DeployLab_AsStudent_ReturnsForbidden()
    {
        // Arrange
        await SeedTestData();
        var deployRequest = new LabDeployRequest
        {
            TemplateId = Guid.Parse("11111111-1111-1111-1111-111111111111"),
            StudentIds = new List<string> { "student-1" },
            TimeoutMinutes = 120,
            MaxDurationMinutes = 240,
            ClassName = "Student Attempt"
        };

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/labs/deploy")
        {
            Content = JsonContent.Create(deployRequest)
        };
        SetAuthHeaders(request, "student-1", "Student", "Student One", "student@test.com");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Forbidden,
            "students should not be authorized to deploy labs");
    }

    [Fact]
    public async Task SubmitFlag_CorrectFlag_ReturnsPoints()
    {
        // Arrange
        await SeedTestData();
        var flagSubmission = new
        {
            SessionId = "44444444-4444-4444-4444-444444444444",
            ObjectiveId = "33333333-3333-3333-3333-333333333333",
            FlagValue = "CTF{xss_found_2024}"
        };

        var request = new HttpRequestMessage(HttpMethod.Post, "/api/gamification/submit-flag")
        {
            Content = JsonContent.Create(flagSubmission)
        };
        SetAuthHeaders(request, "student-1", "Student", "Test Student", "student@test.com");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var content = await response.Content.ReadAsStringAsync();
        content.Should().NotBeNullOrEmpty();

        var result = JsonSerializer.Deserialize<CyberLabPlatform.Core.Interfaces.FlagSubmissionResult>(content,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        result.Should().NotBeNull();
        result!.IsCorrect.Should().BeTrue();
        result.PointsAwarded.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task GetLeaderboard_ReturnsOrderedResults()
    {
        // Arrange
        await SeedTestData();
        var sessionId = "44444444-4444-4444-4444-444444444444";
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/gamification/leaderboard/{sessionId}");
        SetAuthHeaders(request, "student-1", "Student");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var content = await response.Content.ReadAsStringAsync();
        var leaderboard = JsonSerializer.Deserialize<List<CyberLabPlatform.Core.Models.DTOs.LeaderboardEntry>>(content,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        leaderboard.Should().NotBeNull();
        if (leaderboard!.Count > 1)
        {
            for (int i = 1; i < leaderboard.Count; i++)
            {
                leaderboard[i - 1].TotalPoints.Should().BeGreaterOrEqualTo(leaderboard[i].TotalPoints,
                    "leaderboard entries should be ordered by total points descending");
            }
        }
    }

    [Fact]
    public async Task GetResourceUsage_AsAdmin_ReturnsUsage()
    {
        // Arrange
        await SeedTestData();
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/resources/usage");
        SetAuthHeaders(request, "admin-1", "SystemAdministrator", "Admin User", "admin@cyberlab.local");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var content = await response.Content.ReadAsStringAsync();
        content.Should().NotBeNullOrEmpty();

        var usage = JsonSerializer.Deserialize<ResourceUsageSummary>(content,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        usage.Should().NotBeNull();
        usage!.TotalRamGb.Should().BeGreaterThan(0);
        usage.TotalVcpu.Should().BeGreaterThan(0);
        usage.UsedRamGb.Should().BeGreaterOrEqualTo(0);
        usage.RunningVms.Should().BeGreaterOrEqualTo(0);
    }

    public void Dispose()
    {
        _client.Dispose();
    }
}
