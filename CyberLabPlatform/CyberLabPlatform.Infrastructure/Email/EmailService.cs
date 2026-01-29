using System.Net;
using System.Net.Mail;
using System.Text;
using CyberLabPlatform.Core.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CyberLabPlatform.Infrastructure.Email;

public class EmailService : IEmailService, IDisposable
{
    private readonly ILogger<EmailService> _logger;
    private readonly SmtpClient _smtpClient;
    private readonly string _fromAddress;
    private readonly string _fromName;
    private bool _disposed;

    public EmailService(IConfiguration configuration, ILogger<EmailService> logger)
    {
        _logger = logger;

        var emailSection = configuration.GetSection("Email");
        var host = emailSection["SmtpHost"] ?? throw new InvalidOperationException("Email:SmtpHost is required.");
        var port = int.Parse(emailSection["SmtpPort"] ?? "587");
        var username = emailSection["Username"] ?? throw new InvalidOperationException("Email:Username is required.");
        var password = emailSection["Password"] ?? throw new InvalidOperationException("Email:Password is required.");
        _fromAddress = emailSection["FromAddress"] ?? username;
        _fromName = emailSection["FromName"] ?? "CyberLab Platform";

        _smtpClient = new SmtpClient(host, port)
        {
            Credentials = new NetworkCredential(username, password),
            EnableSsl = true
        };
    }

    public async Task SendLabDeployedNotificationAsync(string recipientEmail, string labName,
        string sessionId, DateTime endTime)
    {
        var subject = $"Lab Deployed: {labName}";
        var body = new StringBuilder();
        body.AppendLine($"<h2>Your lab environment is ready!</h2>");
        body.AppendLine($"<p><strong>Lab:</strong> {labName}</p>");
        body.AppendLine($"<p><strong>Session ID:</strong> {sessionId}</p>");
        body.AppendLine($"<p><strong>Available Until:</strong> {endTime:yyyy-MM-dd HH:mm} UTC</p>");
        body.AppendLine($"<p>Log in to the CyberLab Platform to access your lab environment.</p>");

        await SendEmailAsync(recipientEmail, subject, body.ToString());
        _logger.LogInformation("Sent lab deployed notification for session {SessionId} to {Email}",
            sessionId, recipientEmail);
    }

    public async Task SendSessionEndingNotificationAsync(string recipientEmail, string labName,
        int minutesRemaining)
    {
        var subject = $"Lab Session Ending Soon: {labName}";
        var body = new StringBuilder();
        body.AppendLine($"<h2>Your lab session is ending soon</h2>");
        body.AppendLine($"<p><strong>Lab:</strong> {labName}</p>");
        body.AppendLine($"<p><strong>Time Remaining:</strong> {minutesRemaining} minutes</p>");
        body.AppendLine($"<p>Please save your work. The lab environment will be automatically terminated when the session expires.</p>");

        await SendEmailAsync(recipientEmail, subject, body.ToString());
        _logger.LogInformation("Sent session ending notification ({Minutes}m remaining) for lab {Lab} to {Email}",
            minutesRemaining, labName, recipientEmail);
    }

    public async Task SendCredentialsAsync(string recipientEmail, string labName,
        Dictionary<string, (string username, string password)> vmCredentials)
    {
        var subject = $"Lab Credentials: {labName}";
        var body = new StringBuilder();
        body.AppendLine($"<h2>Your Lab Credentials</h2>");
        body.AppendLine($"<p><strong>Lab:</strong> {labName}</p>");
        body.AppendLine("<table border='1' cellpadding='8' cellspacing='0'>");
        body.AppendLine("<tr><th>VM</th><th>Username</th><th>Password</th></tr>");

        foreach (var (vmName, creds) in vmCredentials)
        {
            body.AppendLine($"<tr><td>{vmName}</td><td>{creds.username}</td><td>{creds.password}</td></tr>");
        }

        body.AppendLine("</table>");
        body.AppendLine("<p><em>Please store these credentials securely and do not share them.</em></p>");

        await SendEmailAsync(recipientEmail, subject, body.ToString());
        _logger.LogInformation("Sent credentials for lab {Lab} ({Count} VMs) to {Email}",
            labName, vmCredentials.Count, recipientEmail);
    }

    private async Task SendEmailAsync(string to, string subject, string htmlBody)
    {
        try
        {
            using var message = new MailMessage
            {
                From = new MailAddress(_fromAddress, _fromName),
                Subject = subject,
                Body = htmlBody,
                IsBodyHtml = true
            };
            message.To.Add(new MailAddress(to));

            await _smtpClient.SendMailAsync(message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {Recipient} with subject '{Subject}'", to, subject);
            throw;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _smtpClient.Dispose();
    }
}
