#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for windows-10-vulnerable base image.

.DESCRIPTION
    Image Name    : windows-10-vulnerable
    Purpose       : Windows 10 workstation with intentional vulnerabilities for red team attacks (Lab 1)
    Base OS       : Windows 10 Enterprise 21H2
    Lab           : Lab 1 — Red Team Operations
    Security Level: INTENTIONALLY VULNERABLE — educational use only
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    WARNING: THIS VM IS INTENTIONALLY VULNERABLE — FOR EDUCATIONAL USE ONLY
    DO NOT connect this image to production networks.
    All weaknesses are deliberate and documented for pedagogical purposes.
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

.NOTES
    Run as Administrator after OS installation and Hyper-V integration services.
    The AD promotion variant reboots automatically; this script does not require a reboot.
#>

# INTENTIONALLY VULNERABLE — educational use only
# This VM is designed to be attacked by students

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
Write-Host " SCPS CyberLab — Build-Windows10Vulnerable.ps1" -ForegroundColor Cyan
Write-Host " Image  : windows-10-vulnerable" -ForegroundColor Cyan
Write-Host " WARNING: INTENTIONALLY VULNERABLE IMAGE" -ForegroundColor Red
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
    $password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    return $password
}

function Write-Status {
    param([string]$Message, [string]$Color = 'Green')
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Write-Warn  { param([string]$Message) Write-Status $Message 'Yellow' }
function Write-Err   { param([string]$Message) Write-Status $Message 'Red'    }

# ---------------------------------------------------------------------------
# Credentials file — restricted to Administrators
# ---------------------------------------------------------------------------
$credFile = "$labBuildDir\credentials.txt"
if (-not (Test-Path $credFile)) {
    New-Item -ItemType File -Path $credFile -Force | Out-Null
}
# Restrict permissions: remove inherited, grant Administrators Full only
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" | Out-Null

function Append-Credential {
    param([string]$Line)
    Add-Content -Path $credFile -Value $Line
}

Append-Credential "============================================================"
Append-Credential " SCPS CyberLab — windows-10-vulnerable credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: INTENTIONALLY VULNERABLE (educational)"
Append-Credential "============================================================"
Append-Credential ""

# ---------------------------------------------------------------------------
# [1] Computer name
# ---------------------------------------------------------------------------
Write-Status "Setting computer name to SCPS-WS01..."
try {
    Rename-Computer -NewName 'SCPS-WS01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set to SCPS-WS01."
} catch {
    Write-Warn "Could not rename computer (may already be set): $_"
}

# ---------------------------------------------------------------------------
# [2] Disable Windows Defender (INTENTIONAL VULNERABILITY)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Disabling Windows Defender real-time protection..."
try {
    Set-MpPreference -DisableRealtimeMonitoring $true
    Set-MpPreference -DisableBehaviorMonitoring $true
    Set-MpPreference -DisableBlockAtFirstSeen $true
    Set-MpPreference -DisableIOAVProtection $true
    Set-MpPreference -DisablePrivacyMode $true
    Set-MpPreference -SignatureDisableUpdateOnStartupWithoutEngine $true
    Set-MpPreference -DisableArchiveScanning $true
    Set-MpPreference -DisableIntrusionPreventionSystem $true
    Set-MpPreference -DisableScriptScanning $true
    Set-MpPreference -SubmitSamplesConsent NeverSend

    # Disable via registry for persistence across reboots
    $defenderRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if (-not (Test-Path $defenderRegPath)) {
        New-Item -Path $defenderRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $defenderRegPath -Name 'DisableAntiSpyware' -Value 1 -Type DWord
    Set-ItemProperty -Path $defenderRegPath -Name 'DisableAntiVirus'   -Value 1 -Type DWord

    $rtpPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
    if (-not (Test-Path $rtpPath)) { New-Item -Path $rtpPath -Force | Out-Null }
    Set-ItemProperty -Path $rtpPath -Name 'DisableBehaviorMonitoring'  -Value 1 -Type DWord
    Set-ItemProperty -Path $rtpPath -Name 'DisableOnAccessProtection'  -Value 1 -Type DWord
    Set-ItemProperty -Path $rtpPath -Name 'DisableScanOnRealtimeEnable'-Value 1 -Type DWord
    Set-ItemProperty -Path $rtpPath -Name 'DisableRealtimeMonitoring'  -Value 1 -Type DWord

    # Disable Windows Defender service via registry (sets start to disabled)
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend' -Name 'Start' -Value 4 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Sense'     -Name 'Start' -Value 4 -Type DWord -ErrorAction SilentlyContinue

    Write-Status "Windows Defender disabled (intentional)."
} catch {
    Write-Warn "Defender disable error (may be controlled by external policy): $_"
}

# Disable SmartScreen (INTENTIONAL VULNERABILITY)
Write-Warn "[INTENTIONAL VULN] Disabling SmartScreen..."
try {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' `
        -Name 'EnableSmartScreen' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' `
        -Name 'SmartScreenEnabled' -Value 'Off' -Type String -ErrorAction SilentlyContinue
    Write-Status "SmartScreen disabled (intentional)."
} catch {
    Write-Warn "SmartScreen disable partial: $_"
}

# ---------------------------------------------------------------------------
# [3] Disable Windows Firewall (INTENTIONAL VULNERABILITY)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Disabling Windows Firewall for all profiles..."
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    netsh advfirewall set allprofiles state off | Out-Null
    Write-Status "Windows Firewall disabled (intentional)."
} catch {
    Write-Warn "Firewall disable error: $_"
}

# ---------------------------------------------------------------------------
# [4] Enable SMBv1 (INTENTIONAL VULNERABILITY — EternalBlue etc.)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Enabling SMBv1..."
try {
    Enable-WindowsOptionalFeature -FeatureName SMB1Protocol -Online -NoRestart -ErrorAction SilentlyContinue
    Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
    # Enable via registry as well
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' `
        -Name 'SMB1' -Value 1 -Type DWord
    Write-Status "SMBv1 enabled (intentional — EternalBlue target practice)."
} catch {
    Write-Warn "SMBv1 enable error: $_"
}

# ---------------------------------------------------------------------------
# [5] Enable WinRM (INTENTIONAL VULNERABILITY)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Enabling WinRM with no authentication restrictions..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-WSManQuickConfig -Force -ErrorAction SilentlyContinue

    # Allow unencrypted and basic auth for lab exploitation practice
    winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Null
    winrm set winrm/config/service/auth '@{Basic="true"}' | Out-Null
    winrm set winrm/config/client '@{AllowUnencrypted="true"}' | Out-Null
    winrm set winrm/config/client/auth '@{Basic="true"}' | Out-Null

    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true

    Write-Status "WinRM enabled with weak config (intentional)."
} catch {
    Write-Warn "WinRM setup error: $_"
}

