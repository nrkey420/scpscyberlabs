namespace CyberLabPlatform.Core.Models;

public class StudentLabAssignment
{
    public Guid Id { get; set; }
    public Guid SessionId { get; set; }
    public LabSession Session { get; set; } = null!;
    public string StudentId { get; set; } = string.Empty;
    public string StudentEmail { get; set; } = string.Empty;
    public string StudentName { get; set; } = string.Empty;
    public DateTime EnrolledAt { get; set; }
    public DateTime? FirstAccess { get; set; }
    public int TotalConnectionTimeSeconds { get; set; } = 0;
}
