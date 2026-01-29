namespace CyberLabPlatform.Core.Interfaces;

public interface IEmailService
{
    Task SendLabDeployedNotificationAsync(string recipientEmail, string labName, string sessionId, DateTime endTime);
    Task SendSessionEndingNotificationAsync(string recipientEmail, string labName, int minutesRemaining);
    Task SendCredentialsAsync(string recipientEmail, string labName, Dictionary<string, (string username, string password)> vmCredentials);
}