# ---------------------------------------------------------------------------
# [6] Enable RDP (INTENTIONAL VULNERABILITY — no NLA)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Enabling RDP without NLA..."
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    # Disable NLA (intentional)
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 0 -Type DWord
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    # Also open 3389 explicitly since firewall is disabled anyway
    netsh advfirewall firewall add rule name="RDP" dir=in action=allow protocol=TCP localport=3389 | Out-Null
    Write-Status "RDP enabled without NLA (intentional)."
} catch {
    Write-Warn "RDP setup error: $_"
}

# ---------------------------------------------------------------------------
# [7] Create user accounts (INTENTIONALLY WEAK PASSWORDS)
# ---------------------------------------------------------------------------
Write-Status "Creating intentionally weak user accounts..."

# --- Administrator account ---
Write-Warn "[INTENTIONAL VULN] Setting Administrator password to weak known value..."
try {
    $adminWeakPass = 'Password123!'
    net user Administrator $adminWeakPass /active:yes 2>&1 | Out-Null
    Append-Credential "[INTENTIONAL-WEAK] Administrator : $adminWeakPass  (intentionally weak for brute-force practice)"
    Write-Status "Administrator password set to weak value (intentional)."
} catch {
    Write-Warn "Administrator account setup error: $_"
}

# --- labuser (standard user) ---
Write-Warn "[INTENTIONAL VULN] Creating labuser with weak password..."
try {
    $labuserWeak = 'Summer2024!'
    $existingUser = Get-LocalUser -Name 'labuser' -ErrorAction SilentlyContinue
    if ($null -eq $existingUser) {
        New-LocalUser -Name 'labuser' `
            -Password (ConvertTo-SecureString $labuserWeak -AsPlainText -Force) `
            -FullName 'Lab User' `
            -Description 'Standard workstation user — intentionally weak password' `
            -PasswordNeverExpires $true `
            -UserMayNotChangePassword $false
        Add-LocalGroupMember -Group 'Users' -Member 'labuser' -ErrorAction SilentlyContinue
    } else {
        Set-LocalUser -Name 'labuser' `
            -Password (ConvertTo-SecureString $labuserWeak -AsPlainText -Force)
    }
    Append-Credential "[INTENTIONAL-WEAK] labuser      : $labuserWeak  (weak password — for lateral movement practice)"
    Write-Status "labuser created (intentional weak password)."
} catch {
    Write-Warn "labuser creation error: $_"
}

