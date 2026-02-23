# Splunk Enterprise — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `splunk-enterprise-9.1` |
| **VHDX path** | `C:\CyberLab\Templates\splunk-enterprise-9.1.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team — shared SIEM), Lab 3 (SOC Analyst — shared SIEM) |
| **Role** | Shared class-level SIEM; one instance per class, not per student |
| **Build script** | None — Splunk is installed manually via the Linux package manager; this guide documents each step |
| **Resources** | 4 vCPU, 8 GB RAM, 100 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS (Splunk Enterprise 9.1 is certified for Ubuntu 22.04) |

> **Note:** Splunk Enterprise is a SHARED VM. One instance runs per class session, using `StudentId=0` in the IP scheme: `10.{ClassId}.0.51`. Students access Splunk at `http://10.{ClassId}.0.51:8000`. The instructor must deploy Splunk and verify log forwarding **before** student sessions start.

> **License Note:** Splunk Enterprise operates under a free trial or developer license that allows **500 MB per day** of indexing without cost. The lab-scale data volumes (15 students running a 4-hour session) produce well under this limit. For classes that run longer or generate higher volumes (Lab 1 with active attacks), the limit is sufficient because Splunk continues to search existing data even if new indexing pauses. If indexing is paused by the license limit, Splunk displays a warning banner but remains fully functional for searching.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Installing Splunk Enterprise](#4-installing-splunk-enterprise)
5. [Splunk Initial Configuration](#5-splunk-initial-configuration)
6. [Configured Indexes](#6-configured-indexes)
7. [HEC Token Configuration](#7-hec-token-configuration)
8. [Saved Searches and Alerts](#8-saved-searches-and-alerts)
9. [Splunk Universal Forwarder Connection](#9-splunk-universal-forwarder-connection)
10. [Network Interfaces](#10-network-interfaces)
11. [Default Credentials After Build](#11-default-credentials-after-build)
12. [Verification Steps](#12-verification-steps)
13. [Student Access](#13-student-access)
14. [Snapshot and Storage](#14-snapshot-and-storage)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Prerequisites

### Splunk Download

Splunk Enterprise packages require a free Splunk account to download. Register at `splunk.com` and download the Splunk Enterprise 9.1.x `.deb` package for Linux (amd64):

```
Product: Splunk Enterprise
Version: 9.1.x (latest 9.1 patch)
Platform: Linux (.deb package)
Filename: splunk-9.1.x-linux-2.6-amd64.deb
```

Transfer the `.deb` file to the VM during build.

### Ubuntu Server 22.04 ISO

```
URL: https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso
```

### Build Time

Approximately 45–60 minutes including Splunk configuration.

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **8192 MB** |
| Dynamic Memory | Disabled |
| Processor count | **4 vCPU** |
| Virtual hard disk | **100 GB**, Dynamically expanding |
| Network adapter | External-Internet switch (for package downloads during setup) |
| Installation media | Ubuntu Server 22.04 ISO |

---

## 3. OS Installation

| Installer Step | Setting |
|---------------|---------|
| Language | English |
| Keyboard | Match your physical keyboard |
| Install type | Ubuntu Server |
| Network | Accept DHCP |
| Storage | Entire disk, no LVM |
| Server name | `splunk-template` |
| Username | `splunkadmin` |
| Password | Temporary (overwritten post-build) |
| SSH | Install OpenSSH server |
| Featured snaps | None |

After reboot, log in as `splunkadmin` and switch to root: `sudo -i`.

Update the system:

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y && apt-get autoremove -y
```

---

## 4. Installing Splunk Enterprise

Transfer the Splunk `.deb` package to the VM:

```powershell
scp splunk-9.1.x-linux-2.6-amd64.deb splunkadmin@<VM-IP>:/home/splunkadmin/
```

Install Splunk:

```bash
sudo -i
dpkg -i /home/splunkadmin/splunk-9.1.x-linux-2.6-amd64.deb

# Accept the license and start Splunk for the first time
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt \
    --seed-passwd "LabAdmin2024!"

# Enable Splunk to start at boot
/opt/splunk/bin/splunk enable boot-start -systemd-managed 1 --no-prompt
```

Splunk installs to `/opt/splunk/`. The seed password sets the initial `admin` account password.

---

## 5. Splunk Initial Configuration

### Configure the Receiving Port (for Forwarders)

```bash
/opt/splunk/bin/splunk enable listen 9997 -auth admin:LabAdmin2024!
```

This configures Splunk to accept events from Universal Forwarders on TCP port 9997.

### Configure the Web Interface Port

Splunk's web interface runs on port 8000 by default. Confirm this is set:

```bash
grep 'httpport' /opt/splunk/etc/system/local/web.conf 2>/dev/null || \
    echo -e '[settings]\nhttpport = 8000' >> /opt/splunk/etc/system/local/web.conf
```

### Set Timezone

```bash
# Edit server.conf to set timezone for timestamp normalization
cat > /opt/splunk/etc/system/local/server.conf << 'EOF'
[general]
timezone = America/New_York
serverName = splunk-template
EOF
```

### Restart Splunk

```bash
systemctl restart Splunkd
```

---

## 6. Configured Indexes

The following indexes are pre-created in the base image. At deploy time, student-specific source tags differentiate each student's data within shared indexes.

```bash
/opt/splunk/bin/splunk add index windows -auth admin:LabAdmin2024!
/opt/splunk/bin/splunk add index linux -auth admin:LabAdmin2024!
/opt/splunk/bin/splunk add index sysmon -auth admin:LabAdmin2024!
/opt/splunk/bin/splunk add index network -auth admin:LabAdmin2024!
/opt/splunk/bin/splunk add index alerts -auth admin:LabAdmin2024!
```

| Index | Purpose | Primary Sources |
|-------|---------|----------------|
| `windows` | Windows event logs (Security, System, Application) | Splunk UF on Windows VMs |
| `sysmon` | Sysmon operational events (Process Create, Network Connect, etc.) | Splunk UF on Windows VMs |
| `linux` | Linux syslog, auth.log, audit.log | Splunk UF on Linux VMs |
| `network` | pfSense firewall logs, Zeek-format network data | Syslog forwarding from pfSense |
| `alerts` | Custom lab alert events, flag captures | Platform-injected events |

Configure these indexes via the REST API after install:

```bash
curl -k -u admin:LabAdmin2024! https://localhost:8089/services/data/indexes -d name=sysmon -d datatype=event
# Repeat for each index
```

Alternatively, create `/opt/splunk/etc/system/local/indexes.conf`:

```ini
[windows]
homePath = $SPLUNK_DB/windows/db
coldPath = $SPLUNK_DB/windows/colddb
thawedPath = $SPLUNK_DB/windows/thaweddb
maxDataSize = auto_high_volume
frozenTimePeriodInSecs = 604800

[sysmon]
homePath = $SPLUNK_DB/sysmon/db
coldPath = $SPLUNK_DB/sysmon/colddb
thawedPath = $SPLUNK_DB/sysmon/thaweddb
maxDataSize = auto_high_volume
frozenTimePeriodInSecs = 604800

[linux]
homePath = $SPLUNK_DB/linux/db
coldPath = $SPLUNK_DB/linux/colddb
thawedPath = $SPLUNK_DB/linux/thaweddb
maxDataSize = auto
frozenTimePeriodInSecs = 604800

[network]
homePath = $SPLUNK_DB/network/db
coldPath = $SPLUNK_DB/network/colddb
thawedPath = $SPLUNK_DB/network/thaweddb
maxDataSize = auto
frozenTimePeriodInSecs = 604800

[alerts]
homePath = $SPLUNK_DB/alerts/db
coldPath = $SPLUNK_DB/alerts/colddb
thawedPath = $SPLUNK_DB/alerts/thaweddb
maxDataSize = auto
frozenTimePeriodInSecs = 604800
```

---

## 7. HEC Token Configuration

HTTP Event Collector (HEC) allows the CyberLab platform and custom scripts to push events directly into Splunk over HTTP without a Universal Forwarder.

### Enable HEC

```bash
curl -k -u admin:LabAdmin2024! \
    https://localhost:8089/servicesNS/admin/splunk_httpinput/data/inputs/http/http \
    -d enableSSL=0 -d port=8088 -d disabled=0
```

### Create a HEC Token

```bash
curl -k -u admin:LabAdmin2024! \
    https://localhost:8089/servicesNS/admin/splunk_httpinput/data/inputs/http \
    -d name="cyberlab-hec" \
    -d description="SCPS CyberLab platform event ingestion" \
    -d index="alerts" \
    -d sourcetype="cyberlab:platform"
```

Record the generated token value. It is stored at:

```bash
curl -k -u admin:LabAdmin2024! \
    https://localhost:8089/servicesNS/admin/splunk_httpinput/data/inputs/http/cyberlab-hec \
    | grep -i token
```

Save this token to the template credential file:

```bash
echo "HEC_TOKEN=<token-value>" >> /root/.lab-credentials
```

The HEC endpoint is `http://10.{ClassId}.0.51:8088/services/collector`.

---

## 8. Saved Searches and Alerts

The following saved searches are pre-created in the base image. They are designed to help students identify key events during Labs 1 and 3.

Create each saved search via the Splunk REST API or by placing `.conf` files in `/opt/splunk/etc/apps/search/local/`.

Create `/opt/splunk/etc/apps/search/local/savedsearches.conf`:

```ini
[Failed Logon Attempts - Windows]
search = index=windows EventCode=4625 | stats count by Account_Name, Source_Network_Address, Workstation_Name | sort -count
dispatch.earliest_time = -1h
dispatch.latest_time = now
is_scheduled = 0
description = Detect brute force and failed logon attempts on Windows systems

[Sysmon - New Process Created]
search = index=sysmon EventCode=1 | table _time, host, User, Image, CommandLine, ParentImage | sort -_time
dispatch.earliest_time = -1h
dispatch.latest_time = now
is_scheduled = 0
description = All new processes created - use for lateral movement and persistence detection

[Sysmon - Network Connections]
search = index=sysmon EventCode=3 | table _time, host, User, Image, DestinationIp, DestinationPort | sort -_time
dispatch.earliest_time = -1h
dispatch.latest_time = now
is_scheduled = 0
description = Outbound network connections initiated by processes - C2 and lateral movement

[SSH Authentication Events - Linux]
search = index=linux sourcetype=syslog (Failed OR Accepted) AND sshd | rex "(?P<result>Failed|Accepted) password for (?P<user>\S+) from (?P<src_ip>\S+)" | table _time, result, user, src_ip | sort -_time
dispatch.earliest_time = -1h
dispatch.latest_time = now
is_scheduled = 0
description = SSH login successes and failures on Linux systems

[Firewall Blocks - pfSense]
search = index=network sourcetype=pfsense | stats count by src_ip, dest_ip, dest_port, action | where action="block" | sort -count
dispatch.earliest_time = -1h
dispatch.latest_time = now
is_scheduled = 0
description = pfSense blocked connections - identify scanning and attack traffic

[Domain Admin Activity]
search = index=windows (EventCode=4728 OR EventCode=4732 OR EventCode=4756) Group_Name IN ("Domain Admins","Administrators") | table _time, host, EventCode, Account_Name, Group_Name | sort -_time
dispatch.earliest_time = -24h
dispatch.latest_time = now
is_scheduled = 0
description = Group membership changes to privileged groups - privilege escalation detection

[CyberLab - Lab Alerts]
search = index=alerts | table _time, student_id, objective, flag, message | sort -_time
dispatch.earliest_time = -24h
dispatch.latest_time = now
is_scheduled = 0
description = Platform-generated lab objective completion events
```

### Configured Alerts

One alert is pre-configured to fire when the lab flag for Blue Team detection objectives is captured:

```ini
[ALERT - Brute Force Detected]
search = index=windows EventCode=4625 | stats count by Source_Network_Address | where count > 20
dispatch.earliest_time = -15m
dispatch.latest_time = now
is_scheduled = 1
cron_schedule = */5 * * * *
alert_threshold = 1
alert_comparator = greater than
alert_type = number of results
description = Fires when any source IP has more than 20 failed Windows logon events in 15 minutes
actions = email
```

---

## 9. Splunk Universal Forwarder Connection

The Splunk Universal Forwarder (UF) is pre-installed on Windows 10 Enterprise (`windows-10-enterprise`) and Windows Server 2019 AD (`windows-server-2019-ad`) base images. The UF is configured to forward to `10.{ClassId}.0.51:9997`.

At deploy time, the orchestration module updates the UF `outputs.conf` on each VM to point to the correct class-specific Splunk instance.

**UF configuration template on Windows VMs** (`C:\Program Files\SplunkUniversalForwarder\etc\system\local\outputs.conf`):

```ini
[tcpout]
defaultGroup = scps-cyberlab

[tcpout:scps-cyberlab]
server = 10.CLASS_ID.0.51:9997
useACK = false

[tcpout-server://10.CLASS_ID.0.51:9997]
```

**UF inputs.conf on Windows VMs** (`C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf`):

```ini
[WinEventLog://Security]
index = windows
disabled = false
start_from = oldest

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
```

---

## 10. Network Interfaces

Single network adapter. At deploy time, connected to the `monitor-net-C{ClassId}` switch and assigned `10.{ClassId}.0.51`.

---

## 11. Default Credentials After Build

| Account | Password | Purpose |
|---------|----------|---------|
| `admin` (Splunk web) | `LabAdmin2024!` (template default; changed at deploy time) | Web interface and REST API |
| `splunkadmin` (OS) | Set during OS install | SSH access for administration |

---

## 12. Verification Steps

### Step 1 — Splunk Web Interface

```bash
curl -s -o /dev/null -w "%{http_code}" http://<VM-IP>:8000
# Expected: 200
```

### Step 2 — Receiver Port Active

```bash
/opt/splunk/bin/splunk list forward-server -auth admin:LabAdmin2024!
# No output is expected (no forwarders are connected at build time)

/opt/splunk/bin/splunk list listen -auth admin:LabAdmin2024!
# Expected: 9997 (receiver port)
```

### Step 3 — Indexes Exist

```bash
/opt/splunk/bin/splunk list index -auth admin:LabAdmin2024!
# Expected: windows, sysmon, linux, network, alerts listed
```

### Step 4 — HEC Working

```bash
curl -k http://localhost:8088/services/collector \
    -H "Authorization: Splunk <HEC_TOKEN>" \
    -d '{"event": "test event", "index": "alerts"}'
# Expected: {"text":"Success","code":0}
```

### Step 5 — Monitor Log Forwarding Health Post-Deploy

After deploying a class session and starting Windows VMs with the Splunk UF:

```bash
tail -f /opt/splunk/var/log/splunk/metrics.log | grep group=tcpin_connections
# Lines should appear showing received event counts from student VM IPs
```

---

## 13. Student Access

Students access Splunk through their browser:

```
http://10.{ClassId}.0.51:8000
```

Students log in with the Splunk `admin` credentials surfaced through the CyberLab platform. All students in a class share the same Splunk instance. Students use saved searches and can create their own dashboards within their sessions.

Instructors monitor log forwarding volume from the Splunk metrics log or the web interface: Settings > Monitoring Console > Indexing > Indexing Performance.

---

## 14. Snapshot and Storage

```powershell
Move-Item "splunk-build.vhdx" "C:\CyberLab\Templates\splunk-enterprise-9.1.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\splunk-enterprise-9.1.vhdx" -Name IsReadOnly -Value $true
```

---

## 15. Troubleshooting

### Splunk Web Interface Not Responding

```bash
systemctl status Splunkd
journalctl -u Splunkd -n 50
/opt/splunk/bin/splunk status
```

If Splunk is stopped:

```bash
/opt/splunk/bin/splunk start
```

### Forwarder Events Not Appearing in Splunk

**On the Splunk server:**

```bash
# Check if forwarder connections are being received
/opt/splunk/bin/splunk list forward-server -auth admin:LabAdmin2024!
netstat -tlnp | grep 9997
# Port 9997 should be listening
```

**On the Windows forwarder VM:**

```powershell
# Check UF service status
Get-Service SplunkForwarder
# Check UF internal logs
Get-Content "C:\Program Files\SplunkUniversalForwarder\var\log\splunk\splunkd.log" -Tail 50
```

### License Warning Visible in Web Interface

**Symptom:** A yellow "Splunk license violation" banner appears in the Splunk UI.

**Cause:** The daily 500 MB indexing limit was exceeded. (Under the trial license, Splunk allows unlimited searching but throttles indexing above 500 MB/day.)

**Impact:** Existing indexed data remains fully searchable. New events are queued and indexed after the 24-hour reset window.

**Prevention for long sessions:** Reduce the number of event types forwarded by disabling verbose event sources in `inputs.conf` on forwarder VMs. The Sysmon index generates the highest volume — consider filtering to only EventCodes 1, 3, 10, and 11 for lab purposes.
