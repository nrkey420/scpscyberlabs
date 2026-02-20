# Security Onion — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `security-onion-2.4` |
| **VHDX path** | `C:\CyberLab\Templates\security-onion-2.4.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team — shared Blue Team platform), Lab 3 (SOC Analyst — shared monitoring) |
| **Role** | Shared class-level IDS/NSM platform; one instance per class, not per student |
| **Build script** | None — Security Onion uses a guided setup wizard; this guide documents the wizard answers and post-setup configuration |
| **Resources** | 4 vCPU, 8 GB RAM, 100 GB dynamic VHDX |
| **Base OS** | Security Onion 2.4 (based on Fedora) |

> **Note:** Security Onion is a SHARED VM. One instance runs per class session, not per student. It uses `StudentId=0` in the IP scheme: `10.{ClassId}.0.50`. All students in a class share the same Security Onion instance. The instructor must deploy Security Onion and configure analyst accounts **before** students start their lab sessions.

---

## Table of Contents

1. [Prerequisites and Hyper-V Notes](#1-prerequisites-and-hyper-v-notes)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [Network Adapter Configuration — Promiscuous Monitoring](#3-network-adapter-configuration--promiscuous-monitoring)
4. [OS Installation and Setup Wizard](#4-os-installation-and-setup-wizard)
5. [Setup Wizard Answers](#5-setup-wizard-answers)
6. [Post-Setup Configuration](#6-post-setup-configuration)
7. [Network Interfaces](#7-network-interfaces)
8. [Default Credentials After Build](#8-default-credentials-after-build)
9. [Verification Steps](#9-verification-steps)
10. [Adding Analyst Accounts Post-Deploy](#10-adding-analyst-accounts-post-deploy)
11. [Student Access](#11-student-access)
12. [Snapshot and Storage](#12-snapshot-and-storage)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites and Hyper-V Notes

### ISO Download

```
URL: https://github.com/Security-Onion-Solutions/securityonion/releases
File: securityonion-2.4.x-20XXXXXX.iso (select the latest 2.4.x release)
SHA256: listed on the GitHub releases page alongside the ISO
```

Verify the checksum:

```powershell
Get-FileHash -Algorithm SHA256 "securityonion-2.4.x.iso"
```

### Hyper-V Specific Notes

Security Onion 2.4 requires two network adapters:

- **eth0 (management):** Used for web interface access, SSH, and Elastic stack traffic. Connected to a management switch.
- **eth1 (monitoring/sniffing):** A promiscuous-mode adapter that captures all traffic on the monitored segment. This adapter is **never assigned an IP address** — it operates in promiscuous mode only.

Hyper-V does not natively support promiscuous mode on standard virtual switches. To capture all traffic destined for student VMs on a switch, use **Port Mirroring** on the Hyper-V virtual switch to mirror traffic from student VM adapters to the Security Onion monitoring adapter.

---

## 2. Hyper-V VM Creation

Create the VM with these settings:

| Setting | Value |
|---------|-------|
| Generation | **Generation 1** | Security Onion 2.4 works with Generation 1; Generation 2 can require UEFI adjustments |
| Startup RAM | **8192 MB** |
| Dynamic Memory | Disabled |
| Processor count | **4 vCPU** |
| Virtual hard disk | **100 GB**, Dynamically expanding |
| Network adapters | **Two** — add a second NIC after VM creation |
| Installation media | Security Onion 2.4 ISO |

After creation, add the second network adapter:

1. In Hyper-V Manager, right-click the VM > Settings.
2. Click **Add Hardware > Network Adapter > Add**.
3. Connect the first adapter to your management switch (`Build-Management`).
4. Leave the second adapter connected to the switch that will be mirrored (the `monitor-net-C{ClassId}` switch that student VMs use).

---

## 3. Network Adapter Configuration — Promiscuous Monitoring

### Enable Port Mirroring on Hyper-V

Port mirroring in Hyper-V works by configuring one VM's adapter as a mirror **destination** and each student VM's adapter as a mirror **source**. All traffic flowing through source adapters is duplicated to the destination adapter.

**Step 1: Configure the Security Onion monitoring adapter as a mirror destination.**

This must be run after the student session is deployed (because the student VM names are known at that point). The orchestration module calls this automatically, but for manual setup:

```powershell
# Set the Security Onion eth1 adapter as mirror destination
# Replace "security-onion-C1" with the actual VM name
Get-VMNetworkAdapter -VMName "security-onion-C1" | Where-Object Name -eq "Network Adapter 2" |
    Set-VMNetworkAdapter -PortMirroring Destination
