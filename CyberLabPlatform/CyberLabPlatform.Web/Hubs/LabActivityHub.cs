using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace CyberLabPlatform.Web.Hubs;

[Authorize]
public class LabActivityHub(ILogger<LabActivityHub> logger) : Hub
{
    public async Task JoinSessionRoom(string sessionId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"session-{sessionId}");
        logger.LogInformation("Client {ConnectionId} joined session room {SessionId}", Context.ConnectionId, sessionId);

        await Clients.Group($"session-{sessionId}").SendAsync("StudentActivity", new
        {
            userId = Context.UserIdentifier,
            action = "joined",
            timestamp = DateTime.UtcNow
        });
    }

    public async Task LeaveSessionRoom(string sessionId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"session-{sessionId}");
        logger.LogInformation("Client {ConnectionId} left session room {SessionId}", Context.ConnectionId, sessionId);

        await Clients.Group($"session-{sessionId}").SendAsync("StudentActivity", new
        {
            userId = Context.UserIdentifier,
            action = "left",
            timestamp = DateTime.UtcNow
        });
    }

    public override async Task OnConnectedAsync()
    {
        logger.LogInformation("Client connected: {ConnectionId}, User: {UserId}", Context.ConnectionId, Context.UserIdentifier);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (exception != null)
            logger.LogWarning(exception, "Client disconnected with error: {ConnectionId}", Context.ConnectionId);
        else
            logger.LogInformation("Client disconnected: {ConnectionId}", Context.ConnectionId);

        await base.OnDisconnectedAsync(exception);
    }
}
