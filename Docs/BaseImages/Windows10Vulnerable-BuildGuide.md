# Windows 10 Vulnerable — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `windows-10-vulnerable` |
| **VHDX path** | `C:\CyberLab\Templates\windows-10-vulnerable.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team — primary Windows attack target) |
| **Role** | Intentionally vulnerable Windows 10 workstation |
| **Build script** | `Scripts/BaseImages/Windows/Build-Windows10Vulnerable.ps1` |
| **Script runs** | Inside the VM as Administrator, after OS installation |
| **Resources** | 2 vCPU, 4 GB RAM, 60 GB dynamic VHDX |
| **Base OS** | Windows 10 Enterprise 21H2 (amd64) |

> **WARNING:** This VM contains intentional security vulnerabilities for educational purposes. Every weakness documented below is deliberate. This VM must never be connected to production networks, internet-facing infrastructure, or any environment where live corporate data exists. It is designed to be attacked — deploy only within isolated Hyper-V private virtual switches.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Running the Build Script](#4-running-the-build-script)
5. [Intentional Vulnerability Inventory](#5-intentional-vulnerability-inventory)
6. [What the Script Configures](#6-what-the-script-configures)
7. [Network Interfaces](#7-network-interfaces)
8. [Default Credentials After Build](#8-default-credentials-after-build)
9. [Verification Steps](#9-verification-steps)
10. [Snapshot and Storage](#10-snapshot-and-storage)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

### ISO and License

Windows 10 Enterprise 21H2 ISO is available through Microsoft Volume Licensing, MSDN, or evaluation downloads from the Microsoft Evaluation Center.

```
URL (Evaluation): https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise
Edition: Windows 10 Enterprise (21H2 or later)
Architecture: x64
```

The evaluation edition is fully functional for 90 days without activation, which is sufficient for lab purposes.

### Host Requirements

- At least 80 GB free disk space for the build VM.
- Internet connectivity for the VM (Chocolatey installation and tool downloads).
- Build time: approximately 45–60 minutes.

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **4096 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **60 GB**, Dynamically expanding |
| Network adapter | External-Internet |
| Secure Boot | **Leave enabled** (Windows 10 supports Secure Boot) |

---

## 3. OS Installation

Boot from the Windows 10 Enterprise ISO. Use these settings:

| Setting | Value |
|---------|-------|
| Language | English (United States) |
| Edition | Windows 10 Enterprise |
| Install type | Custom: Install Windows only |
| Partition | Install to unallocated space (full disk) |
| Account setup | Local account — use "I don't have internet" option to avoid Microsoft account requirement |
| Username | `labuser` |
| Password | Set a temporary password (overwritten by script) |
| Privacy settings | Accept defaults or disable all — the VM is not production |

After first boot, log in as `labuser` and then switch to the built-in `Administrator` account. The build script requires the Administrator account.

### Enable and Set Administrator Password

```powershell
# Open an elevated PowerShell prompt (Win+X > Windows PowerShell (Admin))
net user Administrator /active:yes
net user Administrator TemporaryBuildPass!
# Log off labuser and log in as Administrator
```

---

## 4. Running the Build Script

Transfer the script to the VM using one of these methods:

**Method 1 — USB or ISO-attached file:**

Create a small ISO from the Scripts directory and mount it in Hyper-V (Media > Insert Disk).

**Method 2 — Hyper-V File Copy (Guest Services must be enabled):**

```powershell
# On the Hyper-V host
Enable-VMIntegrationService -VMName "win10vuln-build" -Name "Guest Service Interface"
Copy-VMFile -VMName "win10vuln-build" `
    -SourcePath "Scripts\BaseImages\Windows\Build-Windows10Vulnerable.ps1" `
    -DestinationPath "C:\LabBuild\Build-Windows10Vulnerable.ps1" `
    -FileSource Host -CreateFullPath
```

