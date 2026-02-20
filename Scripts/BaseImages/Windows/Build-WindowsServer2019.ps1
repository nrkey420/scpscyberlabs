#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for windows-server-2019 base image.

.DESCRIPTION
    Image Name    : windows-server-2019
    Purpose       : Standard Windows Server 2019 for Network Attack & Defense lab (Lab 4).
                    Representative hardened server — students practice defense.
                    Hosts IIS web application; monitored by Splunk.
    Base OS       : Windows Server 2019 Standard
    Lab           : Lab 4 — Network Attack & Defense
    Security Level: STANDARD (hardened — not intentionally vulnerable)
    IP            : 10.CLASS_ID.0.21 (set at deploy time)
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

.NOTES
    Run as Administrator after OS installation and Hyper-V integration services.
    No reboot required during build (IIS installation may prompt reboot — suppressed here).
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
Write-Host " SCPS CyberLab — Build-WindowsServer2019.ps1" -ForegroundColor Cyan
Write-Host " Image  : windows-server-2019" -ForegroundColor Cyan
Write-Host " Lab    : Lab 4 — Network Attack & Defense (hardened server)" -ForegroundColor Cyan
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
Append-Credential " SCPS CyberLab — windows-server-2019 credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: STANDARD (hardened)"
Append-Credential "============================================================"
Append-Credential ""

$adminPass    = New-RandomPassword -Length 20
$sysadminPass = New-RandomPassword -Length 20
$svcAcctPass  = New-RandomPassword -Length 20

Append-Credential "[SECURE] Administrator : $adminPass"
Append-Credential "[SECURE] sysadmin      : $sysadminPass"
Append-Credential "[SECURE] svcaccount    : $svcAcctPass"
Append-Credential ""

$tempDir = 'C:\Temp'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# [1] Computer name
# ---------------------------------------------------------------------------
Write-Status "Setting computer name to SCPS-SRV01..."
try {
    Rename-Computer -NewName 'SCPS-SRV01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set."
} catch { Write-Warn "Rename failed: $_" }

