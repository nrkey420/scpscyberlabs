#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for windows-10-sandbox base image.

.DESCRIPTION
    Image Name    : windows-10-sandbox
    Purpose       : Clean Windows 10 sandbox target VM for malware detonation (Lab 5).
                    Malware samples are executed here; analysts observe from FLARE-VM.
                    COMPLETELY ISOLATED — outbound blocked except to analysis network.
    Base OS       : Windows 10 Enterprise 21H2
    Lab           : Lab 5 — Malware Analysis (detonation target)
    Security Level: DEFENDER DISABLED + FULLY INSTRUMENTED (malware target)
    IP            : 10.CLASS_ID.0.20 (set at deploy time)
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

    SNAPSHOT NOTE:
    After this script completes, take a snapshot named "clean-sandbox-baseline".
    Students revert to this snapshot before each malware detonation session.
    DO NOT SYSPREP — capture disk as-is.

.NOTES
    Run as Administrator after OS installation and Hyper-V integration services.
    Network isolation is critical — the firewall rules here block all outbound
    except to the analysis network (10.CLASS_ID.0.0/24). Verify at deploy time.
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
Write-Host " SCPS CyberLab — Build-Windows10Sandbox.ps1" -ForegroundColor Cyan
Write-Host " Image  : windows-10-sandbox" -ForegroundColor Cyan
Write-Host " Lab    : Lab 5 — Malware Detonation Target" -ForegroundColor Cyan
Write-Host " CRITICAL: Outbound traffic will be blocked except to analysis net" -ForegroundColor Red
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
Append-Credential " SCPS CyberLab — windows-10-sandbox credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: DEFENDER DISABLED + INSTRUMENTED (malware target)"
Append-Credential " SNAPSHOT: Take 'clean-sandbox-baseline' after build."
Append-Credential " DO NOT SYSPREP — capture disk as-is."
Append-Credential "============================================================"
Append-Credential ""

$victimPass  = New-RandomPassword -Length 20
$analystPass = New-RandomPassword -Length 20
$adminPass   = New-RandomPassword -Length 20

Append-Credential "[SECURE] Administrator : $adminPass"
Append-Credential "[SECURE] victim        : $victimPass  (malware runs as this user)"
Append-Credential "[SECURE] analyst       : $analystPass (accesses logs from FLARE-VM)"
Append-Credential ""

$tempDir = 'C:\Temp'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

# Analysis network — update CLASS_ID at deploy time
$analysisNet = '10.0.0.0/8'

# ---------------------------------------------------------------------------
# [1] Computer name
# ---------------------------------------------------------------------------
Write-Status "Setting computer name to SCPS-TARGET01..."
try {
    Rename-Computer -NewName 'SCPS-TARGET01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set."
} catch { Write-Warn "Rename failed: $_" }

# ---------------------------------------------------------------------------
# [2] Create accounts
# ---------------------------------------------------------------------------
Write-Status "Configuring accounts..."
try {
    net user Administrator $adminPass /active:yes 2>&1 | Out-Null
    Write-Status "Administrator password set."

    # victim — standard user (malware runs as this user)
    $existingVictim = Get-LocalUser -Name 'victim' -ErrorAction SilentlyContinue
    if ($null -eq $existingVictim) {
        New-LocalUser -Name 'victim' `
            -Password (ConvertTo-SecureString $victimPass -AsPlainText -Force) `
            -FullName 'Lab Victim' `
            -Description 'Standard user — malware executes in this context' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Users' -Member 'victim'
    } else {
        Set-LocalUser -Name 'victim' -Password (ConvertTo-SecureString $victimPass -AsPlainText -Force)
    }
    Write-Status "victim account created (standard user)."

    # analyst — local admin (for log access from FLARE-VM)
    $existingAnalyst = Get-LocalUser -Name 'analyst' -ErrorAction SilentlyContinue
    if ($null -eq $existingAnalyst) {
        New-LocalUser -Name 'analyst' `
            -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force) `
            -FullName 'Malware Analyst' `
            -Description 'Admin account for remote log collection' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Administrators' -Member 'analyst'
    } else {
        Set-LocalUser -Name 'analyst' -Password (ConvertTo-SecureString $analystPass -AsPlainText -Force)
    }
    Write-Status "analyst account created (local admin)."
} catch { Write-Warn "Account setup error: $_" }

