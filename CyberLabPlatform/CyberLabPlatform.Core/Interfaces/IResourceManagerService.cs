using CyberLabPlatform.Core.Models.DTOs;

namespace CyberLabPlatform.Core.Interfaces;

public interface IResourceManagerService
{
    Task<ResourceUsageSummary> GetCurrentUsageAsync();
    Task<bool> CanDeployAsync(Guid templateId, int studentCount);
}
