namespace CyberLabPlatform.Core.Interfaces;

public class PowerShellResult
{
    public bool Success { get; set; }
    public string Output { get; set; } = string.Empty;
    public string Error { get; set; } = string.Empty;
    public Dictionary<string, object?> Data { get; set; } = new();
}

public interface IPowerShellExecutor
{
    Task<PowerShellResult> ExecuteAsync(string scriptName, Dictionary<string, object?> parameters);
}