# ---------------------------------------------------------------------------
# [3] Disable Windows Defender (malware target — must be unprotected)
# ---------------------------------------------------------------------------
Write-Status "Disabling Windows Defender (malware target VM — must be unprotected)..."
try {
    Set-MpPreference -DisableRealtimeMonitoring          $true
    Set-MpPreference -DisableBehaviorMonitoring           $true
    Set-MpPreference -DisableBlockAtFirstSeen             $true
    Set-MpPreference -DisableIOAVProtection               $true
    Set-MpPreference -DisableScriptScanning               $true
    Set-MpPreference -DisableArchiveScanning              $true
    Set-MpPreference -DisableIntrusionPreventionSystem    $true
    Set-MpPreference -DisableEmailScanning                $true
    Set-MpPreference -SubmitSamplesConsent                NeverSend
    Set-MpPreference -MAPSReporting                       Disabled

    $defPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $defPath)) { New-Item -Path $defPath -Force | Out-Null }
    Set-ItemProperty -Path $defPath -Name 'DisableAntiSpyware' -Value 1 -Type DWord
    Set-ItemProperty -Path $defPath -Name 'DisableAntiVirus'   -Value 1 -Type DWord

    $rtpPath = "$defPath\Real-Time Protection"
    if (-not (Test-Path $rtpPath)) { New-Item -Path $rtpPath -Force | Out-Null }
    'DisableRealtimeMonitoring','DisableBehaviorMonitoring','DisableOnAccessProtection',
    'DisableScanOnRealtimeEnable','DisableIOAVProtection' | ForEach-Object {
        Set-ItemProperty -Path $rtpPath -Name $_ -Value 1 -Type DWord
    }

    # Disable Defender Scheduled Tasks
    $defenderTasks = @(
        '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance',
        '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup',
        '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan',
        '\Microsoft\Windows\Windows Defender\Windows Defender Verification'
    )
    foreach ($task in $defenderTasks) {
        schtasks /change /tn $task /disable 2>&1 | Out-Null
    }

    # Disable sample submission
    $spynetPath = "$defPath\Spynet"
    if (-not (Test-Path $spynetPath)) { New-Item -Path $spynetPath -Force | Out-Null }
    Set-ItemProperty -Path $spynetPath -Name 'SpynetReporting'    -Value 0 -Type DWord
    Set-ItemProperty -Path $spynetPath -Name 'SubmitSamplesConsent'-Value 2 -Type DWord

    Write-Status "Windows Defender disabled (all components, sample submission off)."
} catch { Write-Warn "Defender disable error: $_" }

# ---------------------------------------------------------------------------
# [4] Disable Windows Update
# ---------------------------------------------------------------------------
Write-Status "Disabling Windows Update..."
try {
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name 'NoAutoUpdate' -Value 1 -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'AUOptions'    -Value 1 -Type DWord
    Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
    Set-Service  -Name 'wuauserv' -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name 'UsoSvc'   -Force -ErrorAction SilentlyContinue
    Set-Service  -Name 'UsoSvc'   -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Status "Windows Update disabled."
} catch { Write-Warn "Windows Update disable error: $_" }

