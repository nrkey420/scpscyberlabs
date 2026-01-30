namespace CyberLabPlatform.Core.Interfaces;

public interface IGuacamoleTokenService
{
    string GenerateConsoleUrl(string userId, string vmIpAddress, string protocol, int port,
        string username, string password, TimeSpan expiration);
}
