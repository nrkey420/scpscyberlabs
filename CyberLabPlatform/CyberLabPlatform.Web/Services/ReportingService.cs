using System.Globalization;
using System.Text;
using CsvHelper;
using CsvHelper.Configuration;
using CyberLabPlatform.Core.Enums;
using CyberLabPlatform.Core.Interfaces;
using CyberLabPlatform.Web.Data;
using Microsoft.EntityFrameworkCore;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace CyberLabPlatform.Web.Services;

public class ReportingService(
    CyberLabDbContext context,
    ILogger<ReportingService> logger) : IReportingService
{
    public async Task<byte[]> GenerateSessionReportAsync(Guid sessionId, ReportFormat format)
    {
        logger.LogInformation("Generating {Format} report for session {SessionId}", format, sessionId);

        try
        {
            var session = await context.LabSessions
                .Include(s => s.Template)
                .Include(s => s.VmInstances)
                .Include(s => s.StudentAssignments)
                .FirstOrDefaultAsync(s => s.Id == sessionId)
                ?? throw new InvalidOperationException($"Session {sessionId} not found");

            var progressRecords = await context.StudentProgress
                .Include(p => p.Objective)
                .Where(p => p.SessionId == sessionId && p.PointsAwarded > 0)
                .ToListAsync();

            return format switch
            {
                ReportFormat.PDF => GeneratePdfReport(session, progressRecords),
                ReportFormat.CSV => GenerateCsvReport(session, progressRecords),
                _ => throw new ArgumentOutOfRangeException(nameof(format))
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating report for session {SessionId}", sessionId);
            throw;
        }
    }

    public async Task<byte[]> ExportActivityLogAsync(Guid sessionId)
    {
        logger.LogInformation("Exporting activity log for session {SessionId}", sessionId);

        try
        {
            var logs = await context.ActivityLogs
                .Where(l => l.SessionId == sessionId)
                .OrderBy(l => l.Timestamp)
                .ToListAsync();

            await using var memoryStream = new MemoryStream();
            await using var writer = new StreamWriter(memoryStream, Encoding.UTF8);
            await using var csv = new CsvWriter(writer, new CsvConfiguration(CultureInfo.InvariantCulture));

            csv.WriteField("Timestamp");
            csv.WriteField("StudentId");
            csv.WriteField("EventType");
            csv.WriteField("EventDetails");
            csv.WriteField("IpAddress");
            await csv.NextRecordAsync();

            foreach (var log in logs)
            {
                csv.WriteField(log.Timestamp.ToString("o"));
                csv.WriteField(log.StudentId);
                csv.WriteField(log.EventType);
                csv.WriteField(log.EventDetails);
                csv.WriteField(log.IpAddress);
                await csv.NextRecordAsync();
            }

            await writer.FlushAsync();
            return memoryStream.ToArray();
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting activity log for session {SessionId}", sessionId);
            throw;
        }
    }

    private static byte[] GeneratePdfReport(
        Core.Models.LabSession session,
        List<Core.Models.StudentProgress> progressRecords)
    {
        QuestPDF.Settings.License = LicenseType.Community;

        var document = Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(40);
                page.DefaultTextStyle(x => x.FontSize(10));

                page.Header().Column(col =>
                {
                    col.Item().Text("CyberLab Session Report").Bold().FontSize(18);
                    col.Item().Text($"Session: {session.ClassName}").FontSize(12);
                    col.Item().Text($"Template: {session.Template.Name}").FontSize(10);
                    col.Item().Text($"Date: {session.StartTime:yyyy-MM-dd HH:mm} - {(session.ActualEndTime?.ToString("HH:mm") ?? "Active")}").FontSize(10);
                    col.Item().PaddingBottom(10).LineHorizontal(1);
                });

                page.Content().Column(col =>
                {
                    // Session Summary
                    col.Item().PaddingBottom(10).Text("Session Summary").Bold().FontSize(14);
                    col.Item().Text($"Status: {session.Status}");
                    col.Item().Text($"Total Students: {session.StudentAssignments.Count}");
                    col.Item().Text($"Total VMs: {session.VmInstances.Count}");
                    col.Item().PaddingBottom(15);

                    // Per-Student Progress
                    col.Item().PaddingBottom(10).Text("Student Progress").Bold().FontSize(14);

                    foreach (var assignment in session.StudentAssignments)
                    {
                        var studentProgress = progressRecords
                            .Where(p => p.StudentId == assignment.StudentId)
                            .ToList();

                        col.Item().PaddingBottom(5).Text($"{assignment.StudentName} ({assignment.StudentEmail})").Bold();
                        col.Item().Text($"  Enrolled: {assignment.EnrolledAt:yyyy-MM-dd HH:mm}");
                        col.Item().Text($"  First Access: {assignment.FirstAccess?.ToString("yyyy-MM-dd HH:mm") ?? "N/A"}");
                        col.Item().Text($"  Total Points: {studentProgress.Sum(p => p.PointsAwarded)}");
                        col.Item().Text($"  Objectives Completed: {studentProgress.Count}");

                        foreach (var progress in studentProgress.OrderBy(p => p.CompletedAt))
                        {
                            col.Item().Text($"    - {progress.Objective.Title}: {progress.PointsAwarded} pts ({progress.CompletedAt:HH:mm})");
                        }

                        col.Item().PaddingBottom(10);
                    }

                    // VM Summary
                    col.Item().PaddingBottom(10).Text("VM Instances").Bold().FontSize(14);

                    foreach (var vm in session.VmInstances)
                    {
                        col.Item().Text($"  {vm.VmName} - Status: {vm.Status}, Type: {vm.VmType}, IP: {vm.IpAddress}");
                    }
                });

                page.Footer().AlignCenter().Text(x =>
                {
                    x.Span("Generated by CyberLab Platform on ");
                    x.Span($"{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
                });
            });
        });

        return document.GeneratePdf();
    }

    private static byte[] GenerateCsvReport(
        Core.Models.LabSession session,
        List<Core.Models.StudentProgress> progressRecords)
    {
        using var memoryStream = new MemoryStream();
        using var writer = new StreamWriter(memoryStream, Encoding.UTF8);
        using var csv = new CsvWriter(writer, new CsvConfiguration(CultureInfo.InvariantCulture));

        // Header
        csv.WriteField("StudentId");
        csv.WriteField("StudentName");
        csv.WriteField("StudentEmail");
        csv.WriteField("EnrolledAt");
        csv.WriteField("FirstAccess");
        csv.WriteField("TotalConnectionTimeSeconds");
        csv.WriteField("ObjectivesCompleted");
        csv.WriteField("TotalPoints");
        csv.WriteField("ObjectiveTitle");
        csv.WriteField("ObjectivePoints");
        csv.WriteField("CompletedAt");
        csv.NextRecord();

        foreach (var assignment in session.StudentAssignments)
        {
            var studentProgress = progressRecords
                .Where(p => p.StudentId == assignment.StudentId)
                .OrderBy(p => p.CompletedAt)
                .ToList();

            if (studentProgress.Count == 0)
            {
                csv.WriteField(assignment.StudentId);
                csv.WriteField(assignment.StudentName);
                csv.WriteField(assignment.StudentEmail);
                csv.WriteField(assignment.EnrolledAt.ToString("o"));
                csv.WriteField(assignment.FirstAccess?.ToString("o") ?? "");
                csv.WriteField(assignment.TotalConnectionTimeSeconds);
                csv.WriteField(0);
                csv.WriteField(0);
                csv.WriteField("");
                csv.WriteField("");
                csv.WriteField("");
                csv.NextRecord();
            }
            else
            {
                foreach (var progress in studentProgress)
                {
                    csv.WriteField(assignment.StudentId);
                    csv.WriteField(assignment.StudentName);
                    csv.WriteField(assignment.StudentEmail);
                    csv.WriteField(assignment.EnrolledAt.ToString("o"));
                    csv.WriteField(assignment.FirstAccess?.ToString("o") ?? "");
                    csv.WriteField(assignment.TotalConnectionTimeSeconds);
                    csv.WriteField(studentProgress.Count);
                    csv.WriteField(studentProgress.Sum(p => p.PointsAwarded));
                    csv.WriteField(progress.Objective.Title);
                    csv.WriteField(progress.PointsAwarded);
                    csv.WriteField(progress.CompletedAt.ToString("o"));
                    csv.NextRecord();
                }
            }
        }

        writer.Flush();
        return memoryStream.ToArray();
    }
}