# ---------------------------------------------------------------------------
# [5] Install Sysmon with Florian Roth's sysmon-modular config (full coverage)
# ---------------------------------------------------------------------------
Write-Status "Installing Sysmon with full logging config..."
try {
    $sysmonDir    = 'C:\Tools\Sysmon'
    $sysmonZip    = "$tempDir\Sysmon.zip"
    $sysmonConfig = "$sysmonDir\sysmon-modular.xml"
    $sysmonExe    = "$sysmonDir\Sysmon64.exe"

    if (-not (Test-Path $sysmonDir)) { New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null }
    if (-not (Test-Path $sysmonExe)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' `
            -OutFile $sysmonZip -UseBasicParsing
        Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
    }

    # Florian Roth's sysmon-modular — comprehensive coverage for malware analysis
    if (-not (Test-Path $sysmonConfig)) {
        Invoke-WebRequest `
            -Uri 'https://raw.githubusercontent.com/Neo23x0/sysmon-config/master/sysmonconfig-export.xml' `
            -OutFile $sysmonConfig -UseBasicParsing
        Write-Status "Florian Roth sysmon config downloaded."
    }

    # Create Sysmon log output directory
    $sysmonLogDir = 'C:\SysmonLogs'
    if (-not (Test-Path $sysmonLogDir)) { New-Item -ItemType Directory -Path $sysmonLogDir -Force | Out-Null }

    # Install or update Sysmon
    $sysmonSvc = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($null -eq $sysmonSvc) {
        & $sysmonExe -accepteula -i $sysmonConfig 2>&1 | Out-Null
        Write-Status "Sysmon installed."
    } else {
        & $sysmonExe -c $sysmonConfig 2>&1 | Out-Null
        Write-Status "Sysmon config updated."
    }

    # Configure Sysmon log export via scheduled task (copies event logs to C:\SysmonLogs)
    $sysmonExportScript = 'C:\SysmonLogs\export-sysmon.ps1'
    Set-Content -Path $sysmonExportScript -Value @'
# Export Sysmon events to C:\SysmonLogs for analyst retrieval
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile   = "C:\SysmonLogs\sysmon-$timestamp.evtx"
wevtutil epl 'Microsoft-Windows-Sysmon/Operational' $outFile
'@
    $sysmonExportTask = Get-ScheduledTask -TaskName 'SysmonLogExport' -ErrorAction SilentlyContinue
    if ($null -ne $sysmonExportTask) { Unregister-ScheduledTask -TaskName 'SysmonLogExport' -Confirm:$false }
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$sysmonExportScript`""
    $trigger   = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 15) `
        -Once -At (Get-Date)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'SysmonLogExport' `
        -Action $action -Trigger $trigger -Principal $principal -Force
    Write-Status "Sysmon log export task scheduled (every 15 minutes)."
} catch { Write-Warn "Sysmon install error: $_" }

# ---------------------------------------------------------------------------
# [6] Full enhanced audit policy
# ---------------------------------------------------------------------------
Write-Status "Configuring full audit policy (all subcategories, success+failure)..."
try {
    # Enable all audit subcategories
    $auditCmds = @(
        # Logon/Logoff
        'auditpol /set /subcategory:"Logon" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Logoff" /success:enable',
        'auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Special Logon" /success:enable',
        'auditpol /set /subcategory:"Other Logon/Logoff Events" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Network Policy Server" /success:enable /failure:enable',
        # Process
        'auditpol /set /subcategory:"Process Creation" /success:enable',
        'auditpol /set /subcategory:"Process Termination" /success:enable',
        'auditpol /set /subcategory:"DPAPI Activity" /success:enable /failure:enable',
        'auditpol /set /subcategory:"RPC Events" /success:enable /failure:enable',
        # Account management
        'auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Other Account Management Events" /success:enable /failure:enable',
        # Object access
        'auditpol /set /subcategory:"File System" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Registry" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Kernel Object" /success:enable /failure:enable',
        'auditpol /set /subcategory:"SAM" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Handle Manipulation" /success:enable /failure:enable',
        'auditpol /set /subcategory:"File Share" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Filtering Platform Connection" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Filtering Platform Packet Drop" /failure:enable',
        # Privilege use
        'auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Non Sensitive Privilege Use" /success:enable',
        # Policy change
        'auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Authentication Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Authorization Policy Change" /success:enable',
        'auditpol /set /subcategory:"MPSSVC Rule-Level Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Filtering Platform Policy Change" /success:enable',
        # System
        'auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security System Extension" /success:enable',
        'auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"IPsec Driver" /success:enable /failure:enable',
        # Credential validation
        'auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable'
    )
    foreach ($cmd in $auditCmds) { Invoke-Expression $cmd 2>&1 | Out-Null }

    # Command-line in process creation events
    $procAuditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $procAuditPath)) { New-Item -Path $procAuditPath -Force | Out-Null }
    Set-ItemProperty -Path $procAuditPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord

    Write-Status "Full audit policy configured."
} catch { Write-Warn "Audit policy error: $_" }

# ---------------------------------------------------------------------------
# [7] PowerShell Script Block Logging
# ---------------------------------------------------------------------------
Write-Status "Enabling PowerShell Script Block and Module logging..."
try {
    $psLogPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    if (-not (Test-Path $psLogPath)) { New-Item -Path $psLogPath -Force | Out-Null }
    Set-ItemProperty -Path $psLogPath -Name 'EnableScriptBlockLogging'          -Value 1 -Type DWord
    Set-ItemProperty -Path $psLogPath -Name 'EnableScriptBlockInvocationLogging' -Value 1 -Type DWord

    $modLogPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
    if (-not (Test-Path $modLogPath)) { New-Item -Path $modLogPath -Force | Out-Null }
    Set-ItemProperty -Path $modLogPath -Name 'EnableModuleLogging' -Value 1 -Type DWord

    $modNamesPath = "$modLogPath\ModuleNames"
    if (-not (Test-Path $modNamesPath)) { New-Item -Path $modNamesPath -Force | Out-Null }
    Set-ItemProperty -Path $modNamesPath -Name '*' -Value '*' -Type String

    Write-Status "PowerShell logging enabled."
} catch { Write-Warn "PS logging error: $_" }

# ---------------------------------------------------------------------------
# [8] Install Wireshark + WinPcap for network capture
# ---------------------------------------------------------------------------
Write-Status "Installing Wireshark with WinPcap driver..."
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    choco install wireshark -y --no-progress 2>&1 | Out-Null
    Write-Status "Wireshark installed."

    # Create network capture script that analyst can trigger remotely
    $captureDir = 'C:\Capture'
    if (-not (Test-Path $captureDir)) { New-Item -ItemType Directory -Path $captureDir -Force | Out-Null }
    Set-Content -Path "$captureDir\start-capture.bat" -Value @"
@echo off
:: Network capture script for malware analysis sessions
:: Invoked remotely by analyst from FLARE-VM via WinRM
:: Output: C:\Capture\capture-TIMESTAMP.pcapng
set TIMESTAMP=%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%
set OUTFILE=C:\Capture\capture-%TIMESTAMP%.pcapng
echo Starting capture to %OUTFILE%
"C:\Program Files\Wireshark\tshark.exe" -i 1 -w "%OUTFILE%" -a duration:3600
echo Capture complete: %OUTFILE%
"@
    Write-Status "Network capture script at $captureDir\start-capture.bat"
} catch { Write-Warn "Wireshark install error: $_" }

# ---------------------------------------------------------------------------
# [9] Enable WinRM for remote management by analyst
# ---------------------------------------------------------------------------
Write-Status "Enabling WinRM for analyst remote access..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
    # Allow WinRM for analyst only (via firewall rule below)
    Write-Status "WinRM enabled."
} catch { Write-Warn "WinRM setup error: $_" }

# ---------------------------------------------------------------------------
# [10] Enable RDP — allow victim and analyst accounts
# ---------------------------------------------------------------------------
Write-Status "Enabling RDP for both accounts..."
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 1 -Type DWord   # NLA required
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'victim'  -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'analyst' -ErrorAction SilentlyContinue
    Write-Status "RDP enabled; victim and analyst added to Remote Desktop Users."
} catch { Write-Warn "RDP setup error: $_" }

# ---------------------------------------------------------------------------
# [11] Create Samples share (Everyone write — analyst drops samples here)
# ---------------------------------------------------------------------------
Write-Status "Creating Samples SMB share (Everyone write)..."
try {
    $samplesPath = 'C:\Samples'
    if (-not (Test-Path $samplesPath)) { New-Item -ItemType Directory -Path $samplesPath -Force | Out-Null }
    $existingShare = Get-SmbShare -Name 'Samples' -ErrorAction SilentlyContinue
    if ($null -ne $existingShare) { Remove-SmbShare -Name 'Samples' -Force }
    New-SmbShare -Name 'Samples' -Path $samplesPath -FullAccess 'Everyone' `
        -Description 'Malware sample drop location — analyst writes, target reads'
    Write-Status "\\SCPS-TARGET01\Samples share created (Everyone: Full)."
} catch { Write-Warn "Samples share creation error: $_" }

