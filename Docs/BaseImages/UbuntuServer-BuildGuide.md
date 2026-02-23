# Ubuntu Server — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `ubuntu-server-22.04` |
| **VHDX path** | `C:\CyberLab\Templates\ubuntu-server-22.04.vhdx` |
| **Used in** | Lab 4 (Network Attack & Defense — internal server target) |
| **Role** | Moderately hardened internal server; provides SSH and HTTP services as a realistic target |
| **Build script** | `Scripts/BaseImages/Linux/Build-UbuntuServer.sh` |
| **Script runs** | Inside the VM as root, after OS installation |
| **Resources** | 1 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS (amd64) |

> **Note:** Unlike the Ubuntu Web Server image, this VM is moderately hardened. It is intended to resist basic, unauthenticated attacks while still providing a realistic target for students practicing lateral movement, credential reuse, and network hardening. It is not intentionally vulnerable.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Running the Build Script](#4-running-the-build-script)
5. [Security Controls Applied](#5-security-controls-applied)
6. [What the Script Configures](#6-what-the-script-configures)
7. [Network Interfaces](#7-network-interfaces)
8. [Default Credentials After Build](#8-default-credentials-after-build)
9. [Verification Steps](#9-verification-steps)
10. [Snapshot and Storage](#10-snapshot-and-storage)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

### ISO Download

```
URL: https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso
SHA256: verify at https://releases.ubuntu.com/22.04/SHA256SUMS
```

### Host Requirements

- At least 30 GB free disk space on the build path.
- Internet access for the VM during build (apt repositories).
- Build time: approximately 25–35 minutes.

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Virtual switch | External-Internet (internet required for apt) |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Installation media | Ubuntu Server 22.04 ISO |

Disable Secure Boot or set the Secure Boot template to **Microsoft UEFI Certificate Authority** after VM creation.

---

## 3. OS Installation

| Installer Step | Setting |
|---------------|---------|
| Language | English |
| Keyboard | Match your physical keyboard |
| Install type | Ubuntu Server |
| Network | Accept DHCP |
| Storage | Entire disk, no LVM |
| Server name | `ubuntu-server` |
| Username | `sysadmin` |
| Password | Temporary (overwritten by script) |
| SSH | Install OpenSSH server |
| Featured snaps | None |

After reboot, log in as `sysadmin` and switch to root: `sudo -i`.

---

## 4. Running the Build Script

```bash
# Transfer the script to the VM
scp Scripts/BaseImages/Linux/Build-UbuntuServer.sh sysadmin@<VM-IP>:/home/sysadmin/

# Execute as root
sudo -i
chmod +x /home/sysadmin/Build-UbuntuServer.sh
/home/sysadmin/Build-UbuntuServer.sh
```

The script logs to `/var/log/lab-build.log`. The VM powers off automatically when complete. Do not interrupt the script — MySQL or nginx partial configuration requires a full reinstall to fix.

---

## 5. Security Controls Applied

This image is the hardened counterpart to the vulnerable Ubuntu Web Server. The security controls below represent what students are expected to find and respect during the Lab 4 offensive phase, and what they should emulate when they implement the defensive hardening phase.

| Control | Implementation | Lab Teaching Point |
|---------|---------------|-------------------|
| SSH key auth only (sysadmin) | `PasswordAuthentication no` for sysadmin; only public key auth | Students cannot brute-force sysadmin without the private key |
| SSH root login disabled | `PermitRootLogin no` | Students must escalate from a lower-privilege account |
| Limited SSH password auth | `/etc/ssh/sshd_config.d/lab-access.conf` — password auth enabled **only** for `labuser` via a `Match User` block | Models a common real-world misconfiguration: one account with password auth exempted from the policy |
| fail2ban active | 5 failed SSH attempts → 15-minute ban | Students see their brute force attempts blocked; teaches rate-limiting |
| UFW firewall with rate limiting | Ports 22, 80, 443 open; `ufw limit 22/tcp` adds rate limiting | Students see a real firewall; port scans return filtered ports |
| Nginx with security headers | X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy headers set | Contrast with the vulnerable web server's missing headers |
| `server_tokens off` in Nginx | Version information hidden from HTTP headers | Students see only "nginx" without version, requiring fingerprinting |
| auditd enabled | Audit rules for `/etc/passwd`, `/etc/shadow`, sudo, SSH auth events, network connections | Blue team students can review audit logs post-attack |
| Kernel hardening (sysctl) | rp_filter, SYN cookies, ICMP broadcast ignore, source routing disabled, log martians, ASLR enabled | Models defence-in-depth; students see the kernel-level controls |
| Unnecessary services disabled | bluetooth, avahi-daemon, cups, cups-browsed, ModemManager, snapd, lxd all disabled | Reduces attack surface |
| No world-writable directories | Standard filesystem permissions | No obvious privilege escalation paths via writable directories |

---

## 6. What the Script Configures

### System Update (Section 1)

Full apt update, upgrade, and dist-upgrade. All packages are current as of the build date.

### Package Installation (Section 2)

Installed packages: `openssh-server`, `ufw`, `fail2ban`, `net-tools`, `nmap`, `curl`, `wget`, `nginx`, `vim`, `git`, `htop`, `unzip`, `jq`, `dnsutils`, `iputils-ping`, `tcpdump`, `netcat-openbsd`, `auditd`, `libpam-pwquality`, `acl`.

### Hyper-V Integration Services (Section 3)

`linux-cloud-tools-virtual` and `linux-tools-virtual` installed. Hyper-V modules loaded and persisted.

### User Accounts (Section 4)

Two accounts are created:

- **sysadmin**: sudo user. Password set randomly (but SSH password auth is disabled — key auth only). An empty `authorized_keys` stub is created at `/home/sysadmin/.ssh/authorized_keys` with a comment directing the deployer to insert the instructor/student public key.
- **labuser**: Standard user, no sudo. Password authentication allowed via the SSH drop-in config. This account simulates a low-privilege user that students may try to abuse.

### SSH Hardened Configuration (Section 5)

The main `sshd_config` enforces:
- `PermitRootLogin no`
- `PasswordAuthentication no` (global default)
- `PubkeyAuthentication yes`
- `AllowTcpForwarding no`, `X11Forwarding no`, `AllowAgentForwarding no`
- `MaxAuthTries 4`, `LoginGraceTime 30s`, `MaxStartups 5:30:20`
- `ClientAliveInterval 300`, `ClientAliveCountMax 2` (session keepalive)
- A legal banner at `/etc/ssh/sshd-banner`
- `Include /etc/ssh/sshd_config.d/*.conf` to pick up the lab-access drop-in

The `/etc/ssh/sshd_config.d/lab-access.conf` drop-in:
```
Match User labuser
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    ForceCommand /bin/bash
```

This allows password authentication only for `labuser`, modelling the common real-world pattern where one account is exempted from strict SSH policy.

### Firewall (Section 6)

UFW rules: default deny incoming, allow outgoing. Rules allow SSH (22/TCP), HTTP (80/TCP), HTTPS (443/TCP). SSH is also rate-limited (`ufw limit 22/tcp`).

### fail2ban (Section 7)

`/etc/fail2ban/jail.local` configures:
- `[DEFAULT]` bantime 600s, findtime 300s, maxretry 5
- `[sshd]` enabled, maxretry 4, bantime 900s
- `[nginx-http-auth]` and `[nginx-noscript]` enabled

fail2ban is started and enabled at boot.

### Nginx (Section 8)

Nginx serves a simple internal server page at port 80. `server_tokens off` is set. Security headers are added via `/etc/nginx/conf.d/security-headers.conf`.

### Auditd (Section 9)

Audit rules in `/etc/audit/rules.d/lab.rules`:
- Watch writes to `/etc/passwd`, `/etc/shadow`, `/etc/group` (identity changes)
- Watch `/var/log/sudo.log` and `/etc/sudoers` (sudo usage)
- Watch `/var/log/auth.log` (authentication events)
- Audit all `connect()` syscalls (network connections)
- Audit `setuid()` syscalls (privilege escalation attempts)

### Kernel Hardening (Section 11)

`/etc/sysctl.d/99-lab-hardening.conf` sets:
- `net.ipv4.conf.all.rp_filter = 1` (reverse path filtering)
- `net.ipv4.icmp_echo_ignore_broadcasts = 1`
- `net.ipv4.conf.all.accept_source_route = 0`
- `net.ipv4.conf.all.log_martians = 1`
- `net.ipv4.tcp_syncookies = 1`
- `net.ipv6.conf.all.accept_ra = 0`
- `kernel.randomize_va_space = 2` (full ASLR)
- `kernel.dmesg_restrict = 1`
- `fs.suid_dumpable = 0`

### Sysprep (Section 13)

Root and user bash histories cleared. SSH host keys removed with firstboot regeneration service. Machine-id cleared. Logs truncated. Free space zeroed.

---

## 7. Network Interfaces

Single network adapter (`eth0`). In Lab 4, connected to `internal-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.20`.

---

## 8. Default Credentials After Build

| Account | Auth Method | Privileges | Notes |
|---------|------------|-----------|-------|
| `sysadmin` | SSH key only (password disabled) | sudo | Deploy SSH public key to `/home/sysadmin/.ssh/authorized_keys` post-deployment |
| `labuser` | Password (see `/root/.lab-credentials`) | None (standard user) | Deploy-time credentials override this |

> **Post-deployment step:** The deploy script must inject the sysadmin SSH public key into `/home/sysadmin/.ssh/authorized_keys`. Without this, sysadmin is inaccessible via SSH (the password is set but SSH password auth is disabled for this account).

---

## 9. Verification Steps

### Step 1 — Nginx Serving

```bash
curl -I http://<VM-IP>/
# Expect: HTTP/1.1 200 OK, no server version in Server header
```

### Step 2 — fail2ban Active

```bash
# On the VM
systemctl status fail2ban
# Status: active (running)

fail2ban-client status sshd
# Should show sshd jail with 0 or more banned IPs
```

### Step 3 — SSH Key Auth Required for sysadmin

```bash
# This should fail (password auth disabled for sysadmin)
ssh -o PasswordAuthentication=yes sysadmin@<VM-IP>
# Expected: Permission denied (publickey)
```

### Step 4 — labuser Password Auth Works

```bash
ssh labuser@<VM-IP>
# Enter the labuser password from /root/.lab-credentials
# Expected: successful login to a restricted bash shell
```

### Step 5 — Kernel Hardening Applied

```bash
# On the VM
sysctl net.ipv4.tcp_syncookies
# Expected: net.ipv4.tcp_syncookies = 1

sysctl kernel.randomize_va_space
# Expected: kernel.randomize_va_space = 2
```

### Step 6 — auditd Running

```bash
systemctl status auditd
# Expected: active (running)

auditctl -l
# Expected: rules from /etc/audit/rules.d/lab.rules listed
```

---

## 10. Snapshot and Storage

```powershell
Set-ItemProperty -Path "C:\CyberLab\Templates\ubuntu-server-22.04.vhdx" -Name IsReadOnly -Value $true
```

Delete the build VM after moving the VHDX.

---

## 11. Troubleshooting

### fail2ban Fails to Start

**Symptom:** `systemctl status fail2ban` shows failed with a Python error.

**Fix:**

```bash
apt-get install -y python3-systemd
systemctl restart fail2ban
```

### nginx Fails to Start — Port Conflict

**Symptom:** nginx reports "bind() to 0.0.0.0:80 failed (98: Address already in use)."

**Fix:**

```bash
ss -tlnp | grep :80
# Identify the process using port 80 and stop it
systemctl stop apache2 2>/dev/null || true
systemctl restart nginx
```

### SSH Host Keys Missing After Boot

**Symptom:** SSH connection refused immediately after deploying a child VM from this template.

**Fix:** The `ssh-keygen-firstboot.service` unit should run automatically. Check its status:

```bash
systemctl status ssh-keygen-firstboot.service
# If failed, run manually:
dpkg-reconfigure openssh-server
systemctl restart ssh
```