# ---------------------------------------------------------------------------
# [2] Configure accounts
# ---------------------------------------------------------------------------
Write-Status "Configuring accounts..."
try {
    net user Administrator $adminPass /active:yes 2>&1 | Out-Null
    Write-Status "Administrator password set."

    # sysadmin — local administrator
    $existingSysadmin = Get-LocalUser -Name 'sysadmin' -ErrorAction SilentlyContinue
    if ($null -eq $existingSysadmin) {
        New-LocalUser -Name 'sysadmin' `
            -Password (ConvertTo-SecureString $sysadminPass -AsPlainText -Force) `
            -FullName 'System Administrator' `
            -Description 'Lab system administrator account' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Administrators' -Member 'sysadmin'
    } else {
        Set-LocalUser -Name 'sysadmin' -Password (ConvertTo-SecureString $sysadminPass -AsPlainText -Force)
    }
    Write-Status "sysadmin account configured."

    # svcaccount — standard user (service account)
    $existingSvc = Get-LocalUser -Name 'svcaccount' -ErrorAction SilentlyContinue
    if ($null -eq $existingSvc) {
        New-LocalUser -Name 'svcaccount' `
            -Password (ConvertTo-SecureString $svcAcctPass -AsPlainText -Force) `
            -FullName 'Service Account' `
            -Description 'Generic service account — limited privileges' `
            -PasswordNeverExpires $true
        Add-LocalGroupMember -Group 'Users' -Member 'svcaccount'
    } else {
        Set-LocalUser -Name 'svcaccount' -Password (ConvertTo-SecureString $svcAcctPass -AsPlainText -Force)
    }
    Write-Status "svcaccount configured."
} catch { Write-Warn "Account setup error: $_" }

# ---------------------------------------------------------------------------
# [3] Disable unnecessary services
# ---------------------------------------------------------------------------
Write-Status "Disabling unnecessary services..."
$servicesToDisable = @('Spooler', 'RemoteRegistry', 'bthserv', 'WSearch', 'XblAuthManager',
                       'XblGameSave', 'XboxNetApiSvc', 'RetailDemo')
foreach ($svcName in $servicesToDisable) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($null -ne $svc) {
            Stop-Service  -Name $svcName -Force -ErrorAction SilentlyContinue
            Set-Service   -Name $svcName -StartupType Disabled
            Write-Status "Service $svcName disabled."
        }
    } catch { Write-Warn "Could not disable $svcName : $_" }
}

# ---------------------------------------------------------------------------
# [4] Enable RDP with NLA required
# ---------------------------------------------------------------------------
Write-Status "Enabling RDP with NLA..."
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
        -Name 'fDenyTSConnections' -Value 0 -Type DWord
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -Value 1 -Type DWord   # 1 = NLA required
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    Write-Status "RDP enabled with NLA."
} catch { Write-Warn "RDP setup error: $_" }

# ---------------------------------------------------------------------------
# [5] Enable WinRM with HTTPS only
# ---------------------------------------------------------------------------
Write-Status "Configuring WinRM (HTTPS only)..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    # Disable HTTP listener; leave only HTTPS
    Remove-WSManInstance -ResourceURI 'winrm/config/listener' `
        -SelectorSet @{Transport='HTTP'; Address='*'} -ErrorAction SilentlyContinue

    # Create self-signed cert for WinRM HTTPS
    $winrmCert = New-SelfSignedCertificate -DnsName 'SCPS-SRV01' `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -NotAfter (Get-Date).AddYears(5)

    $existingHttps = Get-WSManInstance -ResourceURI 'winrm/config/listener' `
        -SelectorSet @{Transport='HTTPS'; Address='*'} -ErrorAction SilentlyContinue
    if ($null -eq $existingHttps) {
        New-WSManInstance -ResourceURI 'winrm/config/listener' `
            -SelectorSet @{Transport='HTTPS'; Address='*'} `
            -ValueSet @{Hostname='SCPS-SRV01'; CertificateThumbprint=$winrmCert.Thumbprint}
    }

    # Harden WinRM: no basic auth, no unencrypted
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic      -Value $false
    Set-Item -Path WSMan:\localhost\Service\Auth\Certificate -Value $false
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true
    Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos    -Value $true

    Write-Status "WinRM configured (HTTPS only, 5986)."
} catch { Write-Warn "WinRM HTTPS config error: $_" }

# ---------------------------------------------------------------------------
# [6] Windows Firewall — strict rules
# ---------------------------------------------------------------------------
Write-Status "Configuring Windows Firewall strict rules..."
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -DefaultInboundAction Block `
        -DefaultOutboundAction Allow

    # Remove default allow rules that are too permissive
    Disable-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue
    Disable-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction SilentlyContinue

    # Internal network — adjust at deploy time to match actual class subnet
    $internalSubnet = '10.0.0.0/8'

    # Allow RDP (3389) from internal only
    New-NetFirewallRule -DisplayName 'Allow-RDP-Internal' -Direction Inbound `
        -Protocol TCP -LocalPort 3389 -RemoteAddress $internalSubnet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow WinRM HTTPS (5986) from internal only
    New-NetFirewallRule -DisplayName 'Allow-WinRM-HTTPS-Internal' -Direction Inbound `
        -Protocol TCP -LocalPort 5986 -RemoteAddress $internalSubnet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow HTTP (80) and HTTPS (443) from internal only
    New-NetFirewallRule -DisplayName 'Allow-HTTP-Internal' -Direction Inbound `
        -Protocol TCP -LocalPort 80 -RemoteAddress $internalSubnet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'Allow-HTTPS-Internal' -Direction Inbound `
        -Protocol TCP -LocalPort 443 -RemoteAddress $internalSubnet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow Splunk forwarder outbound
    New-NetFirewallRule -DisplayName 'Allow-Splunk-UF-Out' -Direction Outbound `
        -Protocol TCP -RemotePort 9997 `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    # Allow ICMP (ping) from internal for diagnostics
    New-NetFirewallRule -DisplayName 'Allow-ICMP-Internal' -Direction Inbound `
        -Protocol ICMPv4 -RemoteAddress $internalSubnet `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue

    Write-Status "Strict firewall rules configured."
} catch { Write-Warn "Firewall rule error: $_" }

# ---------------------------------------------------------------------------
# [7] Enhanced audit policy
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
        'auditpol /set /subcategory:"Special Logon" /success:enable',
        'auditpol /set /subcategory:"Other Logon/Logoff Events" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable',
        'auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security System Extension" /success:enable',
        'auditpol /set /subcategory:"IPsec Driver" /success:enable /failure:enable'
    )
    foreach ($cmd in $auditCmds) { Invoke-Expression $cmd 2>&1 | Out-Null }
    $procAuditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $procAuditPath)) { New-Item -Path $procAuditPath -Force | Out-Null }
    Set-ItemProperty -Path $procAuditPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord
    Write-Status "Enhanced audit policy configured."
} catch { Write-Warn "Audit policy error: $_" }

# ---------------------------------------------------------------------------
# [8] PowerShell Script Block Logging and Module Logging
# ---------------------------------------------------------------------------
Write-Status "Enabling PowerShell logging..."
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
# [9] Install Sysmon with SwiftOnSecurity config
# ---------------------------------------------------------------------------
Write-Status "Installing Sysmon..."
try {
    $sysmonDir    = 'C:\Tools\Sysmon'
    $sysmonZip    = "$tempDir\Sysmon.zip"
    $sysmonConfig = "$sysmonDir\sysmonconfig.xml"
    $sysmonExe    = "$sysmonDir\Sysmon64.exe"
    if (-not (Test-Path $sysmonDir)) { New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null }
    if (-not (Test-Path $sysmonExe)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' `
            -OutFile $sysmonZip -UseBasicParsing
        Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
    }
    if (-not (Test-Path $sysmonConfig)) {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml' `
            -OutFile $sysmonConfig -UseBasicParsing
    }
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
# [10] Install IIS with self-signed HTTPS certificate
# ---------------------------------------------------------------------------
Write-Status "Installing IIS..."
try {
    Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Default-Doc, Web-Dir-Browsing,
        Web-Http-Errors, Web-Static-Content, Web-Http-Logging, Web-Request-Monitor,
        Web-Filtering, Web-Stat-Compression, Web-Mgmt-Console, Web-Scripting-Tools `
        -IncludeManagementTools -ErrorAction Stop
    Write-Status "IIS installed."

    # Create self-signed cert for IIS HTTPS
    $iisCert = New-SelfSignedCertificate -DnsName 'SCPS-SRV01' `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -NotAfter (Get-Date).AddYears(5)

    # Bind HTTPS on port 443 using the cert
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $existingHttpsBinding = Get-WebBinding -Name 'Default Web Site' -Protocol 'https' -ErrorAction SilentlyContinue
    if ($null -eq $existingHttpsBinding) {
        New-WebBinding -Name 'Default Web Site' -Protocol 'https' -Port 443 -IPAddress '*'
    }
    $cert = Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { $_.Subject -like '*SCPS-SRV01*' } | Select-Object -First 1
    if ($null -ne $cert) {
        $binding = Get-WebBinding -Name 'Default Web Site' -Protocol 'https'
        $binding.AddSslCertificate($cert.GetCertHashString(), 'My')
    }
    Write-Status "IIS HTTPS binding created with self-signed certificate."

    # Simple web page
    Set-Content -Path 'C:\inetpub\wwwroot\index.html' -Value @"
<!DOCTYPE html>
<html>
<head><title>SCPS Internal Server</title></head>
<body>
    <h1>SCPS Internal Server</h1>
    <p>This server is part of the SCPS CyberLab network.</p>
    <p>Authorized access only. All access is monitored and logged.</p>
    <p>Server: SCPS-SRV01</p>
</body>
</html>
"@
    # Restart IIS
    iisreset /restart 2>&1 | Out-Null
    Write-Status "IIS web page deployed."
} catch { Write-Warn "IIS install/config error: $_" }