# --- serviceacct (standard user, for pass-the-hash practice) ---
Write-Warn "[INTENTIONAL VULN] Creating serviceacct with weak password (pass-the-hash target)..."
try {
    $svcWeakPass = 'Svc@2024'
    $existingSvc = Get-LocalUser -Name 'serviceacct' -ErrorAction SilentlyContinue
    if ($null -eq $existingSvc) {
        New-LocalUser -Name 'serviceacct' `
            -Password (ConvertTo-SecureString $svcWeakPass -AsPlainText -Force) `
            -FullName 'Service Account' `
            -Description 'Service account — intentionally weak for pass-the-hash practice' `
            -PasswordNeverExpires $true `
            -UserMayNotChangePassword $false
        Add-LocalGroupMember -Group 'Users' -Member 'serviceacct' -ErrorAction SilentlyContinue
    } else {
        Set-LocalUser -Name 'serviceacct' `
            -Password (ConvertTo-SecureString $svcWeakPass -AsPlainText -Force)
    }
    Append-Credential "[INTENTIONAL-WEAK] serviceacct  : $svcWeakPass  (weak — pass-the-hash practice)"
    Write-Status "serviceacct created (intentional weak password for PtH)."
} catch {
    Write-Warn "serviceacct creation error: $_"
}

# ---------------------------------------------------------------------------
# [8] Create network share (INTENTIONAL VULNERABILITY — EveryOne Full)
# ---------------------------------------------------------------------------
Write-Status "Creating intentionally open SMB share..."
try {
    $sharePath = 'C:\Shares\Data'
    if (-not (Test-Path $sharePath)) {
        New-Item -ItemType Directory -Path $sharePath -Force | Out-Null
    }
    # Remove existing share if present (idempotent)
    $existingShare = Get-SmbShare -Name 'Data' -ErrorAction SilentlyContinue
    if ($null -ne $existingShare) {
        Remove-SmbShare -Name 'Data' -Force
    }
    New-SmbShare -Name 'Data' -Path $sharePath -FullAccess 'Everyone' `
        -Description 'Intentionally open share — lab target'
    Write-Status "SMB share \\SCPS-WS01\Data created with Everyone Full Access (intentional)."
} catch {
    Write-Warn "SMB share creation error: $_"
}

# ---------------------------------------------------------------------------
# [9] Place interesting / lure files on the share
# ---------------------------------------------------------------------------
Write-Status "Placing lure files on share..."
try {
    $sharePath = 'C:\Shares\Data'

    # passwords.txt — fake credential file
    Set-Content -Path "$sharePath\passwords.txt" -Value @"
--- Company Passwords (DO NOT SHARE) ---
VPN:         vpnuser / V3ryS3cur3Pass!
Email:       jsmith@company.com / JohnSmith2024
Server:      srvadmin / AdminPass123
Database:    dbadmin / Db@Admin!2024
WiFi:        CompanyWiFi / WifiP@ss2024
Backup:      backupadmin / B@ckup2024!
"@

    # notes.txt — file referencing credentials
    Set-Content -Path "$sharePath\notes.txt" -Value @"
Meeting notes - Q4 2024
- Reminder: rotate passwords after Q4 (still using old ones)
- serviceacct password is Svc@2024 until IT gets around to changing
- Domain admin creds in the usual spot on the DC
- TODO: fix the shared drive permissions (marked as low priority)
- VPN credentials sent to all staff via email last week
- Lab server svc.backup still has domain admin — waiting on helpdesk ticket #4821
"@

    # config.xml — embedded fake credentials
    Set-Content -Path "$sharePath\config.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
    <Database>
        <Server>SCPS-DC01</Server>
        <Name>CorpDB</Name>
        <Username>dbsvc</Username>
        <!-- TODO: move password to secrets manager -->
        <Password>DbPa$$w0rd2024!</Password>
        <Port>1433</Port>
    </Database>
    <Email>
        <SmtpHost>mail.company.com</SmtpHost>
        <Username>noreply@company.com</Username>
        <Password>EmailSvc@2024</Password>
    </Email>
    <Backup>
        <RemoteHost>10.10.0.5</RemoteHost>
        <Username>backupadmin</Username>
        <Password>BackupPassw0rd!</Password>
    </Backup>
</Configuration>
"@

    Write-Status "Lure files placed in $sharePath."
} catch {
    Write-Warn "Lure file creation error: $_"
}

# ---------------------------------------------------------------------------
# [10] Place flag file on labuser Desktop
# ---------------------------------------------------------------------------
Write-Status "Placing flag file..."
try {
    $desktopPath = 'C:\Users\labuser\Desktop'
    if (-not (Test-Path $desktopPath)) {
        New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null
    }
    Set-Content -Path "$desktopPath\flag.txt" -Value "FLAG{lateral_movement_workstation_4d2c}"
    Write-Status "Flag file placed at $desktopPath\flag.txt."
} catch {
    Write-Warn "Flag file placement error: $_"
}

# ---------------------------------------------------------------------------
# [11] Install Chocolatey + tools
# ---------------------------------------------------------------------------
Write-Status "Installing Chocolatey..."
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Status "Chocolatey installed."
    } else {
        Write-Status "Chocolatey already installed."
    }

    # Refresh env so choco is available
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')

    Write-Status "Installing 7zip and Notepad++..."
    choco install 7zip notepadplusplus -y --no-progress 2>&1 | Out-Null
    Write-Status "Tools installed via Chocolatey."
} catch {
    Write-Warn "Chocolatey/tool install error: $_"
}

# ---------------------------------------------------------------------------
# [12] Disable automatic Windows Updates
# ---------------------------------------------------------------------------
Write-Status "Disabling automatic Windows Updates..."
try {
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (-not (Test-Path $wuPath)) {
        New-Item -Path $wuPath -Force | Out-Null
    }
    Set-ItemProperty -Path $wuPath -Name 'NoAutoUpdate'       -Value 1  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'AUOptions'          -Value 1  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'ScheduledInstallDay'-Value 0  -Type DWord

    # Stop and disable the Windows Update service
    Stop-Service  -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
    Set-Service   -Name 'wuauserv' -StartupType Disabled -ErrorAction SilentlyContinue

    Write-Status "Windows Update disabled."
} catch {
    Write-Warn "Windows Update disable error: $_"
}

# ---------------------------------------------------------------------------
# [13] Registry Run key persistence (INTENTIONAL VULNERABILITY — detection practice)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Adding registry Run key persistence example..."
try {
    $runPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $runPath -Name 'WindowsUpdate' `
        -Value 'C:\Windows\System32\cmd.exe /c echo persistence_example > C:\Windows\Temp\persist.txt' `
        -Type String
    # Also HKCU for user-level persistence example
    $hkcuRunPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $hkcuRunPath)) { New-Item -Path $hkcuRunPath -Force | Out-Null }
    Set-ItemProperty -Path $hkcuRunPath -Name 'Updater' `
        -Value 'C:\Windows\System32\cmd.exe /c whoami >> C:\Windows\Temp\user_persist.txt' `
        -Type String
    Write-Status "Registry persistence example added (intentional — for detection lab)."
} catch {
    Write-Warn "Registry run key error: $_"
}

# ---------------------------------------------------------------------------
# [14] Configure AutoRun for USB (INTENTIONAL VULNERABILITY)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Enabling AutoRun for USB drives..."
try {
    # Remove AutoRun restrictions
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -Name 'NoDriveTypeAutoRun' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\IniFileMapping\Autorun.inf' `
        -Name '(Default)' -Value '' -Type String -ErrorAction SilentlyContinue
    # Enable AutoPlay
    $autoPlayPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (-not (Test-Path $autoPlayPath)) { New-Item -Path $autoPlayPath -Force | Out-Null }
    Set-ItemProperty -Path $autoPlayPath -Name 'NoAutoplayfornonVolume' -Value 0 -Type DWord
    Write-Status "AutoRun/AutoPlay enabled for USB (intentional — social engineering lab)."
} catch {
    Write-Warn "AutoRun config error: $_"
}