**Execute the script inside the VM** (as Administrator in an elevated PowerShell session):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
C:\LabBuild\Build-Windows10Vulnerable.ps1
```

The script runs a PowerShell transcript to `C:\LabBuild\build.log`. All actions are logged. The VM shuts down automatically when the script completes (after a 10-second countdown).

---

## 5. Intentional Vulnerability Inventory

Every vulnerability in this table was placed deliberately. This table is the authoritative reference for instructors and should be used when designing the attack and detection exercises for Lab 1.

| Vulnerability | CVE / Technique | Configuration Detail | Educational Purpose | Student Detection Method |
|--------------|----------------|---------------------|-------------------|------------------------|
| **SMBv1 enabled** | EternalBlue (MS17-010) | `Enable-WindowsOptionalFeature -FeatureName SMB1Protocol`; Registry key `HKLM:\SYSTEM\...\Services\LanmanServer\Parameters SMB1=1` | Demonstrates how a legacy protocol with no support remains exploitable years after patches exist | `nmap --script smb-vuln-ms17-010 <IP>` or `Get-SmbServerConfiguration \| Select EnableSMB1Protocol` |
| **Windows Defender disabled** | Payload execution without AV detection | `Set-MpPreference -DisableRealtimeMonitoring $true`; Registry policy `DisableAntiSpyware=1`; WinDefend service `Start=4` (Disabled) | Shows the consequence of disabled endpoint protection; enables payload execution without evasion | Windows Security Center shows red warnings; `Get-MpPreference \| Select DisableRealtimeMonitoring` |
| **SmartScreen disabled** | Malware download execution | Registry `EnableSmartScreen=0` | Removes the download-based warning prompt | Windows Security Center; `Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" EnableSmartScreen` |
| **Windows Firewall disabled** | Port exposure, no packet filtering | `Set-NetFirewallProfile -Enabled False` | Exposes all open ports without filtering | `netsh advfirewall show allprofiles state`; nmap full port scan shows all ports reachable |
| **WinRM enabled (weak config)** | Lateral movement / remote execution | `Enable-PSRemoting -Force`; `AllowUnencrypted=true`; Basic auth enabled | Demonstrates WinRM as a lateral movement vector; shows risks of unencrypted remote management | `netstat -an \| findstr 5985`; `Get-Service WinRM`; `winrm get winrm/config/service` |
| **RDP without NLA** | Credential exposure, BlueKeep surface | `fDenyTSConnections=0`; `UserAuthentication=0` (disables Network Level Authentication) | Allows RDP without pre-authentication; makes pass-the-hash and credential brute force easier | Port 3389 open in nmap; `Get-ItemProperty "HKLM:\...WinStations\RDP-Tcp" UserAuthentication` |
| **Weak Administrator password** | Credential attacks (brute force, pass-the-hash) | `Password123!` set via `net user Administrator` | Demonstrates password policy importance; enables brute force completion | Password audit tools (CrackMapExec, Hydra); SMB share access |
| **labuser weak password** | Credential attacks | `Summer2024!` | Lateral movement via credential reuse | Same as above |
| **serviceacct weak password** | Pass-the-hash practice | `Svc@2024` | Demonstrates service account risk | CrackMapExec spray; local account enumeration |
| **SMB share "Data" — Everyone Full** | Data exfiltration target | `New-SmbShare -Name Data -FullAccess Everyone` | Shows share permission risks; enables unauthenticated data access | `Get-SmbShare`; `net view \\SCPS-WS01` |
| **Lure files on the Data share** | Credential harvest via planted files | `passwords.txt`, `notes.txt`, `config.xml` with realistic fake credentials | Students practice finding and extracting credentials from exposed shares | Manual review after mounting share |
| **Registry Run key persistence** | Persistence mechanism (MITRE T1547.001) | HKLM and HKCU Run keys with `WindowsUpdate` and `Updater` names | Teaches registry-based persistence detection | `reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` |
| **Scheduled task BackupTask — SYSTEM** | Privilege escalation (MITRE T1053.005) | Task runs as SYSTEM; task file is world-writable | Demonstrates scheduled task hijacking for privilege escalation | `schtasks /query /fo LIST /v \| findstr BackupTask`; `Get-ScheduledTask -TaskName BackupTask` |
| **AutoRun/AutoPlay enabled** | Social engineering, USB attacks | `NoDriveTypeAutoRun=0` | Demonstrates USB-based initial access vectors | `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" NoDriveTypeAutoRun` |
| **Flag file on labuser Desktop** | Lab objective validation | `C:\Users\labuser\Desktop\flag.txt: FLAG{lateral_movement_workstation_4d2c}` | Students submit this flag after achieving lateral movement | Read the file contents after gaining access to the labuser session |

---

## 6. What the Script Configures

The PowerShell build script (`Build-Windows10Vulnerable.ps1`) runs 18 numbered sections. Here is a prose summary of each.

**Section 1 — Computer name:** The VM is renamed to `SCPS-WS01`. This gives students a consistent hostname to reference during lab exercises.

**Section 2 — Disable Defender:** Windows Defender real-time protection, behaviour monitoring, IOAV protection, script scanning, and all other active scanning features are disabled via `Set-MpPreference`. The settings are also written to Group Policy registry keys (`HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender`) for persistence across reboots. The WinDefend and Sense services are set to `Start=4` (Disabled).

**Section 3 — Disable Firewall:** All Windows Firewall profiles (Domain, Public, Private) are disabled via `Set-NetFirewallProfile` and `netsh advfirewall`.

**Section 4 — Enable SMBv1:** `Enable-WindowsOptionalFeature -FeatureName SMB1Protocol` and `Set-SmbServerConfiguration -EnableSMB1Protocol $true`. The registry key `SMB1=1` is also set for persistence.

**Section 5 — Enable WinRM:** `Enable-PSRemoting -Force` enables PowerShell Remoting. WinRM is configured to allow unencrypted transport and Basic authentication — both settings are insecure by design.

**Section 6 — Enable RDP without NLA:** The `fDenyTSConnections=0` registry key enables Remote Desktop. `UserAuthentication=0` disables Network Level Authentication, removing pre-authentication credential verification.

**Section 7 — Create user accounts:** Three accounts are created with intentionally weak passwords: `Administrator` (Password123!), `labuser` (Summer2024!), `serviceacct` (Svc@2024). All passwords and their intended weaknesses are written to `C:\LabBuild\credentials.txt`.

