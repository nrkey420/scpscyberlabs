#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for windows-10-enterprise base image.

.DESCRIPTION
    Image Name    : windows-10-enterprise
    Purpose       : Windows 10 Enterprise workstation for SOC Analyst lab (Lab 3).
                    Victim workstation that generates realistic Windows event logs.
                    Monitored by Splunk; domain-joined at deploy time.
    Base OS       : Windows 10 Enterprise 21H2
    Lab           : Lab 3 — SOC Analyst / Blue Team
    Security Level: STANDARD (not intentionally vulnerable)
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

.NOTES
    Run as Administrator after OS installation and Hyper-V integration services.
    Domain join is NOT performed here — it is handled at deploy time via PowerShell Direct.
    Sysmon, Splunk UF, and audit policy are configured at image build time.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------
$labBuildDir = 'C:\LabBuild'
if (-not (Test-Path $labBuildDir)) {
    New-Item -ItemType Directory -Path $labBuildDir -Force | Out-Null
}
Start-Transcript -Path "$labBuildDir\build.log" -Append -Force

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SCPS CyberLab — Build-Windows10Enterprise.ps1" -ForegroundColor Cyan
Write-Host " Image  : windows-10-enterprise" -ForegroundColor Cyan
Write-Host " Lab    : Lab 3 — SOC Analyst" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function New-RandomPassword {
    param([int]$Length = 20)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?'
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    return (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
}

function Write-Status { param([string]$Message, [string]$Color = 'Green') Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color }
function Write-Warn   { param([string]$Message) Write-Status $Message 'Yellow' }
function Write-Err    { param([string]$Message) Write-Status $Message 'Red'    }

# ---------------------------------------------------------------------------
# Credentials file — restricted to Administrators
# ---------------------------------------------------------------------------
$credFile = "$labBuildDir\credentials.txt"
New-Item -ItemType File -Path $credFile -Force | Out-Null
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" | Out-Null

function Append-Credential { param([string]$Line) Add-Content -Path $credFile -Value $Line }

Append-Credential "============================================================"
Append-Credential " SCPS CyberLab — windows-10-enterprise credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: STANDARD"
Append-Credential "============================================================"
Append-Credential ""

# Generate passwords
$adminPass   = New-RandomPassword -Length 20
$analystPass = New-RandomPassword -Length 20

Append-Credential "[SECURE] Administrator : $adminPass"
Append-Credential "[SECURE] analyst       : $analystPass"
Append-Credential ""

# ---------------------------------------------------------------------------
# [1] Computer name
# ---------------------------------------------------------------------------
Write-Status "Setting computer name to SCPS-WS01..."
try {
    Rename-Computer -NewName 'SCPS-WS01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set."
} catch { Write-Warn "Rename failed (may already be set): $_" }

# ---------------------------------------------------------------------------
# [2] Set account passwords
# ---------------------------------------------------------------------------
Write-Status "Configuring Administrator account..."
try {
    net user Administrator $adminPass /active:yes 2>&1 | Out-Null
    Write-Status "Administrator password set."
} catch { Write-Warn "Administrator account error: $_" }

Write-Status "Creating analyst account..."
try {
    $existingAnalyst = Get-LocalUser -Name 'analyst' -ErrorAction SilentlyContinue
    if ($null -eq $existingAnalyst) {
        New-LocalUser -Name 'analyst' `
            -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force) `
            -FullName 'SOC Analyst' `
            -Description 'SOC Analyst workstation user' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Users' -Member 'analyst' -ErrorAction SilentlyContinue
    } else {
        Set-LocalUser -Name 'analyst' -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force)
    }
    Write-Status "analyst account configured."
} catch { Write-Warn "analyst account error: $_" }

# ---------------------------------------------------------------------------
# [3] Create temp directory for downloads
# ---------------------------------------------------------------------------
$tempDir = 'C:\Temp'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# [4] Install Sysmon with SwiftOnSecurity config
# ---------------------------------------------------------------------------
Write-Status "Installing Sysmon..."
try {
    $sysmonDir     = 'C:\Tools\Sysmon'
    $sysmonZip     = "$tempDir\Sysmon.zip"
    $sysmonConfig  = "$sysmonDir\sysmonconfig.xml"
    $sysmonExe     = "$sysmonDir\Sysmon64.exe"

    if (-not (Test-Path $sysmonDir)) { New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null }

    # --- Online path ---
    if (-not (Test-Path $sysmonExe)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' `
            -OutFile $sysmonZip -UseBasicParsing
        Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
        Write-Status "Sysmon downloaded and extracted."
    }

    # --- Offline fallback path: copy from Hyper-V integration share ---
    # If the above fails, mount the ISO and copy from D:\Tools\Sysmon64.exe
    # Uncomment below for offline builds:
    # Copy-Item -Path 'D:\Tools\Sysmon64.exe' -Destination $sysmonExe -Force

    if (-not (Test-Path $sysmonConfig)) {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml' `
            -OutFile $sysmonConfig -UseBasicParsing
        Write-Status "SwiftOnSecurity sysmon config downloaded."
    }

    # Install or update Sysmon
    $sysmonSvc = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($null -eq $sysmonSvc) {
        & $sysmonExe -accepteula -i $sysmonConfig 2>&1 | Out-Null
        Write-Status "Sysmon installed."
    } else {
        & $sysmonExe -c $sysmonConfig 2>&1 | Out-Null
        Write-Status "Sysmon config updated."
    }
} catch { Write-Warn "Sysmon install error: $_" }

# ---------------------------------------------------------------------------
# [5] Enhanced audit policy
# ---------------------------------------------------------------------------
Write-Status "Configuring enhanced audit policy..."
try {
    $auditCmds = @(
        'auditpol /set /subcategory:"Logon" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Logoff" /success:enable',
        'auditpol /set /subcategory:"Account Lockout" /failure:enable',
        'auditpol /set /subcategory:"Process Creation" /success:enable',
        'auditpol /set /subcategory:"Process Termination" /success:enable',
        'auditpol /set /subcategory:"Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Object Access" /success:enable /failure:enable',
        'auditpol /set /subcategory:"File System" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Privilege Use" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Authentication Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Special Logon" /success:enable',
        'auditpol /set /subcategory:"Other Logon/Logoff Events" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Network Policy Server" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Directory Service Changes" /success:enable',
        'auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable',
        'auditpol /set /subcategory:"IPsec Driver" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security System Extension" /success:enable',
        'auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable'
    )
    foreach ($cmd in $auditCmds) {
        Invoke-Expression $cmd 2>&1 | Out-Null
    }
    # Enable command line auditing in process creation events
    $procAuditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $procAuditPath)) { New-Item -Path $procAuditPath -Force | Out-Null }
    Set-ItemProperty -Path $procAuditPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord
    Write-Status "Enhanced audit policy configured."
} catch { Write-Warn "Audit policy error: $_" }

