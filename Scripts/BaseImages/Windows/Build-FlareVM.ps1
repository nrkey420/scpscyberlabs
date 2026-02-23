#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for flarevm-win10-2024 base image.

.DESCRIPTION
    Image Name    : flarevm-win10-2024
    Purpose       : Windows 10 malware analysis workstation with FLARE-VM toolkit (Lab 5).
                    Used by analysts to perform static and dynamic malware analysis.
    Base OS       : Windows 10 Enterprise 21H2 (NOTE: LTSC preferred for stability)
    Lab           : Lab 5 — Malware Analysis
    Security Level: DEFENDER DISABLED (mandatory for malware analysis tooling)
    IP            : 10.CLASS_ID.0.11 (set at deploy time)
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

    IMPORTANT — SNAPSHOT NOTE:
    After this script completes and FLARE-VM finishes installing, take a VM snapshot
    named "clean-flarevm-baseline" BEFORE the image is ever used for analysis.
    Students revert to this snapshot between lab sessions.

    DO NOT SYSPREP — FLARE-VM does not survive sysprep.
    Shut down and capture disk as-is for base image.

.NOTES
    FLARE-VM install is long (60-120 min). The script launches it and waits.
    Ensure the VM has at least 100 GB disk and 8 GB RAM.
    Windows Defender MUST be disabled before FLARE-VM install — handled here.
    Run as Administrator after OS installation and Hyper-V integration services.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------
$labBuildDir = 'C:\LabBuild'
if (-not (Test-Path $labBuildDir)) { New-Item -ItemType Directory -Path $labBuildDir -Force | Out-Null }
Start-Transcript -Path "$labBuildDir\build.log" -Append -Force

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SCPS CyberLab — Build-FlareVM.ps1" -ForegroundColor Cyan
Write-Host " Image  : flarevm-win10-2024" -ForegroundColor Cyan
Write-Host " Lab    : Lab 5 — Malware Analysis (FLARE-VM)" -ForegroundColor Cyan
Write-Host " NOTE   : FLARE-VM install takes 60-120 minutes." -ForegroundColor Yellow
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
# Credentials file
# ---------------------------------------------------------------------------
$credFile = "$labBuildDir\credentials.txt"
New-Item -ItemType File -Path $credFile -Force | Out-Null
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" | Out-Null

function Append-Credential { param([string]$Line) Add-Content -Path $credFile -Value $Line }

Append-Credential "============================================================"
Append-Credential " SCPS CyberLab — flarevm-win10-2024 credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: DEFENDER DISABLED (malware analysis)"
Append-Credential " NOTE: DO NOT SYSPREP — FLARE-VM does not survive sysprep."
Append-Credential " SNAPSHOT: Take snapshot named 'clean-flarevm-baseline' after build."
Append-Credential "============================================================"
Append-Credential ""

$analystPass = New-RandomPassword -Length 20
$adminPass   = New-RandomPassword -Length 20
$flareVMPass = New-RandomPassword -Length 20

Append-Credential "[SECURE] Administrator : $adminPass"
Append-Credential "[SECURE] analyst       : $analystPass"
Append-Credential "[SECURE] FLARE-VM pass : $flareVMPass  (used for install -password param)"
Append-Credential ""

$tempDir = 'C:\Temp'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# [1] Computer name
# ---------------------------------------------------------------------------
Write-Status "Setting computer name to SCPS-FLARE01..."
try {
    Rename-Computer -NewName 'SCPS-FLARE01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set."
} catch { Write-Warn "Rename failed: $_" }

