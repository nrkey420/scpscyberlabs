namespace CyberLabPlatform.Core.Models.DTOs;

public class PowerShellResult
{
    public bool Success { get; set; }
    public string Output { get; set; } = string.Empty;
    public List<string> Errors { get; set; } = new();
}