# ---------------------------------------------------------------------------
# [6] PowerShell Script Block Logging and Module Logging
# ---------------------------------------------------------------------------
Write-Status "Enabling PowerShell Script Block Logging and Module Logging..."
try {
    $psLogPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    if (-not (Test-Path $psLogPath)) { New-Item -Path $psLogPath -Force | Out-Null }
    Set-ItemProperty -Path $psLogPath -Name 'EnableScriptBlockLogging'         -Value 1 -Type DWord
    Set-ItemProperty -Path $psLogPath -Name 'EnableScriptBlockInvocationLogging'-Value 1 -Type DWord

    $modLogPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
    if (-not (Test-Path $modLogPath)) { New-Item -Path $modLogPath -Force | Out-Null }
    Set-ItemProperty -Path $modLogPath -Name 'EnableModuleLogging' -Value 1 -Type DWord

    $modNamesPath = "$modLogPath\ModuleNames"
    if (-not (Test-Path $modNamesPath)) { New-Item -Path $modNamesPath -Force | Out-Null }
    Set-ItemProperty -Path $modNamesPath -Name '*' -Value '*' -Type String

    $transcriptPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
    if (-not (Test-Path $transcriptPath)) { New-Item -Path $transcriptPath -Force | Out-Null }
    Set-ItemProperty -Path $transcriptPath -Name 'EnableTranscripting'    -Value 1 -Type DWord
    Set-ItemProperty -Path $transcriptPath -Name 'EnableInvocationHeader'  -Value 1 -Type DWord
    Set-ItemProperty -Path $transcriptPath -Name 'OutputDirectory'         -Value 'C:\PSTranscripts' -Type String
    if (-not (Test-Path 'C:\PSTranscripts')) { New-Item -ItemType Directory -Path 'C:\PSTranscripts' -Force | Out-Null }

    Write-Status "PowerShell Script Block and Module logging enabled."
} catch { Write-Warn "PowerShell logging config error: $_" }

# ---------------------------------------------------------------------------
# [7] Configure WinRM for management
# ---------------------------------------------------------------------------
Write-Status "Configuring WinRM..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    # Use HTTPS-only in the enterprise image
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
    Write-Status "WinRM configured (encrypted, no basic auth)."
} catch { Write-Warn "WinRM config error: $_" }

# ---------------------------------------------------------------------------
# [8] Enable RDP with NLA
# ---------------------------------------------------------------------------
Write-Status "Enabling RDP with NLA..."
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    # Require NLA
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 1 -Type DWord
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    Write-Status "RDP enabled with NLA."
} catch { Write-Warn "RDP setup error: $_" }