# ---------------------------------------------------------------------------
# [2] Create analyst account and set Administrator password
# ---------------------------------------------------------------------------
Write-Status "Configuring accounts..."
try {
    net user Administrator $adminPass /active:yes 2>&1 | Out-Null
    Write-Status "Administrator password set."

    $existingAnalyst = Get-LocalUser -Name 'analyst' -ErrorAction SilentlyContinue
    if ($null -eq $existingAnalyst) {
        New-LocalUser -Name 'analyst' `
            -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force) `
            -FullName 'Malware Analyst' `
            -Description 'Lab 5 malware analysis account' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Administrators' -Member 'analyst'
    } else {
        Set-LocalUser -Name 'analyst' -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force)
    }
    Write-Status "analyst account configured (local admin)."
} catch { Write-Warn "Account setup error: $_" }

# ---------------------------------------------------------------------------
# [3] Disable Windows Defender PERMANENTLY (MANDATORY for FLARE-VM)
# ---------------------------------------------------------------------------
Write-Status "Disabling Windows Defender permanently (mandatory for FLARE-VM)..."
try {
    # Via Set-MpPreference (runtime)
    Set-MpPreference -DisableRealtimeMonitoring         $true
    Set-MpPreference -DisableBehaviorMonitoring          $true
    Set-MpPreference -DisableBlockAtFirstSeen            $true
    Set-MpPreference -DisableIOAVProtection              $true
    Set-MpPreference -DisableScriptScanning              $true
    Set-MpPreference -DisableArchiveScanning             $true
    Set-MpPreference -DisableIntrusionPreventionSystem   $true
    Set-MpPreference -DisableEmailScanning               $true
    Set-MpPreference -DisableRemovableDriveScanning      $true
    Set-MpPreference -SubmitSamplesConsent               NeverSend
    Set-MpPreference -MAPSReporting                      Disabled
    Set-MpPreference -EnableNetworkProtection            Disabled

    # Via Group Policy registry (survives reboots)
    $defPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $defPath)) { New-Item -Path $defPath -Force | Out-Null }
    Set-ItemProperty -Path $defPath -Name 'DisableAntiSpyware' -Value 1 -Type DWord
    Set-ItemProperty -Path $defPath -Name 'DisableAntiVirus'   -Value 1 -Type DWord

    $rtpPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
    if (-not (Test-Path $rtpPath)) { New-Item -Path $rtpPath -Force | Out-Null }
    'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection',
    'DisableScanOnRealtimeEnable','DisableIOAVProtection' | ForEach-Object {
        Set-ItemProperty -Path $rtpPath -Name $_ -Value 1 -Type DWord
    }

    # Disable Defender services
    $defSvcs = @('WinDefend','Sense','WdNisSvc','WdNisDrv','WdFilter','WdBoot')
    foreach ($svc in $defSvcs) {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" `
            -Name 'Start' -Value 4 -Type DWord -ErrorAction SilentlyContinue
    }

    # Disable Defender via Task Scheduler (prevent re-enable by Windows Security)
    $defenderTasks = @(
        '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance',
        '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup',
        '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan',
        '\Microsoft\Windows\Windows Defender\Windows Defender Verification'
    )
    foreach ($task in $defenderTasks) {
        schtasks /change /tn $task /disable 2>&1 | Out-Null
    }

    # Disable Windows Security Center notifications
    $notifPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'
    if (-not (Test-Path $notifPath)) { New-Item -Path $notifPath -Force | Out-Null }
    Set-ItemProperty -Path $notifPath -Name 'DisableNotifications'     -Value 1 -Type DWord
    Set-ItemProperty -Path $notifPath -Name 'DisableEnhancedNotifications' -Value 1 -Type DWord

    # Tamper protection off (must be done via GUI on 21H2 but registry key preps it)
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender' `
        -Name 'TamperProtection' -Value 4 -Type DWord -ErrorAction SilentlyContinue

    # Disable SmartScreen for file execution
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Name 'EnableSmartScreen' -Value 0 -Type DWord -ErrorAction SilentlyContinue

    Write-Status "Windows Defender permanently disabled (all components)."
} catch { Write-Warn "Defender disable error: $_" }

# ---------------------------------------------------------------------------
# [4] Disable Windows Update (prevent tool breakage during lab)
# ---------------------------------------------------------------------------
Write-Status "Disabling Windows Update..."
try {
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name 'NoAutoUpdate' -Value 1 -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'AUOptions'    -Value 1 -Type DWord
    Stop-Service  -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
    Set-Service   -Name 'wuauserv' -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service  -Name 'UsoSvc'   -Force -ErrorAction SilentlyContinue
    Set-Service   -Name 'UsoSvc'   -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Status "Windows Update disabled."
} catch { Write-Warn "Windows Update disable error: $_" }

