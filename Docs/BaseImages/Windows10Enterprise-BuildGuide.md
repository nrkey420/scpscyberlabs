# Windows 10 Enterprise — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `windows-10-enterprise` |
| **VHDX path** | `C:\CyberLab\Templates\windows-10-enterprise.vhdx` |
| **Used in** | Lab 3 (SOC Analyst — victim workstation that generates events for students to detect) |
| **Role** | Realistic enterprise workstation with Sysmon and Splunk Universal Forwarder; generates simulated attack events |
| **Build script** | None — built manually with Sysmon, Splunk UF, and an attack simulation script installed |
| **Resources** | 2 vCPU, 4 GB RAM, 60 GB dynamic VHDX |
| **Base OS** | Windows 10 Enterprise 21H2 (amd64) |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Installing Sysmon](#4-installing-sysmon)
5. [Installing Splunk Universal Forwarder](#5-installing-splunk-universal-forwarder)
6. [Sysmon Event ID Reference](#6-sysmon-event-id-reference)
7. [Enhanced Audit Policy](#7-enhanced-audit-policy)
8. [Simulated Attack Activities](#8-simulated-attack-activities)
9. [Network Interfaces](#9-network-interfaces)
10. [Default Credentials After Build](#10-default-credentials-after-build)
11. [Verification Steps](#11-verification-steps)
12. [Snapshot and Storage](#12-snapshot-and-storage)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

- Windows 10 Enterprise 21H2 ISO (Volume Licensing / MSDN / Evaluation Center)
- Sysmon (latest): `https://docs.microsoft.com/sysinternals/downloads/sysmon`
- Sysmon configuration file: use the SwiftOnSecurity Sysmon config as base: `https://github.com/SwiftOnSecurity/sysmon-config`
- Splunk Universal Forwarder 9.1.x MSI: `https://www.splunk.com/en_us/download/universal-forwarder.html`
- Build time: approximately 60–90 minutes

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **4096 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **60 GB**, Dynamically expanding |
| Network adapter | External-Internet (for downloads during build) |

---

## 3. OS Installation

| Setting | Value |
|---------|-------|
| Language | English (United States) |
| Edition | Windows 10 Enterprise |
| Partition | Full disk |
| Account setup | Local account — username `corpuser` |
| Password | Strong temporary password |

After installation, enable the Administrator account and log in as Administrator for the build steps.

---

## 4. Installing Sysmon

Sysmon (System Monitor) is a Windows system service and device driver that logs detailed system activity to the Windows Event Log. In Lab 3, Sysmon events are forwarded to Splunk and reviewed by students acting as SOC analysts.

### Download and Install

```powershell
# Download Sysmon from Sysinternals (or transfer from host)
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile "C:\Temp\Sysmon.zip"
Expand-Archive "C:\Temp\Sysmon.zip" -DestinationPath "C:\Sysmon"

# Download the SwiftOnSecurity config as a starting point
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" `
    -OutFile "C:\Sysmon\sysmonconfig.xml"

# Install Sysmon with the configuration
C:\Sysmon\Sysmon64.exe -accepteula -i C:\Sysmon\sysmonconfig.xml

# Verify Sysmon is running
Get-Service Sysmon64
```

### Lab 3 Sysmon Configuration Additions

Add these rules to the Sysmon config file to capture events that the simulated attacks will generate:

```xml
<!-- Add to the sysmonconfig.xml before installation -->
<EventFiltering>
    <!-- EventID 1 — Process Create (all processes) -->
    <ProcessCreate onmatch="exclude">
        <!-- Exclude common noisy processes -->
        <Image condition="is">C:\Windows\System32\conhost.exe</Image>
    </ProcessCreate>

    <!-- EventID 3 — Network Connection -->
    <NetworkConnect onmatch="exclude">
        <Image condition="is">C:\Windows\System32\svchost.exe</Image>
    </NetworkConnect>

    <!-- EventID 7 — Image Loaded -->
    <ImageLoad onmatch="include">
        <ImageLoaded condition="contains">PSAPI.DLL</ImageLoaded>
        <ImageLoaded condition="contains">WININET.dll</ImageLoaded>
    </ImageLoad>

    <!-- EventID 10 — Process Access (credential access) -->
    <ProcessAccess onmatch="include">
        <TargetImage condition="is">C:\Windows\system32\lsass.exe</TargetImage>
    </ProcessAccess>

    <!-- EventID 11 — File Create -->
    <FileCreate onmatch="include">
        <TargetFilename condition="contains">\Temp\</TargetFilename>
        <TargetFilename condition="contains">\AppData\</TargetFilename>
    </FileCreate>
</EventFiltering>
```

---

## 5. Installing Splunk Universal Forwarder

The Splunk UF collects Windows event logs and Sysmon events and forwards them to the class Splunk instance (`10.{ClassId}.0.51`).

```powershell
# Transfer the Splunk UF MSI to the VM
# Install silently with the target Splunk server
msiexec /i "splunkforwarder-9.1.x-x64-release.msi" RECEIVING_INDEXER="10.0.0.51:9997" `
    WINEVENTLOG_SEC_ENABLE=1 WINEVENTLOG_SYS_ENABLE=1 WINEVENTLOG_APP_ENABLE=1 `
    LAUNCHSPLUNK=1 INSTALLDIR="C:\Program Files\SplunkUniversalForwarder" `
    /qn /l*v "C:\Temp\splunk-install.log"

# Wait for service to start
Start-Sleep 15
Get-Service SplunkForwarder
```

### Configure UF Inputs

Create the inputs configuration to capture all required event sources:

```powershell
$inputsConf = @"
[WinEventLog://Security]
index = windows
disabled = false
start_from = oldest
evt_resolve_ad_obj = 1

[WinEventLog://System]
index = windows
disabled = false

[WinEventLog://Application]
index = windows
disabled = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index = sysmon
disabled = false
renderXml = true
start_from = oldest

[WinEventLog://Microsoft-Windows-PowerShell/Operational]
index = windows
disabled = false
"@

$inputsConf | Out-File -FilePath "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf" -Encoding UTF8
```

### Configure UF Outputs (Template Placeholder)

The outputs configuration uses a placeholder IP that the deploy script updates:

```powershell
$outputsConf = @"
[tcpout]
defaultGroup = scps-cyberlab

[tcpout:scps-cyberlab]
server = 10.CLASS_ID.0.51:9997
useACK = false
"@

$outputsConf | Out-File -FilePath "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf" -Encoding UTF8

Restart-Service SplunkForwarder
```

At deploy time, the orchestration module replaces `CLASS_ID` with the actual class identifier.

---

## 6. Sysmon Event ID Reference

The following table lists all Sysmon event IDs enabled in the Lab 3 configuration and what they capture.

| Event ID | Name | What It Captures | Lab 3 Detection Use |
|----------|------|-----------------|---------------------|
| **1** | Process Create | Every new process: image path, command line, parent process, user, hash | Detect malicious process execution, PowerShell download cradles, cmd.exe spawned from Office |
| **2** | File Creation Time Changed | File timestamp manipulation | Detect anti-forensics (timestomping) |
| **3** | Network Connection | Outbound TCP/UDP connections from every process | Detect C2 callbacks, lateral movement via SMB/WinRM |
| **5** | Process Terminated | When each process ends | Correlate with EventID 1 for short-lived malicious processes |
| **7** | Image Loaded | DLLs loaded into processes | Detect reflective DLL injection, process hollowing |
| **8** | CreateRemoteThread | Thread creation in another process | Detect process injection (Meterpreter, etc.) |
| **10** | ProcessAccess | One process accessing another's memory | Detect LSASS credential dumping (Mimikatz) |
| **11** | FileCreate | File creation events | Detect dropped payloads, persistence file creation |
| **12/13/14** | Registry events | Registry key/value creation, modification, deletion | Detect registry-based persistence (Run keys) |
| **15** | FileCreateStreamHash | Alternate Data Stream creation | Detect NTFS ADS-based hiding |
| **17/18** | Pipe Created/Connected | Named pipe events | Detect lateral movement via named pipes (PsExec, SMB) |
| **22** | DNSEvent | DNS query logs | Detect C2 domain resolution, DGA activity |
| **23** | FileDelete | File deletion events | Detect evidence wiping |

---

## 7. Enhanced Audit Policy

Windows Security Event Log auditing is enabled at the OS level to capture authentication events that Sysmon does not cover.

```powershell
# Configure Advanced Audit Policy via auditpol
# Logon/Logoff — captures successful and failed logons
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /set /subcategory:"Account Lockout" /failure:enable

# Account Management — captures user/group changes
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable

# Privilege Use
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable

# Object Access — files, registry
auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /set /subcategory:"Registry" /success:enable /failure:enable

# Process Tracking
auditpol /set /subcategory:"Process Creation" /success:enable
auditpol /set /subcategory:"Process Termination" /success:enable

# Verify
auditpol /get /category:*
```

### Audit Policy Reference Table

| Policy Category | Subcategory | Setting | Events Generated | Lab 3 Detection |
|----------------|------------|---------|-----------------|----------------|
| Logon/Logoff | Logon | Success + Failure | EventID 4624 (success), 4625 (failure) | Brute force, lateral movement |
| Logon/Logoff | Logoff | Success | EventID 4634 | Session tracking |
| Logon/Logoff | Account Lockout | Failure | EventID 4740 | Brute force detection |
| Account Management | User Account Management | Success + Failure | EventID 4720 (create), 4722 (enable), 4726 (delete) | Persistence via new accounts |
| Account Management | Security Group Management | Success | EventID 4728, 4732 (member added to group) | Privilege escalation |
| Privilege Use | Sensitive Privilege Use | Success + Failure | EventID 4672 (special logon), 4673 | Privileged operation tracking |
| Object Access | File System | Success + Failure | EventID 4663 (file accessed) | Data exfiltration detection |
| Detailed Tracking | Process Creation | Success | EventID 4688 (process created with command line) | Malicious process detection (complements Sysmon) |

---

## 8. Simulated Attack Activities

The Windows 10 Enterprise image is configured with a scheduled task that fires 30 minutes after VM startup, generating a realistic attack sequence that students must detect in Splunk and Security Onion. This simulates an attacker who has already gained initial access and is performing post-exploitation.

### Simulated Attack Timeline

The attack simulation task runs `C:\LabScripts\SimulateAttack.ps1` as SYSTEM. The script executes the following actions in sequence, with 2-minute gaps between stages:

| T+0 | **Credential dump attempt:** Accesses `lsass.exe` memory via `OpenProcess` — triggers Sysmon EventID 10 with TargetImage=lsass.exe |
| T+2 | **Enumeration:** Runs `net user`, `net localgroup administrators`, `whoami /all` — triggers EventID 4688 (process creation) and Sysmon EventID 1 |
| T+4 | **Persistence — Run key:** Writes a Run registry key `HKCU:\...\Run\SecurityUpdate` — triggers Sysmon EventIDs 12 and 13 |
| T+6 | **Lateral movement attempt:** Attempts WinRM connection to the DC IP (`10.{ClassId}.{StudentId}.21`) — triggers Sysmon EventID 3 |
| T+8 | **Data staging:** Copies files from `C:\Users\corpuser\Documents\` to `C:\Windows\Temp\staging\` — triggers Sysmon EventID 11 |
| T+10 | **Exfiltration beacon:** Makes HTTP GET to `10.{ClassId}.{StudentId}.10:8080/beacon` (Kali C2 simulation) — triggers Sysmon EventID 3 and DNS EventID 22 |
| T+12 | **Cleanup attempt:** Deletes `C:\Windows\Temp\staging\` — triggers Sysmon EventID 23 |

The script is intentionally written to generate detectable events. Students are given the timeline of when attacks should appear in logs (based on the 30-minute offset) and must correlate events across Splunk indexes to reconstruct the kill chain.

### Installing the Simulation Script

```powershell
# Create the LabScripts directory
New-Item -Path "C:\LabScripts" -ItemType Directory -Force

# Write the simulation task registration (the PowerShell content is provided separately)
# Register the scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -ExecutionPolicy Bypass -File C:\LabScripts\SimulateAttack.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "LabAttackSimulation" -Action $action `
    -Trigger $trigger -Principal $principal -Force
```

---

## 9. Network Interfaces

Single adapter. In Lab 3, connected to the SOC class network and assigned an appropriate address per the `03-soc-analyst.json` template.

---

## 10. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `Administrator` | Set during OS install | Admin access for deploy-time configuration |
| `corpuser` | Set during OS install (overridden at deploy) | Standard corporate user account |

---

## 11. Verification Steps

### Step 1 — Sysmon Running

```powershell
Get-Service Sysmon64 | Select-Object Name, Status
# Expected: Running
```

### Step 2 — Sysmon Events Generating

```powershell
# Trigger a test process creation and check the Sysmon log
notepad.exe &
Start-Sleep 2
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5
# Expected: EventID 1 entries for notepad.exe
```

### Step 3 — Splunk UF Running

```powershell
Get-Service SplunkForwarder | Select-Object Name, Status
# Expected: Running
```

### Step 4 — Audit Policy Active

```powershell
auditpol /get /subcategory:"Logon"
# Expected: Setting includes both Success and Failure
```

### Step 5 — Simulation Task Registered

```powershell
Get-ScheduledTask -TaskName "LabAttackSimulation"
# Expected: Task listed with State = Ready
```

---

## 12. Snapshot and Storage

```powershell
Stop-VM -Name "win10ent-build" -Force
Move-Item "win10ent-build.vhdx" "C:\CyberLab\Templates\windows-10-enterprise.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\windows-10-enterprise.vhdx" -Name IsReadOnly -Value $true
```

---

## 13. Troubleshooting

### Sysmon Not Logging to Event Log

**Fix:**

```powershell
# Verify the Sysmon service is running
Get-Service Sysmon64
# If stopped, start it
Start-Service Sysmon64

# Verify the event log channel exists
Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational"
```

### Splunk UF Not Forwarding

```powershell
# Check UF service
Get-Service SplunkForwarder

# Check UF log for connectivity errors
Get-Content "C:\Program Files\SplunkUniversalForwarder\var\log\splunk\splunkd.log" -Tail 50
# Look for "Connected to idx" or "ERROR" lines
```

### Simulation Task Not Firing

```powershell
# Force-run the task to test
Start-ScheduledTask -TaskName "LabAttackSimulation"
# Check task history
Get-ScheduledTaskInfo -TaskName "LabAttackSimulation"
```
