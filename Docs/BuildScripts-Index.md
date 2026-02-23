# SCPS CyberLab — Build Scripts Reference

> **Audience:** System Administrators responsible for building and maintaining the SCPS CyberLab Hyper-V infrastructure.
> **Related document:** [SystemAdminGuide.md](SystemAdminGuide.md) — covers platform installation, Entra ID, and IIS configuration.

---

## Table of Contents

1. [Overview — Two-Phase Build Approach](#1-overview--two-phase-build-approach)
2. [Prerequisites](#2-prerequisites)
3. [Disk Layout](#3-disk-layout)
4. [Base Image Build Order](#4-base-image-build-order)
5. [Network Naming Convention](#5-network-naming-convention)
6. [Credential Security Model](#6-credential-security-model)
7. [Quick Reference Table](#7-quick-reference-table)
8. [Individual Documentation Links](#8-individual-documentation-links)

---

## 1. Overview — Two-Phase Build Approach

The CyberLab infrastructure is built and deployed in two distinct phases. Understanding the separation between these phases is essential before touching any script.

### Phase 1 — Build Base Images (Done Once per Semester)

Base images are fully configured VHDX files stored in `C:\CyberLab\Templates\`. Each image is built by:

1. Manually creating a Hyper-V VM and installing the base OS from ISO.
2. Running the corresponding build script inside the VM (either a Bash `.sh` script or a PowerShell `.ps1` script).
3. The build script installs all required packages, configures services, creates accounts, hardens (or intentionally weakens) the system, and runs a sysprep step that clears machine-specific state (SSH host keys, machine-id, event logs, bash history, free-space zeroing).
4. The VM shuts itself down when the script completes.
5. The resulting VHDX is moved to `C:\CyberLab\Templates\` and marked read-only.

Base images are parent disks. **They must never be booted directly for student use.** Each student deployment creates a differencing disk child that records only the delta from the parent.

### Phase 2 — Deploy Scenarios On Demand (Done Per Lab Session)

When an instructor deploys a lab through the CyberLab web platform:

1. The `CyberLabOrchestration.psm1` PowerShell module reads the scenario JSON template from `C:\CyberLab\Templates\` (the JSON definitions in `Templates/*.json`, not the VHDXs).
2. For each VM in the scenario, a new differencing VHDX is created under `C:\CyberLab\VMs\{SessionId}\` with the corresponding base image as parent.
3. A new Hyper-V VM is created, connected to the appropriate private virtual switches, and started.
4. Per-student configuration (IP addresses, hostname, credentials) is injected either via Hyper-V Key-Value Pair Exchange or by SSH into the VM's deploy-time hook script (e.g., `/opt/scps-lab/deploy-customise.sh` on pfSense).
5. A session manifest (`credentials.json`) is written to `C:\CyberLab\Sessions\{SessionId}\` and surfaced to students through the ASP.NET web platform.
6. At teardown, VMs are stopped, differencing disks are deleted, virtual switches are removed, and the session record is archived.

The two-phase model means base image builds are expensive (time-consuming) and infrequent, while deployments are fast (seconds to minutes) and happen every class.

---

## 2. Prerequisites

### 2.1 Hyper-V Host Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|-------|
| CPU cores (logical) | 16 | 32 | Hyper-V uses host logical processors |
| RAM | 64 GB | 128 GB | 115 GB usable after OS overhead (configured in `appsettings.json`) |
| OS disk | 500 GB SSD | 1 TB NVMe | For Windows Server 2022 + platform |
| Template disk | 1 TB | 2 TB | All base VHDX files; read-only after build |
| VM disk | 2 TB | 4 TB | Differencing disks for active sessions |
| NIC | 1 Gbps | 10 Gbps | Internal Hyper-V switches use virtual fabric |
| Host OS | Windows Server 2022 | Windows Server 2022 | Hyper-V role enabled |

Enable the Hyper-V role if not already present:

```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

### 2.2 Required Tools

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| PowerShell | 7.4+ | Orchestration module and build scripts | [GitHub Releases](https://github.com/PowerShell/PowerShell/releases) |
| SSH client | Any | Transferring build scripts into Linux VMs; running pfSense deploy hook | Included in Windows 10/11 and Server 2022 |
| SCP / SFTP client | Any | Copying build scripts and ISO-derived files into VMs | WinSCP or OpenSSH `scp` |
| Hyper-V Manager | Included with role | Creating VMs, managing switches, taking checkpoints | Server Manager |
| Kali Linux 2024.1 ISO | 2024.1 | Source OS for Kali image | [kali.org/get-kali](https://www.kali.org/get-kali/) |
| Ubuntu Server 22.04 ISO | 22.04 LTS | Source OS for Ubuntu images | [ubuntu.com](https://ubuntu.com/download/server) |
| pfSense 2.7 ISO | 2.7.x | Source OS for pfSense image | [pfsense.org/download](https://www.pfsense.org/download/) |
| pfSense-base-config.xml | Platform-provided | Base firewall config staged by `Build-pfSense.sh` | `Scripts/BaseImages/Network/` |
| VyOS 1.4 rolling ISO | 1.4 (sagitta) | Source OS for VyOS image | [vyos.io/download](https://vyos.io/download/) |
| REMnux 7.0 OVA | 7.0 | REMnux is distributed as OVA; convert to VHDX | [remnux.org](https://remnux.org/) |
| Windows 10 Enterprise ISO | 21H2 or later | Source OS for Windows 10 images | MSDN / Volume Licensing |
| Windows Server 2019 ISO | LTSC | Source OS for Windows Server images | MSDN / Volume Licensing |
| FLARE-VM installer | 2024 | Run inside a Windows 10 VM to build the FlareVM image | [GitHub: mandiant/flare-vm](https://github.com/mandiant/flare-vm) |
| chocolatey | Latest | Package manager used by Windows build scripts | Auto-installed by build scripts |

### 2.3 Hyper-V Virtual Switch Setup

Create three types of virtual switches before building any images:

```powershell
# External switch — used by pfSense WAN adapter and for ISOs during build
New-VMSwitch -Name "External-Internet" -NetAdapterName "Ethernet" -AllowManagementOS $true

# Internal switch — used for management access during image build
New-VMSwitch -Name "Build-Management" -SwitchType Internal

# Private switches are created dynamically per session by the orchestration module
# No manual creation needed for those
```

---

## 3. Disk Layout

The platform expects a specific directory layout under `C:\CyberLab\`. Deviating from this layout requires updating `appsettings.json`.

```
C:\CyberLab\
├── Templates\                    # Base VHDX images (read-only after build)
│   ├── kali-linux-2024.1.vhdx
│   ├── ubuntu-server-22.04-web.vhdx
│   ├── ubuntu-server-22.04.vhdx
│   ├── security-onion-2.4.vhdx
│   ├── splunk-enterprise-9.1.vhdx
│   ├── dvwa-latest.vhdx
│   ├── webgoat-2023.8.vhdx
│   ├── juice-shop-host.vhdx
│   ├── remnux-7.0.vhdx
│   ├── windows-10-vulnerable.vhdx
│   ├── windows-10-enterprise.vhdx
│   ├── windows-server-2019-ad.vhdx
│   ├── windows-server-2019.vhdx
│   ├── flarevm-win10-2024.vhdx
│   ├── windows-10-sandbox.vhdx
│   ├── pfsense-2.7.vhdx
│   └── vyos-1.4-vulnerable.vhdx
│
├── VMs\                          # Active session VMs (differencing disks)
│   └── {SessionId}\
│       ├── {VMName}-{StudentId}.avhdx   # Child differencing disk
│       └── ...
│
├── Sessions\                     # Per-session metadata and credentials
│   └── {SessionId}\
│       ├── credentials.json      # Surfaced to students via web platform
│       ├── session-manifest.json # Full VM inventory with IPs and states
│       └── session.log           # Deployment and teardown event log
│
├── Logs\                         # Platform application logs (Serilog)
│   └── cyberlab-YYYYMMDD.log
│
├── Modules\                      # PowerShell orchestration module
│   └── CyberLabOrchestration.psm1
│
└── publish\                      # ASP.NET application published output
    ├── appsettings.json
    └── CyberLabPlatform.Web.dll
```

| Directory | Purpose | Access |
|-----------|---------|--------|
| `Templates\` | Parent VHDX files; read-only after build. Never delete or modify while sessions are running. | Administrators only |
| `VMs\` | Child differencing disks for active sessions. Managed entirely by the orchestration module. Do not manually modify. | Administrators only (managed by platform) |
| `Sessions\` | JSON metadata written at deploy time and read by the web platform. Contains credentials surfaced to students. | Administrators + App Pool identity |
| `Logs\` | Serilog rolling daily log files. Retained 90 days. | Administrators; monitoring tools |

---

## 4. Base Image Build Order

Build base images in the order below. pfSense must be built before any lab-specific image because several deployment scripts call the pfSense deploy hook via SSH. Linux base images must be built before Windows images that depend on interoperability testing.

### 4.1 Recommended Build Sequence

| Step | Image Name | Script | Est. Build Time |
|------|-----------|--------|----------------|
| 1 | `pfsense-2.7` | `Scripts/BaseImages/Network/Build-pfSense.sh` | 45 min |
| 2 | `kali-linux-2024.1` | `Scripts/BaseImages/Linux/Build-KaliLinux.sh` | 90 min |
| 3 | `ubuntu-server-22.04` | `Scripts/BaseImages/Linux/Build-UbuntuServer.sh` | 30 min |
| 4 | `ubuntu-server-22.04-web` | `Scripts/BaseImages/Linux/Build-UbuntuWebServer.sh` | 45 min |
| 5 | `security-onion-2.4` | Manual wizard + post-config | 120 min |
| 6 | `splunk-enterprise-9.1` | Manual install + post-config | 60 min |
| 7 | `dvwa-latest` | Manual (Docker-based) | 30 min |
| 8 | `webgoat-2023.8` | Manual (systemd service) | 30 min |
| 9 | `juice-shop-host` | Manual (Docker-based) | 20 min |
| 10 | `remnux-7.0` | OVA import + convert | 30 min |
| 11 | `windows-10-vulnerable` | `Scripts/BaseImages/Windows/Build-Windows10Vulnerable.ps1` | 60 min |
| 12 | `windows-10-enterprise` | Manual + Sysmon + Splunk UF | 90 min |
| 13 | `windows-server-2019-ad` | Manual + AD DS promotion + post-config | 120 min |
| 14 | `windows-server-2019` | Manual + IIS + hardening | 60 min |
| 15 | `flarevm-win10-2024` | Manual + FLARE-VM installer | 180 min |
| 16 | `windows-10-sandbox` | Manual + Sysmon + isolation | 60 min |
| 17 | `vyos-1.4-vulnerable` | Manual VyOS configure mode | 30 min |

### 4.2 Cross-Reference: Which Labs Use Each Image

| Image | Lab 1 Red/Blue | Lab 2 Web Pentest | Lab 3 SOC Analyst | Lab 4 Net Atk/Def | Lab 5 Malware |
|-------|:-:|:-:|:-:|:-:|:-:|
| `kali-linux-2024.1` | Yes | Yes | — | Yes | — |
| `ubuntu-server-22.04-web` | Yes (DMZ) | — | Yes | — | — |
| `ubuntu-server-22.04` | — | — | — | Yes | — |
| `security-onion-2.4` | Yes (shared) | — | Yes (shared) | — | — |
| `splunk-enterprise-9.1` | Yes (shared) | — | Yes (shared) | — | — |
| `dvwa-latest` | — | Yes | — | — | — |
| `webgoat-2023.8` | — | Yes | — | — | — |
| `juice-shop-host` | — | Yes | — | — | — |
| `remnux-7.0` | — | — | — | — | Yes |
| `windows-10-vulnerable` | Yes | — | — | — | — |
| `windows-10-enterprise` | — | — | Yes | — | — |
| `windows-server-2019-ad` | Yes | — | Yes | — | — |
| `windows-server-2019` | — | — | — | Yes | — |
| `flarevm-win10-2024` | — | — | — | — | Yes |
| `windows-10-sandbox` | — | — | — | — | Yes |
| `pfsense-2.7` | Yes | Yes | — | Yes | Yes |
| `vyos-1.4-vulnerable` | — | — | — | Yes | — |

---

## 5. Network Naming Convention

### 5.1 Virtual Switch Names

The orchestration module creates and destroys Hyper-V private virtual switches automatically. The naming scheme encodes the class and student identifiers so multiple classes can run simultaneously without switch collision.

| Pattern | Example | Usage |
|---------|---------|-------|
| `attack-net-C{ClassId}-S{StudentId}` | `attack-net-C1-S3` | Kali attacker segment (Labs 1, 2, 4) |
| `corporate-net-C{ClassId}-S{StudentId}` | `corporate-net-C1-S3` | Internal corporate segment (Lab 1) |
| `dmz-net-C{ClassId}-S{StudentId}` | `dmz-net-C1-S3` | DMZ web server segment (Lab 1) |
| `pentest-net-C{ClassId}-S{StudentId}` | `pentest-net-C2-S7` | Web pentest segment (Lab 2) |
| `internal-net-C{ClassId}-S{StudentId}` | `internal-net-C1-S3` | Internal server segment (Lab 4) |
| `analysis-net-C{ClassId}-S{StudentId}` | `analysis-net-C1-S1` | Isolated malware analysis segment (Lab 5) |
| `monitor-net-C{ClassId}` | `monitor-net-C1` | Shared monitoring segment (Labs 1, 3) — one per class, not per student |

The `monitor-net-C{ClassId}` switch is created once per class session (not per student) because Security Onion and Splunk are shared VMs with class-level scope.

### 5.2 IP Address Schema

All lab IPs follow the scheme `10.ClassId.StudentId.Host`:

| Octet | Meaning | Range |
|-------|---------|-------|
| First (10) | Fixed | Always 10 |
| Second (ClassId) | Class identifier | 1–9 (configured at platform level) |
| Third (StudentId) | Student slot number | 1–15 for per-student VMs; 0 for shared VMs |
| Fourth (Host) | VM role within segment | See table below |

**Host octet assignments (standard roles):**

| Host Octet | VM Role |
|-----------|---------|
| .1 | pfSense gateway / default route |
| .2 | VyOS vulnerable router (Lab 4) |
| .10 | Kali Linux attacker |
| .11 | FlareVM (Lab 5) |
| .20 | Primary Windows or Ubuntu target |
| .21 | Secondary Windows or server target |
| .30 | Linux web server target |
| .0.50 | Security Onion (shared — StudentId=0) |
| .0.51 | Splunk SIEM (shared — StudentId=0) |

**Example for Class 1, Student 3, Lab 1:**

```
10.1.3.1   — pfSense LAN (corporate-net gateway)
10.1.3.10  — Kali Linux (attack-net)
10.1.3.20  — Windows 10 Vulnerable (corporate-net)
10.1.3.21  — Windows Server 2019 AD (corporate-net)
10.1.3.30  — Ubuntu Web Server (dmz-net)
10.1.0.50  — Security Onion (monitor-net, shared for all of Class 1)
10.1.0.51  — Splunk SIEM (monitor-net, shared for all of Class 1)
```

### 5.3 Shared vs Per-Student VMs

| VM Type | Switch | Student Count | Notes |
|---------|--------|:---:|-------|
| Per-student | Unique private switch per student | 1 | Isolated; no cross-student visibility |
| Shared (class) | Shared switch for the whole class | All students in class | Security Onion and Splunk only. Require pre-deployment setup by instructor. |

Shared VMs use StudentId=0 in the IP scheme. They must be deployed and fully started before any per-student VMs are created, because student VMs attempt to register their logs with Splunk at boot.

---

## 6. Credential Security Model

### 6.1 How Credentials Are Generated

Every build script generates cryptographically random passwords using `/dev/urandom` (Linux) or `System.Security.Cryptography.RandomNumberGenerator` (Windows). Passwords are 20 characters drawn from alphanumeric and symbol character sets. They are generated once at build time and embedded into the template image.

At deploy time, the orchestration module generates a new set of per-session, per-student passwords and overwrites the template defaults.

### 6.2 Credential Files in Build Scripts

| File | OS | Location | Permissions | Contents |
|------|----|----|---|---------|
| `credentials.txt` | Windows | `C:\LabBuild\credentials.txt` | NTFS: Administrators only (inherited permissions removed) | Plaintext account list including intentional vulnerability summary |
| `.lab-credentials` | Linux | `/root/.lab-credentials` | `600` (root read-only) | Shell-variable format: `USER=name`, `PASS=value` |
| `build.log` | Windows | `C:\LabBuild\build.log` | NTFS: Administrators only | Full PowerShell transcript |
| `lab-build.log` | Linux | `/var/log/lab-build.log` | `600` (root read-only) | Full script output with timestamps |

> **Warning:** The credential files embedded in the template VHDX are the **build-time** credentials. They are intentionally preserved so an administrator can retrieve them if needed. However, deployment scripts **replace** these with per-session credentials. Never use build-time credentials as student-facing passwords.

### 6.3 Credential Flow

```
Build Script
  └── generates random password
  └── writes to /root/.lab-credentials (Linux) or C:\LabBuild\credentials.txt (Windows)
  └── sets password on local account(s)
  └── sysprep: image is generalized but credentials file IS preserved

Deployment (CyberLabOrchestration.psm1)
  └── creates differencing disk from parent VHDX
  └── boots VM
  └── injects per-student credentials via:
        - Hyper-V KVP (Windows VMs)
        - SSH → /opt/scps-lab/deploy-customise.sh (pfSense, Linux VMs)
  └── writes C:\CyberLab\Sessions\{SessionId}\credentials.json

ASP.NET Platform (LabOrchestrationService.cs)
  └── reads credentials.json
  └── stores in database (vm_instances table, encrypted at rest)
  └── surfaces to students via Student Dashboard (read-only display)
```

### 6.4 Encryption Approach

- The `credentials.json` session manifest is stored at rest on the host filesystem under `C:\CyberLab\Sessions\`. Apply NTFS permissions to restrict access to the App Pool identity and Administrators only.
- Credentials in the PostgreSQL database are stored in the `vm_instances` table. The connection string in `appsettings.json` must use SSL (`SSL Mode=Require`). See the [SystemAdminGuide.md](SystemAdminGuide.md) Security Hardening Checklist for database hardening steps.
- Credentials are transmitted to the student browser over HTTPS only. The IIS site must have a valid TLS certificate and HTTP must redirect to HTTPS.
- The build-time credential files inside the VHDX (`.lab-credentials`, `credentials.txt`) are protected only by the NTFS/filesystem permissions of the template disk. Mark the template VHDXs as read-only and restrict the `C:\CyberLab\Templates\` directory to Administrators and the App Pool identity.

---

## 7. Quick Reference Table

| Script / Config | Image Built | Runtime Location | Labs | Purpose |
|----------------|------------|-----------------|------|---------|
| `Scripts/BaseImages/Linux/Build-KaliLinux.sh` | `kali-linux-2024.1` | Inside Kali VM (root) | 1, 2, 4 | Install attack tools, configure SSH, sysprep |
| `Scripts/BaseImages/Linux/Build-UbuntuServer.sh` | `ubuntu-server-22.04` | Inside Ubuntu VM (root) | 4 | Hardened server, fail2ban, auditd, nginx |
| `Scripts/BaseImages/Linux/Build-UbuntuWebServer.sh` | `ubuntu-server-22.04-web` | Inside Ubuntu VM (root) | 1, 3 | Intentionally vulnerable LAMP + DVWA |
| `Scripts/BaseImages/Network/Build-pfSense.sh` | `pfsense-2.7` | Inside pfSense shell (root, sh) | 1, 2, 4, 5 | Firewall config, interface assignments, deploy hook |
| `Scripts/BaseImages/Windows/Build-Windows10Vulnerable.ps1` | `windows-10-vulnerable` | Inside Windows VM (Administrator) | 1 | Disable Defender/firewall, enable SMBv1/WinRM, weak accounts |
| `pfSense-base-config.xml` (companion to Build-pfSense.sh) | `pfsense-2.7` | Copied to pfSense /tmp before build | 1, 2, 4, 5 | Starting config.xml for pfSense build |
| `Templates/01-red-team-blue-team.json` | N/A (scenario def) | Read by orchestration module at deploy | 1 | VM list, IP schema, objectives for Lab 1 |
| `Templates/02-web-app-pentest.json` | N/A (scenario def) | Read by orchestration module at deploy | 2 | VM list, IP schema, objectives for Lab 2 |
| `Templates/03-soc-analyst.json` | N/A (scenario def) | Read by orchestration module at deploy | 3 | VM list, IP schema, objectives for Lab 3 |
| `Templates/04-network-attack-defense.json` | N/A (scenario def) | Read by orchestration module at deploy | 4 | VM list, IP schema, objectives for Lab 4 |
| `Templates/05-malware-analysis.json` | N/A (scenario def) | Read by orchestration module at deploy | 5 | VM list, IP schema, objectives for Lab 5 |
| `PowerShell/CyberLabOrchestration.psm1` | N/A (platform module) | Host PowerShell (called by ASP.NET) | All | Deploy/teardown sessions, manage Hyper-V |

---

## 8. Individual Documentation Links

### Base Image Build Guides

| Guide | Image | Labs |
|-------|-------|------|
| [KaliLinux-BuildGuide.md](BaseImages/KaliLinux-BuildGuide.md) | `kali-linux-2024.1` | 1, 2, 4 |
| [UbuntuWebServer-BuildGuide.md](BaseImages/UbuntuWebServer-BuildGuide.md) | `ubuntu-server-22.04-web` | 1, 3 |
| [UbuntuServer-BuildGuide.md](BaseImages/UbuntuServer-BuildGuide.md) | `ubuntu-server-22.04` | 4 |
| [SecurityOnion-BuildGuide.md](BaseImages/SecurityOnion-BuildGuide.md) | `security-onion-2.4` | 1, 3 |
| [Splunk-BuildGuide.md](BaseImages/Splunk-BuildGuide.md) | `splunk-enterprise-9.1` | 1, 3 |
| [DVWA-BuildGuide.md](BaseImages/DVWA-BuildGuide.md) | `dvwa-latest` | 2 |
| [WebGoat-BuildGuide.md](BaseImages/WebGoat-BuildGuide.md) | `webgoat-2023.8` | 2 |
| [JuiceShop-BuildGuide.md](BaseImages/JuiceShop-BuildGuide.md) | `juice-shop-host` | 2 |
| [REMnux-BuildGuide.md](BaseImages/REMnux-BuildGuide.md) | `remnux-7.0` | 5 |
| [Windows10Vulnerable-BuildGuide.md](BaseImages/Windows10Vulnerable-BuildGuide.md) | `windows-10-vulnerable` | 1 |
| [Windows10Enterprise-BuildGuide.md](BaseImages/Windows10Enterprise-BuildGuide.md) | `windows-10-enterprise` | 3 |
| [WindowsServer2019AD-BuildGuide.md](BaseImages/WindowsServer2019AD-BuildGuide.md) | `windows-server-2019-ad` | 1, 3 |
| [WindowsServer2019-BuildGuide.md](BaseImages/WindowsServer2019-BuildGuide.md) | `windows-server-2019` | 4 |
| [FlareVM-BuildGuide.md](BaseImages/FlareVM-BuildGuide.md) | `flarevm-win10-2024` | 5 |
| [Windows10Sandbox-BuildGuide.md](BaseImages/Windows10Sandbox-BuildGuide.md) | `windows-10-sandbox` | 5 |
| [pfSense-BuildGuide.md](BaseImages/pfSense-BuildGuide.md) | `pfsense-2.7` | 1, 2, 4, 5 |
| [VyOS-BuildGuide.md](BaseImages/VyOS-BuildGuide.md) | `vyos-1.4-vulnerable` | 4 |

### Lab Scenario Deployment Guides

| Guide | Lab |
|-------|-----|
| [Deploy-RedTeamBlueTeam-Guide.md](LabScenarios/Deploy-RedTeamBlueTeam-Guide.md) | Lab 1 — Red Team / Blue Team |
| [Deploy-WebAppPentest-Guide.md](LabScenarios/Deploy-WebAppPentest-Guide.md) | Lab 2 — Web App Pentest |
| [Deploy-SOCAnalyst-Guide.md](LabScenarios/Deploy-SOCAnalyst-Guide.md) | Lab 3 — SOC Analyst |
| [Deploy-NetworkAttackDefense-Guide.md](LabScenarios/Deploy-NetworkAttackDefense-Guide.md) | Lab 4 — Network Attack & Defense |
| [Deploy-MalwareAnalysis-Guide.md](LabScenarios/Deploy-MalwareAnalysis-Guide.md) | Lab 5 — Malware Analysis Sandbox |