# ---------------------------------------------------------------------------
# [12] Place bait files in victim Documents
# ---------------------------------------------------------------------------
Write-Status "Placing bait files in victim Documents..."
try {
    $victimDocs = 'C:\Users\victim\Documents'
    if (-not (Test-Path $victimDocs)) { New-Item -ItemType Directory -Path $victimDocs -Force | Out-Null }

    # Fake Word document (just text — simulates doc bait)
    Set-Content -Path "$victimDocs\Q4_Financial_Report_CONFIDENTIAL.txt" -Value @"
CONFIDENTIAL — DO NOT DISTRIBUTE
Q4 2024 Financial Report

Revenue:    $4,850,000
Expenses:   $3,200,000
Net Profit: $1,650,000

Executive Summary:
This report contains sensitive financial data for internal use only.
Distribution outside of executive team is prohibited.

Approved by: CFO
Date: 2024-12-15
"@

    Set-Content -Path "$victimDocs\Employee_Salary_Data_2024.txt" -Value @"
STRICTLY CONFIDENTIAL — HR USE ONLY
Employee Compensation Data — FY2024

CEO:           $350,000
CTO:           $280,000
CFO:           $275,000
VP Engineering:$220,000
Sr. Engineer:  $155,000
...

This document is restricted to HR and executive leadership.
Unauthorized access or distribution is a disciplinary offense.
"@

    Set-Content -Path "$victimDocs\VPN_Credentials_Backup.txt" -Value @"
VPN Backup Credentials (Emergency Use Only)
Last updated: 2024-11-01

Primary VPN:
  Server: vpn.company.com
  User:   vpnadmin
  Pass:   VpnAdmin2024!

Backup VPN:
  Server: vpn-backup.company.com
  User:   vpnadmin2
  Pass:   VpnB@ck2024

Note: Rotate these after Q1 2025 audit
"@

    Write-Status "Bait files placed in $victimDocs."
} catch { Write-Warn "Bait file placement error: $_" }

