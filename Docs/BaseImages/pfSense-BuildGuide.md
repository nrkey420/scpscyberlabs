# pfSense 2.7 — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `pfsense-2.7` |
| **VHDX path** | `C:\CyberLab\Templates\pfsense-2.7.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team), Lab 2 (Web App Pentest), Lab 4 (Network Attack & Defense), Lab 5 (Malware Analysis) |
| **Role** | Network gateway and firewall separating lab network segments per student |
| **Build script** | `Scripts/BaseImages/Network/Build-pfSense.sh` (run inside pfSense shell) |
| **Resources** | 2 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | pfSense CE 2.7 (FreeBSD 14) |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Running the Build Script](#4-running-the-build-script)
5. [Per-Lab NIC Assignment](#5-per-lab-nic-assignment)
6. [Firewall Rule Templates](#6-firewall-rule-templates)
7. [Deploy-Time Customisation](#7-deploy-time-customisation)
8. [Network Interfaces](#8-network-interfaces)
9. [Default Credentials After Build](#9-default-credentials-after-build)
10. [Verification Steps](#10-verification-steps)
11. [Snapshot and Storage](#11-snapshot-and-storage)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

- pfSense CE 2.7 ISO — download from `https://www.pfsense.org/download/` (Architecture: AMD64, Installer: DVD Image / ISO)
- The build script `Scripts/BaseImages/Network/Build-pfSense.sh` and companion file `pfSense-base-config.xml` must be transferred to the VM before running
- FreeBSD note: the build script is written for `/bin/sh` (POSIX sh), not bash — this is intentional; do not modify it to use bash constructs
- Build time: approximately 30–45 minutes

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 1** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Network adapters | **Three NICs**: NIC1 = WAN (External-Internet), NIC2 = LAN (placeholder), NIC3 = OPT1 (placeholder; lab-specific) |
| Secure Boot | **Not available** (Generation 1 VMs only support Legacy BIOS) |

> Generation 1 is required for pfSense. Generation 2 (UEFI) is not supported by pfSense 2.7 under Hyper-V due to FreeBSD UEFI boot limitations.

### NIC Naming in pfSense

| Hyper-V NIC Order | pfSense Interface | Purpose |
|-------------------|------------------|---------|
| First NIC | `hn0` (or `vtnet0`) | WAN — upstream connectivity or external switch |
| Second NIC | `hn1` (or `vtnet1`) | LAN — student's primary lab segment |
| Third NIC | `hn2` (or `vtnet2`) | OPT1 — additional segment (Lab 1 DMZ, Lab 4 internal) |

---

## 3. OS Installation

Boot the VM from the pfSense CE ISO. Use the console installer:

| Setting | Value |
|---------|-------|
| Keymap | Default (US) |
| Partition | Auto (ZFS) or Auto (UFS) — UFS is recommended for lab simplicity |
| ZFS Configuration | If using ZFS, select stripe (single disk) |
| Install target | `da0` (the 20 GB virtual disk) |
| Final step | When prompted, remove the install media and reboot |

After reboot, the pfSense console menu appears. Do **not** configure interfaces manually here — the build script handles all configuration.

---

## 4. Running the Build Script

### Transfer the Script and Config File

The build script and `pfSense-base-config.xml` must be copied to the pfSense VM before running. Use SCP from the Hyper-V host (if OpenSSH is available) or paste the script content via the pfSense console:

**Method — SCP from Host:**

```powershell
# On the Hyper-V host (requires SSH enabled on pfSense — enabled by default after install)
scp Scripts\BaseImages\Network\Build-pfSense.sh admin@<pfSense-IP>:/tmp/
scp Scripts\BaseImages\Network\pfSense-base-config.xml admin@<pfSense-IP>:/tmp/
```

**Method — Console Paste:**

From the pfSense console menu, choose option **8 (Shell)**. Use `vi` or `ee` to create `/tmp/Build-pfSense.sh` and paste the script content.

### Execute the Script

From the pfSense console menu, choose **option 8 (Shell)**:

```sh
cd /tmp
sh Build-pfSense.sh
```

The script runs 8 sections:

