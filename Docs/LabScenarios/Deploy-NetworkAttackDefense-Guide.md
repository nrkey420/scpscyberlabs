# Lab 04 — Network Attack & Defense: Deployment Guide

| Field | Value |
|-------|-------|
| **Lab number** | 04 |
| **Lab name** | Network Attack & Defense |
| **Difficulty** | Beginner |
| **Estimated duration** | 120 minutes |
| **Deploy script** | `Scripts/LabScenarios/Deploy-04-NetworkAttackDefense.ps1` |
| **Template file** | `Templates/04-network-attack-defense.json` |
| **Maximum students** | 15 |

---

## Table of Contents

1. [Lab Overview](#1-lab-overview)
2. [Network Topology](#2-network-topology)
3. [Resource Requirements](#3-resource-requirements)
4. [Prerequisites](#4-prerequisites)
5. [Deployment Steps](#5-deployment-steps)
6. [VyOS Console Access](#6-vyos-console-access)
7. [Three Lab Phases](#7-three-lab-phases)
8. [Verification After Deployment](#8-verification-after-deployment)
9. [Student Credential Distribution](#9-student-credential-distribution)
10. [Lab Objectives Reference](#10-lab-objectives-reference)
11. [Instructor Stumbling Points](#11-instructor-stumbling-points)
12. [Teardown](#12-teardown)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Lab Overview

Lab 04 is a beginner-level network security lab. Students perform network reconnaissance, firewall analysis, a man-in-the-middle attack, and then harden the pfSense firewall and VyOS router. The lab has three sequential phases:

1. **Reconnaissance Phase:** Students use Kali to map the network topology, discover services, and identify vulnerabilities
2. **Attack Phase:** Students exploit specific weaknesses (MITM via ARP spoofing, SNMP enumeration, Telnet interception)
3. **Defense Phase:** Students harden pfSense and VyOS to block the attacks they just performed

**VMs deployed per student (5 per student):**
- Kali Linux 2024.1 — Attacker workstation (on `attack-net`)
- pfSense 2.7 — Firewall separating attack-net from internal-net
- Ubuntu Server 22.04 (hardened) — Internal server target
- Windows Server 2019 (hardened) — Internal server target with IIS
- VyOS 1.4 Vulnerable Router — Internal router with intentional misconfigurations

---

## 2. Network Topology

```
attack-net-C{C}-S{S}:
    [Kali 10.C.S.10]
         |
    [pfSense WAN=attack .1, LAN=internal .1]
         |
internal-net-C{C}-S{S}:
    [VyOS    10.C.S.2]
    [Ubuntu  10.C.S.20]
    [WinSrv  10.C.S.21]
```

| Segment | Switch Name | VMs |
|---------|------------|-----|
| Attack | `attack-net-C{C}-S{S}` | Kali (`.10`), pfSense WAN (`.1`) |
| Internal | `internal-net-C{C}-S{S}` | pfSense LAN (`.1`), VyOS (`.2`), Ubuntu (`.20`), WinSrv (`.21`) |

Kali can only reach the internal network by traversing pfSense. The pfSense base configuration permits `attack-net` → `internal-net` traffic (students can reach internal hosts), but internal hosts cannot initiate connections back to Kali.

VyOS sits at `.2` on the internal network. It is a router/switch with no upstream routing role — it is present as a target for SNMP enumeration, Telnet exploitation, and RIP injection demonstrations.

---

## 3. Resource Requirements

### Per-Student Allocation

| VM | vCPU | RAM | Initial Disk (Differencing) |
|----|------|-----|-----------------------------|
| Kali Linux | 2 | 4 GB | ~8 GB |
| pfSense | 2 | 2 GB | ~3 GB |
| Ubuntu Server | 1 | 2 GB | ~5 GB |
| Windows Server 2019 | 2 | 4 GB | ~14 GB |
| VyOS | 1 | 1 GB | ~3 GB |
| **Per-student total** | **8 vCPU** | **13 GB** | **~33 GB** |

### Total for Class of N Students

| Students | vCPU | RAM | Estimated Disk |
|----------|------|-----|---------------|
| 8 | 64 | 104 GB | 264 GB |
| 12 | 96 | 156 GB | 396 GB |
| 15 | 120 | 195 GB | 495 GB |

---

## 4. Prerequisites

### Template VHDXs Required

| File | Size Approx |
|------|------------|
| `kali-linux-2024.1.vhdx` | 25 GB |
| `pfsense-2.7.vhdx` | 8 GB |
| `ubuntu-server-22.04.vhdx` | 8 GB |
| `windows-server-2019.vhdx` | 35 GB |
| `vyos-1.4-vulnerable.vhdx` | 4 GB |

### Pre-Deployment Check

```powershell
Scripts\LabScenarios\Common\Test-LabReadiness.ps1 -LabType NetworkAttackDefense -ClassId 1 -StudentCount 12
```

---

## 5. Deployment Steps

```powershell
$sessionId = [guid]::NewGuid()

.\Scripts\LabScenarios\Deploy-04-NetworkAttackDefense.ps1 `
    -SessionId $sessionId `
    -ClassId 1 `
    -StudentIds @('alice','bob','carol','dan','eva','frank','grace','henry','ivan','julia','karen','liam') `
    -TimeoutMinutes 60
```

### Deployment Phases and Timing

| Phase | Actions | Estimated Time |
|-------|---------|---------------|
| Prerequisites validation | Templates, disk | ~15 seconds |
| Switch creation | 2 per student = 24 switches for 12 students | ~15 seconds |
| Per-student VM deployment (parallel, ThrottleLimit=5) | 5 VMs × 12 students = 60 VMs | ~12–20 minutes |
| Readiness validation | Heartbeat, VyOS Telnet check | ~3 minutes |
| Credential export | Session manifest | ~5 seconds |
| **Total** | | **~15–25 minutes** |

### VyOS VM Note

VyOS uses Generation 1 Hyper-V VMs. The deploy script creates VyOS VMs with `-Generation 1`. Generation 1 VMs do not support Hyper-V Integration Services heartbeat in the same way as Generation 2 — the deploy script uses SSH connectivity as the readiness check instead.

---

## 6. VyOS Console Access

VyOS does not have a web interface. Configuration is done via SSH or the Hyper-V console. During the lab, students must use SSH from Kali to configure the router during the hardening phase.

### Accessing VyOS Console from Hyper-V Host

```powershell
# Open a VM console connection (Virtual Machine Connection)
vmconnect.exe localhost "Lab04-VyOS-C1-S1-${shortId}"
```

Log in with `vyos` / `vyos2024`.

### From Kali (After Network is Set Up)

```bash
ssh vyos@10.C.S.2
# Password: vyos2024
```

### VyOS Configuration Mode Reference

Students must understand the VyOS two-mode CLI. A quick reference card should be distributed at session start:

```
# Enter configuration mode:
configure

# View the entire configuration:
show

# Apply a change:
set system host-name new-name
commit
save

# Leave configuration mode:
exit

# Show interfaces (operational mode):
show interfaces

# Show routing table (operational mode):
show ip route
```

---

## 7. Three Lab Phases

### Phase 1 — Network Reconnaissance (Objective 1 + 4)

Students map the network from Kali. They are given only their Kali IP (`10.C.S.10`) and told there is a network to explore.

Expected student workflow:
1. `nmap -sn 10.C.S.0/24` — host discovery
2. `nmap -sV -sC 10.C.S.1,2,20,21` — service detection
3. `nmap -sU -p 161 10.C.S.2` — SNMP discovery
4. `snmpwalk -v2c -c public 10.C.S.2` — enumerate VyOS MIB
5. `nmap --script telnet-info 10.C.S.2` — detect Telnet
6. `traceroute 10.C.S.20` — observe routing path

At the end of Phase 1, students should have mapped all 4 internal hosts and identified the VyOS vulnerabilities.

**Flag for Objective 1:** Students submit the output of their host discovery scan. The web portal validates that they found all 4 internal hosts.

### Phase 2 — Attack Phase (Objectives 2 + 3)

Students perform two attacks:

**Attack 1 — ARP Spoofing MITM (Objective 3):**
```bash
# On Kali, ARP poison between Ubuntu Server and pfSense gateway
sudo arpspoof -i eth0 -t 10.C.S.20 10.C.S.1 &
sudo arpspoof -i eth0 -t 10.C.S.1 10.C.S.20 &

# In another terminal, capture with Wireshark or tcpdump
sudo tcpdump -i eth0 -w /tmp/mitm-capture.pcap
```

**Attack 2 — Telnet Credential Interception:**
Students connect to VyOS via Telnet from Kali, and simultaneously capture traffic from a second Kali terminal:
```bash
# Terminal 1: Capture
sudo tcpdump -i eth0 -w /tmp/telnet-capture.pcap port 23

# Terminal 2: Connect via Telnet (generates plaintext credential traffic)
telnet 10.C.S.2
```
Students open the PCAP in Wireshark and follow the TCP stream to extract the `vyos2024` password in plaintext.

### Phase 3 — Defense Phase (Objectives 5 + 6)

Students harden pfSense and VyOS to block the attacks from Phase 2.

**pfSense Hardening:**
- Add ARP inspection (pfSense → Diagnostics → ARP or use pfBlockerNG)
- Add egress filtering to block traffic from internal hosts that did not originate from pfSense
- Restrict inbound traffic to only known-needed ports

**VyOS Hardening:**
Students SSH to VyOS (`ssh vyos@10.C.S.2`) and apply the hardening commands from the VyOS Build Guide:
- Disable Telnet: `delete service telnet`
- Restrict SNMP community: restrict to read-only, specific source IP
- Enable RIP MD5 authentication
- Set strong password

After hardening, students must demonstrate that:
1. Telnet to `10.C.S.2` on port 23 now fails
2. `snmpwalk -v2c -c public 10.C.S.2` returns no data (community removed)
3. ARP spoofing no longer poisons the forwarding table (pfSense ARP inspection)

---

## 8. Verification After Deployment

### Check All VMs Running

```powershell
$shortId = $sessionId.ToString().Substring(0, 8)
Get-VM | Where-Object { $_.Name -like "*Lab04*${shortId}" } |
    Select-Object Name, State | Format-Table -AutoSize
```

### Verify VyOS Vulnerabilities Present

```bash
# From Kali for student 1
nmap -p 23 10.1.1.2
# Expected: 23/tcp open

snmpwalk -v2c -c public 10.1.1.2 sysDescr
# Expected: Returns VyOS sysDescr string
```

### Verify pfSense Permits Attack → Internal Traffic

```bash
# From Kali
ping -c 3 10.1.1.20
# Expected: Replies (pfSense allows attack-net → internal-net)
```

### Verify Internal Cannot Reach Attack Network

```bash
# SSH to Ubuntu Server
ssh labuser@10.1.1.20
ping -c 3 10.1.1.10  # Kali
# Expected: No reply (pfSense blocks internal → attack)
```

---

## 9. Student Credential Distribution

| Field | Value |
|-------|-------|
| `Kali.IPAddress` | `10.C.S.10` |
| `Kali.student.Password` | SSH password for Kali |
| `VyOS.IPAddress` | `10.C.S.2` |
| `VyOS.Password` | `vyos2024` (intentionally weak — lab objective) |
| `Ubuntu.IPAddress` | `10.C.S.20` |
| `Ubuntu.labuser.Password` | Session-generated |
| `WinSrv.IPAddress` | `10.C.S.21` |
| `WinSrv.Administrator.Password` | Session-generated |
| `pfSense.admin.Password` | Session-generated pfSense admin |
| `pfSense.URL` | `https://10.C.S.1` |

Students are told their Kali IP and given the VyOS password as a starting credential (they can change it after cracking it — but the template password is provided to start the Telnet demo).

---

## 10. Lab Objectives Reference

| Objective | Phase | Points | Flag |
|-----------|-------|--------|------|
| Network Reconnaissance | 1 | 100 | `FLAG{network_recon_topology_mapped_5a2d}` |
| Firewall Rule Analysis | 1 | 150 | `FLAG{firewall_misconfig_identified_8c4f}` |
| MITM Attack | 2 | 200 | `FLAG{mitm_credentials_captured_7e3b}` |
| Port Scanning & Service ID | 2 | 100 | `FLAG{services_enumerated_vulns_found_4d9a}` |
| Firewall Hardening | 3 | 150 | `FLAG{firewall_hardened_attacks_blocked_6b1e}` |
| Network Defense Report | 3 | 100 | `FLAG{network_defense_report_complete_3f8c}` |

MITM flag: Students submit the plaintext password extracted from the Telnet PCAP (`vyos2024`) — the web portal accepts this as `FLAG{mitm_credentials_captured_7e3b}`.

---

## 11. Instructor Stumbling Points

The following are the most common places where instructors encounter unexpected issues during Lab 04.

### VyOS Not Reachable from Kali After pfSense Boots

**Why it happens:** pfSense routes from `attack-net` to `internal-net`, but VyOS is at `.2` on `internal-net` and has its own routing table. If pfSense's route to `internal-net` is not correct, packets destined for `10.C.S.2` may not reach it.

**Resolution:** Confirm pfSense `internal-net` (OPT1) interface IP is `10.C.S.1/24`. From pfSense WebUI (Diagnostics → Ping), ping `10.C.S.2`. If it responds, the route is correct. If not, check VyOS's interface IP (`show interfaces` in operational mode).

### Students Cannot Enter VyOS Configure Mode

**Why it happens:** Students SSH as `vyos` and type `configure` but see `bash: configure: command not found`.

**Resolution:** The `vyos` user must be in a VyOS shell, not a bash shell. If logging in via SSH drops to bash, check that VyOS Integration Services or the guest agent is functioning correctly. The `configure` command is only available in the VyOS-specific shell (vbash). Ensure students log in without appending a shell override: `ssh vyos@10.C.S.2` (not `ssh -t vyos@10.C.S.2 bash`).

### ARP Spoofing Does Not Work — pfSense Has ARP Inspection Already Enabled

**Why it happens:** If the pfSense base image was deployed from a VHDX that already has ARP inspection enabled (e.g., from a previous hardened session), the MITM attack will fail.

**Resolution:** Verify the `InitialState` checkpoint was taken before any hardening. If the VHDX itself has ARP inspection, it needs to be rebuilt from scratch. Check pfSense WebUI → Diagnostics → Packet Capture on the `internal-net` interface to see if ARP replies from Kali are reaching the segment.

### IIS on Windows Server 2019 Returns 401 Not 200

**Why it happens:** The Windows Server 2019 (hardened) image has Windows Authentication enabled and anonymous authentication disabled on IIS. All HTTP requests return 401.

**Resolution:** This is intentional (documented in the WindowsServer2019 build guide). Students testing the IIS web server from Kali need to provide Windows credentials: `curl -u Administrator:{password} http://10.C.S.21/`. This is a teaching moment about Windows-integrated authentication.

---

## 12. Teardown

```powershell
$shortId = $sessionId.ToString().Substring(0, 8)

Get-VM | Where-Object { $_.Name -like "*Lab04*${shortId}" } | ForEach-Object {
    Stop-VM -Name $_.Name -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $_.Name -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path "C:\CyberLab\VMs\${sessionId}" -Recurse -Force

Get-VMSwitch | Where-Object { $_.Name -match "(attack|internal)-net-C1-S\d+" } | Remove-VMSwitch -Force

Remove-Item "C:\CyberLab\Sessions\${sessionId}-credentials.json"
```

---

## 13. Troubleshooting

### VyOS Loses Configuration After Checkpoint Restore

**Symptom:** After restoring to `InitialState`, VyOS shows a clean but unconfigured state (no IPs, no Telnet, no SNMP).

**Cause:** The `InitialState` checkpoint was taken before the VyOS build script ran, capturing the state after OS install but before vulnerability configuration.

**Fix:** The VyOS VHDX must be rebuilt using the `VyOS-BuildGuide.md` build procedure. After applying all vulnerabilities and running `save`, take the `InitialState` checkpoint on the final configured state.

### pfSense WAN Interface Shows DHCP Failure

**Symptom:** pfSense console shows `WAN (DHCP) — no IP` for the WAN interface.

**Cause:** In Lab 04, pfSense WAN is connected to `attack-net`, which is a Private switch — there is no DHCP server on `attack-net`. pfSense WAN should have a static IP.

**Fix:** From the pfSense console (option 2 — Set interface IP address), set WAN to `10.C.S.1` static. The deploy script should have handled this via the pfSense deploy hook — if it did not, the hook may have failed. Check `/var/log/lab-build-pfsense.log` on the pfSense VM.