```

**Step 2: Configure each student VM adapter as a mirror source.**

```powershell
# Set a student VM adapter as mirror source
# Repeat for each student VM on the monitored network
Get-VMNetworkAdapter -VMName "kali-C1-S3" | Where-Object SwitchName -eq "corporate-net-C1-S3" |
    Set-VMNetworkAdapter -PortMirroring Source
```

> **Important:** Port mirroring sources and destinations must be on the same virtual switch. The `monitor-net-C{ClassId}` switch is shared across all student slots for a given class. Security Onion's eth1 must be connected to this same switch, and each student VM's NIC on the monitored segment must be configured as a source.

**Verify port mirroring is active:**

```powershell
Get-VMNetworkAdapter -VMName "security-onion-C1" | Select-Object Name, PortMirroring
# Should show: PortMirroring = Destination
```

### Enable Promiscuous Mode via VLAN

Alternatively, if port mirroring at the vSwitch level is not working, configure the monitoring NIC to accept traffic from all VLANs:

```powershell
Set-VMNetworkAdapterVlan -VMName "security-onion-C1" -VMNetworkAdapterName "Network Adapter 2" `
    -Trunk -AllowedVlanIdList "1-4094" -NativeVlanId 0
```

---

## 4. OS Installation and Setup Wizard

1. Boot the VM from the Security Onion 2.4 ISO.
2. At the boot menu, select **Install Security Onion**.
3. The text-mode installer runs automatically. When prompted, set:
   - Root password: set a strong temporary password (changed by the build process)
   - Initial user: `analyst`
4. After the installer completes, the system reboots into the Security Onion setup wizard — a guided ncurses-based tool.

---

## 5. Setup Wizard Answers

Work through the Security Onion setup wizard using these answers. The wizard presents screens in the order listed below.

| Wizard Screen | Answer |
|--------------|--------|
| **Agree to terms** | Yes |
| **Install type** | Standalone (handles all roles on one node — appropriate for lab) |
| **Hostname** | `securityonion-template` (will be updated at deploy time) |
| **NIC for management** | Select `eth0` (the management adapter) |
| **Assign static or DHCP** | Static |
| **Management IP** | `10.0.0.50/24` (template placeholder; updated at deploy) |
| **Gateway** | `10.0.0.1` (template placeholder) |
| **DNS** | `8.8.8.8` |
| **NTP server** | `pool.ntp.org` |
| **Sniffing NIC** | Select `eth1` (the monitoring/promiscuous adapter) |
| **SOC admin email** | `analyst@scps.lab` |
| **SOC admin password** | Set a strong password; record it — this is the initial web console login |
| **Allow web access from** | `10.0.0.0/8` (covers all lab IP ranges) |
| **Enable alerts to email** | No (email is not configured in the lab environment) |
| **Enable so-allow after setup** | Yes |

After completing the wizard, Security Onion runs its post-installation scripts. This takes approximately 30–60 minutes. Do not interrupt it.

---

## 6. Post-Setup Configuration

After the wizard completes, log in via SSH as `analyst` to perform the following hardening and lab-specific configuration.

### Set Management IP Placeholder

The management IP is changed at deploy time by the orchestration module via SSH. The deploy-time IP scheme assigns `10.{ClassId}.0.50` to Security Onion. No manual IP change is needed now — record the wizard IP as the template default.

### Configure so-allow for Student Networks

Allow students to reach the web interface from their lab subnets:

```bash
sudo so-allow
# When prompted for service, select: analyst
# When prompted for IP/CIDR, enter: 10.0.0.0/8
# This allows any 10.x.x.x address to access the analyst web interface
```

### Verify Elastic Stack is Running

```bash
sudo so-status
# All services should show: running
# Key services: elasticsearch, kibana, logstash, zeek, suricata, steno
```

### Record the Initial Admin Credentials

The analyst account password set during the wizard is the primary web console credential. Record it in the host's secure credential store. At deploy time, the orchestration module will create per-student analyst accounts (see Section 10).

---

## 7. Network Interfaces

