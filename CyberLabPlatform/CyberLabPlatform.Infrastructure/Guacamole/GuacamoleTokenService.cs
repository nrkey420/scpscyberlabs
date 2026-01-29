using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CyberLabPlatform.Core.Interfaces;
using Jose;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CyberLabPlatform.Infrastructure.Guacamole;

public class GuacamoleTokenService : IGuacamoleTokenService
{
    private readonly ILogger<GuacamoleTokenService> _logger;
    private readonly string _baseUrl;
    private readonly byte[] _secretKey;
    private readonly byte[] _aesKey;

    public GuacamoleTokenService(IConfiguration configuration, ILogger<GuacamoleTokenService> logger)
    {
        _logger = logger;
        _baseUrl = configuration["Guacamole:BaseUrl"]
            ?? throw new InvalidOperationException("Guacamole:BaseUrl configuration is required.");
        var secret = configuration["Guacamole:SecretKey"]
            ?? throw new InvalidOperationException("Guacamole:SecretKey configuration is required.");
        _secretKey = Encoding.UTF8.GetBytes(secret);

        var aesKeyString = configuration["Guacamole:AesKey"] ?? secret;
        _aesKey = DeriveAesKey(aesKeyString);
    }

    public string GenerateConsoleUrl(string userId, string vmIpAddress, string protocol, int port,
        string username, string password, TimeSpan expiration)
    {
        var now = DateTimeOffset.UtcNow;
        var payload = new Dictionary<string, object>
        {
            ["sub"] = userId,
            ["iat"] = now.ToUnixTimeSeconds(),
            ["exp"] = now.Add(expiration).ToUnixTimeSeconds(),
            ["GUAC_ID"] = $"{userId}-{vmIpAddress}-{now.ToUnixTimeMilliseconds()}",
            ["guac.hostname"] = vmIpAddress,
            ["guac.port"] = port.ToString(),
            ["guac.protocol"] = protocol,
            ["guac.username"] = username,
            ["guac.password"] = password,
            ["guac.ignore-cert"] = "true",
            ["guac.enable-wallpaper"] = "false",
            ["guac.enable-font-smoothing"] = "true",
            ["guac.resize-method"] = "display-update"
        };

        var token = JWT.Encode(payload, _secretKey, JwsAlgorithm.HS256);

        var url = $"{_baseUrl.TrimEnd('/')}/#/client/{token}";

        _logger.LogInformation(
            "Generated Guacamole console URL for user {UserId} connecting to {VmIp}:{Port} via {Protocol}",
            userId, vmIpAddress, port, protocol);

        return url;
    }

    public string DecryptPassword(string encryptedPassword)
    {
        try
        {
            var cipherBytes = Convert.FromBase64String(encryptedPassword);

            using var aes = Aes.Create();
            aes.Key = _aesKey;

            // First 16 bytes are the IV
            var iv = new byte[16];
            Buffer.BlockCopy(cipherBytes, 0, iv, 0, 16);
            aes.IV = iv;

            using var decryptor = aes.CreateDecryptor();
            var decrypted = decryptor.TransformFinalBlock(cipherBytes, 16, cipherBytes.Length - 16);
            return Encoding.UTF8.GetString(decrypted);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to decrypt password.");
            throw new InvalidOperationException("Password decryption failed.", ex);
        }
    }

    private static byte[] DeriveAesKey(string keyString)
    {
        var keyBytes = Encoding.UTF8.GetBytes(keyString);
        using var sha256 = SHA256.Create();
        return sha256.ComputeHash(keyBytes);
    }
}
