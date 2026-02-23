# Lab 03 — SOC Analyst Training Lab: Deployment Guide

| Field | Value |
|-------|-------|
| **Lab number** | 03 |
| **Lab name** | SOC Analyst Training Lab |
| **Difficulty** | Intermediate |
| **Estimated duration** | 240 minutes |
| **Deploy script** | `Scripts/LabScenarios/Deploy-03-SOCAnalyst.ps1` |
| **Template file** | `Templates/03-soc-analyst.json` |
| **Maximum students** | 15 |

---

## Table of Contents

1. [Lab Overview](#1-lab-overview)
2. [Network Topology](#2-network-topology)
3. [Resource Requirements](#3-resource-requirements)
4. [Prerequisites](#4-prerequisites)
5. [Deployment Steps](#5-deployment-steps)
6. [Shared SIEM Pre-Deployment Requirements](#6-shared-siem-pre-deployment-requirements)
7. [Splunk Multi-Student Index Configuration](#7-splunk-multi-student-index-configuration)
8. [Security Onion Multi-Student Provisioning](#8-security-onion-multi-student-provisioning)
9. [Log Forwarding Verification](#9-log-forwarding-verification)
10. [Simulated Attack Timeline](#10-simulated-attack-timeline)
11. [Student Credential Distribution](#11-student-credential-distribution)
12. [Lab Objectives Reference](#12-lab-objectives-reference)
13. [Teardown](#13-teardown)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Lab Overview

Lab 03 trains students to work as SOC analysts. Each student receives their own isolated endpoint environment (a Windows 10 workstation, a Windows Server AD, and an Ubuntu web server) pre-configured to generate security events. The key difference from other labs is that all student environments forward their logs to two shared, class-wide SIEM platforms: Splunk Enterprise and Security Onion.

Students do not attack anything in this lab. Instead, they observe, detect, and investigate a simulated attack sequence that fires automatically on the Windows 10 workstation 30 minutes after VM startup.

**VMs deployed per student (3 per student):**
- Windows 10 Enterprise — Victim workstation with Sysmon + Splunk UF; runs the `LabAttackSimulation` scheduled task
- Windows Server 2019 AD — Active Directory domain controller; generates authentication events
- Ubuntu Linux Web Server — Web server generating Apache access logs and auth logs

**VMs deployed per class (2 shared):**
- Security Onion 2.4 — IDS/NSM; receives mirrored traffic; hosts Kibana for alert review
- Splunk Enterprise 9.1 — SIEM; receives forwarded events from all student endpoints

---

## 2. Network Topology

Each student's endpoints connect to a per-student `soc-net` switch. The shared monitoring VMs connect to a class-wide `shared-soc-net` switch. Splunk Universal Forwarders on the Windows VMs forward to Splunk over the `soc-net` segment.

```
Per-student segment (soc-net-C{C}-S{S}):
   [Win10 Workstation 10.C.S.20]  ---> [Splunk 10.C.0.51:9997 via shared-soc-net]
   [Windows Server AD 10.C.S.21]  ---> [Splunk 10.C.0.51:9997 via shared-soc-net]
   [Linux Web Server  10.C.S.30]  ---> [Splunk 10.C.0.51:9997 via shared-soc-net]

Shared class segment (shared-soc-net-C{C}):
   [Security Onion 10.C.0.50]
   [Splunk         10.C.0.51]
```

All student `soc-net` switches are bridged to `shared-soc-net` via pfSense (one pfSense per student) so that the Splunk UF can reach `10.C.0.51`. Security Onion uses port mirroring to capture traffic from all student switches.

---

## 3. Resource Requirements

### Per-Student Allocation

| VM | vCPU | RAM | Initial Disk (Differencing) |
|----|------|-----|-----------------------------|
| Windows 10 Enterprise | 2 | 4 GB | ~14 GB |
| Windows Server AD | 2 | 4 GB | ~14 GB |
| Ubuntu Web Server | 1 | 2 GB | ~5 GB |
| **Per-student total** | **5 vCPU** | **10 GB** | **~33 GB** |

### Shared VMs (one set per class)

| VM | vCPU | RAM | Disk |
|----|------|-----|------|
| Security Onion | 4 | 8 GB | ~20 GB (differencing) |
| Splunk | 4 | 8 GB | ~20 GB (differencing) |
| **Shared total** | **8 vCPU** | **16 GB** | **~40 GB** |

### Total for Class of N Students

| Students | vCPU | RAM | Estimated Disk |
|----------|------|-----|---------------|
| 5 | 33 | 66 GB | 205 GB |
| 10 | 58 | 116 GB | 370 GB |
| 15 | 83 | 166 GB | 535 GB |

---

## 4. Prerequisites

### Template VHDXs Required

| File | Size Approx |
|------|------------|
| `windows-10-enterprise.vhdx` | 40 GB |
| `windows-server-2019-ad.vhdx` | 40 GB |
| `ubuntu-server-22.04-web.vhdx` | 10 GB |
| `security-onion-2.4.vhdx` | 60 GB |
| `splunk-enterprise-9.1.vhdx` | 60 GB |

### Splunk Must Be Running Before Student VMs Start

The Splunk Universal Forwarder on each Windows VM attempts to connect to `10.C.0.51:9997` immediately on boot. If Splunk is not running when the student VMs start, the UF will fail to connect and may not automatically reconnect. Always deploy and verify Splunk before starting student endpoint VMs.

### Security Onion Setup Wizard Must Be Complete

Security Onion's setup wizard runs interactively and cannot be scripted — it must be completed by the instructor before the class session. See Section 8.

---

## 5. Deployment Steps

### Step 1 — Deploy Shared VMs First

```powershell
$sessionId = [guid]::NewGuid()

.\Scripts\LabScenarios\Deploy-03-SOCAnalyst.ps1 `
    -SessionId $sessionId `
    -ClassId 1 `
    -StudentIds @('alice','bob','carol','dan','eva','frank','grace','henry','ivan','julia') `
    -TimeoutMinutes 90
```

The deploy script deploys shared VMs (Security Onion and Splunk) before per-student VMs and waits for both to be reachable before continuing.

### Deployment Phases and Timing

| Phase | Actions | Estimated Time |
|-------|---------|---------------|
| Prerequisites validation | Templates, disk, SSH | ~15 seconds |
| Switch creation | 1 per-student + 1 shared = 11 switches for 10 students | ~15 seconds |
| Shared VM deployment | Security Onion + Splunk boot and configure | ~10–15 minutes |
| Per-student VM deployment (parallel) | 3 VMs × 10 students = 30 VMs | ~8–15 minutes |
| Readiness validation | Heartbeat + UF connectivity | ~3 minutes |
| Credential export | Session manifest | ~5 seconds |
| **Total** | | **~25–35 minutes** |

---

## 6. Shared SIEM Pre-Deployment Requirements

### Security Onion — Setup Wizard (One-Time)

Security Onion's initial setup wizard must be run by an instructor after the first deployment of the Security Onion VHDX. This is a one-time requirement — once the VHDX has been through the wizard and a checkpoint taken, subsequent deployments use that checkpoint.

If this is the first time deploying the `security-onion-2.4.vhdx`:

1. Boot the Security Onion VM
2. Log in as `analyst` / `changeme` (initial password from the base image)
3. Run the setup wizard: `sudo so-setup`
4. Answer the prompts:

| Prompt | Value |
|--------|-------|
| Installation type | Standalone (all-in-one) |
| Management interface | `eth0` |
| Management IP | `10.C.0.50` (static) |
| Monitoring interface | `eth1` |
| Allow analyst access from | `10.C.0.0/16` (covers all student subnets) |
| Web interface password | Set a strong password (stored in credential manifest) |

5. Setup takes approximately 15–20 minutes
6. After completion, take a Hyper-V checkpoint named `SetupComplete`

For subsequent class sessions, the deploy script restores from `SetupComplete` rather than re-running the wizard.

---

## 7. Splunk Multi-Student Index Configuration

Splunk receives events from all students' endpoints simultaneously. Events are differentiated by the `host` field (the VM's hostname, set to `WS-C{C}-S{S}` for workstations and `DC-C{C}-S{S}` for domain controllers).

### Index Configuration

Splunk is pre-configured with these indexes (from the base image build):

| Index | Purpose | Sources |
|-------|---------|---------|
| `windows` | Windows Event Logs (Security, System, Application, PowerShell) | Splunk UF on Win10 and WinAD VMs |
| `sysmon` | Sysmon operational events | Splunk UF on Win10 VM |
| `linux` | Linux syslog and auth.log | Splunk UF on Ubuntu Web Server |
| `network` | pfSense firewall logs | Syslog from pfSense |
| `alerts` | Custom CyberLab correlation alerts | Internal Splunk alert actions |

### Per-Student Search Filter

Because all students share one Splunk instance, students must filter by their own hostname to see only their events. Provide students with this search template:

```
index=* host="WS-C1-S{S}" OR host="DC-C1-S{S}" OR host="web-c1-s{S}" | <rest of search>
```

Substitute `{S}` with the student's student number (1–15).

### Confirm Index Intake Rate

After deployment, verify events are flowing from all students:

```
index=* earliest=-10m | stats count by host, index | sort -count
```

Expected: Entries for each student's hostnames in the `windows` and `sysmon` indexes.

---

## 8. Security Onion Multi-Student Provisioning

Security Onion requires individual analyst accounts for each student. Create accounts after the Security Onion VM is running:

```bash
# SSH to Security Onion as instructor
ssh instructor@10.C.0.50

# Create one account per student (run as root/sudo)
sudo so-user-add -u alice   --role analyst --password "AliceLabPass2024!"
sudo so-user-add -u bob     --role analyst --password "BobLabPass2024!"
sudo so-user-add -u carol   --role analyst --password "CarolLabPass2024!"
# ... repeat for all students
```

Or use a loop from the credential manifest (after the deploy script runs and generates passwords):

```bash
# The deploy script writes student usernames to /opt/scps-lab/students.txt on Security Onion
# Use it to create accounts
while IFS=',' read -r username password; do
    sudo so-user-add -u "$username" --role analyst --password "$password"
done < /opt/scps-lab/students.txt
```

### Verify Analyst Access

Each student accesses Security Onion via:
```
https://10.C.0.50
```

Log in with their `analyst` account credentials. Confirm the Kibana Discover view shows events.

---

## 9. Log Forwarding Verification

Before starting the lab, confirm that all student endpoints are forwarding logs to Splunk.

### Check Splunk UF Connectivity (from Splunk VM)

```bash
ssh splunkadmin@10.C.0.51

# Check which forwarders have connected recently
/opt/splunk/bin/splunk list forward-server

# View the last 10 connections in the UF log
sudo grep "connected to" /opt/splunk/var/log/splunk/splunkd.log | tail -20
```

Expected: One entry per student's Windows 10 workstation and Windows Server AD.

### Check from Splunk Web

Navigate to `http://10.C.0.51:8000` and run:

```
| rest splunk_server=local /services/admin/inputstatus/tcp:cooked:connections
| table host, status, connection_host
```

Expected: All student endpoints listed with `status=connected`.

### Manually Restart Splunk UF on a Specific VM

If a student's UF is not connecting, restart it:

```powershell
# Via PowerShell Direct from Hyper-V host
$cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'Password' -AsPlainText -Force))
Invoke-Command -VMName "Lab03-Win10-C1-S1-{shortId}" -Credential $cred -ScriptBlock {
    Restart-Service SplunkForwarder
    Get-Service SplunkForwarder
}
```

---

## 10. Simulated Attack Timeline

The Windows 10 Enterprise image contains a scheduled task (`LabAttackSimulation`) that fires 30 minutes after VM startup and generates a realistic multi-stage attack sequence. Students are not told the exact timings — they must discover events by searching logs.

The attack simulation generates the following events in sequence (all timestamps relative to when the VM boots):

| T+ | Stage | Sysmon Event(s) | Windows Event(s) |
|----|-------|----------------|-----------------|
| 30 min | VM startup trigger | — | — |
| T+0 | LSASS credential dump attempt | EventID 10 (ProcessAccess, TargetImage=lsass.exe) | EventID 4672 |
| T+2 | Enumeration commands | EventID 1 (net.exe, whoami.exe) | EventID 4688 |
| T+4 | Registry Run key persistence | EventID 12, 13 (RegistryEvent) | — |
| T+6 | WinRM lateral movement attempt | EventID 3 (NetworkConnect to .21:5985) | EventID 4625 on AD |
| T+8 | Data staging to Temp | EventID 11 (FileCreate in C:\Windows\Temp) | EventID 4663 |
| T+10 | HTTP beacon | EventID 3 (NetworkConnect outbound port 8080) | — |
| T+12 | File deletion (cleanup) | EventID 23 (FileDelete) | — |

### Providing the Attack Timeline to Students

Students receive a brief that says:

> "A security incident occurred on the Windows workstation in your environment. The incident began approximately 30 minutes after your environment was provisioned. Use Splunk and Security Onion to reconstruct the full kill chain, identify the attacker's techniques, extract all IOCs, and write an incident report."

Do not give students the table above until after the exercise is complete (use it for the debrief).

### Instructor Search to Verify Attack Fired

After approximately 45 minutes from VM start (30 min trigger + 15 min attack sequence):

```
index=sysmon host="WS-C1-S{S}" EventCode=10 | stats count by TargetImage
```

Expected: At least one EventID 10 event with `TargetImage=C:\Windows\system32\lsass.exe`.

---

## 11. Student Credential Distribution

Students receive:

| Field | Value |
|-------|-------|
| `Win10.IPAddress` | `10.C.S.20` |
| `Win10.RDPPassword` | Session-generated Administrator password |
| `WinAD.IPAddress` | `10.C.S.21` |
| `LinuxWeb.IPAddress` | `10.C.S.30` |
| `Splunk.URL` | `http://10.C.0.51:8000` |
| `Splunk.Username` | `admin` |
| `Splunk.Password` | Shared admin password from credential manifest |
| `SecurityOnion.URL` | `https://10.C.0.50` |
| `SecurityOnion.Username` | Per-student username (e.g., `alice`) |
| `SecurityOnion.Password` | Per-student password from credential manifest |
| `SplunkHostFilter` | `host="WS-C1-S{S}" OR host="DC-C1-S{S}"` — search filter for their events |

---

## 12. Lab Objectives Reference

| Objective | Points | Flag |
|-----------|--------|------|
| Log Analysis | 100 | `FLAG{log_analysis_anomalies_identified_4a9c}` |
| Alert Triage | 150 | `FLAG{alert_triage_complete_classified_7b3e}` |
| Malware Detection | 200 | `FLAG{malware_detected_trojan_dropper_6d2f}` |
| Incident Timeline | 200 | `FLAG{incident_timeline_reconstructed_8e5a}` |
| IOC Extraction | 150 | `FLAG{iocs_extracted_threat_intel_9c1b}` |
| Threat Hunting | 200 | `FLAG{threat_hunt_persistence_found_3f7d}` |
| Write Incident Report | 100 | `FLAG{incident_report_submitted_complete_2a8e}` |

Flags are not planted as files in this lab. They are submitted by the student as proof of detection (e.g., pasting the Splunk search that discovered the event, or the MITRE ATT&CK mapping they identified). The web portal validates submissions against the flag list.

---

## 13. Teardown

```powershell
$shortId = $sessionId.ToString().Substring(0, 8)

# Stop and remove per-student VMs
Get-VM | Where-Object { $_.Name -like "Lab03*S*${shortId}" } | ForEach-Object {
    Stop-VM -Name $_.Name -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $_.Name -Force -ErrorAction SilentlyContinue
}

# Remove per-student disks
Get-ChildItem "C:\CyberLab\VMs\${sessionId}" -Recurse | Remove-Item -Force
Remove-Item "C:\CyberLab\VMs\${sessionId}" -Force

# Remove per-student switches (preserve shared-soc-net if running another session)
Get-VMSwitch | Where-Object { $_.Name -match "soc-net-C1-S\d+" } | Remove-VMSwitch -Force

# Optionally stop shared VMs if class is complete
# Stop-VM -Name "Lab03-SecOnion-C1-${shortId}" -TurnOff -Force
# Stop-VM -Name "Lab03-Splunk-C1-${shortId}" -TurnOff -Force
```

---

## 14. Troubleshooting

### Attack Simulation Does Not Fire

**Symptom:** No LSASS access event appears in Sysmon logs around T+30 minutes.

**Cause:** The `LabAttackSimulation` scheduled task may have failed or the trigger time is calculated from the first boot (before the VM was configured), not from when the student session started.

**Fix:** Force-run the simulation task via PowerShell Direct:

```powershell
$cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'Password' -AsPlainText -Force))
Invoke-Command -VMName "Lab03-Win10-C1-S{S}-${shortId}" -Credential $cred -ScriptBlock {
    Start-ScheduledTask -TaskName "LabAttackSimulation"
    Get-ScheduledTaskInfo -TaskName "LabAttackSimulation" | Select-Object LastRunTime, LastTaskResult
}
```

### Sysmon Events Not Appearing in Splunk

**Symptom:** The `sysmon` index in Splunk is empty for a student's workstation.

**Cause:** The Splunk UF `outputs.conf` may still have `CLASS_ID` as a placeholder (not substituted at deploy time), or the UF cannot reach `10.C.0.51`.

**Fix:**
```powershell
# Check the outputs.conf on the Windows 10 VM
$cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'Password' -AsPlainText -Force))
Invoke-Command -VMName "Lab03-Win10-C1-S{S}-${shortId}" -Credential $cred -ScriptBlock {
    Get-Content "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf"
}
```

If the file still contains `CLASS_ID`, re-apply the substitution:

```powershell
Invoke-Command -VMName "Lab03-Win10-C1-S{S}-${shortId}" -Credential $cred -ScriptBlock {
    param($classId)
    $file = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf"
    (Get-Content $file) -replace "CLASS_ID", $classId | Set-Content $file
    Restart-Service SplunkForwarder
} -ArgumentList 1
```

### Security Onion Setup Wizard Locks Up

**Symptom:** `sudo so-setup` hangs at a configuration step.

**Cause:** Network interface detection or Elastic stack initialization can take several minutes. The wizard may also require a minimum of 8 GB RAM (some hypervisor configurations may show less).

**Fix:** Wait at least 5 minutes at any hanging step. If it has been more than 10 minutes, Ctrl+C and review `/var/log/so-setup.log` for errors. Common fix: ensure the Security Onion VM has at least 8 GB RAM assigned with Dynamic Memory disabled.
