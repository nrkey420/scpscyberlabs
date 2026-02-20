# Kali Linux — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `kali-linux-2024.1` |
| **VHDX path** | `C:\CyberLab\Templates\kali-linux-2024.1.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team), Lab 2 (Web App Pentest), Lab 4 (Network Attack & Defense) |
| **Role** | Red team attacker workstation |
| **Build script** | `Scripts/BaseImages/Linux/Build-KaliLinux.sh` |
| **Script runs** | Inside the VM as root, after OS installation |
| **Resources** | 2 vCPU, 4 GB RAM, 40 GB dynamic VHDX |
| **Base OS** | Kali Linux 2024.1 (amd64) |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Running the Build Script](#4-running-the-build-script)
5. [What the Script Configures](#5-what-the-script-configures)
6. [Network Interfaces](#6-network-interfaces)
7. [Default Credentials After Build](#7-default-credentials-after-build)
8. [Verification Steps](#8-verification-steps)
9. [Taking the BaseTemplate Checkpoint](#9-taking-the-basetemp-checkpoint)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Prerequisites

### ISO Download

Download the Kali Linux 2024.1 installer ISO from the official Kali mirrors. Use the **64-bit installer** (not live) image.

```
URL: https://cdimage.kali.org/kali-2024.1/kali-linux-2024.1-installer-amd64.iso
SHA256: verify against https://www.kali.org/get-kali/#kali-installer-images
```

Verify the checksum before use:

```powershell
Get-FileHash -Algorithm SHA256 "kali-linux-2024.1-installer-amd64.iso"
```

Compare the output against the value listed on the official Kali download page. Do not proceed if the checksums do not match.

### Host Requirements

- Hyper-V role enabled on Windows Server 2022.
- At least 60 GB free on the disk where you will store the build VM's VHDX during construction (40 GB for the VHDX plus overhead).
- Internet connectivity from the Hyper-V host so the VM can reach `apt` repositories and GitHub release endpoints during the build.

---

## 2. Hyper-V VM Creation

Create the build VM in Hyper-V Manager with the following exact settings. Do not deviate from the Generation 2 setting or Secure Boot configuration — Kali requires both to be set correctly.

### Step-by-Step

1. Open **Hyper-V Manager** on the host.
2. Click **Action > New > Virtual Machine**.
3. **Before You Begin** — click Next.
4. **Specify Name and Location:**
   - Name: `kali-linux-build`
   - Location: any temporary build path (this VM is discarded after the VHDX is extracted)
5. **Specify Generation:** Select **Generation 2**.
6. **Assign Memory:** Set Startup memory to **4096 MB**. Uncheck "Use Dynamic Memory" for stability during the build.
7. **Configure Networking:** Connect to your **Build-Management** or **External-Internet** internal switch so the VM can reach the internet during package installation.
8. **Connect Virtual Hard Disk:**
   - Select "Create a virtual hard disk"
   - Name: `kali-linux-build.vhdx`
   - Location: temporary build path
   - Size: **40 GB** — use a **Dynamically expanding** disk
9. **Installation Options:** Select "Install an operating system from a bootable image file" and browse to the Kali 2024.1 ISO.
10. Click **Finish**.

### Post-Creation: Disable Secure Boot

Kali does not ship Microsoft-signed shim bootloaders and will fail to boot under the default Hyper-V Generation 2 Secure Boot policy.

1. In Hyper-V Manager, right-click `kali-linux-build` > **Settings**.
2. Expand **Security**.
3. Uncheck **Enable Secure Boot**.
4. Click **OK**.

### Verify VM Settings

```powershell
Get-VM -Name "kali-linux-build" | Select-Object Name, Generation, MemoryStartup, ProcessorCount
Get-VMFirmware -VMName "kali-linux-build" | Select-Object SecureBootEnabled
# SecureBootEnabled must be False
```

---

## 3. OS Installation

1. Start the VM and connect to the console via Hyper-V Manager (Action > Connect).
2. At the Kali boot menu, select **Graphical Install** or **Install** (text mode is fine).
3. Work through the installer with these specific settings:

| Installer Step | Setting |
|---------------|---------|
| Language | English |
| Location | Your institution's country/timezone |
| Locale | en_US.UTF-8 |
| Keyboard | English (US) or match your physical keyboard |
| Hostname | `kali` (will be updated at deploy time) |
| Domain | Leave blank |
| Root password | Set any temporary password (overwritten by build script) |
| Full name | `Kali Lab User` |
| Username | `kali` |
| User password | Set any temporary password (overwritten by build script) |
| Partitioning | Guided — use entire disk, all files in one partition |
| Package manager mirror | Select a mirror close to your geography |
| Software selection | At the tasksel screen, **uncheck all desktop environments**. Select only **Standard system utilities**. This keeps the image small; tools are installed by the build script. |
| GRUB bootloader | Install to the primary drive (`/dev/sda`) |

4. When the installer completes, remove the ISO from the VM settings (Media > DVD Drive > Eject) and reboot.
5. Log in as `root` using the root password you set.

---

## 4. Running the Build Script

Transfer `Build-KaliLinux.sh` from the host to the VM, then execute it as root. The script handles everything else.

### Transfer the Script

From the host (PowerShell with OpenSSH):

```powershell
# Replace 192.168.x.x with the VM's IP on the Build-Management switch
scp Scripts/BaseImages/Linux/Build-KaliLinux.sh root@192.168.x.x:/root/
```

Or use the Hyper-V Manager File Copy feature (requires Guest Services integration enabled):

```powershell
Copy-VMFile -VMName "kali-linux-build" -SourcePath "Scripts\BaseImages\Linux\Build-KaliLinux.sh" `
            -DestinationPath "/root/Build-KaliLinux.sh" -FileSource Host -CreateFullPath
```