# ---------------------------------------------------------------------------
# [15] Create weak scheduled task (INTENTIONAL VULNERABILITY — priv esc practice)
# ---------------------------------------------------------------------------
Write-Warn "[INTENTIONAL VULN] Creating weak scheduled task BackupTask running as SYSTEM..."
try {
    $existingTask = Get-ScheduledTask -TaskName 'BackupTask' -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) {
        Unregister-ScheduledTask -TaskName 'BackupTask' -Confirm:$false
    }

    $action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c "echo backup >> C:\Windows\Temp\backup.log"'
    $trigger   = New-ScheduledTaskTrigger -Daily -At '03:00'
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName 'BackupTask' `
        -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description 'Daily backup task (intentionally misconfigured — weak binary path, SYSTEM context)' `
        -Force

    # Make the task folder world-writable (allows task hijacking — intentional vuln)
    $taskPath = 'C:\Windows\System32\Tasks'
    icacls "$taskPath\BackupTask" /grant "BUILTIN\Users:(F)" 2>&1 | Out-Null

    Write-Status "Weak scheduled task BackupTask registered (SYSTEM, world-writable — intentional priv esc)."
} catch {
    Write-Warn "Scheduled task creation error: $_"
}

# ---------------------------------------------------------------------------
# [16] Install .NET 3.5 (required for older exploit payloads)
# ---------------------------------------------------------------------------
Write-Status "Installing .NET Framework 3.5..."
try {
    $dotnet35 = Get-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -ErrorAction SilentlyContinue
    if ($null -eq $dotnet35 -or $dotnet35.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -FeatureName 'NetFx3' -Online -NoRestart -ErrorAction SilentlyContinue
        Write-Status ".NET Framework 3.5 installed."
    } else {
        Write-Status ".NET Framework 3.5 already enabled."
    }
} catch {
    Write-Warn ".NET 3.5 install error (may require Windows media): $_"
}