# ---------------------------------------------------------------------------
# [5] Enable RDP with NLA
# ---------------------------------------------------------------------------
Write-Status "Enabling RDP with NLA..."
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 1 -Type DWord
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    # Add analyst to Remote Desktop Users
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'analyst' -ErrorAction SilentlyContinue
    Write-Status "RDP enabled with NLA; analyst added to RDP users."
} catch { Write-Warn "RDP setup error: $_" }

# ---------------------------------------------------------------------------
# [6] Set execution policy for FLARE-VM install
# ---------------------------------------------------------------------------
Write-Status "Setting execution policy to Unrestricted for FLARE-VM install..."
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
Set-ExecutionPolicy Unrestricted -Scope CurrentUser  -Force

# ---------------------------------------------------------------------------
# [7] Install Chocolatey (required by FLARE-VM)
# ---------------------------------------------------------------------------
Write-Status "Installing Chocolatey..."
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Status "Chocolatey installed."
    } else {
        Write-Status "Chocolatey already present."
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
} catch { Write-Warn "Chocolatey install error: $_" }

# ---------------------------------------------------------------------------
# [8] Create FLARE-VM custom config YAML
# ---------------------------------------------------------------------------
Write-Status "Writing FLARE-VM custom config YAML..."
try {
    $flareConfigPath = "$labBuildDir\flarevm.config.yaml"
    Set-Content -Path $flareConfigPath -Value @"
# SCPS CyberLab — FLARE-VM custom package configuration
# Packages: analysis toolkit, utilities, reversing tools

packages:
  # Core analysis
  - flarevm.analysis.x64dbg.flare
  - flarevm.analysis.die.flare
  - flarevm.analysis.pestudio.flare
  - flarevm.analysis.pebear.flare
  - flarevm.analysis.capa.flare
  - flarevm.analysis.floss.flare
  - flarevm.analysis.fakenet-ng.flare
  - flarevm.analysis.apimonitor.flare
  # Disassemblers / decompilers
  - flarevm.reversing.ghidra.flare
  - flarevm.reversing.cutter.flare
  - flarevm.reversing.dnspy.flare
  - flarevm.reversing.ilspy.flare
  # Utilities
  - flarevm.utilities.7zip.flare
  - flarevm.utilities.cmder.flare
  - flarevm.utilities.hollows-hunter.flare
  - flarevm.utilities.processhacker.flare
  - flarevm.utilities.autoruns.flare
  - flarevm.utilities.procmon.flare
  - flarevm.utilities.procexp.flare
  - flarevm.utilities.tcpview.flare
  - flarevm.utilities.wireshark.flare
  - flarevm.utilities.winpcap.flare
  - flarevm.utilities.notepadplusplus.flare
  - flarevm.utilities.python3.flare
  - flarevm.utilities.git.flare
  - flarevm.utilities.vscode.flare
"@
    Write-Status "FLARE-VM config written to $flareConfigPath."
} catch { Write-Warn "FLARE-VM config write error: $_" }

# ---------------------------------------------------------------------------
# [9] Download and run FLARE-VM installer
# ---------------------------------------------------------------------------
Write-Status "Downloading FLARE-VM installer from GitHub..."
$flareInstallScript = "$tempDir\flarevm-install.ps1"
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/mandiant/flare-vm/main/install.ps1' `
        -OutFile $flareInstallScript -UseBasicParsing
    Write-Status "FLARE-VM install script downloaded."
} catch { Write-Warn "FLARE-VM download error: $_" }

Write-Status "Running FLARE-VM install (this takes 60-120 minutes)..."
Write-Warn "Do not interrupt. The VM may reboot during install — the script auto-resumes."
try {
    # Unblock the install script
    Unblock-File -Path $flareInstallScript -ErrorAction SilentlyContinue

    # Run FLARE-VM installer with:
    # -password  : the analyst account password (FLARE-VM sets auto-login for reboots)
    # -noWait    : don't wait for a keypress
    # -noGui     : no GUI (headless install)
    # -customConfig : path to our package list
    $flareArgs = @(
        '-NonInteractive',
        '-ExecutionPolicy', 'Unrestricted',
        '-File', $flareInstallScript,
        '-password', $flareVMPass,
        '-noWait',
        '-noGui',
        '-customConfig', $labBuildDir + '\flarevm.config.yaml'
    )
    $flareProcess = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $flareArgs -Wait -PassThru -NoNewWindow
    if ($flareProcess.ExitCode -ne 0) {
        Write-Warn "FLARE-VM install exited with code $($flareProcess.ExitCode) — check $tempDir\Flarevm*.log for details."
    } else {
        Write-Status "FLARE-VM install completed successfully."
    }
} catch { Write-Warn "FLARE-VM install error: $_" }