# ---------------------------------------------------------------------------
# [9] Install Splunk Universal Forwarder
# ---------------------------------------------------------------------------
Write-Status "Installing Splunk Universal Forwarder..."
# NOTE: Replace 10.CLASS_ID.0.51 with the actual Splunk indexer IP at deploy time.
# The splunkd process reads outputs.conf from $SPLUNK_HOME\etc\system\local\
$splunkIndexerIP   = '10.CLASS_ID.0.51'
$splunkIndexerPort = '9997'
$splunkInstallDir  = 'C:\Program Files\SplunkUniversalForwarder'
$splunkMsi         = "$tempDir\splunkforwarder.msi"
try {
    if (-not (Test-Path "$splunkInstallDir\bin\splunk.exe")) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        # Download latest Splunk UF 9.x MSI — update URL as needed
        Invoke-WebRequest `
            -Uri 'https://download.splunk.com/products/universalforwarder/releases/9.2.1/windows/splunkforwarder-9.2.1-78803f08aabb-x64-release.msi' `
            -OutFile $splunkMsi -UseBasicParsing
        $splunkPass = New-RandomPassword -Length 20
        Append-Credential "[SECURE] SplunkForwarder admin : $splunkPass"
        Start-Process msiexec.exe -Wait -ArgumentList @(
            '/i', $splunkMsi,
            'INSTALLDIR="C:\Program Files\SplunkUniversalForwarder"',
            "SPLUNKUSERNAME=admin",
            "SPLUNKPASSWORD=$splunkPass",
            "RECEIVING_INDEXER=${splunkIndexerIP}:${splunkIndexerPort}",
            'WINEVENTLOG_SEC_ENABLE=1',
            'WINEVENTLOG_SYS_ENABLE=1',
            'WINEVENTLOG_APP_ENABLE=1',
            'WINEVENTLOG_FWD_ENABLE=1',
            'WINEVENTLOG_SET_ENABLE=1',
            'AGREETOLICENSE=Yes',
            '/qn'
        )
        Write-Status "Splunk UF installed."
    } else {
        Write-Status "Splunk UF already installed."
    }

    # Write outputs.conf
    $splunkOutputsDir  = "$splunkInstallDir\etc\system\local"
    if (-not (Test-Path $splunkOutputsDir)) { New-Item -ItemType Directory -Path $splunkOutputsDir -Force | Out-Null }
    Set-Content -Path "$splunkOutputsDir\outputs.conf" -Value @"
[tcpout]
defaultGroup = scps_indexers

[tcpout:scps_indexers]
server = ${splunkIndexerIP}:${splunkIndexerPort}
compressed = true