# ---------------------------------------------------------------------------
# [11] Configure Windows Update — schedule without auto-install
# ---------------------------------------------------------------------------
Write-Status "Configuring Windows Update (scheduled, not auto-install)..."
try {
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    # 3 = Auto download and notify for install (student manually approves)
    Set-ItemProperty -Path $wuPath -Name 'NoAutoUpdate'                  -Value 0  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'AUOptions'                     -Value 3  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'ScheduledInstallDay'            -Value 0  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'ScheduledInstallTime'           -Value 3  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'AutoInstallMinorUpdates'        -Value 0  -Type DWord
    Set-ItemProperty -Path $wuPath -Name 'NoAutoRebootWithLoggedOnUsers'  -Value 1  -Type DWord
    Write-Status "Windows Update set to download-only (students approve install)."
} catch { Write-Warn "Windows Update config error: $_" }

# ---------------------------------------------------------------------------
# [12] Install Splunk Universal Forwarder
# ---------------------------------------------------------------------------
Write-Status "Installing Splunk Universal Forwarder..."
$splunkIndexerIP   = '10.CLASS_ID.0.51'
$splunkIndexerPort = '9997'
$splunkInstallDir  = 'C:\Program Files\SplunkUniversalForwarder'
$splunkMsi         = "$tempDir\splunkforwarder.msi"
try {
    if (-not (Test-Path "$splunkInstallDir\bin\splunk.exe")) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -Uri 'https://download.splunk.com/products/universalforwarder/releases/9.2.1/windows/splunkforwarder-9.2.1-78803f08aabb-x64-release.msi' `
            -OutFile $splunkMsi -UseBasicParsing
        $splunkPass = New-RandomPassword -Length 20
        Append-Credential "[SECURE] SplunkForwarder admin : $splunkPass"
        Start-Process msiexec.exe -Wait -ArgumentList @(
            '/i', $splunkMsi,
            'INSTALLDIR="C:\Program Files\SplunkUniversalForwarder"',
            "SPLUNKUSERNAME=admin", "SPLUNKPASSWORD=$splunkPass",
            "RECEIVING_INDEXER=${splunkIndexerIP}:${splunkIndexerPort}",
            'WINEVENTLOG_SEC_ENABLE=1', 'WINEVENTLOG_SYS_ENABLE=1',
            'WINEVENTLOG_APP_ENABLE=1', 'AGREETOLICENSE=Yes', '/qn'
        )
    }
    $splunkLocalDir = "$splunkInstallDir\etc\system\local"
    if (-not (Test-Path $splunkLocalDir)) { New-Item -ItemType Directory -Path $splunkLocalDir -Force | Out-Null }
    Set-Content -Path "$splunkLocalDir\outputs.conf" -Value @"
[tcpout]
defaultGroup = scps_indexers

[tcpout:scps_indexers]
server = ${splunkIndexerIP}:${splunkIndexerPort}
compressed = true
"@
    Set-Content -Path "$splunkLocalDir\inputs.conf" -Value @"
[WinEventLog://Application]
disabled = 0
[WinEventLog://Security]
disabled = 0
[WinEventLog://System]
disabled = 0
[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
renderXml = true
[WinEventLog://Microsoft-Windows-PowerShell/Operational]
disabled = 0

[monitor://C:\inetpub\logs\LogFiles]
disabled = 0
index = iis
sourcetype = iis
"@
    Start-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue
    Write-Status "Splunk UF configured (→ $splunkIndexerIP:$splunkIndexerPort)."
} catch { Write-Warn "Splunk UF install/config error: $_" }

# ---------------------------------------------------------------------------
# [13] Finalize credentials file
# ---------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== CONFIGURATION SUMMARY ==="
Append-Credential "- Sysmon : INSTALLED (SwiftOnSecurity config)"
Append-Credential "- Audit  : ENHANCED (full subcategory set)"
Append-Credential "- PSLog  : Script block + module logging ENABLED"
Append-Credential "- WinRM  : HTTPS only (5986)"
Append-Credential "- RDP    : ENABLED with NLA (3389)"
Append-Credential "- IIS    : HTTP + HTTPS (self-signed cert)"
Append-Credential "- Firewall: STRICT — internal subnet only"
Append-Credential "- Splunk : UF → ${splunkIndexerIP}:${splunkIndexerPort}"
Append-Credential "- WinUpdate: Download-and-notify (no auto-install)"
Append-Credential "- Services disabled: Spooler, RemoteRegistry, Bluetooth, WSearch"
Write-Status "credentials.txt written."

# ---------------------------------------------------------------------------
# [14] Cleanup — clear logs, history, zero space, shutdown
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

Write-Status "Zeroing free disk space..."
try { cipher /w:C:\ 2>&1 | Out-Null } catch { Write-Warn "cipher /w error: $_" }

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Build-WindowsServer2019.ps1 completed successfully." -ForegroundColor Green
Write-Host " Shutting down in 10 seconds..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

Stop-Transcript
Start-Sleep -Seconds 10
Stop-Computer -Force