### Execute the Script

In the VM console or SSH session:

```bash
chmod +x /root/Build-KaliLinux.sh
sudo /root/Build-KaliLinux.sh
```

The script requires root (EUID 0) and will exit immediately with an error if run as a non-root user. All output is logged to `/var/log/lab-build.log` and also printed to the console. The build takes approximately **60–90 minutes** depending on network speed, because it downloads the `kali-tools-top10` metapackage and several GitHub-released binaries (nuclei, chisel, ligolo-ng).

**Do not interrupt the script.** If it is interrupted, reboot the VM from the original OS install (not a saved checkpoint) and re-run from the beginning.

The script ends by printing a credential summary and then calling `/sbin/poweroff`. The VM shuts down automatically when the build is complete.

---

## 5. What the Script Configures

The script is divided into 14 numbered sections. Here is what each section does, expressed as the state of the finished image.

### System Update (Section 1)

The image is fully updated: `apt-get update`, `apt-get upgrade`, and `apt-get dist-upgrade` are all run with `DEBIAN_FRONTEND=noninteractive` to prevent any interactive prompts. Unused packages are removed.

### Kali Toolset (Section 2)

The `kali-tools-top10` metapackage is installed, giving students the standard Kali toolkit (nmap, metasploit-framework, john, hashcat, wireshark, etc.). Additionally, the following tools are installed individually:

| Tool | Category |
|------|---------|
| ffuf, feroxbuster, gobuster | Web directory and content fuzzing |
| seclists, wordlists | Wordlist collections |
| nikto | Web server scanner |
| bloodhound, neo4j | AD attack path mapping |
| crackmapexec | SMB/WinRM/LDAP enumeration |
| evil-winrm | WinRM exploitation shell |
| responder | LLMNR/NBT-NS/mDNS poisoner |
| python3-impacket, impacket-scripts | AD protocol attack toolkit |
| pwncat, netcat-traditional, socat | Reverse shell handlers and tunnelling |
| proxychains4 | SOCKS proxy chaining |
| nuclei | Vulnerability scanner (latest binary from GitHub) |
| chisel | TCP tunnelling over HTTP (latest binary from GitHub) |
| ligolo-proxy, ligolo-agent | Layer 3 tunnelling (latest binaries from GitHub) |

