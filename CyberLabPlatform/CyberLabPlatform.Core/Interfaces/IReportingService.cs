using CyberLabPlatform.Core.Enums;

namespace CyberLabPlatform.Core.Interfaces;

public interface IReportingService
{
    Task<byte[]> GenerateSessionReportAsync(Guid sessionId, ReportFormat format);
    Task<byte[]> ExportActivityLogAsync(Guid sessionId);
}
