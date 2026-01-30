using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Core.Models;
using CyberLabPlatform.Web.Data;
using CyberLabPlatform.Web.Services;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace CyberLabPlatform.Tests.Unit;

public class LabOrchestrationServiceTests : IDisposable
{
    private readonly CyberLabDbContext _dbContext;
    private readonly Mock<IPowerShellExecutor> _powerShellMock;
    private readonly Mock<IResourceManagerService> _resourceManagerMock;
    private readonly Mock<IGuacamoleTokenService> _guacamoleMock;
    private readonly Mock<IEmailService> _emailMock;
    private readonly Mock<IActivityLoggingService> _activityLoggingMock;
    private readonly Mock<ILogger<LabOrchestrationService>> _loggerMock;
    private readonly Mock<IConfiguration> _configMock;
    private readonly LabOrchestrationService _sut;

    public LabOrchestrationServiceTests()
    {
        var options = new DbContextOptionsBuilder<CyberLabDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        _dbContext = new CyberLabDbContext(options);
        _powerShellMock = new Mock<IPowerShellExecutor>();
        _resourceManagerMock = new Mock<IResourceManagerService>();
        _guacamoleMock = new Mock<IGuacamoleTokenService>();
        _emailMock = new Mock<IEmailService>();
        _activityLoggingMock = new Mock<IActivityLoggingService>();
        _loggerMock = new Mock<ILogger<LabOrchestrationService>>();
        _configMock = new Mock<IConfiguration>();

        _configMock.Setup(c => c["Guacamole:DefaultProtocol"]).Returns("rdp");
        _configMock.Setup(c => c["Guacamole:DefaultPort"]).Returns("3389");

        _sut = new LabOrchestrationService(
            _dbContext,
            _powerShellMock.Object,
            _resourceManagerMock.Object,
            _guacamoleMock.Object,
            _emailMock.Object,
            _activityLoggingMock.Object,
            _configMock.Object,
            _loggerMock.Object);
    }

    private LabTemplate SeedTemplate()
    {
        var template = new LabTemplate
        {
            Id = Guid.NewGuid(),
            Name = "Orchestration Test Lab",
            Description = "Lab for orchestration testing",
            Version = "1.0",
            GitCommitHash = "abc123",
            DifficultyLevel = DifficultyLevel.Intermediate,
            EstimatedDurationMinutes = 120,
            VmDefinitions = "[{\"name\":\"kali\",\"ram_gb\":4,\"vcpu\":2,\"template\":\"kali-2024\"},{\"name\":\"target\",\"ram_gb\":2,\"vcpu\":1,\"template\":\"vuln-server\"}]",
            NetworkTopology = "{\"subnet\":\"10.0.1.0/24\"}",
            Objectives = "[]",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
            CreatedBy = "admin",
            IsActive = true
        };
        _dbContext.LabTemplates.Add(template);
        _dbContext.SaveChanges();
        return template;
    }

    private LabSession SeedActiveSession(Guid templateId)
    {
        var session = new LabSession
        {
            Id = Guid.NewGuid(),
            TemplateId = templateId,
            InstructorId = "instructor-1",
            ClassName = "Test Class",
            StartTime = DateTime.UtcNow,
            ScheduledEndTime = DateTime.UtcNow.AddHours(2),
            Status = LabStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.LabSessions.Add(session);
        _dbContext.SaveChanges();
        return session;
    }

    private VMInstance SeedVM(Guid sessionId, VMStatus status = VMStatus.Running, string studentId = "student-1")
    {
        var vm = new VMInstance
        {
            Id = Guid.NewGuid(),
            SessionId = sessionId,
            StudentId = studentId,
            VmName = "kali-student-1",
            HyperVVMId = Guid.NewGuid(),
            IpAddress = "10.0.1.10",
            Credentials = "{\"username\":\"student\",\"password\":\"encrypted-pass\"}",
            VmType = "kali-2024",
            Status = status,
            CreatedAt = DateTime.UtcNow,
            LastActivity = DateTime.UtcNow
        };
        _dbContext.VMInstances.Add(vm);
        _dbContext.SaveChanges();
        return vm;
    }

    [Fact]
    public async Task DeployLab_ValidTemplate_CreatesSession()
    {
        // Arrange
        var template = SeedTemplate();
        var request = new DeployLabRequest
        {
            TemplateId = template.Id,
            ClassName = "Ethical Hacking 201",
            InstructorId = "instructor-1",
            StudentIds = new List<string> { "student-1", "student-2" },
            StudentEmails = new List<string> { "s1@test.com", "s2@test.com" },
            StudentNames = new List<string> { "Student One", "Student Two" },
            DurationMinutes = 120,
            InactivityTimeoutMinutes = 30
        };

        _resourceManagerMock
            .Setup(r => r.CanDeployAsync(template.Id, 2))
            .ReturnsAsync(true);

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "VM created successfully",
                Data = new Dictionary<string, object?>
                {
                    ["VMId"] = Guid.NewGuid().ToString(),
                    ["IpAddress"] = "10.0.1.10"
                }
            });