| Adapter | Interface | Assignment | Purpose |
|---------|-----------|-----------|---------|
| Network Adapter 1 | eth0 | `10.{ClassId}.0.50/24` | Management, web interface, SSH |
| Network Adapter 2 | eth1 | No IP (promiscuous only) | Passive traffic capture for IDS/NSM |

---

## 8. Default Credentials After Build

| Account | Password | Purpose |
|---------|----------|---------|
| `analyst` (OS) | Set during wizard | SSH and initial SOC web interface login |
| SOC web console admin | Same as wizard `analyst` password | `https://10.{ClassId}.0.50` |

---

## 9. Verification Steps

### Step 1 — Services Running

```bash
sudo so-status
# All services: running
```

### Step 2 — Web Interface Accessible

From a management workstation with access to the management network:

```
https://10.{ClassId}.0.50
```

Log in with `analyst` and the wizard password. The SOC web interface should load. Accept the self-signed certificate warning.

### Step 3 — Traffic Capture Active

On the Security Onion VM:

```bash
# Zeek should be capturing on eth1
sudo zeekctl status
# Status: running

# Check that Zeek is seeing traffic
sudo tail -f /nsm/zeek/logs/current/conn.log
# Should show connection records if any traffic is flowing through the monitored switch
```

### Step 4 — Suricata Active

```bash
sudo systemctl status suricata
# Active: running

# Check Suricata is reading from eth1
sudo suricata --list-runmodes | head -5
```

---

## 10. Adding Analyst Accounts Post-Deploy

After deploying a class session, create one analyst account per student so each student can log into the Security Onion web console with their own credentials.

```bash
# On the Security Onion VM — repeat for each student
sudo so-user-add

# When prompted:
# Email: student1@scps.lab
# First name: Student
# Last name: 1
# Role: analyst (not admin)
# Password: (the password surfaced to the student via the platform)
```

Alternatively, use the web interface: Security Onion Console > Admin > Users > Add User.

**For 15 students, run this script on the Security Onion VM:**

```bash
#!/bin/bash
# Run on Security Onion VM to bulk-add student accounts
# Passwords must match what is written to credentials.json by the orchestration module
for i in $(seq 1 15); do
    echo "Adding student$i..."
    # Use the so-user-add command interactively or via expect
    # Consult 'so-user-add --help' for non-interactive options in SO 2.4
done
```

---

## 11. Student Access

Students access Security Onion through the web browser using the IP address for their class:

```
https://10.{ClassId}.0.50
```

Students log in with the analyst account credentials that the instructor created for them (surfaced through the CyberLab platform credential display). All students share the same Security Onion instance but use individual logins.

The Security Onion web interface provides:
- **Alerts** — Suricata and OSSEC alerts
- **Hunt** — Zeek log queries (Connections, DNS, HTTP, Files, etc.)
- **PCAP** — Full packet captures via Stenographer
- **Cases** — Incident tracking

---

## 12. Snapshot and Storage

After the setup wizard and post-configuration are complete, shut down the VM.

```powershell
Move-Item "securityonion-build.vhdx" "C:\CyberLab\Templates\security-onion-2.4.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\security-onion-2.4.vhdx" -Name IsReadOnly -Value $true
```

> **Important:** Security Onion stores significant state in its Elasticsearch database. At deploy time, the orchestration module creates a new child differencing disk which starts with a clean database. Students see only events generated during their session.

---

## 13. Troubleshooting

### Zeek Not Seeing Traffic on eth1

**Symptom:** `conn.log` is empty even when student VMs are active.

**Cause:** Port mirroring is not configured, or it was configured before the student VMs were started.

**Fix:** Re-run the port mirroring PowerShell commands on the host after confirming all student VMs are running and connected to the monitored switch.

```powershell
# Verify the student VM adapter is a source
Get-VMNetworkAdapter -VMName "kali-C1-S1" | Select-Object Name, SwitchName, PortMirroring
```

### Web Interface Returns 502 Bad Gateway

**Symptom:** Browsing to `https://10.{ClassId}.0.50` shows 502.

**Cause:** Kibana or nginx is not running.

**Fix:**

```bash
sudo so-restart
sudo so-status
```

### Setup Wizard Fails Partway Through

**Symptom:** The wizard errors out after the NIC configuration step.

**Cause:** Insufficient disk space or the monitoring NIC was not detected.

**Fix:** Verify the VHDX is at least 100 GB and that the second NIC is properly added in Hyper-V Manager before starting the wizard. Re-run `sudo so-setup` after fixing the issue.
