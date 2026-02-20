# Windows Server 2019 — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `windows-server-2019` |
| **VHDX path** | `C:\CyberLab\Templates\windows-server-2019.vhdx` |
| **Used in** | Lab 4 (Network Attack & Defense — hardened internal server target) |
| **Role** | Moderately hardened Windows Server with IIS; internal target behind the VyOS router |
| **Build script** | None — built manually |
| **Resources** | 2 vCPU, 4 GB RAM, 60 GB dynamic VHDX |
| **Base OS** | Windows Server 2019 Standard (Desktop Experience) |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Security Controls Applied](#4-security-controls-applied)
5. [IIS Configuration](#5-iis-configuration)
6. [Network Interfaces](#6-network-interfaces)
7. [Default Credentials After Build](#7-default-credentials-after-build)
8. [Verification Steps](#8-verification-steps)
9. [Snapshot and Storage](#9-snapshot-and-storage)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

- Windows Server 2019 ISO (Volume Licensing / MSDN / Evaluation: `https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019`)
- Build time: approximately 50–60 minutes

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **4096 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **60 GB**, Dynamically expanding |
| Network adapter | External-Internet (for Windows updates during build) |

---

## 3. OS Installation

| Setting | Value |
|---------|-------|
| Edition | Windows Server 2019 Standard (Desktop Experience) |
| Install type | Custom full disk install |
| Computer name | `SCPS-SRV01` |
| Administrator password | `LabBuildPass!2024` (overridden at deploy) |

After installation: rename, set timezone, and run Windows Update (this server should be patched — unlike the vulnerable image):

```powershell
Rename-Computer -NewName "SCPS-SRV01" -Force
Set-TimeZone -Id "Eastern Standard Time"

# Install all available Windows updates (important — this is a hardened server)
Install-Module PSWindowsUpdate -Force
Get-WindowsUpdate -Install -AcceptAll -AutoReboot
```

---

## 4. Security Controls Applied

This server represents a reasonably hardened internal server. The security controls below are applied during the build and represent the defensive baseline students should use when writing the Lab 4 hardening report.

| Control | Implementation | Command / Setting |
|---------|---------------|-----------------|
| **Windows Firewall enabled** | All profiles active; only required ports open | `Set-NetFirewallProfile -Enabled True` |
| **WinRM restricted** | WinRM enabled but limited to management subnet only | Firewall rule scoped to admin IP range |
| **RDP with NLA** | Remote Desktop enabled with Network Level Authentication | `UserAuthentication=1` |
| **Password policy** | Minimum 12 chars, complexity required, 90-day max age | `secedit.exe` + GPO |
| **Account lockout** | 5 failed attempts → 30 min lockout | Local security policy |
| **Auditing enabled** | Logon, privilege use, object access, process creation | `auditpol /set ...` |
| **SMBv1 disabled** | Legacy SMB protocol disabled | `Set-SmbServerConfiguration -EnableSMB1Protocol $false` |
| **Guest account disabled** | Built-in Guest not usable | `net user Guest /active:no` |
| **Defender active** | Windows Defender running with signatures updated | Default (not disabled) |
| **No unnecessary services** | Bluetooth, Print Spooler (if not needed), Xbox services disabled | Service Manager |
| **TLS 1.0/1.1 disabled** | Registry keys to disable old TLS versions on IIS | Schannel registry settings |

### Apply Security Controls

```powershell
# Firewall: enable all profiles, specific rules below
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
New-NetFirewallRule -DisplayName "Allow HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "Allow HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
New-NetFirewallRule -DisplayName "Allow WinRM HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow

# Disable SMBv1
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

# Enable NLA for RDP
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name "UserAuthentication" -Value 1

# Disable Guest account
net user Guest /active:no

# Audit policy
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /failure:enable
auditpol /set /subcategory:"Process Creation" /success:enable
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable

# Disable TLS 1.0 and 1.1
$tlsPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server",
    "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server"
)
foreach ($path in $tlsPaths) {
    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name "Enabled" -Value 0 -Type DWord
    Set-ItemProperty -Path $path -Name "DisabledByDefault" -Value 1 -Type DWord
}

# Account lockout policy via secedit
$cfgFile = "C:\Temp\secpol.cfg"
secedit /export /cfg $cfgFile
(Get-Content $cfgFile) -replace "LockoutBadCount = .*", "LockoutBadCount = 5" |
    Set-Content $cfgFile
(Get-Content $cfgFile) -replace "ResetLockoutCount = .*", "ResetLockoutCount = 30" |
    Set-Content $cfgFile
(Get-Content $cfgFile) -replace "LockoutDuration = .*", "LockoutDuration = 30" |
    Set-Content $cfgFile
secedit /configure /db "C:\Windows\security\local.sdb" /cfg $cfgFile /areas SECURITYPOLICY
```

---

## 5. IIS Configuration

Install and harden IIS to serve as a realistic internal web server:

```powershell
# Install IIS with commonly used features
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Http-Logging, `
    Web-Request-Monitor, Web-Static-Content, Web-Default-Doc, `
    Web-Http-Errors, Web-Mgmt-Console, Web-Windows-Auth -IncludeManagementTools

# Create a simple internal intranet page
$webroot = "C:\inetpub\wwwroot"
Set-Content -Path "$webroot\index.html" -Value @"
<!DOCTYPE html>
<html>
<head><title>SCPS Internal Server</title></head>
<body>
<h1>Internal Server — Authorized Access Only</h1>
<p>Server: SCPS-SRV01 | Windows Server 2019</p>
<p>This is an internal server for the SCPS CyberLab Lab 4 exercise.</p>
</body>
</html>
"@

# Harden IIS
# Remove server header (version disclosure)
Import-Module WebAdministration
Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/security/requestFiltering" -name "removeServerHeader" -value "True"

# Disable directory browsing
Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/directoryBrowse" -name "enabled" -value "False"

# Add security headers
Add-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/httpProtocol/customHeaders" -name "." `
    -value @{name="X-Frame-Options"; value="SAMEORIGIN"}
Add-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/httpProtocol/customHeaders" -name "." `
    -value @{name="X-Content-Type-Options"; value="nosniff"}

# Enable Windows Authentication for the site
Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/security/authentication/windowsAuthentication" -name "enabled" -value "True"
Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/security/authentication/anonymousAuthentication" -name "enabled" -value "False"

# Verify IIS is running
Get-Service W3SVC
```

---

## 6. Network Interfaces

Single adapter. In Lab 4, connected to `internal-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.21`. This places it behind the VyOS router, accessible from the Kali attacker only after traversing the network topology.

---

## 7. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `Administrator` | `LabBuildPass!2024` (overridden at deploy) | Local administrator |

---

## 8. Verification Steps

### Step 1 — IIS Running

```powershell
Get-Service W3SVC | Select-Object Name, Status
# Expected: Running
Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing | Select-Object StatusCode
# Expected: 401 (Windows Auth — expected; anonymous auth is disabled)
```

### Step 2 — SMBv1 Disabled

```powershell
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol
# Expected: False
```

### Step 3 — Firewall Enabled

```powershell
Get-NetFirewallProfile | Select-Object Name, Enabled
# Expected: All profiles showing Enabled=True
```

### Step 4 — Defender Running

```powershell
Get-Service WinDefend | Select-Object Name, Status
# Expected: Running
```

---

## 9. Snapshot and Storage

```powershell
Stop-VM -Name "winserv2019-build" -Force
Move-Item "winserv2019-build.vhdx" "C:\CyberLab\Templates\windows-server-2019.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\windows-server-2019.vhdx" -Name IsReadOnly -Value $true
```

---

## 10. Troubleshooting

### IIS Returning 401 Instead of the Page

**Expected:** For the internal intranet page, 401 is correct because anonymous authentication is disabled. Students will need to provide Windows credentials to access the page.

If you want the page to be publicly accessible (no auth), re-enable anonymous authentication:

```powershell
Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST" `
    -filter "system.webServer/security/authentication/anonymousAuthentication" -name "enabled" -value "True"
```

### Windows Update Causes Extended Build Time

Windows Server 2019 may have a large update backlog on first install. Allow 60–90 minutes for initial patching. After patching, run:

```powershell
Get-WindowsUpdate | Measure-Object
# If 0 updates remaining, the system is current
```