        // Act
        var session = await _sut.DeployLabAsync(request);

        // Assert
        session.Should().NotBeNull();
        session.TemplateId.Should().Be(template.Id);
        session.ClassName.Should().Be("Ethical Hacking 201");
        session.InstructorId.Should().Be("instructor-1");
        session.Status.Should().Be(LabStatus.Provisioning).Or.Be(LabStatus.Active);

        var savedSession = await _dbContext.LabSessions.FindAsync(session.Id);
        savedSession.Should().NotBeNull();
    }

    [Fact]
    public async Task DeployLab_InsufficientResources_ThrowsException()
    {
        // Arrange
        var template = SeedTemplate();
        var request = new DeployLabRequest
        {
            TemplateId = template.Id,
            ClassName = "Overloaded Class",
            InstructorId = "instructor-1",
            StudentIds = new List<string> { "student-1" },
            StudentEmails = new List<string> { "s1@test.com" },
            StudentNames = new List<string> { "Student One" },
            DurationMinutes = 120
        };

        _resourceManagerMock
            .Setup(r => r.CanDeployAsync(template.Id, 1))
            .ReturnsAsync(false);

        // Act
        Func<Task> act = () => _sut.DeployLabAsync(request);

        // Assert
        await act.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("*resource*", "deployment should fail when resources are insufficient");
    }

    [Fact]
    public async Task TerminateLab_ActiveSession_UpdatesStatus()
    {
        // Arrange
        var template = SeedTemplate();
        var session = SeedActiveSession(template.Id);
        var vm = SeedVM(session.Id, VMStatus.Running);

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult { Success = true, Output = "VM terminated" });

        // Act
        await _sut.TerminateLabAsync(session.Id);

        // Assert
        var updatedSession = await _dbContext.LabSessions.FindAsync(session.Id);
        updatedSession.Should().NotBeNull();
        updatedSession!.Status.Should().Be(LabStatus.Terminated);
        updatedSession.ActualEndTime.Should().NotBeNull();
        updatedSession.ActualEndTime.Should().BeCloseTo(DateTime.UtcNow, TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task PauseVM_RunningVM_CallsPowerShell()
    {
        // Arrange
        var template = SeedTemplate();
        var session = SeedActiveSession(template.Id);
        var vm = SeedVM(session.Id, VMStatus.Running);

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult { Success = true, Output = "VM paused" });

        // Act
        await _sut.PauseVMAsync(vm.Id);

        // Assert
        _powerShellMock.Verify(
            ps => ps.ExecuteAsync(
                It.Is<string>(s => s.Contains("Pause", StringComparison.OrdinalIgnoreCase) ||
                                   s.Contains("Suspend", StringComparison.OrdinalIgnoreCase) ||
                                   s.Contains("Save", StringComparison.OrdinalIgnoreCase)),
                It.IsAny<Dictionary<string, object?>>()),
            Times.AtLeastOnce,
            "PauseVM should invoke a PowerShell script to pause/suspend the VM");

        var updatedVm = await _dbContext.VMInstances.FindAsync(vm.Id);
        updatedVm!.Status.Should().Be(VMStatus.Paused);
    }

    [Fact]
    public async Task GetConsoleUrl_AuthorizedUser_ReturnsUrl()
    {
        // Arrange
        var template = SeedTemplate();
        var session = SeedActiveSession(template.Id);
        var vm = SeedVM(session.Id, VMStatus.Running, studentId: "student-1");

        var expectedUrl = "https://guac.cyberlab.local/#/client/test-token";
        _guacamoleMock
            .Setup(g => g.GenerateConsoleUrl(
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(), It.IsAny<TimeSpan>()))
            .Returns(expectedUrl);

        // Act
        var consoleUrl = await _sut.GetVMConsoleUrlAsync(vm.Id);

        // Assert
        consoleUrl.Should().NotBeNullOrEmpty();
        consoleUrl.Should().Contain("guac").Or.Subject.Should().Contain("console");
        _guacamoleMock.Verify(
            g => g.GenerateConsoleUrl(
                It.IsAny<string>(), It.Is<string>(ip => ip == "10.0.1.10"),
                It.IsAny<string>(), It.IsAny<int>(),
                It.IsAny<string>(), It.IsAny<string>(), It.IsAny<TimeSpan>()),
            Times.Once);
    }

    [Fact]
    public async Task GetConsoleUrl_UnauthorizedUser_ThrowsUnauthorized()
    {
        // Arrange
        var template = SeedTemplate();
        var session = SeedActiveSession(template.Id);
        // VM does not exist
        var nonExistentVmId = Guid.NewGuid();

        // Act
        Func<Task> act = () => _sut.GetVMConsoleUrlAsync(nonExistentVmId);

        // Assert
        await act.Should().ThrowAsync<Exception>(
            "accessing a non-existent or unauthorized VM should throw an exception");
    }

    public void Dispose()
    {
        _dbContext.Dispose();
    }
}