**Section 1 — Stage config.xml:** Backs up any existing `/conf/config.xml`, then copies the `pfSense-base-config.xml` template into place. This template contains placeholder values for IP addresses, passwords, and interface names that are substituted at deploy time.

**Section 2 — Set Administrator password:** Uses `pfSsh.php playback` to set the webConfigurator and console password to `LabAdmin2024!`. This is the build-phase password. It is overridden at deploy time by `Set-VMNetworkConfig.ps1`.

**Section 3 — Interface assignment:** Assigns `hn0` as WAN, `hn1` as LAN, and `hn2` as OPT1 via `pfSsh.php playback`. Also disables the hardware checksum offload feature (required under Hyper-V for correct network operation).

**Section 4 — DHCP and DNS:** Enables the DHCP server on the LAN interface with a pool of `.100`–`.200`. Configures the DNS resolver (Unbound) to forward to 1.1.1.1 and 8.8.8.8.

**Section 5 — NAT and firewall rules:** Configures NAT (outbound masquerade on WAN). Sets baseline firewall rules: LAN → WAN: pass all; ICMP: pass; WAN → LAN: block (default); LAN → OPT1: block (default, overridden per-lab at deploy). Writes rules via direct XML edit to `/conf/config.xml` and calls `pfctl -f /tmp/rules.conf` to activate.

**Section 6 — SSH hardening:** Enables SSH console access, restricts to key authentication where possible, and disables SSH version 1. This allows `Set-VMNetworkConfig.ps1` to configure the pfSense at deploy time via SSH commands.

**Section 7 — Install deploy hook:** Copies the deploy customisation script to `/opt/scps-lab/deploy-customise.sh`. This script is called at deploy time with the class ID, student ID, LAN IP, and admin password arguments to finalise per-student configuration.

**Section 8 — Sysprep and power off:** Clears the pfSense event log, removes any SSH host keys (regenerated on first boot), sets the system hostname to `pfsense-template`, and powers off the VM.

---

## 5. Per-Lab NIC Assignment

The pfSense image is a single base VHDX used across four labs. The NIC-to-virtual-switch mapping differs per lab. The deployment script connects the differencing disk VM's NICs to the correct Hyper-V virtual switches at deploy time.

### Lab 1 — Red Team / Blue Team (3 segments)

| pfSense NIC | Hyper-V vSwitch | Network Name | Student IP |
|-------------|----------------|-------------|-----------|
| `hn0` (WAN) | `External-Internet` | Internet/WAN | DHCP from host |
| `hn1` (LAN) | `attack-net-C{C}-S{S}` | Attack network | `10.C.S.1` |
| `hn2` (OPT1) | `corporate-net-C{C}-S{S}` | Corporate network | `10.C.S.1` |
| Additional | `dmz-net-C{C}-S{S}` | DMZ | `10.C.S.1` |

Lab 1 uses pfSense as a 3-interface router: Kali is on `attack-net`, Windows targets are on `corporate-net`, and the Ubuntu Web Server is on `dmz-net`. Firewall rules permit `attack-net` → `corporate-net` and `attack-net` → `dmz-net` while blocking direct `attack-net` → `corporate-net` without traversing the firewall.

### Lab 2 — Web App Pentest (1 segment)

| pfSense NIC | Hyper-V vSwitch | Network Name | Student IP |
|-------------|----------------|-------------|-----------|
| `hn0` (WAN) | `External-Internet` | Internet/WAN | DHCP from host |
| `hn1` (LAN) | `pentest-net-C{C}-S{S}` | Pentest network | `10.C.S.1` |
| `hn2` (OPT1) | Not connected | — | — |

Lab 2 is a flat single-segment lab. Kali, DVWA, WebGoat, and Juice Shop all sit on `pentest-net`. pfSense provides a default gateway and DNS only — no inter-segment filtering required.

### Lab 4 — Network Attack & Defense (2 segments)

| pfSense NIC | Hyper-V vSwitch | Network Name | Student IP |
|-------------|----------------|-------------|-----------|
| `hn0` (WAN) | `External-Internet` | Internet/WAN | DHCP from host |
| `hn1` (LAN) | `attack-net-C{C}-S{S}` | Attack network | `10.C.S.1` |
| `hn2` (OPT1) | `internal-net-C{C}-S{S}` | Internal network | `10.C.S.1` |

