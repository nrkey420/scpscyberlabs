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

public class ResourceManagerServiceTests : IDisposable
{
    private readonly CyberLabDbContext _dbContext;
    private readonly Mock<IPowerShellExecutor> _powerShellMock;
    private readonly Mock<ILogger<ResourceManagerService>> _loggerMock;
    private readonly Mock<IConfiguration> _configMock;
    private readonly ResourceManagerService _sut;

    public ResourceManagerServiceTests()
    {
        var options = new DbContextOptionsBuilder<CyberLabDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        _dbContext = new CyberLabDbContext(options);
        _powerShellMock = new Mock<IPowerShellExecutor>();
        _loggerMock = new Mock<ILogger<ResourceManagerService>>();
        _configMock = new Mock<IConfiguration>();

        // Default config: 128 GB RAM, 64 vCPU total capacity
        _configMock.Setup(c => c["Resources:TotalRamGb"]).Returns("128");
        _configMock.Setup(c => c["Resources:TotalVcpu"]).Returns("64");
        _configMock.Setup(c => c["Resources:OverheadReservationPercent"]).Returns("10");

        _sut = new ResourceManagerService(_dbContext, _powerShellMock.Object, _configMock.Object, _loggerMock.Object);
    }

    private LabTemplate SeedTemplate(string vmDefinitions)
    {
        var template = new LabTemplate
        {
            Id = Guid.NewGuid(),
            Name = "Resource Test Lab",
            Description = "Lab for resource testing",
            Version = "1.0",
            GitCommitHash = "def456",
            DifficultyLevel = DifficultyLevel.Beginner,
            EstimatedDurationMinutes = 60,
            VmDefinitions = vmDefinitions,
            NetworkTopology = "{}",
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

    private void SeedRunningVMs(int count, int ramGbPerVm = 4, int vcpuPerVm = 2)
    {
        var template = SeedTemplate("{\"vms\":[]}");
        var session = new LabSession
        {
            Id = Guid.NewGuid(),
            TemplateId = template.Id,
            InstructorId = "instructor-1",
            ClassName = "Test Class",
            StartTime = DateTime.UtcNow,
            ScheduledEndTime = DateTime.UtcNow.AddHours(2),
            Status = LabStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
        _dbContext.LabSessions.Add(session);

        for (int i = 0; i < count; i++)
        {
            _dbContext.VmInstances.Add(new VMInstance
            {
                Id = Guid.NewGuid(),
                SessionId = session.Id,
                StudentId = $"student-{i}",
                VmName = $"vm-{i}",
                HyperVVMId = Guid.NewGuid(),
                IpAddress = $"10.0.0.{i + 10}",
                Credentials = "{}",
                VmType = $"ram:{ramGbPerVm},vcpu:{vcpuPerVm}",
                Status = VMStatus.Running,
                CreatedAt = DateTime.UtcNow
            });
        }
        _dbContext.SaveChanges();
    }

    [Fact]
    public async Task CanDeploy_SufficientResources_ReturnsTrue()
    {
        // Arrange
        // Template requiring 2 VMs, each 4GB RAM, 2 vCPU per student
        var template = SeedTemplate("{\"vms\":[{\"ram_gb\":4,\"vcpu\":2},{\"ram_gb\":4,\"vcpu\":2}]}");
        int studentCount = 5; // 5 students x 2 VMs x 4GB = 40GB (well within 128GB)

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "Available",
                Data = new Dictionary<string, object?>
                {
                    ["UsedRamGb"] = 20,
                    ["UsedVcpu"] = 10
                }
            });

        // Act
        var result = await _sut.CanDeployAsync(template.Id, studentCount);

        // Assert
        result.Should().BeTrue();
    }

    [Fact]
    public async Task CanDeploy_InsufficientRAM_ReturnsFalse()
    {
        // Arrange
        // Template requiring 2 VMs, each 8GB RAM per student
        var template = SeedTemplate("{\"vms\":[{\"ram_gb\":8,\"vcpu\":2},{\"ram_gb\":8,\"vcpu\":2}]}");
        int studentCount = 10; // 10 students x 2 VMs x 8GB = 160GB (exceeds 128GB)

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "Available",
                Data = new Dictionary<string, object?>
                {
                    ["UsedRamGb"] = 10,
                    ["UsedVcpu"] = 5
                }
            });

        // Act
        var result = await _sut.CanDeployAsync(template.Id, studentCount);

        // Assert
        result.Should().BeFalse();
    }

    [Fact]
    public async Task CanDeploy_InsufficientCPU_ReturnsFalse()
    {
        // Arrange
        // Template requiring 1 VM with 8 vCPU per student
        var template = SeedTemplate("{\"vms\":[{\"ram_gb\":2,\"vcpu\":8}]}");
        int studentCount = 10; // 10 students x 8 vCPU = 80 vCPU (exceeds 64 vCPU)

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "Available",
                Data = new Dictionary<string, object?>
                {
                    ["UsedRamGb"] = 0,
                    ["UsedVcpu"] = 0
                }
            });

        // Act
        var result = await _sut.CanDeployAsync(template.Id, studentCount);

        // Assert
        result.Should().BeFalse();
    }

    [Fact]
    public async Task CanDeploy_WithOverheadReservation_CalculatesCorrectly()
    {
        // Arrange
        // With 10% overhead reservation, effective capacity is 115.2 GB RAM and 57.6 vCPU
        // Template: 2 VMs x 4GB = 8GB per student
        var template = SeedTemplate("{\"vms\":[{\"ram_gb\":4,\"vcpu\":2},{\"ram_gb\":4,\"vcpu\":2}]}");
        int studentCount = 14; // 14 students x 8GB = 112GB; within 115.2 effective capacity

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "Available",
                Data = new Dictionary<string, object?>
                {
                    ["UsedRamGb"] = 0,
                    ["UsedVcpu"] = 0
                }
            });

        // Act
        var result = await _sut.CanDeployAsync(template.Id, studentCount);

        // Assert
        // 14 x 8GB = 112GB. Effective capacity = 128 * 0.9 = 115.2GB. Should fit.
        result.Should().BeTrue();
    }

    [Fact]
    public async Task GetCurrentUsage_ReturnsAccurateValues()
    {
        // Arrange
        SeedRunningVMs(count: 5, ramGbPerVm: 4, vcpuPerVm: 2);

        _powerShellMock
            .Setup(ps => ps.ExecuteAsync(It.IsAny<string>(), It.IsAny<Dictionary<string, object?>>()))
            .ReturnsAsync(new PowerShellResult
            {
                Success = true,
                Output = "Usage retrieved",
                Data = new Dictionary<string, object?>
                {
                    ["UsedRamGb"] = 20,
                    ["UsedVcpu"] = 10
                }
            });

        // Act
        var usage = await _sut.GetCurrentUsageAsync();

        // Assert
        usage.Should().NotBeNull();
        usage.TotalRamGb.Should().Be(128);
        usage.TotalVcpu.Should().Be(64);
        usage.UsedRamGb.Should().Be(20);
        usage.UsedVcpu.Should().Be(10);
        usage.RunningVms.Should().Be(5);
        usage.ActiveSessions.Should().BeGreaterOrEqualTo(1);
    }

    public void Dispose()
    {
        _dbContext.Dispose();
    }
}
