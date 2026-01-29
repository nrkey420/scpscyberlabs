using CyberLabPlatform.Core.Interfaces;
using Microsoft.Graph;
using Microsoft.Graph.Models;

namespace CyberLabPlatform.Web.Services;

public class EntraIdService(
    GraphServiceClient graphClient,
    ILogger<EntraIdService> logger) : IEntraIdService
{
    public async Task<EntraUser?> GetUserByIdAsync(string userId)
    {
        try
        {
            var user = await graphClient.Users[userId].GetAsync(config =>
            {
                config.QueryParameters.Select = ["id", "displayName", "mail", "userPrincipalName"];
            });

            if (user == null) return null;

            return new EntraUser
            {
                Id = user.Id ?? string.Empty,
                DisplayName = user.DisplayName ?? string.Empty,
                Email = user.Mail ?? user.UserPrincipalName ?? string.Empty
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching user {UserId} from Entra ID", userId);
            return null;
        }
    }

    public async Task<List<EntraUser>> GetGroupMembersAsync(string groupId)
    {
        try
        {
            var members = await graphClient.Groups[groupId].Members.GetAsync(config =>
            {
                config.QueryParameters.Select = ["id", "displayName", "mail", "userPrincipalName"];
            });

            var users = new List<EntraUser>();

            if (members?.Value != null)
            {
                foreach (var member in members.Value.OfType<User>())
                {
                    users.Add(new EntraUser
                    {
                        Id = member.Id ?? string.Empty,
                        DisplayName = member.DisplayName ?? string.Empty,
                        Email = member.Mail ?? member.UserPrincipalName ?? string.Empty
                    });
                }
            }

            return users;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching group members for group {GroupId}", groupId);
            return [];
        }
    }

    public async Task<List<string>> GetUserRolesAsync(string userId)
    {
        try
        {
            var appRoleAssignments = await graphClient.Users[userId].AppRoleAssignments.GetAsync();

            var roles = new List<string>();
            if (appRoleAssignments?.Value != null)
            {
                roles.AddRange(appRoleAssignments.Value
                    .Where(a => !string.IsNullOrEmpty(a.ResourceDisplayName))
                    .Select(a => a.ResourceDisplayName!));
            }

            return roles;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error fetching roles for user {UserId}", userId);
            return [];
        }
    }
}