Lab 4 has pfSense separating Kali (on `attack-net`) from the Ubuntu Server and Windows Server (on `internal-net`). The VyOS vulnerable router also connects to `internal-net` at `10.C.S.2`.

### Lab 5 — Malware Analysis (1 isolated segment, no WAN)

| pfSense NIC | Hyper-V vSwitch | Network Name | Student IP |
|-------------|----------------|-------------|-----------|
| `hn0` (WAN) | **Not connected** | — | — |
| `hn1` (LAN) | `analysis-net-C{C}-S{S}` | Analysis network | `10.C.S.1` |
| `hn2` (OPT1) | Not connected | — | — |

> **Critical:** In Lab 5, the WAN adapter has no virtual switch attached. There is no route from `analysis-net` to the internet or to any production network. FakeNet-NG on the FlareVM handles all simulated network responses. pfSense in Lab 5 functions only as a local gateway and DNS server for the analysis-net segment.

---

## 6. Firewall Rule Templates

The base image ships with generic rules. The deploy script adds lab-specific rules. The following tables document the rules active after deployment for each lab.

### Lab 1 — Red Team / Blue Team

| Direction | Source | Destination | Protocol | Action | Purpose |
|-----------|--------|-------------|----------|--------|---------|
| LAN (attack) → WAN | any | any | any | Pass | Kali outbound access |
| LAN (attack) → OPT1 (corporate) | any | any | any | Pass | Attack path to corporate targets |
| LAN (attack) → OPT2 (DMZ) | any | any | any | Pass | Attack path to web server |
| OPT1 (corporate) → LAN (attack) | any | any | any | Block | Prevent corporate from reaching attacker |
| WAN → any | any | any | any | Block | Default WAN block |

### Lab 4 — Network Attack & Defense

| Direction | Source | Destination | Protocol | Action | Purpose |
|-----------|--------|-------------|----------|--------|---------|
| LAN (attack) → OPT1 (internal) | any | any | any | Pass | Kali can reach internal segment |
| OPT1 (internal) → LAN (attack) | any | any | any | Block | Internal cannot initiate to attack |
| LAN (attack) → WAN | any | any | any | Pass | Kali internet access |
| ICMP | any | any | ICMP | Pass | Permit ping for diagnostics |
| WAN → any | any | any | any | Block | Default WAN block |

### Lab 5 — Malware Analysis (most restrictive)

| Direction | Source | Destination | Protocol | Action | Purpose |
|-----------|--------|-------------|----------|--------|---------|
| LAN (analysis) → WAN | any | any | any | Block | **No internet; WAN is disconnected** |
| LAN (analysis) → LAN (analysis) | any | any | any | Pass | Intra-segment communication (REMnux, FlareVM, Sandbox) |
| All other | any | any | any | Block | Default deny |

---

## 7. Deploy-Time Customisation

At deploy time, the orchestration layer calls the deploy hook installed on the pfSense VM:

```sh
/opt/scps-lab/deploy-customise.sh \
    --class-id 1 \
    --student-id 5 \
    --lan-ip 10.1.5.1 \
    --admin-password "RandomPass!2024"
```

The deploy hook:
1. Substitutes `LAN_IP_PLACEHOLDER` with the actual LAN IP in `/conf/config.xml`
2. Substitutes `CLASS_ID` and `STUDENT_ID` placeholders
3. Sets the webConfigurator admin password to the deploy-time random password
4. Applies the lab-specific additional firewall rules (passed by the orchestration layer)
5. Calls `pfSsh.php playback` to reload the configuration without a full reboot

---

## 8. Network Interfaces

pfSense always connects to:
- One WAN interface facing the Hyper-V external switch (or disconnected in Lab 5)
- One or more LAN/OPT interfaces connecting to student-specific Hyper-V internal switches

Interface names within pfSense are `hn0`, `hn1`, `hn2` (Hyper-V synthetic NIC driver). The IP address assigned to each LAN interface is `10.{ClassId}.{StudentId}.1`, making pfSense the default gateway for all VMs on that student's segment.

---

## 9. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `admin` | `LabAdmin2024!` | pfSense webConfigurator and console; overridden at deploy |

