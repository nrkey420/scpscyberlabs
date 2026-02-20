# VyOS 1.4 Vulnerable Router — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `vyos-1.4-vulnerable` |
| **VHDX path** | `C:\CyberLab\Templates\vyos-1.4-vulnerable.vhdx` |
| **Used in** | Lab 4 (Network Attack & Defense — vulnerable internal router target) |
| **Role** | Intentionally misconfigured VyOS router on the internal network segment; acts as a secondary router behind pfSense with deliberate vulnerabilities for students to discover and remediate |
| **Build script** | None — configured manually in VyOS configure mode |
| **Resources** | 1 vCPU, 1 GB RAM, 10 GB dynamic VHDX |
| **Base OS** | VyOS 1.4 LTS (based on Debian Bookworm) |

> **WARNING:** This VyOS image contains intentional security misconfigurations for educational purposes. The vulnerabilities documented in this guide are deliberate. Deploy only within isolated Hyper-V private switches. Never connect this image to production infrastructure.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [VyOS Configure Mode Overview](#2-vyos-configure-mode-overview)
3. [Hyper-V VM Creation](#3-hyper-v-vm-creation)
4. [OS Installation](#4-os-installation)
5. [Base Network Configuration](#5-base-network-configuration)
6. [Intentional Vulnerabilities](#6-intentional-vulnerabilities)
7. [Applying Vulnerabilities — Full Configuration](#7-applying-vulnerabilities--full-configuration)
8. [Network Interfaces](#8-network-interfaces)
9. [Default Credentials After Build](#9-default-credentials-after-build)
10. [Verification Steps](#10-verification-steps)
11. [Hardening Commands for Lab 4 Defensive Phase](#11-hardening-commands-for-lab-4-defensive-phase)
12. [Snapshot and Storage](#12-snapshot-and-storage)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

- VyOS 1.4 LTS rolling release ISO — download from `https://vyos.io/get-vyos/` (select LTS build; 1.4.x)
- VyOS runs on standard x86-64; no special drivers required for Hyper-V
- Build time: approximately 20–30 minutes

---

## 2. VyOS Configure Mode Overview

VyOS uses a two-mode CLI similar to Junos:

| Mode | How to Enter | What You Can Do |
|------|-------------|----------------|
| **Operational mode** | Default on login | Show commands (`show interfaces`, `show route`, `ping`, `traceroute`), reboot, poweroff |
| **Configure mode** | Type `configure` | Set configuration (`set`, `delete`, `commit`, `save`) |

### Key Commands

| Command | Mode | Purpose |
|---------|------|---------|
| `configure` | Operational | Enter configure mode |
| `set <path>` | Configure | Apply a configuration setting |
| `delete <path>` | Configure | Remove a configuration setting |
| `commit` | Configure | Apply pending changes to running config (does not save) |
| `save` | Configure | Write running config to disk persistently |
| `exit` | Configure | Return to operational mode |
| `show configuration` | Operational or Configure | Display entire running configuration |
| `show interfaces` | Operational | Show interface state and IP addresses |
| `show route` | Operational | Show routing table |

---

## 3. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 1** |
| Startup RAM | **1024 MB** |
| Dynamic Memory | Disabled |
| Processor count | **1 vCPU** |
| Virtual hard disk | **10 GB**, Dynamically expanding |
| Network adapters | **Two NICs**: NIC1 = `internal-net` (primary), NIC2 = optional second segment |
| Secure Boot | Not available (Generation 1) |

---

## 4. OS Installation

Boot from the VyOS ISO. At the login prompt:

```
Username: vyos
Password: vyos
```

Run the disk installer:

```
install image
```

Follow the prompts:

| Prompt | Value |
|--------|-------|
| Partition | Auto partition entire disk |
| Image name | `1.4-lts` (default) |
| Config directory | Default |
| Password for vyos user | `LabBuildPass!2024` (overridden at deploy) |

After installation completes, reboot and remove the ISO.

---

## 5. Base Network Configuration

Log in after reboot (username `vyos`, password set during install). Enter configure mode:

```
configure
```

### Assign Interfaces and Static IP

```
set interfaces ethernet eth0 address 10.CLASS_ID.STUDENT_ID.2/24
set interfaces ethernet eth0 description "internal-net"
commit
```

At build time, use placeholder values (e.g., `10.0.0.2/24`). The deploy script substitutes the actual class and student IDs.

### Set Hostname

```
set system host-name vyos-router
commit
```

### Configure Default Route

```
set protocols static route 0.0.0.0/0 next-hop 10.CLASS_ID.STUDENT_ID.1
commit
```

### Configure DNS

```
set system name-server 1.1.1.1
set system name-server 8.8.8.8
commit
```

### Save Base Configuration

```
save
exit
```

---

## 6. Intentional Vulnerabilities

The following vulnerabilities are deliberately applied to the VyOS router. Each row documents the vulnerability, how it manifests, how students detect and exploit it during the offensive phase of Lab 4, and how to remediate it during the defensive phase.

| Vulnerability | Configuration Detail | Detection Method | Exploitation Method | Remediation Command |
|--------------|---------------------|-----------------|--------------------|--------------------|
| **Telnet enabled** | `service telnet` enabled; plaintext remote access on TCP/23 | `nmap -p 23 10.C.S.2` returns open; `telnet 10.C.S.2` connects | Login with `vyos` credentials over Telnet; captures plaintext password with Wireshark ARP spoof | `delete service telnet` → `commit` → `save` |
| **SNMPv2c with public community** | SNMP agent listening on UDP/161; community string `public` | `nmap -sU -p 161 10.C.S.2`; `snmpwalk -v2c -c public 10.C.S.2` returns full MIB tree | `snmpwalk` retrieves interface names, IP addresses, routing table, ARP table; enables full network map | `delete service snmp community public` → `set service snmp community lab-monitor authorization ro` (restrict to known IP) |
| **RIP without authentication** | RIP protocol enabled on `eth0`; no authentication key; accepts routes from any peer | `nmap --script rip-info 10.C.S.2`; `tcpdump udp port 520` shows RIP broadcasts | Inject malicious RIP routes from Kali using `quagga` or Scapy; re-routes traffic through Kali for MITM | `delete protocols rip` → `set protocols rip interface eth0 authentication md5 key-id 1 md5-password <key>` |
| **Weak administrator password** | VyOS `vyos` account password: `vyos2024` (dictionary word + year) | CrackMapExec SSH spray; Hydra SSH brute force | `ssh vyos@10.C.S.2` with cracked password → full router access | `set system login user vyos authentication plaintext-password <strong-password>` → `commit` → `save` |

---

## 7. Applying Vulnerabilities — Full Configuration

Log in as `vyos` and enter configure mode:

```
configure
```

### Enable Telnet

```
set service telnet
commit
```

### Configure SNMPv2c with Public Community

```
set service snmp community public authorization rw
set service snmp listen-address 0.0.0.0
commit
```

### Configure RIP Without Authentication

```
set protocols rip interface eth0
set protocols rip network 10.0.0.0/8
commit
```

> This enables RIP on the entire internal network prefix. Any VyOS, Cisco, or Linux Quagga/FRR instance on the same segment can inject routes.

### Set Weak Password

```
set system login user vyos authentication plaintext-password vyos2024
commit
```

### Disable Firewall (No Packet Filtering)

By default, VyOS has no firewall rules applied to interfaces. Confirm no firewall policy is applied:

```
delete firewall
commit
```

If a firewall policy was previously applied to an interface, delete the interface policy assignment:

```
delete interfaces ethernet eth0 firewall
commit
```

### Save Everything

```
save
exit
```

---

## 8. Network Interfaces

Single adapter (`eth0`) in Lab 4. Connected to `internal-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.2`. The VyOS router sits behind the pfSense firewall on the internal network, between pfSense (`.1`) and the Ubuntu Server (`.20`) and Windows Server (`.21`).

The network topology on `internal-net` in Lab 4:

```
pfSense .1 <--> VyOS .2 <--> Ubuntu Server .20
                            <--> Windows Server .21
```

Kali (on `attack-net`) reaches the internal segment only through pfSense. Once inside the internal network, all VMs can communicate directly. Students must discover VyOS's presence via network scanning and then attack/harden it.

---

## 9. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `vyos` | `vyos2024` | Intentionally weak; SSH and console access; Telnet access (plaintext) |

---

## 10. Verification Steps

### Step 1 — Telnet Open

From Kali (on the internal network or through pfSense):

```bash
nmap -p 23 10.C.S.2
# Expected: 23/tcp open telnet

telnet 10.C.S.2
# Expected: VyOS login prompt
```

### Step 2 — SNMP Accessible

```bash
snmpwalk -v2c -c public 10.C.S.2
# Expected: Full MIB tree output including sysDescr, interface table, IP address table
```

### Step 3 — RIP Broadcasting

```bash
# On any host on internal-net
tcpdump -i eth0 udp port 520 -c 5
# Expected: RIP v2 multicast packets from 10.C.S.2 to 224.0.0.9
```

### Step 4 — SSH with Weak Password

```bash
ssh vyos@10.C.S.2
# Use password: vyos2024
# Expected: VyOS shell login without error
```

### Step 5 — VyOS Reachable from Kali

After pfSense rules permit access, confirm Kali can reach the VyOS router:

```bash
ping 10.C.S.2
# Expected: Replies from 10.C.S.2
```

---

## 11. Hardening Commands for Lab 4 Defensive Phase

In the second phase of Lab 4, students harden the VyOS router after exploiting it. The following commands are the correct remediations. Instructors use this section to verify student hardening reports.

### Disable Telnet — Enable SSH Only

```
configure

# Disable Telnet
delete service telnet

# Ensure SSH is enabled with a reasonable timeout
set service ssh listen-address 0.0.0.0
set service ssh timeout 300

commit
save
```

### Restrict SNMP

```
configure

# Remove the public read-write community
delete service snmp community public

# Add a read-only community restricted to the management IP
set service snmp community lab-monitor authorization ro
set service snmp community lab-monitor client 10.C.S.10

commit
save
```

### Enable RIP with MD5 Authentication

```
configure

# Add authentication to the existing RIP configuration
set protocols rip interface eth0 authentication mode md5
set protocols rip interface eth0 authentication md5 key-id 1 md5-password "RipAuthKey2024!"

commit
save
```

Or, if eliminating RIP entirely in favour of static routing:

```
configure
delete protocols rip
set protocols static route 10.C.S.0/24 next-hop 10.C.S.1
commit
save
```

### Set Strong Password

```
configure
set system login user vyos authentication plaintext-password "StrongPass!Lab4"
commit
save
```

### Apply Firewall Policy

A minimal defensive firewall policy that blocks inbound connections to Telnet and limits SNMP access:

```
configure

# Create a firewall ruleset for the internal interface
set firewall name INTERNAL-IN default-action drop
set firewall name INTERNAL-IN rule 10 action accept
set firewall name INTERNAL-IN rule 10 state established enable
set firewall name INTERNAL-IN rule 10 state related enable
set firewall name INTERNAL-IN rule 20 action accept
set firewall name INTERNAL-IN rule 20 protocol icmp
set firewall name INTERNAL-IN rule 30 action accept
set firewall name INTERNAL-IN rule 30 protocol tcp
set firewall name INTERNAL-IN rule 30 destination port 22

# Apply to the interface (inbound direction = traffic arriving from internal-net destined for the router)
set interfaces ethernet eth0 firewall in name INTERNAL-IN

commit
save
```

---

## 12. Snapshot and Storage

```powershell
Stop-VM -Name "vyos-build" -Force
Move-Item "vyos-build.vhd" "C:\CyberLab\Templates\vyos-1.4-vulnerable.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\vyos-1.4-vulnerable.vhdx" -Name IsReadOnly -Value $true
```

---

## 13. Troubleshooting

### VyOS Does Not Retain Configuration After Reboot

**Cause:** `commit` was run but `save` was not. VyOS commits apply to the running configuration but do not persist across reboots unless `save` is also run.

**Fix:** In configure mode, always run both:

```
commit
save
```

### RIP Routes Not Propagating to Other Hosts

**Symptom:** VyOS is sending RIP packets but other hosts on the segment are not accepting the routes.

**Cause:** RIP v2 uses multicast `224.0.0.9`. Some hosts may need to join the multicast group or have RIP enabled on their interface.

**Fix:** This is expected behavior for the lab — RIP injection from Kali requires Kali to be running a RIP daemon (Quagga/FRR) listening on port 520. The vulnerability is that VyOS accepts unauthenticated routes from any peer; demonstrating the exploit requires Kali to send crafted RIP response packets.

### SSH Access Denied with Correct Password

**Symptom:** `ssh vyos@10.C.S.2` returns `Permission denied (publickey)`.

**Cause:** VyOS defaults to publickey authentication only on some installations.

**Fix:** In the VyOS shell (via console), ensure password authentication is enabled:

```
configure
set service ssh disable-password-authentication false
commit
save
```

Or, confirm the deployment used `vyos2024` as the password (not the install-time `LabBuildPass!2024`).

### Telnet Hangs After Login

**Symptom:** Telnet connects and shows the login prompt, but hangs after entering credentials.

**Cause:** VyOS's Telnet implementation may time out during configure mode entry over Telnet.

**Fix:** This is a known VyOS quirk. For the lab exercise, Telnet is primarily used to demonstrate the credential interception vulnerability (Wireshark captures the plaintext password). Students are not expected to do sustained configuration work over Telnet — they switch to SSH once they have the credentials.