# ---------------------------------------------------------------------------
# [17] Finalise credentials file
# ---------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== INTENTIONAL VULNERABILITIES SUMMARY ==="
Append-Credential "- Windows Defender: DISABLED"
Append-Credential "- SmartScreen: DISABLED"
Append-Credential "- Windows Firewall: DISABLED"
Append-Credential "- SMBv1: ENABLED"
Append-Credential "- WinRM: ENABLED (basic auth, unencrypted)"
Append-Credential "- RDP: ENABLED (no NLA)"
Append-Credential "- AutoRun/AutoPlay: ENABLED"
Append-Credential "- Registry persistence: RUN key (HKLM + HKCU)"
Append-Credential "- Scheduled task BackupTask: SYSTEM, world-writable"
Append-Credential ""
Append-Credential "=== NETWORK SHARE ==="
Append-Credential "\\SCPS-WS01\Data -> C:\Shares\Data (Everyone: Full)"
Append-Credential ""
Append-Credential "=== FLAG ==="
Append-Credential "C:\Users\labuser\Desktop\flag.txt : FLAG{lateral_movement_workstation_4d2c}"

Write-Status "credentials.txt written to $credFile."

# ---------------------------------------------------------------------------
# [18] Cleanup — clear event logs, PSReadLine history, zero free space, shutdown
# ---------------------------------------------------------------------------
Write-Status "Clearing event logs..."
try {
    Clear-EventLog -LogName Application -ErrorAction SilentlyContinue
    Clear-EventLog -LogName System      -ErrorAction SilentlyContinue
    Clear-EventLog -LogName Security    -ErrorAction SilentlyContinue
    wevtutil cl 'Microsoft-Windows-PowerShell/Operational' 2>&1 | Out-Null
    wevtutil cl 'Microsoft-Windows-Sysmon/Operational'     2>&1 | Out-Null
    Write-Status "Event logs cleared."
} catch {
    Write-Warn "Event log clear error: $_"
}

Write-Status "Clearing PowerShell history..."
try {
    $histPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    Remove-Item -Path $histPath -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue
    Write-Status "PowerShell history cleared."
} catch {
    Write-Warn "PSReadLine history clear error: $_"
}

# Zero free space to reduce disk image size (sdelete-style via cipher)
Write-Status "Zeroing free disk space (this may take several minutes)..."
try {
    cipher /w:C:\ 2>&1 | Out-Null
    Write-Status "Free space zeroed."
} catch {
    Write-Warn "Free space zero error: $_"
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Build-Windows10Vulnerable.ps1 completed successfully." -ForegroundColor Green
Write-Host " Shutting down in 10 seconds..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

Stop-Transcript
Start-Sleep -Seconds 10
Stop-Computer -Force
