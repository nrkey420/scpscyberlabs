# Windows 10 Sandbox — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `windows-10-sandbox` |
| **VHDX path** | `C:\CyberLab\Templates\windows-10-sandbox.vhdx` |
| **Used in** | Lab 5 (Malware Analysis — isolated execution target for dynamic analysis) |
| **Role** | Clean Windows 10 workstation where malware samples are executed under observation; monitored by Sysmon and Process Monitor |
| **Build script** | None — built manually |
| **Resources** | 2 vCPU, 4 GB RAM, 60 GB dynamic VHDX |
| **Base OS** | Windows 10 Enterprise 21H2 (amd64) |

> **CRITICAL — Isolation Requirement:** The Windows 10 Sandbox VM is the execution target for live malware samples. It must never be connected to any network segment that has internet access or a route to production infrastructure. In Lab 5, it connects only to `analysis-net`, which is a Hyper-V internal private switch. The pfSense VM in Lab 5 has its WAN adapter removed from any external switch. Verify isolation before every sample execution using the pre-session checks in Section 11.

> **Checkpoint Mandate:** Before every malware execution, the VM must be restored to the `InitialState` checkpoint. This is non-negotiable. Running a second sample on a system compromised by the first sample produces invalid and potentially dangerous results. See Section 11 (Snapshot Strategy) for the restore procedure.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Sysmon Installation and Configuration](#4-sysmon-installation-and-configuration)
5. [Analysis Support Tools](#5-analysis-support-tools)
6. [User Account Configuration](#6-user-account-configuration)
7. [Network Interfaces](#7-network-interfaces)
8. [Default Credentials After Build](#8-default-credentials-after-build)
9. [Sysmon Event Reference](#9-sysmon-event-reference)
10. [Analysis Workflow on the Sandbox](#10-analysis-workflow-on-the-sandbox)
11. [Snapshot Strategy](#11-snapshot-strategy)
12. [Verification Steps](#12-verification-steps)
13. [Snapshot and Storage](#13-snapshot-and-storage)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

- Windows 10 Enterprise 21H2 ISO (Volume Licensing / MSDN / Evaluation Center)
- Sysmon binary (download from Sysinternals or transfer from host)
- SwiftOnSecurity Sysmon configuration file as base
- Process Monitor (Sysinternals) — pre-installed in the image
- Build time: approximately 40–50 minutes

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **4096 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **60 GB**, Dynamically expanding |
| Network adapter | External-Internet (for downloads during build only; removed before Lab 5) |
| Secure Boot | Leave enabled |

---

## 3. OS Installation

Boot from the Windows 10 Enterprise ISO:

| Setting | Value |
|---------|-------|
| Language | English (United States) |
| Edition | Windows 10 Enterprise |
| Install type | Custom: full disk |
| Account | Local account — username `victim` |
| Password | Set a strong temporary password (overridden at deploy) |

After installation:

```powershell
# Set computer name
Rename-Computer -NewName "SCPS-SANDBOX" -Force

# Set timezone
Set-TimeZone -Id "Eastern Standard Time"

# Enable and set Administrator password for build work
net user Administrator /active:yes
net user Administrator LabBuildPass!2024

# Log off victim and log in as Administrator for remaining build steps
```

### Do Not Apply Windows Updates

The Sandbox image is intentionally not patched. Students may execute samples that target known Windows vulnerabilities, and patching the image could prevent those samples from working as designed. Disable automatic updates:

```powershell
# Disable Windows Update service
Stop-Service wuauserv
Set-Service wuauserv -StartupType Disabled

# Disable via Group Policy registry
$wuPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $wuPolicy -Force | Out-Null
Set-ItemProperty -Path $wuPolicy -Name "NoAutoUpdate" -Value 1 -Type DWord
Set-ItemProperty -Path $wuPolicy -Name "AUOptions" -Value 1 -Type DWord
```

---

## 4. Sysmon Installation and Configuration

Sysmon captures detailed system activity during malware execution. Its event log is the primary data source for dynamic analysis in Lab 5.

### Download and Install

```powershell
# Transfer Sysmon to the VM (from host via Hyper-V file copy or mounted ISO)
# Download the SwiftOnSecurity config as a base
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" `
    -OutFile "C:\Sysmon\sysmonconfig.xml"

# Install Sysmon with the configuration
C:\Sysmon\Sysmon64.exe -accepteula -i C:\Sysmon\sysmonconfig.xml

# Verify installation
Get-Service Sysmon64
```

### Malware Analysis Sysmon Configuration

The base SwiftOnSecurity config is augmented with additional rules to capture all events relevant to malware dynamic analysis:

```xml
<EventFiltering>
    <!-- Capture all process creation — critical for malware dropper chains -->
    <ProcessCreate onmatch="exclude">
        <!-- Reduce noise from known-clean system processes -->
        <Image condition="is">C:\Windows\System32\conhost.exe</Image>
        <Image condition="is">C:\Windows\System32\wbem\WmiPrvSE.exe</Image>
    </ProcessCreate>

    <!-- Capture all network connections — critical for C2 detection -->
    <NetworkConnect onmatch="exclude">
        <!-- Exclude only well-known system noise -->
        <Image condition="is">C:\Windows\System32\svchost.exe</Image>
        <DestinationPort condition="is">443</DestinationPort>
    </NetworkConnect>

    <!-- Image Load — detect DLL injection -->
    <ImageLoad onmatch="include">
        <ImageLoaded condition="contains">AppData</ImageLoaded>
        <ImageLoaded condition="contains">Temp</ImageLoaded>
        <ImageLoaded condition="contains">ProgramData</ImageLoaded>
    </ImageLoad>

    <!-- Process Access — detect LSASS credential dumping -->
    <ProcessAccess onmatch="include">
        <TargetImage condition="is">C:\Windows\system32\lsass.exe</TargetImage>
    </ProcessAccess>

    <!-- File Create — detect dropped payloads -->
    <FileCreate onmatch="include">
        <TargetFilename condition="contains">\Temp\</TargetFilename>
        <TargetFilename condition="contains">\AppData\</TargetFilename>
        <TargetFilename condition="contains">\ProgramData\</TargetFilename>
        <TargetFilename condition="contains">.exe</TargetFilename>
        <TargetFilename condition="contains">.dll</TargetFilename>
        <TargetFilename condition="contains">.bat</TargetFilename>
        <TargetFilename condition="contains">.ps1</TargetFilename>
    </FileCreate>

    <!-- Registry — detect persistence -->
    <RegistryEvent onmatch="include">
        <TargetObject condition="contains">Run</TargetObject>
        <TargetObject condition="contains">RunOnce</TargetObject>
        <TargetObject condition="contains">Services</TargetObject>
        <TargetObject condition="contains">Winlogon</TargetObject>
    </RegistryEvent>

    <!-- DNS events — detect C2 domain lookups -->
    <DnsQuery onmatch="exclude">
        <QueryName condition="end with">microsoft.com</QueryName>
        <QueryName condition="end with">windowsupdate.com</QueryName>
    </DnsQuery>
</EventFiltering>
```

Update Sysmon with the modified configuration:

```powershell
C:\Sysmon\Sysmon64.exe -c C:\Sysmon\sysmonconfig.xml
```

---

## 5. Analysis Support Tools

Install the following tools on the Sandbox. These are lightweight monitoring utilities that run alongside malware samples:

```powershell
# Create a tools directory
New-Item -Path "C:\AnalysisTools" -ItemType Directory -Force
```

### Process Monitor (ProcMon)

```powershell
# Transfer ProcMon to the VM (Sysinternals Suite)
# ProcMon is placed at C:\AnalysisTools\Procmon64.exe
# Configure a desktop shortcut for quick access
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("C:\Users\Public\Desktop\ProcMon.lnk")
$shortcut.TargetPath = "C:\AnalysisTools\Procmon64.exe"
$shortcut.Save()
```

### Regshot (Registry Snapshot)

Download Regshot to the image. Regshot takes before/after registry snapshots and generates an HTML diff report showing all keys added, modified, or deleted during malware execution.

```powershell
# Place Regshot at C:\AnalysisTools\Regshot-x64-Unicode.exe
$shortcut = $shell.CreateShortcut("C:\Users\Public\Desktop\Regshot.lnk")
$shortcut.TargetPath = "C:\AnalysisTools\Regshot-x64-Unicode.exe"
$shortcut.Save()
```

### Autoruns (Persistence Check)

Autoruns from Sysinternals enumerates all startup locations. Used after malware execution to identify persistence mechanisms:

```powershell
# Place at C:\AnalysisTools\Autoruns64.exe
$shortcut = $shell.CreateShortcut("C:\Users\Public\Desktop\Autoruns.lnk")
$shortcut.TargetPath = "C:\AnalysisTools\Autoruns64.exe"
$shortcut.Save()
```

### Configure WinPmem for Memory Capture

WinPmem is used to dump physical memory for offline analysis with Volatility on FlareVM:

```powershell
# Place at C:\AnalysisTools\winpmem_mini_x64.exe
# No installation required — runs from command line
# Usage: winpmem_mini_x64.exe C:\Captures\memory.raw
```

---

## 6. User Account Configuration

The `victim` account is the unprivileged user under which malware samples execute. This simulates a realistic end-user scenario where malware arrives without Administrator privileges and must escalate.

```powershell
# Ensure the victim account exists and has a known password
net user victim LabBuildPass!2024 /add
# If it already exists:
net user victim LabBuildPass!2024

# Ensure victim is a standard user (not in Administrators)
net localgroup Administrators victim /delete 2>$null

# Create the victim Desktop directory for sample delivery
New-Item -Path "C:\Users\victim\Desktop\Samples" -ItemType Directory -Force
```

---

## 7. Network Interfaces

Single adapter. In Lab 5, connected to `analysis-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.20`. This places it on the same isolated segment as the FlareVM (`10.{ClassId}.{StudentId}.11`) and REMnux (`10.{ClassId}.{StudentId}.10`).

The FakeNet-NG instance running on the FlareVM intercepts all outbound network connections from the Sandbox. Traffic destined for any external IP is intercepted by FakeNet-NG at the analysis-net layer.

---

## 8. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `Administrator` | `LabBuildPass!2024` (overridden at deploy) | Local administrator; used for analysis setup |
| `victim` | `LabBuildPass!2024` (overridden at deploy) | Standard user; sample execution account |

---

## 9. Sysmon Event Reference

The following table covers the Sysmon event IDs captured by the Sandbox configuration and their relevance to malware analysis.

| Event ID | Name | What It Captures | Lab 5 Analysis Use |
|----------|------|-----------------|-------------------|
| **1** | Process Create | New process: image path, command line, parent, user, hash | Identify dropper chains; detect cmd.exe/PowerShell spawned from malware |
| **2** | File Creation Time Changed | File timestamp manipulation | Detect anti-forensics (timestomping) |
| **3** | Network Connection | Outbound TCP/UDP connections | Identify C2 callback IPs and ports; detect FakeNet-NG intercepts |
| **5** | Process Terminated | Process exit events | Correlate with EventID 1 for short-lived helper processes |
| **7** | Image Loaded | DLLs loaded into processes | Detect reflective DLL injection; identify hooking libraries |
| **8** | CreateRemoteThread | Thread injection into another process | Detect process injection (Meterpreter, shellcode loaders) |
| **10** | ProcessAccess | One process accessing another's memory | Detect LSASS credential dumping |
| **11** | FileCreate | File creation | Detect dropped payloads; identify staging directories |
| **12** | RegistryEvent (Object Create/Delete) | Registry key creation/deletion | Detect registry-based persistence setup and cleanup |
| **13** | RegistryEvent (Value Set) | Registry value modification | Detect Run key persistence; detect config writing |
| **14** | RegistryEvent (Key/Value Rename) | Registry rename operations | Detect obfuscated persistence via key renaming |
| **15** | FileCreateStreamHash | NTFS Alternate Data Stream creation | Detect ADS-based hiding of payloads |
| **17** | PipeEvent (Pipe Created) | Named pipe creation | Detect lateral movement prep (PsExec, Cobalt Strike) |
| **18** | PipeEvent (Pipe Connected) | Named pipe connection | Detect C2 via named pipes |
| **22** | DNSEvent | DNS query and response | Identify C2 domain queries; detect DGA patterns |
| **23** | FileDelete | File deletion | Detect evidence wiping and self-deletion |
| **25** | ProcessTampering | Process hollowing detected | Detect process hollowing and doppelganging |

### Viewing Sysmon Events

```powershell
# View most recent 50 Sysmon events
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 50 |
    Select-Object TimeCreated, Id, Message | Format-List

# Filter for specific EventID (e.g., network connections = EventID 3)
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" |
    Where-Object { $_.Id -eq 3 } | Select-Object TimeCreated, Message
```

---

## 10. Analysis Workflow on the Sandbox

The following sequence is the standard dynamic analysis workflow students follow in Lab 5.

### Before Execution

1. Restore the `InitialState` checkpoint (see Section 11)
2. On the FlareVM: start FakeNet-NG in its own window
3. On the Sandbox: start ProcMon (Admin) — capture immediately begins
4. On the Sandbox: run Regshot → First Shot → save to `C:\Analysis\regshot_before.hiv`
5. On the Sandbox: verify Sysmon is running: `Get-Service Sysmon64`

### During Execution

1. Copy the sample to `C:\Users\victim\Desktop\Samples\`
2. Switch to the `victim` user account
3. Execute the sample (double-click or via cmd.exe)
4. Observe for 5–10 minutes, noting any visible behavior (windows, dialogs, CPU spikes)

### After Execution

1. Return to `Administrator` account
2. In ProcMon: File → Save → export all captured events to `C:\Analysis\procmon.csv`
3. Run Regshot → Second Shot → Compare → save HTML diff to `C:\Analysis\regshot_diff.html`
4. Run Autoruns → File → Save → `C:\Analysis\autoruns_after.arn`
5. On FlareVM: stop FakeNet-NG (Ctrl+C); save `C:\FakeNetLogs\fakenet.pcap`
6. On FlareVM: capture memory if process is still running: `winpmem_mini_x64.exe C:\Captures\memory.raw`
7. Export Sysmon log:

```powershell
wevtutil epl "Microsoft-Windows-Sysmon/Operational" "C:\Analysis\sysmon_dump.evtx"
```

Transfer artifacts to FlareVM for analysis via Hyper-V file copy or analysis-net shared folder.

---

## 11. Snapshot Strategy

### InitialState Checkpoint

After the image is fully built and all tools are configured, take a Hyper-V checkpoint named `InitialState`. This checkpoint is taken **before** any malware analysis is performed and represents a completely clean system.

```powershell
# On the Hyper-V host
Checkpoint-VM -Name "Win10Sandbox-Build" -SnapshotName "InitialState"
```

### Restoring Before Each Session

Before every malware execution, restore to `InitialState`. This is enforced procedure — it takes approximately 30–60 seconds:

```powershell
# Restore to clean state
Restore-VMSnapshot -VMName "Win10Sandbox-S{StudentId}" -Name "InitialState"
Start-VM -Name "Win10Sandbox-S{StudentId}"
```

Or in Hyper-V Manager: right-click the VM → Checkpoints → `InitialState` → Apply.

### How the Checkpoint Works with Differencing Disks

In Lab 5, each student's Sandbox is a differencing disk child of the `windows-10-sandbox.vhdx` parent. The `InitialState` checkpoint captures only the delta state in the child AVHDX. Restoring to `InitialState` discards all changes made since that checkpoint was taken, leaving the parent VHDX unaffected. This is fast (seconds) regardless of how much the malware modified the system.

---

## 12. Verification Steps

### Step 1 — Sysmon Running

```powershell
Get-Service Sysmon64 | Select-Object Name, Status
# Expected: Running
```

### Step 2 — Sysmon Logging Events

```powershell
notepad.exe
Start-Sleep 2
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5
# Expected: EventID 1 for notepad.exe
Stop-Process -Name notepad
```

### Step 3 — Network Isolation Confirmed

```powershell
# Attempt connection to an external IP — should fail or be intercepted by FakeNet-NG
Test-NetConnection -ComputerName 8.8.8.8 -Port 53 -InformationLevel Quiet
# Expected: False (no route) or FakeNet-NG intercept with success (if FakeNet is running)

# Confirm default gateway is only the analysis-net pfSense/FakeNet-NG address
Get-NetRoute -DestinationPrefix "0.0.0.0/0"
# Expected: NextHop = 10.{ClassId}.{StudentId}.1 (pfSense LAN) — not a real internet gateway
```

### Step 4 — Analysis Tools Present

```powershell
Test-Path "C:\AnalysisTools\Procmon64.exe"
Test-Path "C:\AnalysisTools\Regshot-x64-Unicode.exe"
Test-Path "C:\AnalysisTools\Autoruns64.exe"
Test-Path "C:\AnalysisTools\winpmem_mini_x64.exe"
Test-Path "C:\Sysmon\Sysmon64.exe"
# Expected: All True
```

### Step 5 — Victim Account Exists

```powershell
Get-LocalUser -Name "victim"
# Expected: Enabled = True

Get-LocalGroupMember -Group "Administrators" | Where-Object Name -like "*victim*"
# Expected: No output (victim is not an admin)
```

---

## 13. Snapshot and Storage

```powershell
Stop-VM -Name "win10sandbox-build" -Force
Move-Item "win10sandbox-build.vhdx" "C:\CyberLab\Templates\windows-10-sandbox.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\windows-10-sandbox.vhdx" -Name IsReadOnly -Value $true
```

---

## 14. Troubleshooting

### Sysmon Stops During Malware Execution

**Symptom:** Sysmon service is found stopped after malware runs.

**Cause:** Some malware specifically targets and terminates Sysmon to evade detection.

**Fix:** This is expected and is itself a detection indicator (Sysmon EventID 4 or gap in event log). Document the time gap as an evasion indicator. Restart Sysmon for subsequent executions, or restore to `InitialState`.

### ProcMon Does Not Capture All Events

**Symptom:** ProcMon shows less activity than expected from the malware sample.

**Cause:** ProcMon must be running before the sample executes. If started after, early events are missed.

**Fix:** Always start ProcMon and let it begin capturing before executing the sample. Set the capture filter to the sample filename to reduce noise.

### Checkpoint Restore Takes Too Long

**Symptom:** Restoring the `InitialState` checkpoint takes more than 2–3 minutes.

**Cause:** The AVHDX has grown large due to many malware executions writing extensively to disk.

**Fix:** If the differencing disk grows beyond 10 GB, delete and recreate the student's AVHDX from the parent VHDX. The `InitialState` checkpoint was taken on the parent, so starting fresh from the parent restores the clean state instantly.

### Memory Dump Fails with Access Denied

**Symptom:** `winpmem_mini_x64.exe` reports access denied when capturing memory.

**Fix:** Run WinPmem from an elevated command prompt (Run as Administrator). The victim user account does not have rights to dump physical memory; switch to Administrator for this step.