The webConfigurator is accessible at `https://10.{ClassId}.{StudentId}.1` after deployment. The self-signed certificate will generate a browser warning — this is expected.

---

## 10. Verification Steps

### Step 1 — Web Interface Accessible

From any VM on the LAN segment after deployment:

```bash
curl -k https://10.1.1.1 -o /dev/null -w "%{http_code}"
# Expected: 200 or 302 (redirect to login page)
```

### Step 2 — DHCP Server Active

From a VM on the LAN configured for DHCP:

```bash
# On Kali or Ubuntu
dhclient eth0
ip addr show eth0
# Expected: IP in the 10.{ClassId}.{StudentId}.100-200 range
```

### Step 3 — DNS Resolution Working

```bash
dig @10.1.1.1 google.com
# Expected: Resolves to A record via pfSense DNS resolver
```

### Step 4 — Firewall Rules Active

```bash
# On Kali — test that internal network hosts are reachable (Lab 4)
nmap -sn 10.1.1.20-21
# Expected: Both Ubuntu Server and Windows Server respond to ping/scan
```

### Step 5 — Lab 5 Isolation Confirmed

```bash
# On REMnux (analysis-net) — attempt outbound
curl --max-time 5 http://1.1.1.1
# Expected: Connection timeout (no WAN route)
```

---

## 11. Snapshot and Storage

```powershell
Stop-VM -Name "pfsense-build" -Force
Move-Item "pfsense-build.vhd" "C:\CyberLab\Templates\pfsense-2.7.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\pfsense-2.7.vhdx" -Name IsReadOnly -Value $true
```

> Note: pfSense on Generation 1 Hyper-V VMs uses a `.vhd` (fixed or dynamic) disk, not `.vhdx`. When exporting, verify the disk format. If it is `.vhd`, it may be converted to `.vhdx` with `Convert-VHD` for consistency with the rest of the template library, but this is optional.

---

## 12. Troubleshooting

### pfSsh.php Playback Fails

**Symptom:** The build script exits with `pfSsh.php: playback failed` or a PHP error.

**Cause:** pfSsh.php requires the pfSense PHP environment to be initialised. It must be run from the pfSense shell (option 8 from the console menu), not a generic sh session.

**Fix:** Ensure you launched the shell from the pfSense console menu (option 8) and not via direct SSH to a generic user shell. Re-run the script from option 8.

### NIC Not Detected as hn0/hn1/hn2

**Symptom:** pfSense detects NICs as `vtnet0` instead of `hn0`.

**Cause:** This occurs with some Hyper-V configurations or after importing from another hypervisor. Both `hn*` and `vtnet*` are valid Hyper-V interface names.

**Fix:** The build script accounts for both naming schemes. The `pfSense-base-config.xml` template should reference the actual NIC names found in `dmesg`. To check:

```sh
dmesg | grep -E 'hn[0-9]|vtnet[0-9]'
```

Update the config template NIC names to match what `dmesg` reports.

### Checksum Errors — VMs Cannot Communicate Through pfSense

**Symptom:** VMs can ping pfSense but cannot reach other VMs through it. TCP connections hang or packets are dropped.

**Cause:** Hyper-V's NIC offloading features conflict with pfSense's packet processing.

**Fix:** The build script disables checksum offloading. If the issue persists after deployment:

```sh
# In pfSense shell (option 8)
ifconfig hn1 -rxcsum -txcsum -tso
ifconfig hn2 -rxcsum -txcsum -tso
```

Also add to `/etc/rc.local`:

```sh
/sbin/ifconfig hn1 -rxcsum -txcsum -tso
/sbin/ifconfig hn2 -rxcsum -txcsum -tso
```

### Deploy Hook Not Found After Restore

**Symptom:** `Set-VMNetworkConfig.ps1` cannot find `/opt/scps-lab/deploy-customise.sh` on the pfSense VM.

**Cause:** The script was not installed during the build, or the VHDX was not built from the correct template.

**Fix:** Confirm the template VHDX was built using the full `Build-pfSense.sh` script and that Section 7 completed without error. Check the build log at `/var/log/lab-build-pfsense.log` on the pfSense VHDX.