[tcpout-server://${splunkIndexerIP}:${splunkIndexerPort}]
"@

    # Write inputs.conf — collect Windows Event Logs and Sysmon
    Set-Content -Path "$splunkOutputsDir\inputs.conf" -Value @"
[WinEventLog://Application]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false

[WinEventLog://Security]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false

[WinEventLog://System]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = true

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false
"@

    Start-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue
    Write-Status "Splunk UF configured (→ $splunkIndexerIP:$splunkIndexerPort)."
} catch { Write-Warn "Splunk UF install/config error: $_" }

# ---------------------------------------------------------------------------
# [10] Windows Firewall — allow RDP, WinRM, Splunk outbound
# ---------------------------------------------------------------------------
Write-Status "Configuring Windows Firewall rules..."
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    # Allow RDP inbound
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    # Allow WinRM inbound (HTTPS only)
    New-NetFirewallRule -DisplayName 'WinRM-HTTPS-In' -Direction Inbound `
        -Protocol TCP -LocalPort 5986 -Action Allow -ErrorAction SilentlyContinue
    # Allow Splunk forwarder outbound
    New-NetFirewallRule -DisplayName 'Splunk-UF-Out' -Direction Outbound `
        -Protocol TCP -RemotePort 9997 -RemoteAddress $splunkIndexerIP `
        -Action Allow -ErrorAction SilentlyContinue
    Write-Status "Firewall rules configured."
} catch { Write-Warn "Firewall rule error: $_" }

# ---------------------------------------------------------------------------
# [11] Install Chocolatey + tools
# ---------------------------------------------------------------------------
Write-Status "Installing Chocolatey and tools..."
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    choco install notepadplusplus 7zip -y --no-progress 2>&1 | Out-Null
    Write-Status "Tools installed."
} catch { Write-Warn "Chocolatey/tools install error: $_" }

# ---------------------------------------------------------------------------
# [12] Windows Event Forwarding — WEC subscription stub
# NOTE: Full WEC subscription requires the WEC server to exist at deploy time.
# This configures the WEF client side so the workstation is ready to forward.
# ---------------------------------------------------------------------------
Write-Status "Configuring WEF client (Windows Event Forwarding)..."
try {
    # Enable the Windows Remote Management service for WEF
    Set-Service -Name 'wecsvc' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'wecsvc' -ErrorAction SilentlyContinue

    # Configure the WEF subscription URL — replace with WEC server at deploy time
    # winrm quickconfig -q
    # wecutil qc /q
    # The actual subscription XML is pushed from the WEC server via GPO at domain join
    Write-Status "WEF client (wecsvc) enabled — subscriptions applied at domain join via GPO."
} catch { Write-Warn "WEF client config error: $_" }

# ---------------------------------------------------------------------------
# [13] Simulate realistic event log entries via self-deleting scheduled tasks
# ---------------------------------------------------------------------------
Write-Status "Creating realistic event log simulation tasks..."
try {
    # Simulate successful logon (event 4624) and failed logon (event 4625) using
    # net use with bad credentials — generates realistic Security log entries.
    $simulateScript = @'
# Simulate logon events for SOC analyst log analysis practice
# Successful logons — just open a local net use
net use \\localhost\IPC$ /user:analyst "" 2>&1 | Out-Null
net use \\localhost\IPC$ /delete 2>&1 | Out-Null
# Simulate 3 failed logon attempts with wrong password
net use \\localhost\IPC$ /user:fakeuser WrongPassword1 2>&1 | Out-Null
net use \\localhost\IPC$ /user:fakeuser WrongPassword2 2>&1 | Out-Null
net use \\localhost\IPC$ /user:administrator BadPass! 2>&1 | Out-Null
# Remove this scheduled task after running
schtasks /delete /tn "SimulateLogons" /f 2>&1 | Out-Null
'@

    $simScriptPath = "$tempDir\SimulateLogons.ps1"
    Set-Content -Path $simScriptPath -Value $simulateScript

    $existingSim = Get-ScheduledTask -TaskName 'SimulateLogons' -ErrorAction SilentlyContinue
    if ($null -ne $existingSim) { Unregister-ScheduledTask -TaskName 'SimulateLogons' -Confirm:$false }

    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NonInteractive -WindowStyle Hidden -File `"$simScriptPath`""
    # Run 5 minutes after next boot
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT5M'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 'PT10M'
    Register-ScheduledTask -TaskName 'SimulateLogons' `
        -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Status "LogonSimulation task registered (runs once on next boot, self-deletes)."
} catch { Write-Warn "Log simulation task error: $_" }

# ---------------------------------------------------------------------------
# [14] Finalize credentials file
# ---------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== CONFIGURATION SUMMARY ==="
Append-Credential "- Sysmon : INSTALLED (SwiftOnSecurity config)"
Append-Credential "- Audit  : ENHANCED (full subcategory coverage)"
Append-Credential "- PSLog  : Script block + module logging ENABLED"
Append-Credential "- WinRM  : ENABLED (encrypted, no basic auth)"
Append-Credential "- RDP    : ENABLED with NLA"
Append-Credential "- Splunk : UF → ${splunkIndexerIP}:${splunkIndexerPort}"
Append-Credential "- Domain : JOIN deferred to deploy time (PowerShell Direct)"
Write-Status "credentials.txt written."

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Build-Windows10Enterprise.ps1 configuration complete." -ForegroundColor Green
Write-Host " Running sysprep to generalize image for deployment..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

# ---------------------------------------------------------------------------
# [15] Sysprep — generalize for image deployment
# ---------------------------------------------------------------------------
Write-Status "Running sysprep to generalize image..."
try {
    $sysprepExe = 'C:\Windows\System32\Sysprep\sysprep.exe'
    # Clear event logs before sysprep
    Clear-EventLog -LogName Application -ErrorAction SilentlyContinue
    Clear-EventLog -LogName System      -ErrorAction SilentlyContinue
    Clear-EventLog -LogName Security    -ErrorAction SilentlyContinue
    wevtutil cl 'Microsoft-Windows-PowerShell/Operational' 2>&1 | Out-Null
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" `
        -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue

    # Zero free space
    Write-Status "Zeroing free disk space..."
    cipher /w:C:\ 2>&1 | Out-Null

    Stop-Transcript
    # Sysprep with OOBE and shutdown — triggers generalize
    Start-Process -FilePath $sysprepExe `
        -ArgumentList '/generalize', '/oobe', '/shutdown', '/quiet' `
        -Wait -NoNewWindow
} catch {
    Write-Warn "Sysprep failed: $_ — falling back to shutdown."
    Stop-Transcript
    Stop-Computer -Force
}