### Development Tools (Section 3)

Installed: `tmux`, `vim`, `python3-pip`, `python3-venv`, `golang-go`, `git`, `jq`, `unzip`, `net-tools`, `dnsutils`, `iputils-ping`, `ncat`, `screen`. These support script development, payload crafting, and general CLI work during lab sessions.

### Hyper-V Integration Services (Section 4)

`hyperv-daemons` is installed and the following kernel modules are loaded and persisted across reboots via `/etc/modules-load.d/hyperv.conf`: `hv_vmbus`, `hv_storvsc`, `hv_blkvsc`, `hv_netvsc`, `hv_utils`, `hv_balloon`. These modules enable Hyper-V heartbeat, shutdown, time sync, and the KVP data exchange service used for credential injection at deploy time.

### User Account Configuration (Section 5)

The `kali` user is confirmed to exist (created if missing on a minimal install). A randomly generated 20-character password is set. The `kali` user is added to the `sudo` group. A passwordless sudo configuration is written to `/etc/sudoers.d/kali-lab` for lab convenience: `kali ALL=(ALL) NOPASSWD: ALL`.

### SSH Configuration (Section 6)

OpenSSH server is installed and enabled at boot. The SSH configuration at `/etc/ssh/sshd_config` is set to:

- Port 22, Protocol 2
- Root login: **disabled** (`PermitRootLogin no`)
- Password authentication: **enabled** — this is intentional for the attacker VM so students can practice SSH-based attacks and port forwarding
- Public key authentication: enabled
- TCP forwarding: **allowed** (`AllowTcpForwarding yes`, `GatewayPorts yes`) — enables SSH tunnelling exercises
- X11 forwarding: enabled
- An SSH banner at `/etc/ssh/lab-banner` identifies the VM as the SCPS CyberLab Kali attacker

### Firewall (Section 7)

UFW is installed and configured with a default-deny inbound policy, default-allow outbound. Port 22/TCP (SSH) is the only inbound allow rule. The attacker VM is an offensive platform; its firewall is intentionally minimal.

### /etc/hosts Placeholders (Section 8)

Commented-out host entries are appended to `/etc/hosts` listing standard lab VM hostnames and their IP scheme placeholders (e.g., `10.CLASS_ID.0.50 securityonion.lab`). Instructors or the deploy hook uncomment and populate these at deploy time.

### Shell Configuration and Aliases (Section 9)

A global shell profile `/etc/profile.d/lab-aliases.sh` adds useful aliases (`ll`, `la`, `ports`, `myip`, `update`), exports `GOPATH`, and sets a coloured PS1 prompt that displays the VM's current IP address. The same configuration is appended to `/home/kali/.bashrc`. A tmux configuration with mouse support and 50,000-line history is written to `/root/.tmux.conf` and `/home/kali/.tmux.conf`.

### /opt/tools Directory (Section 10)

`/opt/tools/` is created (chmod 755) and added to `PATH`. A `README.sh` placeholder documents tools that require live internet access at deploy time (e.g., `pip3 install bloodhound`, `pip3 install certipy-ad`) and cannot be pre-installed in the base image.

### MOTD (Section 11)

`/etc/motd` is set to a Kali-branded ASCII banner identifying the VM's role, image name, and lab scope.

### Neo4j / BloodHound Pre-configuration (Section 12)

If Neo4j is installed (as part of the bloodhound metapackage), it is enabled at boot. Students change the default Neo4j credentials (`neo4j/neo4j`) on first BloodHound login during the lab.

### Disable Unnecessary Services (Section 13)

The following services are disabled and stopped: `bluetooth`, `avahi-daemon`, `cups`, `cups-browsed`, `ModemManager`, `wpa_supplicant`. These are not needed in a VM environment and reduce the attack surface and boot time.

### Sysprep — Generalise the Image (Section 14)

The image is generalised so each deployed clone has a unique identity:

