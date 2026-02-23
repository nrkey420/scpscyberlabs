# FLARE-VM (Windows 10) — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `flarevm-win10-2024` |
| **VHDX path** | `C:\CyberLab\Templates\flarevm-win10-2024.vhdx` |
| **Used in** | Lab 5 (Malware Analysis — Windows-side static/dynamic analysis workstation) |
| **Role** | FLARE-VM tool distribution on Windows 10; provides PE analysis, disassembly, debugging, and FakeNet-NG for network simulation |
| **Build script** | None — built manually; FLARE-VM installer handles tool deployment |
| **Resources** | 4 vCPU, 8 GB RAM, 80 GB dynamic VHDX |
| **Base OS** | Windows 10 Enterprise 21H2 (amd64) |

> **Why Defender is Disabled:** FLARE-VM installs legitimate malware analysis tools (debuggers, disassemblers, PE parsers) that Windows Defender flags as malicious due to their dual-use nature. Defender must be disabled for the FLARE-VM installer to function and for analysts to work with malware samples without interference. This is mitigated entirely by network isolation — the FlareVM is deployed on `analysis-net`, which is an internal Hyper-V private switch with no external routing. In Lab 5, the pfSense WAN adapter is disconnected from any external switch, making internet access impossible from the analysis network.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Disabling Windows Defender](#4-disabling-windows-defender)
5. [Installing FLARE-VM](#5-installing-flare-vm)
6. [Tool Inventory](#6-tool-inventory)
7. [FakeNet-NG Configuration](#7-fakenet-ng-configuration)
8. [Sample Submission Workflow](#8-sample-submission-workflow)
9. [Network Interfaces](#9-network-interfaces)
10. [Default Credentials After Build](#10-default-credentials-after-build)
11. [Snapshot Strategy](#11-snapshot-strategy)
12. [Verification Steps](#12-verification-steps)
13. [Snapshot and Storage](#13-snapshot-and-storage)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

- Windows 10 Enterprise 21H2 ISO (Volume Licensing / MSDN / Evaluation Center)
- Internet access during the build — FLARE-VM downloads tools from GitHub and Chocolatey during installation
- PowerShell 5.1 (included with Windows 10)
- Build time: approximately 90–120 minutes (tool download time depends on bandwidth)

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **8192 MB** |
| Dynamic Memory | Disabled |
| Processor count | **4 vCPU** |
| Virtual hard disk | **80 GB**, Dynamically expanding |
| Network adapter | External-Internet (for tool downloads during build) |
| Secure Boot | Leave enabled |

---

## 3. OS Installation

Boot from the Windows 10 Enterprise ISO:

| Setting | Value |
|---------|-------|
| Language | English (United States) |
| Edition | Windows 10 Enterprise |
| Install type | Custom: full disk |
| Account | Local account — username `analyst` |
| Password | Set a strong temporary password (overwritten at deploy) |

After first boot, enable the Administrator account and set the build password:

```powershell
# Open elevated PowerShell
net user Administrator /active:yes
net user Administrator LabBuildPass!2024
# Log off analyst and log in as Administrator for the build steps
```

---

## 4. Disabling Windows Defender

Defender must be fully disabled before running the FLARE-VM installer. Partial disabling (real-time protection only) is insufficient — Defender's cloud-delivered protection and tamper protection will re-enable components.

### Step 1 — Disable Tamper Protection (GUI required)

Tamper Protection cannot be disabled via PowerShell on Windows 10. It must be turned off manually:

1. Open **Windows Security** (Start → Windows Security)
2. Navigate to **Virus & threat protection** → **Virus & threat protection settings**
3. Scroll to **Tamper Protection** and toggle it **Off**
4. Confirm the UAC prompt

### Step 2 — Disable Defender via PowerShell

```powershell
# After tamper protection is off, run as Administrator
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true
Set-MpPreference -DisableIOAVProtection $true
Set-MpPreference -DisableScriptScanning $true
Set-MpPreference -DisableBlockAtFirstSeen $true
Set-MpPreference -DisableAntiSpyware $true
Set-MpPreference -DisableAntiVirus $true

# Disable via Group Policy registry keys for persistence
$defenderPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
New-Item -Path $defenderPolicy -Force | Out-Null
Set-ItemProperty -Path $defenderPolicy -Name "DisableAntiSpyware" -Value 1 -Type DWord
Set-ItemProperty -Path $defenderPolicy -Name "DisableAntiVirus" -Value 1 -Type DWord

# Disable cloud protection
New-Item -Path "$defenderPolicy\Spynet" -Force | Out-Null
Set-ItemProperty -Path "$defenderPolicy\Spynet" -Name "SpynetReporting" -Value 0 -Type DWord

# Disable WinDefend and Sense services
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend" -Name "Start" -Value 4 -Type DWord
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Sense" -Name "Start" -Value 4 -Type DWord

Restart-Computer -Force
```

After reboot, verify Defender is disabled:

```powershell
Get-MpPreference | Select-Object DisableRealtimeMonitoring, DisableAntiSpyware
# Expected: Both True
```

---

## 5. Installing FLARE-VM

FLARE-VM is a Mandiant-maintained PowerShell installer that uses Chocolatey and FLARE's custom Chocolatey packages to install the full malware analysis tool suite.

### Download and Run the Installer

```powershell
# Set execution policy for the session
Set-ExecutionPolicy Bypass -Scope Process -Force

# Download the FLARE-VM installer
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/mandiant/flare-vm/main/install.ps1" `
    -OutFile "C:\Temp\flare-install.ps1" -UseBasicParsing

# Run the installer (unattended)
# The -noWait flag skips the countdown; -noGui skips the optional GUI package selector
C:\Temp\flare-install.ps1 -noWait -noGui -noChecks
```

The installer will:
1. Install Chocolatey
2. Add the FLARE-VM Chocolatey package source
3. Download and install all tools from the FLARE-VM package list
4. Configure the desktop with tool shortcuts
5. Reboot automatically when complete

The installation takes 60–90 minutes depending on download speed. Installation progress is logged to the PowerShell console. If the session disconnects, re-run the same command — Chocolatey will skip already-installed packages.

---

## 6. Tool Inventory

The following tools are installed by FLARE-VM and are used in Lab 5.

### Static Analysis Tools

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **pestudio** | PE file analysis — imports, exports, strings, entropy | First-pass analysis of unknown binaries; identifies suspicious API imports |
| **PE-bear** | PE header viewer and editor | Examining PE section characteristics, TLS callbacks, rich headers |
| **CFF Explorer** | PE header and data directory browser | Navigating PE structures, editing resources |
| **Detect-It-Easy (DIE)** | File format detection and packer identification | Determining if a binary is packed or obfuscated before analysis |
| **strings** (Sysinternals) | ASCII and Unicode string extraction | Extracting readable IOCs (URLs, registry keys, filenames) from binaries |
| **FLOSS** | FLARE Obfuscated String Solver | Extracts strings decoded at runtime that `strings` misses; handles XOR encoding |
| **binwalk** | Embedded file extraction | Finding embedded executables, archives, or blobs in binary files |
| **oletools** | Office document macro analysis | Analyzing VBA macros in `.doc`/`.xls` files; extracting shellcode |
| **exiftool** | Metadata extraction | Extracting author, creation date, and embedded metadata from files |
| **HashMyFiles** | File hashing (MD5, SHA1, SHA256) | Computing hashes for VirusTotal lookups and IOC documentation |

### Disassembly and Decompilation Tools

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **Ghidra** | NSA open-source reverse engineering framework | Primary disassembly and decompilation; analyzing crypto routines |
| **IDA Free** | IDA Pro free edition — industry-standard disassembler | Cross-referencing disassembly; stack frame analysis |
| **x64dbg / x32dbg** | Dynamic debugger for 64-bit and 32-bit binaries | Setting breakpoints, stepping through decryption loops, dumping memory |
| **Binary Ninja** (demo) | Modern disassembly and decompilation platform | Alternative decompiler; HLIL output often clearer than Ghidra |
| **dnSpy** | .NET assembly decompiler and debugger | Decompiling C# malware to readable source; live .NET debugging |
| **de4dot** | .NET obfuscation remover | Deobfuscating .NET assemblies before loading into dnSpy |

### Dynamic Analysis and Monitoring Tools

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **Process Monitor (ProcMon)** | File system, registry, process, and network activity monitor | Capturing all file and registry changes during malware execution |
| **Process Explorer** | Advanced Task Manager with DLL and handle views | Identifying injected DLLs, parent-child process relationships |
| **Autoruns** | Startup entry enumerator across all persistence locations | Comparing pre- and post-execution persistence mechanisms |
| **Wireshark** | Packet capture and protocol dissection | Capturing FakeNet-NG traffic; examining C2 protocol structure |
| **FakeNet-NG** | Network simulation for malware sandboxing | Intercepting and logging all network activity from malware samples |
| **regshot** | Registry snapshot and comparison | Diff-ing registry state before and after malware execution |

### Memory Analysis Tools

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **Volatility** | Memory forensics framework | Analyzing memory dumps from the Windows 10 Sandbox target |
| **WinPmem** | Physical memory acquisition | Capturing live memory images for analysis |

### Script and Shellcode Analysis

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **CyberChef** | Data transformation and decoding Swiss army knife | Decoding base64, XOR decryption, decompressing payloads |
| **scdbg** | Shellcode emulation and API call logging | Running shellcode without executing it natively |
| **malwoverview** | Multi-engine file reputation lookup | Batch VirusTotal lookups from command line |

### YARA

| Tool | Purpose | Common Usage in Lab 5 |
|------|---------|----------------------|
| **YARA** | Pattern-matching rule engine for malware detection | Writing detection rules for the Lab 5 objective; testing against samples |
| **YARA-X** | Next-generation YARA implementation | Alternative rule execution; supports module extensions |

---

## 7. FakeNet-NG Configuration

FakeNet-NG (Fake Network) is a network simulation tool that captures and responds to all outbound network connections, making malware believe it has internet access while logging all communications. In Lab 5, FakeNet-NG runs on the FlareVM and handles the network traffic that malware generates.

### How FakeNet-NG Works

When a malware sample calls out to a C2 server, FakeNet-NG:
1. Intercepts the DNS query and returns a local IP
2. Accepts the TCP/UDP connection on the requested port
3. Responds with a protocol-appropriate default response (HTTP 200, SMTP banner, etc.)
4. Logs the full request and response to a PCAP file and log file

### Configuration File Location

FakeNet-NG is installed to `C:\Program Files\FLARE\FakeNet-NG\`. The primary configuration file is:

```
C:\Program Files\FLARE\FakeNet-NG\configs\default.ini
```

### Key Configuration Settings

```ini
[FakeNet]
# Network mode: SingleHost (all traffic intercepted on this machine)
NetworkMode: SingleHost

# Divert all traffic, including traffic to other hosts on the segment
DivertTraffic: Yes

# Default listener (catches anything not matched by a specific listener)
DefaultListener: RawListener

[Logging]
LogFile: C:\FakeNetLogs\fakenet.log
PcapDumpFile: C:\FakeNetLogs\fakenet.pcap

[DNS]
Enabled: True
Port: 53
Protocol: UDP
# Return this IP for all DNS queries — FakeNet itself
ResponseA: 127.0.0.1

[HTTP]
Enabled: True
Port: 80
Protocol: TCP
# Respond with a 200 OK and a generic HTML body to all HTTP requests
DefaultResponse: C:\Program Files\FLARE\FakeNet-NG\listeners\templates\http_default.html

[HTTPS]
Enabled: True
Port: 443
Protocol: TCP
UseSSL: Yes

[SMTP]
Enabled: True
Port: 25
Protocol: TCP

[FTP]
Enabled: True
Port: 21
Protocol: TCP

[IRC]
Enabled: True
Port: 6667
Protocol: TCP

[RawListener]
Enabled: True
Port: 1337
Protocol: TCP
```

### Creating the Log Directory

```powershell
New-Item -Path "C:\FakeNetLogs" -ItemType Directory -Force
```

### Starting FakeNet-NG

```powershell
# Run as Administrator in an elevated command prompt
cd "C:\Program Files\FLARE\FakeNet-NG"
fakenet.exe -c configs\default.ini
```

### Reading FakeNet-NG Output

FakeNet-NG writes to both the console and the log file. Key log entries:

- `[*] DNS query: evil.example.com` — malware DNS resolution
- `[HTTP] GET /beacon HTTP/1.1` — C2 beacon request
- `[*] Saved PCAP: C:\FakeNetLogs\fakenet.pcap` — capture complete

Open the PCAP file in Wireshark for protocol-level analysis:

```powershell
Start-Process "C:\Program Files\Wireshark\Wireshark.exe" -ArgumentList "C:\FakeNetLogs\fakenet.pcap"
```

---

## 8. Sample Submission Workflow

The Lab 5 workflow involves transferring malware samples from REMnux (the Linux analysis VM) to either FlareVM or the Windows 10 Sandbox target for analysis. This section documents the FlareVM side of the workflow.

### Receiving Samples from REMnux

Samples are placed on a shared analysis directory. The recommended transfer method uses a Hyper-V file copy from the instructor's host:

```powershell
# On the Hyper-V host — copy a sample to the FlareVM
Copy-VMFile -VMName "FlareVM-S01" `
    -SourcePath "C:\CyberLab\Samples\Lab5\sample01.exe" `
    -DestinationPath "C:\MalwareSamples\sample01.exe.sample" `
    -FileSource Host -CreateFullPath
```

The `.sample` extension prevents accidental execution. Analysts must rename the file before analysis.

### Pre-Analysis Checklist

Before executing any sample in the Windows 10 Sandbox target:

1. Verify network isolation — confirm `analysis-net` has no external route
2. Start FakeNet-NG on the FlareVM
3. Start ProcMon on the target with a capture filter set to the sample's process name
4. Take a regshot baseline snapshot on the target
5. Copy the sample to the target via Hyper-V file copy or shared folder on analysis-net

### Submitting a Sample to the Windows 10 Sandbox Target

```powershell
# On the Hyper-V host
Copy-VMFile -VMName "Win10Sandbox-S01" `
    -SourcePath "C:\CyberLab\Samples\Lab5\sample01.exe" `
    -DestinationPath "C:\Samples\sample01.exe.sample" `
    -FileSource Host -CreateFullPath
```

The student then logs into the Windows 10 Sandbox and renames the file for execution:

```powershell
# On the Windows 10 Sandbox target
Rename-Item "C:\Samples\sample01.exe.sample" "C:\Samples\sample01.exe"
```

### Post-Analysis Artifacts

After execution, collect:

| Artifact | Location | Collection Method |
|----------|----------|-------------------|
| FakeNet-NG PCAP | `C:\FakeNetLogs\fakenet.pcap` | Copy from FlareVM |
| FakeNet-NG log | `C:\FakeNetLogs\fakenet.log` | Copy from FlareVM |
| ProcMon log | Saved as `.pml` from ProcMon File menu | Export CSV for searching |
| Regshot diff | Second shot taken after execution; diff saved as HTML | Review in browser |
| Memory dump | Captured with WinPmem from target | Analyze with Volatility on FlareVM |

---

## 9. Network Interfaces

Single adapter. In Lab 5, connected to `analysis-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.11`. The analysis network is an isolated Hyper-V private switch. The pfSense WAN adapter in Lab 5 has no external switch attachment — there is no route to the internet or to production networks.

---

## 10. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `Administrator` | `LabBuildPass!2024` (overridden at deploy) | Local administrator; primary analysis account |
| `analyst` | Set during OS install (overridden at deploy) | Standard user created during Windows setup |

---

## 11. Snapshot Strategy

The FLARE-VM build is resource-intensive and time-consuming. The snapshot strategy uses Hyper-V checkpoints during the build phase only, then converts to a read-only parent VHDX.

### Build-Phase Checkpoints

Take Hyper-V checkpoints at these milestones during the build:

| Checkpoint Name | When to Take |
|----------------|-------------|
| `FlareVM-OSInstalled` | After Windows 10 install + Administrator account setup, before Defender disable |
| `FlareVM-DefenderDisabled` | After Defender fully disabled and rebooted, before FLARE-VM installer |
| `FlareVM-ToolsInstalled` | After FLARE-VM installer completes — this is the **AnalysisReady** state |

The `FlareVM-ToolsInstalled` checkpoint represents the **AnalysisReady** state: all tools installed, Defender disabled, FakeNet-NG configured, ready for analysis work. If an install step fails partway through, restore to `FlareVM-DefenderDisabled` and re-run the FLARE-VM installer.

### AnalysisReady Checkpoint

The `AnalysisReady` checkpoint (equivalent to `FlareVM-ToolsInstalled`) is the reference state from which all per-student differencing disks are derived. After creating the final VHDX:

1. Delete all Hyper-V checkpoints (they are embedded in the build AVHDX, not the final VHDX)
2. Export the merged VHDX as the read-only parent

```powershell
# After all tools installed and configured
Stop-VM -Name "flarevm-build" -Force

# Merge and export the VHDX (if checkpoints exist, they must be merged first)
# In Hyper-V Manager: right-click VM → Delete Checkpoint (this merges AVHDX into VHDX)
# Then move the clean VHDX
Move-Item "flarevm-build.vhdx" "C:\CyberLab\Templates\flarevm-win10-2024.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\flarevm-win10-2024.vhdx" -Name IsReadOnly -Value $true
```

---

## 12. Verification Steps

### Step 1 — FLARE-VM Tools Present

```powershell
# Check for key tools on the desktop and PATH
Test-Path "C:\Tools\FLARE\x64dbg\x64dbg.exe"
# Expected: True

Test-Path "C:\ProgramData\chocolatey\bin\pestudio.exe"
# Expected: True

Get-Command ghidra -ErrorAction SilentlyContinue
# Expected: returns a CommandInfo object
```

### Step 2 — FakeNet-NG Starts

```powershell
# Test FakeNet-NG starts without error (press Ctrl+C to stop after verification)
cd "C:\Program Files\FLARE\FakeNet-NG"
fakenet.exe -c configs\default.ini
# Expected: console output shows listeners starting, no exceptions thrown
```

### Step 3 — Defender Disabled

```powershell
Get-MpPreference | Select-Object DisableRealtimeMonitoring, DisableAntiSpyware
# Expected: Both True

Get-Service WinDefend | Select-Object Name, StartType, Status
# Expected: StartType=Disabled or Manual, Status=Stopped
```

### Step 4 — FLOSS Working

```powershell
floss --help
# Expected: FLOSS usage information printed without error
```

### Step 5 — Wireshark Accessible

```powershell
Test-Path "C:\Program Files\Wireshark\Wireshark.exe"
# Expected: True
```

---

## 13. Snapshot and Storage

```powershell
Stop-VM -Name "flarevm-build" -Force
Move-Item "flarevm-build.vhdx" "C:\CyberLab\Templates\flarevm-win10-2024.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\flarevm-win10-2024.vhdx" -Name IsReadOnly -Value $true
```

---

## 14. Troubleshooting

### FLARE-VM Installer Fails Partway Through

**Symptom:** The installer exits with a Chocolatey error mid-way through tool installation.

**Fix:** Re-run the installer. Chocolatey tracks installed packages and skips anything already completed:

```powershell
C:\Temp\flare-install.ps1 -noWait -noGui -noChecks
```

If a specific package consistently fails, exclude it:

```powershell
C:\Temp\flare-install.ps1 -noWait -noGui -noChecks -packages_to_exclude "ida-free"
```

### Ghidra Fails to Launch — Java Not Found

**Symptom:** Ghidra launches but immediately exits, or shows a Java error.

**Fix:** FLARE-VM installs a compatible JDK. If it is missing:

```powershell
choco install openjdk17 -y
# Restart after install and retry Ghidra
```

### FakeNet-NG — Access Denied on Network Capture

**Symptom:** FakeNet-NG starts but reports access denied when attempting to capture.

**Fix:** Run FakeNet-NG as Administrator in an elevated command prompt, not a regular PowerShell window.

### Windows Defender Re-Enables After Reboot

**Symptom:** After rebooting the deployed FlareVM, Defender real-time protection re-activates.

**Cause:** The Group Policy registry keys were not set, or Windows Update reset the tamper protection policy.

**Fix:** After deploy, re-apply the registry keys and disable tamper protection from the Security Center GUI before proceeding with lab activities.
