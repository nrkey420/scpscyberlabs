using System.Management.Automation;
using System.Management.Automation.Runspaces;
using CyberLabPlatform.Core.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CyberLabPlatform.Infrastructure.PowerShell;

public class PowerShellExecutor : IPowerShellExecutor, IDisposable
{
    private readonly ILogger<PowerShellExecutor> _logger;
    private readonly string _modulePath;
    private readonly SemaphoreSlim _semaphore = new(1, 1);
    private Runspace? _runspace;
    private bool _disposed;

    public PowerShellExecutor(IConfiguration configuration, ILogger<PowerShellExecutor> logger)
    {
        _logger = logger;
        _modulePath = configuration["PowerShell:ModulePath"] ?? string.Empty;
        if (string.IsNullOrEmpty(_modulePath))
            _logger.LogWarning("PowerShell:ModulePath is not configured. PowerShell execution will be unavailable.");
    }

    public async Task<PowerShellResult> ExecuteAsync(string scriptName, Dictionary<string, object?> parameters)
    {
        if (string.IsNullOrEmpty(_modulePath))
        {
            _logger.LogError("Cannot execute PowerShell command '{Command}': PowerShell:ModulePath is not configured.", scriptName);
            return new PowerShellResult { Success = false, Error = "PowerShell is not configured on this server. Set PowerShell:ModulePath in appsettings." };
        }

        await _semaphore.WaitAsync();
        try
        {
            EnsureRunspace();

            using var ps = System.Management.Automation.PowerShell.Create();
            ps.Runspace = _runspace;
            ps.AddCommand(scriptName);

            foreach (var kvp in parameters)
            {
                ps.AddParameter(kvp.Key, kvp.Value);
            }

            _logger.LogInformation("Executing PowerShell command: {Command}", scriptName);

            var outputCollection = await Task.Run(() => ps.Invoke());

            var result = new PowerShellResult
            {
                Success = !ps.HadErrors,
                Output = string.Join(Environment.NewLine,
                    outputCollection.Select(o => o?.ToString() ?? string.Empty))
            };

            if (ps.HadErrors)
            {
                result.Error = string.Join("; ", ps.Streams.Error.Select(e => e.ToString()));
                _logger.LogError("PowerShell command '{Command}' completed with errors: {Errors}",
                    scriptName, result.Error);
            }
            else
            {
                _logger.LogInformation("PowerShell command '{Command}' completed successfully with {Count} output objects.",
                    scriptName, outputCollection.Count);
            }

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to execute PowerShell command: {Command}", scriptName);
            return new PowerShellResult
            {
                Success = false,
                Error = ex.Message
            };
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private void EnsureRunspace()
    {
        if (_runspace is { RunspaceStateInfo.State: RunspaceState.Opened })
            return;

        _runspace?.Dispose();

        var initialState = InitialSessionState.CreateDefault();
        initialState.ImportPSModule(new[] { _modulePath });

        _runspace = RunspaceFactory.CreateRunspace(initialState);
        _runspace.Open();

        _logger.LogInformation("PowerShell runspace opened with module: {ModulePath}", _modulePath);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _runspace?.Dispose();
        _semaphore.Dispose();

        _logger.LogInformation("PowerShell executor disposed.");
    }
}