- Bash history cleared for root and kali (`/root/.bash_history`, `/home/kali/.bash_history`)
- SSH host keys removed from `/etc/ssh/ssh_host_*`; a `ssh-keygen-firstboot.service` systemd unit is created and enabled so new keys are generated on first boot of each clone
- Machine-id truncated (`/etc/machine-id`) and `/var/lib/dbus/machine-id` replaced with a symlink
- All files in `/var/log/` truncated (not deleted — services expect them to exist)
- `journalctl --rotate` and `journalctl --vacuum-time=1s` run to clear the journal
- `/tmp/` and `/var/tmp/` cleared
- Free space zeroed with `dd if=/dev/zero` to improve VHDX compressibility

---

## 6. Network Interfaces

The Kali base image has a single network adapter (`eth0`). At deploy time, the orchestration module connects this adapter to the student's `attack-net-C{ClassId}-S{StudentId}` private switch and assigns the static IP `10.{ClassId}.{StudentId}.10`.

The image has no static IP configured — netplan or interfaces are left at DHCP default. The deploy-time IP assignment is handled either by the Hyper-V KVP integration or by the scenario's post-boot script.

---

## 7. Default Credentials After Build

> **Note:** The template has no persistent student-facing password. Credentials are injected at deploy time by the scenario deployment script. The build-time password written to `/root/.lab-credentials` is only used by administrators for verification purposes.

| Account | Authentication | Notes |
|---------|---------------|-------|
| `kali` | Password (set by build script, overridden at deploy) | Passwordless sudo |
| `root` | Disabled for SSH (`PermitRootLogin no`) | Console access only |

The build-time `kali` password is displayed at the end of the build script output and saved to `/root/.lab-credentials`. Read it from the console before the VM shuts down, or access it by mounting the VHDX on the host:

```powershell
# Mount the completed VHDX to read the credentials file
Mount-VHD -Path "C:\CyberLab\Templates\kali-linux-2024.1.vhdx" -ReadOnly
# Navigate to the mounted volume and read /root/.lab-credentials
# Dismount when done
Dismount-VHD -Path "C:\CyberLab\Templates\kali-linux-2024.1.vhdx"
```

---

## 8. Verification Steps

After the script completes and the VM has shut down, perform these verification steps **before** moving the VHDX to the Templates directory. Boot the completed VHDX attached to a temporary VM (not the build VM — create a new one).

### Step 1 — Boot and Log In

Boot the VM and log in as `kali` using the credential from `/root/.lab-credentials`. If the console shows the SSH banner or the branded MOTD, the build succeeded.

### Step 2 — Verify Tools

```bash
# Check key tools are in PATH
which nmap metasploit-framework gobuster ffuf bloodhound nuclei chisel ligolo-proxy

# Verify impacket is installed
python3 -c "import impacket; print(impacket.__version__)"

# Check seclists is present
ls /usr/share/seclists/ | head -5
```

### Step 3 — Verify SSH

From the host or another VM:

```bash
ssh kali@<VM-IP>
# Confirm the lab-banner appears
# Confirm login succeeds with the build-time password
```

### Step 4 — Verify Hyper-V Integration

```bash
# Hyper-V KVP daemon should be running
systemctl status hv-kvp-daemon 2>/dev/null || systemctl status hyperv-daemons.hv-kvp-daemon
# All Hyper-V modules should be loaded
lsmod | grep hv_
```

### Step 5 — Verify Sysprep State

```bash
# Machine-id should be empty (will be populated on first boot of each clone)
cat /etc/machine-id
# Should output empty line or single newline

# SSH host keys should not exist
ls /etc/ssh/ssh_host_* 2>&1
# Should report: No such file or directory

# Bash history should be empty
cat /root/.bash_history
# Should be empty
```

---

## 9. Taking the BaseTemplate Checkpoint

After all verification steps pass, shut down the verification VM. Do **not** take a checkpoint of the verification VM — checkpoints on a VM that will become a parent disk cause problems for child differencing disks.

Instead, use the VHDX file itself as the "checkpoint":

1. Move or copy the verified VHDX to `C:\CyberLab\Templates\kali-linux-2024.1.vhdx`.
2. Mark it read-only:

```powershell
Set-ItemProperty -Path "C:\CyberLab\Templates\kali-linux-2024.1.vhdx" -Name IsReadOnly -Value $true
```

3. Delete the build VM and its associated temporary VHDX from the build location (the final VHDX in Templates is the authoritative copy).

If you need a named restore point for reference, document the build date and script commit hash in a sidecar text file:

```
C:\CyberLab\Templates\kali-linux-2024.1.vhdx.info
Built: 2026-02-20
Script commit: abc1234
Kali version: 2024.1
Notes: Full build, all tools verified.
```

---

## 10. Troubleshooting

### Hyper-V Integration Services Not Loading

**Symptom:** `systemctl status hv-kvp-daemon` shows `failed` or the unit is not found. Heartbeat shows as `Unknown` in Hyper-V Manager.

**Cause:** The kernel running in the VM does not include the Hyper-V modules, or `hyperv-daemons` is not installed for the running kernel version.

**Fix:**

```bash
# Verify the running kernel has hv_vmbus
uname -r
ls /lib/modules/$(uname -r)/kernel/drivers/hv/

# If modules are missing, install the correct hyperv tools for the kernel
apt-get install -y linux-tools-$(uname -r) linux-cloud-tools-$(uname -r) || \
apt-get install -y linux-tools-generic linux-cloud-tools-generic

# Rebuild the initramfs
update-initramfs -u

# Load modules manually to test
modprobe hv_vmbus hv_storvsc hv_netvsc hv_utils

# Reboot
reboot
```

### SSH Not Starting

**Symptom:** `ssh kali@<IP>` is refused or times out; `systemctl status ssh` shows failed.

**Cause:** SSH host keys are missing (expected after sysprep — the firstboot service should regenerate them, but sometimes systemd ordering delays it).

**Fix:**

```bash
# Manually trigger key regeneration
dpkg-reconfigure openssh-server
systemctl restart ssh
systemctl status ssh
```

### Specific Tool Install Failures

**Symptom:** The build script prints `[WARN]` for nuclei, chisel, or ligolo-ng and they are missing from `/usr/local/bin/`.

**Cause:** GitHub API rate limiting or network connectivity issues during the build. The GitHub releases API (`api.github.com`) is called to discover the latest version, and `curl` then downloads the binary. If the download fails, the `if ! command -v` guard means the install block is skipped on subsequent re-runs.

**Fix:** Re-run only the failed download manually:

```bash
# Example: re-install nuclei manually
NUCLEI_VER=$(curl -sL https://api.github.com/repos/projectdiscovery/nuclei/releases/latest \
    | grep tag_name | cut -d'"' -f4)
curl -sL "https://github.com/projectdiscovery/nuclei/releases/download/${NUCLEI_VER}/nuclei_${NUCLEI_VER#v}_linux_amd64.zip" \
    -o /tmp/nuclei.zip
unzip -q /tmp/nuclei.zip -d /tmp/nuclei-bin/
mv /tmp/nuclei-bin/nuclei /usr/local/bin/nuclei
chmod 755 /usr/local/bin/nuclei
```

Repeat the pattern for chisel and ligolo-ng, substituting the correct GitHub repository paths.

### apt Errors During kali-tools-top10 Install

**Symptom:** `apt-get install kali-tools-top10` fails with dependency errors.

**Cause:** The Kali repository may have a transient inconsistency, or the installed base has a version conflict from a prior partial install.

**Fix:**

```bash
apt-get clean
apt-get update
apt-get install -f
apt-get install -y kali-tools-top10
```

If the conflict persists, note the conflicting package from the error output and pin or manually exclude it.

### VM Will Not Boot After Build (Secure Boot Error)

**Symptom:** After the build the VM shows a Secure Boot error or black screen on boot.

**Cause:** Secure Boot was accidentally left enabled on the build VM. The sysprep regenerates the initramfs which may change the boot signature.

**Fix:** In Hyper-V Manager, go to VM Settings > Security > uncheck Enable Secure Boot. Reboot.