# ---------------------------------------------------------------------------
# [13] Windows Firewall — critical network isolation
# ---------------------------------------------------------------------------
Write-Status "Configuring critical network isolation firewall rules..."
Write-Warn "CRITICAL: All outbound blocked except to analysis network ($analysisNet)."
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True `
        -DefaultInboundAction  Block `
        -DefaultOutboundAction Block  # Block all outbound by default

    # INBOUND — allow only what analyst needs
    # RDP (3389) — analyst accesses target
    New-NetFirewallRule -DisplayName 'Allow-RDP-In' -Direction Inbound `
        -Protocol TCP -LocalPort 3389 -RemoteAddress $analysisNet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # WinRM (5985 HTTP — for lab use; analyst connects from FLARE-VM)
    New-NetFirewallRule -DisplayName 'Allow-WinRM-In' -Direction Inbound `
        -Protocol TCP -LocalPort 5985 -RemoteAddress $analysisNet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # SMB (445) — for sample drop via \\SCPS-TARGET01\Samples
    New-NetFirewallRule -DisplayName 'Allow-SMB-In' -Direction Inbound `
        -Protocol TCP -LocalPort 445 -RemoteAddress $analysisNet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # ICMP — allow from analysis net for ping
    New-NetFirewallRule -DisplayName 'Allow-ICMP-In' -Direction Inbound `
        -Protocol ICMPv4 -RemoteAddress $analysisNet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # OUTBOUND — allow only to analysis network
    New-NetFirewallRule -DisplayName 'Allow-Out-AnalysisNet' -Direction Outbound `
        -RemoteAddress $analysisNet -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow DNS outbound to analysis net only (malware DNS will be intercepted by FakeNet-NG)
    New-NetFirewallRule -DisplayName 'Allow-DNS-Out' -Direction Outbound `
        -Protocol UDP -RemotePort 53 -RemoteAddress $analysisNet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow loopback
    New-NetFirewallRule -DisplayName 'Allow-Loopback-Out' -Direction Outbound `
        -RemoteAddress '127.0.0.1' -Action Allow -Profile Any -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Allow-Loopback-In' -Direction Inbound `
        -RemoteAddress '127.0.0.1' -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # BLOCK all other inbound and outbound (covered by DefaultInboundAction/DefaultOutboundAction Block)
    Write-Status "Critical network isolation configured. All outbound blocked except to $analysisNet."
} catch { Write-Warn "Firewall rule error: $_" }