**Section 8 — Open SMB share:** A share named `Data` is created at `C:\Shares\Data` with `Everyone: Full` access.

**Section 9 — Plant lure files:** Three files are written to the Data share: `passwords.txt` (contains realistic fake corporate credentials), `notes.txt` (references the service account password and domain admin access), `config.xml` (embedded database and email credentials in an XML config format).

**Section 10 — Plant flag file:** `flag.txt` containing `FLAG{lateral_movement_workstation_4d2c}` is written to `C:\Users\labuser\Desktop\`.

**Section 11 — Install Chocolatey and tools:** Chocolatey is installed, then `7zip` and `notepadplusplus` are installed. These are benign tools that provide a realistic workstation feel.

**Section 12 — Disable automatic Windows Updates:** The Windows Update service is stopped and disabled via registry policy and service configuration. This prevents updates from patching intentional vulnerabilities during a lab session.

**Section 13 — Registry Run key persistence:** A Run key entry `WindowsUpdate` is written to `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` (runs at system boot) and `Updater` to `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` (runs at user logon). These are named to appear legitimate and test students' ability to distinguish malicious from real update entries.

**Section 14 — Enable AutoRun:** AutoRun and AutoPlay are re-enabled by removing the `NoDriveTypeAutoRun` restriction.

**Section 15 — Scheduled task BackupTask:** A scheduled task named `BackupTask` is created running as SYSTEM, triggered daily at 03:00. The task binary path is designed for hijacking — the task file in `C:\Windows\System32\Tasks\` is made world-writable (`icacls /grant "BUILTIN\Users:(F)"`).

**Section 16 — Install .NET 3.5:** The .NET Framework 3.5 feature is enabled. Many older exploit payloads and tools require .NET 3.5.

**Section 17 — Finalise credentials file:** A summary of all intentional vulnerabilities is appended to `C:\LabBuild\credentials.txt`.

**Section 18 — Sysprep:** Event logs (Application, System, Security, PowerShell Operational, Sysmon Operational) are cleared. PowerShell history file is deleted. Free disk space is zeroed with `cipher /w:C:\`. The VM shuts down after a 10-second delay.

---

## 7. Network Interfaces

Single adapter. In Lab 1, connected to `corporate-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.20`.

---

## 8. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `Administrator` | `Password123!` | Intentionally weak — for brute force practice |
| `labuser` | `Summer2024!` | Intentionally weak — standard user, flag on Desktop |
| `serviceacct` | `Svc@2024` | Intentionally weak — pass-the-hash target |

All credentials are also written to `C:\LabBuild\credentials.txt` inside the VHDX.

---

## 9. Verification Steps

### Step 1 — SMBv1 Enabled

```powershell
Get-SmbServerConfiguration | Select EnableSMB1Protocol
# Expected: True
```

### Step 2 — Defender Disabled

```powershell
Get-MpPreference | Select DisableRealtimeMonitoring
# Expected: True
```

### Step 3 — WinRM Accessible

From the Kali VM (after deployment):

```bash
evil-winrm -i 10.{ClassId}.{StudentId}.20 -u Administrator -p 'Password123!'
# Expected: WinRM shell opens
```

### Step 4 — SMB Share Accessible

From Kali:

```bash
smbclient //10.{ClassId}.{StudentId}.20/Data -N
# Expected: connects and lists files without credentials
```

### Step 5 — Scheduled Task

```powershell
Get-ScheduledTask -TaskName "BackupTask"
# Expected: Task listed with Principal=SYSTEM
```

---

## 10. Snapshot and Storage

```powershell
Stop-VM -Name "win10vuln-build" -Force
Move-Item "win10vuln-build.vhdx" "C:\CyberLab\Templates\windows-10-vulnerable.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\windows-10-vulnerable.vhdx" -Name IsReadOnly -Value $true
```

---

## 11. Troubleshooting

### SMBv1 Not Enabled After Build

**Symptom:** `Get-SmbServerConfiguration` returns `EnableSMB1Protocol = False`.

**Cause:** Windows Updates may have run between OS install and build script, applying the SMBv1 removal update.

**Fix:** The build script disables Windows Update to prevent this. If it occurs, re-enable SMBv1 manually:

```powershell
Enable-WindowsOptionalFeature -FeatureName SMB1Protocol -Online -NoRestart
Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force
```

### Build Script Fails at Chocolatey Install — TLS Error

**Symptom:** `Invoke-Expression ... chocolatey.org ...` fails with TLS error.

**Fix:**

```powershell
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
```

This is already in the script. If the issue persists, check that the VM has internet access and the Windows date/time is correct (TLS validation requires accurate time).

### WinRM Enable-PSRemoting Fails

**Symptom:** `Enable-PSRemoting` fails with network profile error.

**Fix:** The script uses `-SkipNetworkProfileCheck`. If this fails on a domain profile:

```powershell
Set-NetConnectionProfile -NetworkCategory Private
Enable-PSRemoting -Force
```