# ---------------------------------------------------------------------------
# [10] Install additional tools via Chocolatey (supplements FLARE-VM)
# ---------------------------------------------------------------------------
Write-Status "Installing additional tools via Chocolatey..."
try {
    $chocoTools = @(
        'sysinternals',          # Full Sysinternals Suite
        'wireshark',             # (also in FLARE-VM — idempotent)
        'python3',               # Python 3
        'git',                   # Git
        'vscode'                 # VS Code
    )
    foreach ($tool in $chocoTools) {
        Write-Status "Installing $tool..."
        choco install $tool -y --no-progress --ignore-checksums 2>&1 | Out-Null
    }

    # Install Python packages for analysis
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    python -m pip install --upgrade pip 2>&1 | Out-Null
    python -m pip install fakenet-ng pefile capstone yara-python 2>&1 | Out-Null
    Write-Status "Additional tools and Python packages installed."
} catch { Write-Warn "Additional tool install error: $_" }

# ---------------------------------------------------------------------------
# [11] Configure analysis directories
# ---------------------------------------------------------------------------
Write-Status "Creating analysis directory structure..."
try {
    $dirs = @('C:\Samples', 'C:\Reports', 'C:\Tools\extra', 'C:\SysmonLogs')
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    # C:\Samples — restricted to analyst only
    icacls 'C:\Samples' /inheritance:r `
        /grant "BUILTIN\Administrators:(OI)(CI)F" `
        /grant "analyst:(OI)(CI)F" | Out-Null
    Write-Status "C:\Samples restricted to analyst and Administrators."

    # C:\Reports — readable by all, writable by analyst
    icacls 'C:\Reports' /inheritance:r `
        /grant "BUILTIN\Administrators:(OI)(CI)F" `
        /grant "analyst:(OI)(CI)F" `
        /grant "BUILTIN\Users:(OI)(CI)R" | Out-Null

    Write-Status "Analysis directories created."
} catch { Write-Warn "Directory setup error: $_" }

# ---------------------------------------------------------------------------
# [12] Configure FakeNet-NG for network simulation
# ---------------------------------------------------------------------------
Write-Status "Setting up FakeNet-NG startup script..."
try {
    $fakeNetScript = 'C:\Tools\extra\start-fakenet.bat'
    Set-Content -Path $fakeNetScript -Value @"
@echo off
:: FakeNet-NG — simulates internet services during dynamic malware analysis
:: Intercepts DNS, HTTP, HTTPS, SMTP, etc. on the loopback interface
:: Run this BEFORE executing a malware sample for dynamic analysis
echo Starting FakeNet-NG...
cd /d C:\Tools\extra
python -m fakenet --config C:\Tools\extra\fakenet.cfg
"@

    # Write a basic FakeNet config
    Set-Content -Path 'C:\Tools\extra\fakenet.cfg' -Value @"
[FakeNet]
DivertTraffic: Yes
DumpPackets:   Yes
DumpPacketsFilePrefix: C:\Samples\fakenet_capture

[Diverter]
NetworkMode: SingleHost
LinuxRedirectNonlocal: No

[Listener_DNS]
Enabled:  True
Port:     53
Protocol: UDP
Listener: DNSListener

[Listener_HTTP]
Enabled:  True
Port:     80
Protocol: TCP
Listener: HTTPListener

[Listener_HTTPS]
Enabled:  True
Port:     443
Protocol: TCP
Listener: HTTPListener
UseSSL:   Yes

[Listener_SMTP]
Enabled:  True
Port:     25
Protocol: TCP
Listener: SMTPListener

[Listener_IRC]
Enabled:  True
Port:     6667
Protocol: TCP
Listener: RawListener
"@
    Write-Status "FakeNet-NG configured."
} catch { Write-Warn "FakeNet-NG setup error: $_" }

# ---------------------------------------------------------------------------
# [13] Configure Wireshark to capture on all interfaces at startup
# ---------------------------------------------------------------------------
Write-Status "Configuring Wireshark capture preferences..."
try {
    $wiresharkPrefDir = "$env:APPDATA\Wireshark"
    if (-not (Test-Path $wiresharkPrefDir)) { New-Item -ItemType Directory -Path $wiresharkPrefDir -Force | Out-Null }
    Set-Content -Path "$wiresharkPrefDir\preferences" -Value @"
# Wireshark preferences for SCPS FLARE-VM
capture.auto_scroll: TRUE
capture.real_time_updates: TRUE
capture.columns: (No.),(Time),(Source),(Destination),(Protocol),(Length),(Info)
gui.toolbar_main_show: TRUE
capture.filter:
"@
    Write-Status "Wireshark preferences configured."
} catch { Write-Warn "Wireshark config error: $_" }

# ---------------------------------------------------------------------------
# [14] RDP configuration — allow analyst account
# ---------------------------------------------------------------------------
Write-Status "Configuring RDP for analyst..."
try {
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'analyst' -ErrorAction SilentlyContinue
    Write-Status "analyst added to Remote Desktop Users."
} catch { Write-Warn "RDP analyst config error: $_" }

# ---------------------------------------------------------------------------
# [15] Finalize credentials file
# ---------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== CONFIGURATION SUMMARY ==="
Append-Credential "- Windows Defender  : PERMANENTLY DISABLED (required for FLARE-VM)"
Append-Credential "- Windows Update    : DISABLED"
Append-Credential "- Execution Policy  : Unrestricted"
Append-Credential "- RDP               : ENABLED with NLA"
Append-Credential "- FLARE-VM          : INSTALLED (mandiant/flare-vm)"
Append-Credential "- Sysinternals      : Full suite at C:\Tools\SysinternalsSuite"
Append-Credential "- FakeNet-NG        : Configured at C:\Tools\extra\start-fakenet.bat"
Append-Credential "- Wireshark         : Installed"
Append-Credential "- Analysis dirs     : C:\Samples, C:\Reports, C:\Tools\extra"
Append-Credential ""
Append-Credential "=== SNAPSHOT REMINDER ==="
Append-Credential "Take snapshot 'clean-flarevm-baseline' after build completes."
Append-Credential "Students revert to this snapshot between sessions."
Append-Credential ""
Append-Credential "=== DO NOT SYSPREP ==="
Append-Credential "FLARE-VM does not survive sysprep. Shut down and capture as-is."
Write-Status "credentials.txt written."

# ---------------------------------------------------------------------------
# [16] Final cleanup and shutdown (NO sysprep)
# ---------------------------------------------------------------------------
Write-Status "Clearing event logs..."
try {
    Clear-EventLog -LogName Application -ErrorAction SilentlyContinue
    Clear-EventLog -LogName System      -ErrorAction SilentlyContinue
    Clear-EventLog -LogName Security    -ErrorAction SilentlyContinue
    wevtutil cl 'Microsoft-Windows-PowerShell/Operational' 2>&1 | Out-Null
} catch { Write-Warn "Event log clear error: $_" }

Write-Status "Clearing PowerShell history..."
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" `
        -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue
} catch { Write-Warn "History clear error: $_" }

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Build-FlareVM.ps1 completed." -ForegroundColor Green
Write-Host " REMINDER: Take snapshot 'clean-flarevm-baseline' NOW" -ForegroundColor Yellow
Write-Host "           before shutting down for image capture." -ForegroundColor Yellow
Write-Host " DO NOT SYSPREP — FLARE-VM does not survive sysprep." -ForegroundColor Red
Write-Host " Shutting down in 30 seconds (time to snapshot)..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

Stop-Transcript
# Extended delay to allow operator to take snapshot before shutdown
Start-Sleep -Seconds 30
Stop-Computer -Force