# ---------------------------------------------------------------------------
# [14] Install .NET 3.5 and VCRedist (malware often requires these)
# ---------------------------------------------------------------------------
Write-Status "Installing .NET 3.5..."
try {
    $dotnet35 = Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -ErrorAction SilentlyContinue
    if ($null -eq $dotnet35 -or $dotnet35.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -FeatureName 'NetFx3' -Online -NoRestart -ErrorAction SilentlyContinue
        Write-Status ".NET 3.5 installed."
    } else {
        Write-Status ".NET 3.5 already enabled."
    }
} catch { Write-Warn ".NET 3.5 install error (may need Windows media): $_" }

Write-Status "Installing Visual C++ Redistributables (various versions)..."
try {
    # 2005 x86/x64
    choco install vcredist2005 -y --no-progress 2>&1 | Out-Null
    # 2008 x86/x64
    choco install vcredist2008 -y --no-progress 2>&1 | Out-Null
    # 2010 x86/x64
    choco install vcredist2010 -y --no-progress 2>&1 | Out-Null
    # 2012 x86/x64
    choco install vcredist2012 -y --no-progress 2>&1 | Out-Null
    # 2013 x86/x64
    choco install vcredist2013 -y --no-progress 2>&1 | Out-Null
    # 2015-2022 x86/x64 (covers 2015, 2017, 2019, 2022)
    choco install vcredist140 -y --no-progress 2>&1 | Out-Null
    Write-Status "VCRedist packages installed."
} catch { Write-Warn "VCRedist install error: $_" }

# ---------------------------------------------------------------------------
# [15] Finalize credentials file
# ---------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== CONFIGURATION SUMMARY ==="
Append-Credential "- Windows Defender  : PERMANENTLY DISABLED"
Append-Credential "- Windows Update    : DISABLED"
Append-Credential "- Sysmon            : INSTALLED (Florian Roth sysmon-modular config)"
Append-Credential "- Audit Policy      : FULL (all subcategories, success+failure)"
Append-Credential "- PS Logging        : Script block + module logging ENABLED"
Append-Credential "- WinRM             : ENABLED (HTTP, analysis net only)"
Append-Credential "- RDP               : ENABLED with NLA"
Append-Credential "- Firewall          : STRICT isolation — outbound BLOCKED except $analysisNet"
Append-Credential "- SMB Share         : \\SCPS-TARGET01\Samples (Everyone: Full)"
Append-Credential "- Capture Script    : C:\Capture\start-capture.bat"
Append-Credential "- Sysmon Log Export : C:\SysmonLogs\ (15-min schedule)"
Append-Credential ""
Append-Credential "=== SNAPSHOT REMINDER ==="
Append-Credential "Take snapshot 'clean-sandbox-baseline' after build completes."
Append-Credential "Students revert before each detonation session."
Append-Credential ""
Append-Credential "=== DO NOT SYSPREP ==="
Append-Credential "Capture disk image as-is after shutdown."
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
    wevtutil cl 'Microsoft-Windows-Sysmon/Operational'     2>&1 | Out-Null
} catch { Write-Warn "Event log clear error: $_" }

Write-Status "Clearing PowerShell history..."
try {
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" `
        -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue
} catch { Write-Warn "History clear error: $_" }

# Zero free space to minimise image size
Write-Status "Zeroing free disk space..."
try { cipher /w:C:\ 2>&1 | Out-Null } catch { Write-Warn "cipher /w error: $_" }

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Build-Windows10Sandbox.ps1 completed." -ForegroundColor Green
Write-Host " REMINDER: Take snapshot 'clean-sandbox-baseline' NOW" -ForegroundColor Yellow
Write-Host "           before capturing the disk image." -ForegroundColor Yellow
Write-Host " DO NOT SYSPREP — capture disk as-is." -ForegroundColor Red
Write-Host " Shutting down in 30 seconds (time to snapshot)..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

Stop-Transcript
Start-Sleep -Seconds 30
Stop-Computer -Force
