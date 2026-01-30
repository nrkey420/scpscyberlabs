namespace CyberLabPlatform.Core.Interfaces;

public class EntraUser
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public List<string> Roles { get; set; } = new();
}

public interface IEntraIdService
{
    Task<EntraUser?> GetUserByIdAsync(string userId);
    Task<List<EntraUser>> GetGroupMembersAsync(string groupId);
    Task<List<string>> GetUserRolesAsync(string userId);
}
