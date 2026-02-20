# Lab 01 — Red Team / Blue Team Cyber Range: Deployment Guide

| Field | Value |
|-------|-------|
| **Lab number** | 01 |
| **Lab name** | Red Team / Blue Team Cyber Range |
| **Difficulty** | Advanced |
| **Estimated duration** | 240 minutes |
| **Deploy script** | `Scripts/LabScenarios/Deploy-01-RedTeamBlueTeam.ps1` |
| **Template file** | `Templates/01-red-team-blue-team.json` |
| **Maximum students** | 15 (8 strongly recommended — see capacity note) |

---

## Table of Contents

1. [Lab Overview](#1-lab-overview)
2. [Network Topology](#2-network-topology)
3. [Resource Requirements](#3-resource-requirements)
4. [Prerequisites](#4-prerequisites)
5. [Deployment Steps](#5-deployment-steps)
6. [Shared VM Pre-Deployment](#6-shared-vm-pre-deployment)
7. [Verification After Deployment](#7-verification-after-deployment)
8. [Student Credential Distribution](#8-student-credential-distribution)
9. [Instructor Monitoring Setup](#9-instructor-monitoring-setup)
10. [Lab Objectives Reference](#10-lab-objectives-reference)
11. [Teardown](#11-teardown)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Lab Overview

Lab 01 is a full cyber range split between a Red Team (attackers using Kali Linux) and a Blue Team (defenders monitoring with Security Onion and Splunk). Each student receives an isolated network environment containing all target systems. Two shared monitoring VMs — Security Onion and Splunk — serve the entire class and receive forwarded logs and mirrored traffic from all student environments.

**VMs deployed per student (5 per student):**
- Kali Linux 2024.1 — Red team attacker workstation
- Windows 10 Vulnerable — Primary attack target (intentionally misconfigured)
- Windows Server 2019 AD — Active Directory domain controller (attack target)
- Ubuntu Linux Web Server — DMZ web server (attack target)
- pfSense 2.7 — Network gateway and segmentation firewall

**VMs deployed per class (2 shared):**
- Security Onion 2.4 — Blue team IDS/NSM platform
- Splunk Enterprise 9.1 — Blue team SIEM

---

## 2. Network Topology

Each student receives three private Hyper-V network segments. The shared monitoring VMs attach to a class-wide shared switch. The example below uses ClassId=1, StudentId=3.

```
                    [Kali 10.1.3.10]
                           |
                   attack-net-C1-S3
                           |
          [pfSense  WAN=attack .1  LAN=corp .1  OPT1=dmz .1]
                    |                              |
        corporate-net-C1-S3              dmz-net-C1-S3
           |               |                      |
    [Win10 .20]      [WinAD .21]           [WebSrv .30]

Shared monitoring network (shared-monitor-net-C1):
    [Security Onion 10.1.0.50]   [Splunk 10.1.0.51]
```

| Segment | Switch Name | IPs |
|---------|------------|-----|
| Attack | `attack-net-C{C}-S{S}` | Kali: `.10`, pfSense WAN: `.1` |
| Corporate | `corporate-net-C{C}-S{S}` | pfSense LAN: `.1`, Win10: `.20`, WinAD: `.21` |
| DMZ | `dmz-net-C{C}-S{S}` | pfSense OPT1: `.1`, WebSrv: `.30` |
| Shared Monitor | `shared-monitor-net-C{C}` | Security Onion: `10.C.0.50`, Splunk: `10.C.0.51` |

---

## 3. Resource Requirements

### Per-Student Allocation

| VM | vCPU | RAM | Initial Disk (Differencing) |
|----|------|-----|-----------------------------|
| Kali Linux | 2 | 4 GB | ~8 GB |
| Windows 10 | 2 | 4 GB | ~12 GB |
| Windows Server AD | 2 | 4 GB | ~14 GB |
| Ubuntu Web Server | 1 | 2 GB | ~5 GB |
| pfSense | 2 | 2 GB | ~3 GB |
| **Per-student total** | **9 vCPU** | **16 GB** | **~42 GB** |

### Shared VM Allocation (one set per class)

| VM | vCPU | RAM | Disk |
|----|------|-----|------|
| Security Onion | 4 | 8 GB | ~20 GB (differencing) |
| Splunk | 4 | 8 GB | ~20 GB (differencing) |
| **Shared total** | **8 vCPU** | **16 GB** | **~40 GB** |

### Total for Class of N Students

| Students | vCPU | RAM | Estimated Disk |
|----------|------|-----|---------------|
| 4 | 44 | 80 GB | 208 GB |
| 8 | 80 | 144 GB | 376 GB |
| 12 | 116 | 208 GB | 544 GB |
| 15 | 143 | 256 GB | 670 GB |

> **Capacity Warning:** Lab 01 is the most resource-intensive scenario. A Hyper-V host with 256 GB RAM and 1 TB available disk is required for a class of 15. Strongly recommend capping at 8 students per session on a host with 192 GB RAM. Differencing disk usage grows throughout the session; allocate 50–100 GB headroom beyond the estimates above.

---

## 4. Prerequisites

### Host Requirements

- Windows Server 2022 with Hyper-V role enabled
- PowerShell 7.x (for `-Parallel` ForEach-Object support)
- OpenSSH client: `winget install Microsoft.OpenSSH.Beta` or `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`
- `sshpass` utility on PATH (used by the deploy script to non-interactively authenticate to Linux VMs)
- Administrator privileges on the Hyper-V host

### Template VHDXs Required (all read-only in `C:\CyberLab\Templates\`)

| File | Size Approx |
|------|------------|
| `kali-linux-2024.1.vhdx` | 25 GB |
| `windows-10-vulnerable.vhdx` | 35 GB |
| `windows-server-2019-ad.vhdx` | 40 GB |
| `ubuntu-server-22.04-web.vhdx` | 10 GB |
| `pfsense-2.7.vhdx` | 8 GB |
| `security-onion-2.4.vhdx` | 60 GB |
| `splunk-enterprise-9.1.vhdx` | 60 GB |

### Pre-Deployment Checks

```powershell
# Run from elevated PowerShell on the Hyper-V host
Scripts\LabScenarios\Common\Test-LabReadiness.ps1 -LabType RedTeamBlueTeam -ClassId 1 -StudentCount 8
```

This script verifies:
- All template VHDXs are present and marked read-only
- Sufficient free disk space
- Hyper-V service running
- No conflicting VM or switch names from a prior session

---

## 5. Deployment Steps

### Step 1 — Run the Deploy Script

```powershell
# Elevated PowerShell on the Hyper-V host
$sessionId = [guid]::NewGuid()

.\Scripts\LabScenarios\Deploy-01-RedTeamBlueTeam.ps1 `
    -SessionId $sessionId `
    -ClassId 1 `
    -StudentIds @('alice', 'bob', 'carol', 'dan', 'eva', 'frank', 'grace', 'henry') `
    -TimeoutMinutes 90
```

### Deployment Phases and Timing

| Phase | Actions | Estimated Time |
|-------|---------|---------------|
| Prerequisites validation | Template checks, disk space, switch conflicts | ~30 seconds |
| Virtual switch creation | 3 per-student + 1 shared = 25 switches for 8 students | ~30 seconds |
| Shared VM deployment | Security Onion + Splunk differencing disks, VMs, boot, configure | ~8–12 minutes |
| Per-student VM deployment (parallel, ThrottleLimit=5) | 5 VMs × 8 students = 40 VMs | ~10–20 minutes |
| Readiness validation | Heartbeat check on all VMs | ~2 minutes |
| Credential export | Write session manifest to `C:\CyberLab\Sessions\` | ~5 seconds |
| **Total** | | **~20–35 minutes** |

### Deployment Log

All output is captured to:
```
C:\CyberLab\Logs\Deploy-Lab01-{ShortSessionId}-{timestamp}.log
```

Monitor progress by tailing the log in a second PowerShell window:
```powershell
Get-Content "C:\CyberLab\Logs\Deploy-Lab01-*.log" -Wait -Tail 40
```

---

## 6. Shared VM Pre-Deployment

Security Onion and Splunk are deployed once per class, not per student. They must be up and configured before students begin. The deploy script handles this automatically in Step 2, but if the shared VMs were deployed in a prior session and are already running, skip re-deployment:

```powershell
# Check if shared VMs are already running for this ClassId
Get-VM | Where-Object { $_.Name -like "*SecOnion-C1*" -or $_.Name -like "*Splunk-C1*" } |
    Select-Object Name, State, Heartbeat
```

If shared VMs are running with `State=Running` and `Heartbeat=OkApplicationsHealthy`, pass the existing VM names to the deploy script via the `-SkipSharedVMs` switch (if re-running).

### Security Onion Multi-Student Access

After deployment, the deploy script creates the `analyst` and `instructor` accounts on Security Onion. For a class where all students share Security Onion, each student accesses it with the same `soanalyst` credentials (from the credential manifest).

If you want individual student accounts:

```bash
# On the Security Onion VM (as instructor)
for student in alice bob carol dan eva frank grace henry; do
    sudo so-user-add -u "$student" --role analyst --password "$(openssl rand -base64 12)"
done
```

---

## 7. Verification After Deployment

### Check All VMs Running

```powershell
# Get all VMs for this session by ShortId (first 8 chars of SessionId)
$shortId = $sessionId.ToString().Substring(0, 8)
Get-VM | Where-Object { $_.Name -like "*-${shortId}" } |
    Select-Object Name, State, Heartbeat | Sort-Object Name | Format-Table -AutoSize
```

Expected: All VMs show `State=Running`, `Heartbeat=OkApplicationsHealthy`.

### Verify Network Connectivity Per Student

```powershell
# From the Hyper-V host, use PowerShell Direct to test connectivity from Kali
# (substitute the actual Kali VM name and student credentials)
$kaliCred = [PSCredential]::new('student', (ConvertTo-SecureString 'StudentPassword' -AsPlainText -Force))
Invoke-Command -VMName "Lab01-Kali-C1-S1-${shortId}" -Credential $kaliCred -ScriptBlock {
    ping -c 3 10.1.1.20   # Win10
    ping -c 3 10.1.1.21   # WinAD
    ping -c 3 10.1.1.30   # WebSrv
}
```

### Verify Splunk Receiving Logs

Open a browser on the Hyper-V host and navigate to:
```
http://10.1.0.51:8000
```

Log in with the Splunk admin credentials from the session manifest. Run:
```
index=windows earliest=-5m | stats count by host
```
Expected: Counts for each student's Windows VMs.

### Verify Security Onion Alerts

Navigate to `https://10.1.0.50` and log in as `analyst`. Confirm Zeek is logging and Suricata is generating alerts.

---

## 8. Student Credential Distribution

The deploy script writes all session credentials to:
```
C:\CyberLab\Sessions\{SessionId}-credentials.json
```

The file permissions are set to `Administrators:Full` only (non-admins cannot read it). The web portal reads this file and displays per-student credentials to students at the start of the session.

The credential manifest contains, per student:

| Field | Description |
|-------|-------------|
| `Kali.IPAddress` | `10.C.S.10` — Kali SSH IP |
| `Kali.student.Password` | Session-generated password for the `student` account |
| `Windows10.IPAddress` | `10.C.S.20` |
| `Windows10.Administrator.Password` | Session-generated; used for RDP/WinRM |
| `Windows10.labuser.Password` | Session-generated; used for lateral movement objectives |
| `WindowsAD.IPAddress` | `10.C.S.21` |
| `WindowsAD.Administrator.Password` | Session-generated domain admin password |
| `LinuxWebServer.IPAddress` | `10.C.S.30` |
| `pfSense.IPAddress` | `10.C.S.1` |
| `pfSense.admin.Password` | Session-generated pfSense admin password |
| Shared Security Onion | `10.C.0.50`, `soanalyst` credentials |
| Shared Splunk | `10.C.0.51`, `admin` credentials |

Students access their credentials via the web portal at `https://{host-ip}:8443/session/{SessionId}`.

---

## 9. Instructor Monitoring Setup

### Monitoring Student Progress

The instructor has admin access to both shared monitoring VMs:

| System | URL | Role |
|--------|-----|------|
| Security Onion | `https://10.C.0.50` | IDS alerts, Zeek logs, PCAP |
| Splunk | `http://10.C.0.51:8000` | Aggregated Windows, Sysmon, Linux logs |
| pfSense (per student) | `https://10.C.S.1` | Firewall state per student |

### Splunk Search for Instructor Overview

To see all active students and their activity level:

```
index=* earliest=-30m | stats count by host, index | sort -count
```

To detect if a student has achieved domain admin (flag planted on AD):

```
index=windows EventCode=4672 OR source="*domain_admin*" | stats count by host, Account_Name | sort -count
```

### Observing Blue Team Responses

Blue team students monitor the same Security Onion and Splunk instances. To observe what a specific student is doing in Splunk without interfering:

```powershell
# SSH to Splunk VM as instructor
ssh instructor@10.1.0.51

# View recent saved searches run by students (in Splunk's internal log)
sudo grep "user=" /opt/splunk/var/log/splunk/audit.log | tail -50
```

---

## 10. Lab Objectives Reference

| Objective | Team | Points | Flag |
|-----------|------|--------|------|
| Initial Reconnaissance | Red | 100 | `FLAG{recon_complete_hosts_discovered_7a3b}` |
| Exploit Web Server Vulnerability | Red | 200 | `FLAG{web_server_compromised_rce_9f1e}` |
| Lateral Movement to Workstation | Red | 200 | `FLAG{lateral_movement_workstation_4d2c}` |
| Privilege Escalation on AD | Red | 300 | `FLAG{domain_admin_achieved_8b7a}` |
| Blue Team: Detect Initial Access | Blue | 150 | `FLAG{initial_access_detected_blue_5e9d}` |
| Blue Team: Identify Lateral Movement | Blue | 150 | `FLAG{lateral_movement_detected_blue_3c8f}` |
| Blue Team: Contain and Eradicate | Blue | 200 | `FLAG{threat_contained_eradicated_2a6b}` |
| Write After-Action Report | Both | 100 | `FLAG{after_action_report_complete_1d4e}` |

Red Team flag files are planted at:
- `FLAG{web_server_compromised_rce_9f1e}` — `/root/flag.txt` on the Ubuntu Web Server
- `FLAG{lateral_movement_workstation_4d2c}` — `C:\Users\labuser\Desktop\flag.txt` on Windows 10
- `FLAG{domain_admin_achieved_8b7a}` — `C:\Users\Administrator\Desktop\flag.txt` on Windows Server AD

---

## 11. Teardown

### Automated Teardown

```powershell
# Stop all VMs for this session
$shortId = $sessionId.ToString().Substring(0, 8)
Get-VM | Where-Object { $_.Name -like "*-${shortId}" } | Stop-VM -TurnOff -Force

# Remove VMs
Get-VM | Where-Object { $_.Name -like "*-${shortId}" } | Remove-VM -Force

# Remove differencing disks
Remove-Item -Path "C:\CyberLab\VMs\${sessionId}" -Recurse -Force

# Remove per-student virtual switches
Get-VMSwitch | Where-Object { $_.Name -match "-C1-S\d+" } | Remove-VMSwitch -Force
```

### Preserve Shared VMs Between Sessions

Security Onion and Splunk are shared and may retain useful data between sessions. Do not delete them unless starting a completely new class cohort:

```powershell
# Keep shared VMs running — just delete per-student resources
# Shared VMs are named: Lab01-SecOnion-C1-*, Lab01-Splunk-C1-*
```

### Session Data Retention

The credentials JSON file at `C:\CyberLab\Sessions\{SessionId}-credentials.json` contains all session passwords. Retain it until after after-action report submission, then delete:

```powershell
Remove-Item "C:\CyberLab\Sessions\${sessionId}-credentials.json"
```

---

## 12. Troubleshooting

### Parallel Deployment — Some Students Fail

**Symptom:** The deploy script reports N student deployment failures with error messages.

**Cause:** The `-Parallel` ForEach-Object block runs 5 jobs simultaneously. If the host runs out of memory or disk I/O during differencing disk creation for all 5, some jobs time out.

**Fix:** Re-run the deploy script for only the failed students by passing a reduced `-StudentIds` array. The script detects and removes partially-created VMs before re-creating them.

### Windows VMs Not Responding to PowerShell Direct

**Symptom:** `Invoke-Command -VMName` returns `Cannot connect to the virtual machine`.

**Cause:** PowerShell Direct requires Hyper-V Integration Services to be installed inside the guest and the VM to be fully booted. The deploy script waits for heartbeat, but some Windows VMs (especially AD) take longer.

**Fix:** Wait an additional 2–3 minutes and retry the configuration step. If the issue persists, connect via Hyper-V console (Virtual Machine Connection) to check the VM state. If Sysprep is still running, wait for it to complete.

### Security Onion Not Generating Alerts

**Symptom:** Students report no alerts in Security Onion after running attacks.

**Cause:** Security Onion's Suricata must have the correct promiscuous-mode NIC configured. If the NIC is not on the correct switch, it will not see student traffic.

**Fix:**
1. Check that Security Onion's monitoring NIC (`eth1`) is attached to `shared-monitor-net-C{ClassId}`
2. Check that pfSense NICs for each student are set to mirror traffic to `shared-monitor-net`:
```powershell
# Verify port mirroring (should have been set during build)
Get-VMNetworkAdapter -VMName "Lab01-PfS-C1-S1-*" | Select-Object Name, PortMirroringMode
# Expected: Some adapters show PortMirroringMode = Source
```

### pfSense WebUI Not Accessible

**Symptom:** Students cannot reach `https://10.C.S.1`.

**Cause:** pfSense has not finished booting, or the LAN interface was not correctly assigned.

**Fix:** Connect to the pfSense VM via Hyper-V console and verify from the pfSense console menu (option 1) that interfaces are assigned correctly and the LAN IP is `10.C.S.1`.
