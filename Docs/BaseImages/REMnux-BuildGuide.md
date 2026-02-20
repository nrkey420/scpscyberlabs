# REMnux — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `remnux-7.0` |
| **VHDX path** | `C:\CyberLab\Templates\remnux-7.0.vhdx` |
| **Used in** | Lab 5 (Malware Analysis Sandbox) |
| **Role** | Malware analyst workstation and fake internet provider (INetSim); per-student |
| **Build script** | None — REMnux is distributed as a pre-built OVA; this guide covers the import and conversion process |
| **Resources** | 2 vCPU, 4 GB RAM, 40 GB dynamic VHDX |
| **Base OS** | REMnux 7.0 (Ubuntu 20.04 LTS base) |

> **CRITICAL — NETWORK ISOLATION:** This VM must **never** have access to the real internet during lab sessions. REMnux runs INetSim, which simulates internet services (DNS, HTTP, HTTPS, SMTP, etc.) and serves as the fake internet for the malware sandbox. If REMnux has real internet access, malware callbacks will reach real C2 infrastructure. The `analysis-net-C{ClassId}-S{StudentId}` private switch has no external routing — this isolation must be verified before every lab.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Importing the REMnux OVA into Hyper-V](#2-importing-the-remnux-ova-into-hyper-v)
3. [Post-Import Configuration](#3-post-import-configuration)
4. [Tools Installed on REMnux](#4-tools-installed-on-remnux)
5. [INetSim Configuration Reference](#5-inetsim-configuration-reference)
6. [Network Isolation — Verification and Architecture](#6-network-isolation--verification-and-architecture)
7. [Malware Analysis Workflow](#7-malware-analysis-workflow)
8. [Network Interfaces](#8-network-interfaces)
9. [Default Credentials After Build](#9-default-credentials-after-build)
10. [Verification Steps](#10-verification-steps)
11. [Snapshot and Storage](#11-snapshot-and-storage)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

### Download REMnux OVA

REMnux is distributed as an OVA (Open Virtual Appliance). Download from the official site:

```
URL: https://remnux.org/
Version: REMnux 7.0 (Ubuntu 20.04 base)
File: remnux-v7.0-focal-disk.ova
```

Verify the download using the SHA256 checksum published on the REMnux website.

### Tools Required on the Host

- **StarWind V2V Converter** (free) or **VirtualBox** — used to convert the OVA's VMDK to VHDX format. Download from StarWind: `https://www.starwindsoftware.com/starwind-v2v-converter`
- Hyper-V with at least 50 GB free on the template storage path.

---

## 2. Importing the REMnux OVA into Hyper-V

Hyper-V cannot natively import OVA files. The VMDK disk image must first be extracted from the OVA and converted to VHDX.

### Step 1 — Extract the VMDK from the OVA

An OVA file is a tar archive. Extract it:

```powershell
# Extract OVA (OVA is a tar file)
# Using 7-Zip (install if not present: choco install 7zip)
& "C:\Program Files\7-Zip\7z.exe" e "remnux-v7.0-focal-disk.ova" -o"C:\Temp\remnux-extract"
# The extracted directory contains .ovf and .vmdk files
```

### Step 2 — Convert VMDK to VHDX

Using StarWind V2V Converter (GUI):

1. Open StarWind V2V Converter.
2. Source: select the extracted `.vmdk` file.
3. Target: select `Microsoft VHDX — Dynamically expanding`.
4. Output path: `C:\Temp\remnux-7.0.vhdx`.
5. Run the conversion. This takes 10–20 minutes depending on disk speed.

Or using Hyper-V's `Convert-VHD`:

```powershell
# Convert VMDK to VHDX using Hyper-V PowerShell
# Note: Convert-VHD supports VMDK for Hyper-V 2012R2 and later
Convert-VHD -Path "C:\Temp\remnux-extract\remnux-v7.0-focal-disk.vmdk" `
            -DestinationPath "C:\Temp\remnux-7.0.vhdx" `
            -VHDType Dynamic
```

### Step 3 — Create a Hyper-V VM Using the Converted VHDX

```powershell
# Create the VM
New-VM -Name "remnux-build" -MemoryStartupBytes 4GB -Generation 1 `
       -VHDPath "C:\Temp\remnux-7.0.vhdx" -SwitchName "Build-Management"

# Set processor count
Set-VMProcessor -VMName "remnux-build" -Count 2

# Generation 1 is used for REMnux because the OVA uses BIOS, not UEFI
```

Boot the VM and log in to verify it works before proceeding.

---

## 3. Post-Import Configuration

### Default Login

REMnux default credentials:

| Account | Password |
|---------|----------|
| `remnux` | `malware` |

Log in as `remnux` and switch to root: `sudo -s`.

### Update REMnux

```bash
# Update REMnux tools (this downloads updates for the malware analysis toolkit)
sudo remnux upgrade
# This may take 30-60 minutes depending on network speed
# Alternatively, skip for an offline build and pre-download specific tools
```

### Install Hyper-V Integration Services

REMnux is Ubuntu 20.04-based. Install the Hyper-V integration packages:

```bash
sudo apt-get install -y linux-tools-virtual linux-cloud-tools-virtual
# Load modules
for mod in hv_vmbus hv_storvsc hv_blkvsc hv_netvsc hv_utils hv_balloon; do
    sudo modprobe "$mod" 2>/dev/null || true
done
# Persist
echo -e "hv_vmbus\nhv_storvsc\nhv_blkvsc\nhv_netvsc\nhv_utils\nhv_balloon" | \
    sudo tee /etc/modules-load.d/hyperv.conf
```

### Configure INetSim

See Section 5 for full INetSim configuration.

### Sysprep

```bash
sudo -s
# Clear bash history
history -c; cat /dev/null > /root/.bash_history; cat /dev/null > /home/remnux/.bash_history
# Clear machine-id (IDs regenerated on first boot)
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
# Truncate logs
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
# Zero free space
dd if=/dev/zero of=/zero.fill bs=1M status=progress 2>/dev/null || true; sync; rm -f /zero.fill; sync
# Shut down
poweroff
```

---

## 4. Tools Installed on REMnux

REMnux 7.0 includes an extensive toolkit pre-installed by the REMnux project. The following table lists the tools used in Lab 5 and their purpose.

### Static Analysis Tools

| Tool | Purpose | Lab 5 Usage |
|------|---------|------------|
| `file` | Identify file type by magic bytes | First step on every unknown sample |
| `strings` | Extract printable strings from binaries | Find embedded URLs, IPs, registry keys, hardcoded credentials |
| `FLOSS` | FireEye FLARE Obfuscated String Solver — extracts obfuscated strings | Supplements `strings` for packed/obfuscated malware |
| `binwalk` | Firmware and binary analysis, entropy analysis | Detect packed sections, embedded files |
| `ssdeep` | Fuzzy hashing for malware family comparison | Correlate samples with known malware families |
| `exiftool` | Metadata extraction | Analyse document metadata in malicious Office/PDF files |
| `pdfid` / `pdf-parser` | PDF structure analysis | Identify malicious PDF elements (JavaScript, embedded files) |
| `oletools` (olevba, oledump) | Microsoft Office macro analysis | Extract VBA macros from malicious .doc/.xls files |
| `pecheck` / `pe-sieve` | PE file structure analysis | Examine PE headers, imports, exports, sections |
| `objdump` / `radare2` | Disassembly | Command-line disassembly for quick static analysis |
| `Ghidra` | Full reverse engineering framework | Decompilation and deep disassembly (Objective 4 in Lab 5) |

### Dynamic Analysis Tools

| Tool | Purpose | Lab 5 Usage |
|------|---------|------------|
| `strace` | System call tracer for Linux | Monitor syscalls made by Linux malware samples |
| `ltrace` | Library call tracer | Track library function calls |
| `Wireshark` | Network packet capture and analysis | Capture C2 traffic during malware detonation |
| `tcpdump` | Command-line packet capture | Lightweight alternative to Wireshark |
| `NetworkMiner` | Network forensics — extracts files from PCAP | Recover dropped files transmitted over HTTP from PCAP |
| `ngrep` | Network grep — match patterns in live traffic | Quick protocol inspection without full capture |

### Network Simulation (INetSim)

| Tool | Purpose | Lab 5 Usage |
|------|---------|------------|
| `INetSim` | Simulates internet services (DNS, HTTP, HTTPS, SMTP, FTP, IRC, etc.) | Provides a fake internet for malware to connect to; captures callbacks |

### YARA

| Tool | Purpose | Lab 5 Usage |
|------|---------|------------|
| `yara` | Malware classification by pattern matching | Students write YARA rules (Objective 5) and test them against samples |
| `yarGen` | Automatic YARA rule generation from strings | Assists in rule creation for detected unique strings |

### Threat Intelligence

| Tool | Purpose | Lab 5 Usage |
|------|---------|------------|
| `CyberChef` | Encoding/decoding/crypto operations (web-based) | Decode base64-encoded strings, reverse XOR obfuscation |

---

## 5. INetSim Configuration Reference

INetSim (Internet Services Simulator) is the centrepiece of the REMnux malware analysis setup. It binds to the `analysis-net` IP address and simulates all common internet services, capturing every request the malware makes.

### Configuration File

INetSim's configuration is at `/etc/inetsim/inetsim.conf`. The following settings are applied during the REMnux build:

```ini
# /etc/inetsim/inetsim.conf — SCPS CyberLab Lab 5 configuration

# Bind to the REMnux analysis-net IP address
service_bind_address    10.CLASS_ID.STUDENT_ID.10

# DNS settings — INetSim responds to all DNS queries with its own IP
# This causes malware to connect to INetSim when resolving any domain
dns_default_ip          10.CLASS_ID.STUDENT_ID.10
dns_default_ttl         1800
dns_bind_port           53
dns_bind_port_udp       53

# HTTP/HTTPS — INetSim serves a generic response to all HTTP requests
http_bind_port          80
https_bind_port         443
http_fakemode           yes
http_fakefile           sample200.html
https_fakefile          sample200.html

# SMTP — captures all email sent by malware (e.g., spam bots)
smtp_bind_port          25
smtp_fqdn_hostname      mail.inetsimdomain.com
smtp_banner             220 mail.inetsimdomain.com ESMTP

# FTP — captures FTP upload/download attempts
ftp_bind_port           21
ftp_banner              220 FTP server ready.

# IRC — captures IRC-based botnet communication
irc_bind_port           6667
irc_fqdn_hostname       irc.inetsimdomain.com

# POP3/IMAP
pop3_bind_port          110
imap_bind_port          143

# Logging directory
log_dir                 /var/log/inetsim
data_dir                /var/lib/inetsim

# Report directory (written when INetSim is stopped)
report_dir              /var/log/inetsim/reports
```

> **Note:** The IP placeholders `10.CLASS_ID.STUDENT_ID.10` are substituted at deploy time by the orchestration module's deploy hook.

### Starting and Stopping INetSim

```bash
# Start INetSim (must run as root)
sudo inetsim

# INetSim runs in the foreground and logs all activity to the terminal
# To run in background:
sudo inetsim &

# Stop INetSim (Ctrl+C if foreground, or kill the process)
# On stop, INetSim writes a summary report to /var/log/inetsim/reports/
sudo pkill inetsim

# Check INetSim logs
ls /var/log/inetsim/
cat /var/log/inetsim/main.log
```

### Checking INetSim Service Logs

Each INetSim simulated service writes its own log:

```bash
ls /var/log/inetsim/
# Example files:
# service_17_dns_53.log    — DNS queries received from malware
# service_17_http_80.log   — HTTP requests received from malware
# service_17_https_443.log — HTTPS requests received from malware
# service_17_smtp_25.log   — Email send attempts
```

Students review these logs to identify which domains, URLs, and services the malware contacts.

---

## 6. Network Isolation — Verification and Architecture

### Why Isolation is Critical

If REMnux has internet access during malware detonation:
- Malware successfully reaches its real C2 server
- Real malware payloads may be downloaded and staged
- The lab network could be used for real C2 communication
- Attacker infrastructure receives reconnaissance data about the lab environment

### Architecture

The `analysis-net` private switch connects REMnux, FlareVM, and the Windows Sandbox. pfSense sits on the same switch and has its WAN adapter **disconnected** (no external routing) in Lab 5 configuration. The only DNS, HTTP, and SMTP services on the network are provided by INetSim on REMnux.

### Verification Before Each Lab Session

Run these checks from the Hyper-V host **before telling students to detonate any samples**:

```powershell
# 1. Confirm the analysis-net switch has no external adapter
Get-VMSwitch -Name "analysis-net-C*" | Select-Object Name, SwitchType
# SwitchType must be: Private (not External or Internal)

# 2. Confirm pfSense WAN adapter is disconnected (Lab 5 only)
Get-VMNetworkAdapter -VMName "pfsense-C1-S1" | Select-Object Name, SwitchName
# The WAN adapter (first NIC) should have SwitchName = "" (not connected)

# 3. From inside the Windows Sandbox VM (via console), attempt to ping a real IP
# ping 8.8.8.8
# Expected: Request timed out (no route to external internet)

# 4. Confirm INetSim is running on REMnux (from the REMnux console)
# ps aux | grep inetsim
# Expected: inetsim process listed
```

---

## 7. Malware Analysis Workflow

The Lab 5 malware analysis workflow proceeds in this sequence. Each step must complete before starting the next.

1. **Start INetSim on REMnux** — REMnux begins simulating internet services and logging all requests.
2. **Start Wireshark capture on REMnux** — capture all traffic on `eth0` (the analysis-net interface).
3. **Perform static analysis on FlareVM** — students analyse the sample before execution (strings, PE structure, imports).
4. **Snapshot the Windows Sandbox** — restore the `InitialState` checkpoint on the Windows Sandbox before each detonation.
5. **Copy the malware sample to the Windows Sandbox** — delivered via Hyper-V file copy (not network transfer) to avoid triggering early network callbacks.
6. **Detonate the malware on the Windows Sandbox** — run the sample; monitor with Process Monitor and Process Explorer.
7. **Stop the Windows Sandbox** — do not let the sandbox run unmonitored after detonation.
8. **Analyse on REMnux** — review INetSim logs and the Wireshark PCAP.
9. **Restore the Windows Sandbox to InitialState** — mandatory before any subsequent detonation.

---

## 8. Network Interfaces

Single adapter (`eth0`). In Lab 5, connected to `analysis-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.10`.

INetSim binds to this IP address and serves all simulated internet services on it.

---

## 9. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `remnux` (OS) | `malware` (REMnux default) | Change recommended but not enforced for lab use |
| `root` (sudo) | Same as `remnux` (via sudo) | `sudo -s` for root shell |

---

## 10. Verification Steps

### Step 1 — INetSim Starts

```bash
sudo inetsim &
sleep 3
# Check that INetSim reports all services started
# Expected output includes lines like:
# [*]  Starting service http (listening on 10.x.x.x:80)
# [*]  Starting service dns (listening on 10.x.x.x:53)
# [*]  Starting service smtp (listening on 10.x.x.x:25)
```

### Step 2 — DNS Simulation Works

From the Windows Sandbox VM (via Hyper-V console), set DNS to `10.{ClassId}.{StudentId}.10` and resolve any domain:

```
nslookup google.com 10.x.x.x
# Expected: Returns 10.x.x.x (INetSim's own IP for all DNS queries)
```

### Step 3 — HTTP Simulation Works

```bash
curl http://google.com
# Expected: INetSim fake HTML page (not Google's real page)
```

### Step 4 — Wireshark Captures Traffic

```bash
# Capture traffic on the analysis-net interface for 10 seconds
sudo timeout 10 tcpdump -i eth0 -w /tmp/test.pcap
ls -la /tmp/test.pcap
# Expected: file exists with non-zero size
```

### Step 5 — Ghidra Launches

```bash
ghidra &
# Ghidra GUI should open (requires X11 or VNC session)
```

### Step 6 — YARA Is Functional

```bash
yara --version
# Expected: YARA version string
```

---

## 11. Snapshot and Storage

```powershell
Stop-VM -Name "remnux-build" -Force
Move-Item "remnux-build.vhdx" "C:\CyberLab\Templates\remnux-7.0.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\remnux-7.0.vhdx" -Name IsReadOnly -Value $true
```

---

## 12. Troubleshooting

### INetSim Fails to Bind — Address Already in Use

**Symptom:** INetSim reports "address already in use" for port 53 or 80.

**Cause:** `systemd-resolved` is using port 53 on localhost. On Ubuntu 20.04, `systemd-resolved` binds to `127.0.0.53:53` — this does not conflict with INetSim binding to the lab IP `10.x.x.x:53`, but if INetSim tries to bind to `0.0.0.0:53`, there is a conflict.

**Fix:** Ensure `service_bind_address` in `inetsim.conf` is set to the specific `10.x.x.x` IP, not `0.0.0.0`. If the IP changes at deploy time, update the config before starting INetSim.

### Ghidra Fails to Launch — No Display

**Symptom:** Running `ghidra` returns "cannot connect to X server."

**Fix:** Connect to the REMnux VM via VNC (REMnux runs a VNC-accessible desktop) rather than SSH. Use a VNC client on the instructor workstation to connect to `10.{ClassId}.{StudentId}.10:5900`. Alternatively, use Hyper-V Enhanced Session mode if enabled.

### Malware Sample Triggers Real Network Callbacks

**Symptom:** Wireshark shows connections to real external IP addresses.

**Cause:** Network isolation has failed — the analysis-net switch has external routing.

**Immediate action:** Stop all VMs on the affected analysis-net switch immediately. Verify the switch type in Hyper-V Manager. If the switch type is not Private, delete it and recreate as Private. Review the session deployment logs to identify how external routing was introduced.
