#!/usr/bin/env bash
# =============================================================================
# Build-REMnux.sh
# SCPS CyberLab — Base Image Builder
# Image  : remnux-7.0
# Purpose: Linux malware analysis workstation for Lab 5, IP .10
# Host path (Hyper-V): C:\CyberLab\Templates\remnux-7.0.vhdx
#
# PREREQUISITES:
#   - Start from Ubuntu 20.04 LTS (REMnux 7 is Ubuntu 20.04 based)
#   - Internet access required for REMnux installer and tool downloads
#   - Minimum 4GB RAM, 50GB disk recommended for full toolset
#
# NETWORK ISOLATION NOTE:
#   This VM should be placed on an ISOLATED network segment.
#   INetSim simulates internet services locally for safe malware analysis.
#   The ufw rules restrict inbound to SSH only from management range.
#   Analysts MANUALLY start INetSim before running malware samples.
#
# Run inside the VM after Ubuntu 20.04 LTS minimal OS installation.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="remnux-7.0"
ANALYST_USER="analyst"
ANALYST_HOME="/home/analyst"
TOOLS_DIR="${ANALYST_HOME}/tools"
SAMPLES_DIR="${ANALYST_HOME}/samples"
REPORTS_DIR="${ANALYST_HOME}/reports"

# Lab management network — only SSH from this range
LAB_MGMT_NETWORK="10.0.0.0/8"

# =============================================================================
# COLOR OUTPUT FUNCTIONS
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*" | tee -a "$LOGFILE"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOGFILE"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOGFILE"; exit 1; }
success() { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOGFILE"; }
section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}" | tee -a "$LOGFILE"; }

# =============================================================================
# PREREQUISITE CHECK
# =============================================================================
[[ $EUID -ne 0 ]] && error "This script must be run as root."

# Verify Ubuntu 20.04 (REMnux base)
UBUNTU_VER="$(lsb_release -rs 2>/dev/null || echo 'unknown')"
if [[ "$UBUNTU_VER" != "20.04" ]]; then
    warn "Expected Ubuntu 20.04, got: $UBUNTU_VER"
    warn "REMnux 7 requires Ubuntu 20.04. Continuing anyway..."
fi

touch "$LOGFILE"
chmod 600 "$LOGFILE"
touch "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

exec > >(tee -a "$LOGFILE") 2>&1

info "Build started: $BUILD_TIMESTAMP"
info "Image: $IMAGE_NAME"
info "Ubuntu version: $UBUNTU_VER"

# =============================================================================
# PASSWORD GENERATION
# =============================================================================
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 20
}

ANALYST_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
ANALYST_USER=$ANALYST_USER
ANALYST_PASS=$ANALYST_PASS
# NETWORK: This VM should be ISOLATED. INetSim simulates internet.
# Start INetSim: sudo systemctl start inetsim
# Stop INetSim : sudo systemctl stop inetsim
EOF

success "Credentials file initialised."

# =============================================================================
# SECTION 1: SYSTEM UPDATE
# =============================================================================
section "System Update"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
apt-get dist-upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
apt-get autoremove -y
apt-get autoclean -y

success "System updated."

# =============================================================================
# SECTION 2: PREREQUISITE PACKAGES
# =============================================================================
section "Prerequisite Packages"

apt-get install -y \
    curl \
    wget \
    git \
    vim \
    tmux \
    net-tools \
    openssh-server \
    ufw \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    jq \
    unzip \
    p7zip-full \
    binutils \
    hexedit \
    xxd \
    file \
    strace \
    ltrace \
    gdb \
    tcpdump \
    wireshark-common \
    tshark \
    ncat \
    socat

success "Prerequisite packages installed."

# =============================================================================
# SECTION 3: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

# Note: REMnux / Ubuntu 20.04 uses linux-tools-generic naming
apt-get install -y \
    linux-tools-generic \
    linux-cloud-tools-generic || \
    apt-get install -y \
        linux-tools-virtual \
        linux-cloud-tools-virtual || \
    warn "Hyper-V tools install may have failed — verify kernel compatibility."

for mod in hv_vmbus hv_storvsc hv_blkvsc hv_netvsc hv_utils hv_balloon; do
    modprobe "$mod" 2>/dev/null || true
done

cat > /etc/modules-load.d/hyperv.conf <<'EOF'
hv_vmbus
hv_storvsc
hv_blkvsc
hv_netvsc
hv_utils
hv_balloon
EOF

success "Hyper-V integration configured."

# =============================================================================
# SECTION 4: REMNUX TOOLKIT INSTALLATION
# =============================================================================
section "REMnux Toolkit Installation"

info "Downloading REMnux installer..."
if curl -L https://remnux.org/get-remnux.sh -o /tmp/remnux-installer.sh 2>/dev/null; then
    chmod +x /tmp/remnux-installer.sh
    info "Running REMnux installer in 'dedicated' mode (installs as root)..."
    info "This will take 20-60 minutes depending on internet speed..."
    bash /tmp/remnux-installer.sh --mode=dedicated 2>&1 | tee -a "$LOGFILE" || \
        warn "REMnux installer returned non-zero — some tools may not have installed."
    rm -f /tmp/remnux-installer.sh
else
    warn "REMnux installer download failed — installing individual tools manually."
    warn "Ensure internet access and re-run, or download get-remnux.sh manually."

    # Fallback: install common malware analysis tools individually
    info "Installing core malware analysis tools as fallback..."

    # Common REMnux tools available in Ubuntu 20.04 repos
    apt-get install -y \
        foremost \
        scalpel \
        binwalk \
        radare2 \
        ghidra 2>/dev/null || true

    pip3 install \
        pefile \
        capstone \
        yara-python \
        oletools \
        virustotal-api \
        pyelftools \
        r2pipe \
        frida-tools 2>/dev/null || true
fi

success "REMnux toolkit installation completed."

# =============================================================================
# SECTION 5: ADDITIONAL PYTHON TOOLS
# =============================================================================
section "Additional Python Analysis Tools"

info "Installing Python analysis packages (pinned versions)..."
pip3 install --upgrade pip 2>/dev/null || true

pip3 install \
    pefile==2023.2.7 \
    capstone==5.0.1 \
    "yara-python>=4.3.0" \
    oletools==0.60.1 \
    dnspython==2.4.2 \
    pyelftools==0.30 \
    lief==0.14.0 \
    frida \
    frida-tools \
    angr \
    r2pipe \
    hexdump \
    construct 2>&1 | tee -a "$LOGFILE" || \
    warn "Some Python packages failed to install — check log."

success "Python analysis tools installed."

# =============================================================================
# SECTION 6: CAPA (FLARE CAPA) INSTALLATION
# =============================================================================
section "FLARE CAPA Installation"

if ! command -v capa &>/dev/null; then
    info "Installing FLARE CAPA binary..."
    CAPA_VER="$(curl -sL https://api.github.com/repos/mandiant/capa/releases/latest \
        | grep tag_name | cut -d'"' -f4)"
    CAPA_URL="https://github.com/mandiant/capa/releases/download/${CAPA_VER}/capa-${CAPA_VER}-linux.zip"

    curl -sL "$CAPA_URL" -o /tmp/capa.zip && \
        unzip -q /tmp/capa.zip -d /tmp/capa-bin/ && \
        mv /tmp/capa-bin/capa /usr/local/bin/capa && \
        chmod 755 /usr/local/bin/capa && \
        rm -rf /tmp/capa.zip /tmp/capa-bin/ && \
        success "CAPA installed: $(capa --version 2>/dev/null || echo 'version check failed')" || \
        warn "CAPA installation failed — install manually from https://github.com/mandiant/capa/releases"
else
    info "CAPA already installed: $(capa --version 2>/dev/null || true)"
fi

# =============================================================================
# SECTION 7: INETSIM INSTALLATION AND CONFIGURATION
# =============================================================================
section "INetSim Installation and Configuration"

info "Installing INetSim..."
# INetSim is in official Kali/Debian repos but requires adding the repo for Ubuntu
if ! apt-get install -y inetsim 2>/dev/null; then
    warn "INetSim not in default repos — adding Kali repo for inetsim..."

    # Add Kali Linux repo (for inetsim only)
    curl -fsSL https://archive.kali.org/archive-key.asc \
        | gpg --dearmor -o /usr/share/keyrings/kali-archive-keyring.gpg 2>/dev/null

    echo "deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] \
        http://http.kali.org/kali kali-rolling main contrib non-free" \
        > /etc/apt/sources.list.d/kali.list

    apt-get update -y 2>/dev/null || true
    apt-get install -y inetsim 2>/dev/null || \
        warn "INetSim install failed from Kali repo. Try: apt-get install -y inetsim after deploy."
    rm -f /etc/apt/sources.list.d/kali.list
fi

# Configure INetSim for malware sandbox use
INETSIM_CONF="/etc/inetsim/inetsim.conf"
if [[ -f "$INETSIM_CONF" ]]; then
    info "Configuring INetSim..."

    # Backup original
    cp -n "$INETSIM_CONF" "${INETSIM_CONF}.orig"

    cat > "$INETSIM_CONF" <<'INSIMEOF'
# =============================================================================
# INetSim configuration — SCPS CyberLab Malware Sandbox
# Start manually: sudo systemctl start inetsim
# Stop manually : sudo systemctl stop inetsim
# =============================================================================

# Bind all services to all interfaces
service_bind_address    0.0.0.0

# DNS configuration
start_service           dns
dns_bind_port           53
dns_default_ip          0.0.0.0       # Returns analyst VM's IP for all queries
dns_default_hostname    www.example.com
dns_default_domainname  example.com

# HTTP — intercepts malware HTTP callbacks
start_service           http
http_bind_port          80
http_version            1.1
http_fakemode           Yes

# HTTPS — serves self-signed cert for HTTPS callbacks
start_service           https
https_bind_port         443

# SMTP — captures outbound email attempts
start_service           smtp
smtp_bind_port          25
smtp_fqdn_hostname      mail.example.com
smtp_banner             220 mail.example.com ESMTP

# FTP — intercepts FTP exfiltration attempts
start_service           ftp
ftp_bind_port           21
ftp_banner              220 FTP service

# Logging
logfile_dir             /var/log/inetsim/
logfile_enable          1
report_dir              /var/log/inetsim/reports
INSIMEOF

    # Create INetSim log directory
    mkdir -p /var/log/inetsim/reports
    chown -R inetsim:inetsim /var/log/inetsim 2>/dev/null || true

    # Set INetSim service to manual start (analyst enables when needed)
    systemctl disable inetsim 2>/dev/null || true
    systemctl stop inetsim 2>/dev/null || true

    success "INetSim configured (manual start — run: sudo systemctl start inetsim)."
else
    warn "INetSim config not found — configure manually after installation."
fi

# =============================================================================
# SECTION 8: FAKEDNS AND MITMPROXY
# =============================================================================
section "fakedns and mitmproxy Installation"

info "Installing fakedns..."
pip3 install fakedns 2>/dev/null || \
    pip3 install dnspython 2>/dev/null || \
    warn "fakedns install failed — install manually: pip3 install fakedns"

info "Installing mitmproxy..."
if ! command -v mitmproxy &>/dev/null; then
    pip3 install mitmproxy 2>&1 | tee -a "$LOGFILE" || \
        warn "mitmproxy pip install failed — trying binary..."

    # Fallback: download mitmproxy binary
    MITM_VER="$(curl -sL https://api.github.com/repos/mitmproxy/mitmproxy/releases/latest \
        | grep tag_name | cut -d'"' -f4)"
    MITM_URL="https://github.com/mitmproxy/mitmproxy/releases/download/${MITM_VER}/mitmproxy-${MITM_VER#v}-linux.tar.gz"
    curl -sL "$MITM_URL" -o /tmp/mitmproxy.tar.gz && \
        tar -xzf /tmp/mitmproxy.tar.gz -C /usr/local/bin/ && \
        rm -f /tmp/mitmproxy.tar.gz && \
        chmod 755 /usr/local/bin/mitmproxy /usr/local/bin/mitmdump \
                  /usr/local/bin/mitmweb 2>/dev/null && \
        success "mitmproxy binary installed." || \
        warn "mitmproxy binary install also failed — install post-deployment."
fi

# =============================================================================
# SECTION 9: ANALYST USER ACCOUNT
# =============================================================================
section "Analyst User Account"

if ! id "$ANALYST_USER" &>/dev/null; then
    useradd -m -s /bin/bash -c "Malware Analyst" "$ANALYST_USER"
fi
echo "${ANALYST_USER}:${ANALYST_PASS}" | chpasswd
usermod -aG sudo "$ANALYST_USER"

# Passwordless sudo for specific analysis commands
cat > /etc/sudoers.d/analyst-lab <<'SUDOEOF'
# SCPS CyberLab — Analyst sudo privileges
# Allow starting/stopping network simulation services
analyst ALL=(ALL) NOPASSWD: /bin/systemctl start inetsim
analyst ALL=(ALL) NOPASSWD: /bin/systemctl stop inetsim
analyst ALL=(ALL) NOPASSWD: /bin/systemctl restart inetsim
analyst ALL=(ALL) NOPASSWD: /bin/systemctl status inetsim
analyst ALL=(ALL) NOPASSWD: /usr/sbin/tcpdump
analyst ALL=(ALL) NOPASSWD: /usr/bin/tshark
analyst ALL=(ALL) NOPASSWD: /sbin/ip
analyst ALL=(ALL) NOPASSWD: /sbin/iptables
SUDOEOF
chmod 440 /etc/sudoers.d/analyst-lab

success "Analyst account configured."

# =============================================================================
# SECTION 10: WORKSPACE DIRECTORIES
# =============================================================================
section "Analysis Workspace Directories"

mkdir -p "$SAMPLES_DIR"
mkdir -p "$REPORTS_DIR"
mkdir -p "$TOOLS_DIR"
mkdir -p "${ANALYST_HOME}/.local/share"

# samples — restricted directory for malware samples
chmod 700 "$SAMPLES_DIR"
chown "${ANALYST_USER}:${ANALYST_USER}" "$SAMPLES_DIR"

# reports — world-readable for team sharing
chmod 755 "$REPORTS_DIR"
chown "${ANALYST_USER}:${ANALYST_USER}" "$REPORTS_DIR"

# tools — extra tools not in REMnux
chmod 755 "$TOOLS_DIR"
chown -R "${ANALYST_USER}:${ANALYST_USER}" "$TOOLS_DIR"

# Create README files for each workspace
cat > "${SAMPLES_DIR}/README.txt" <<'README'
SCPS CyberLab — Malware Samples Directory
=========================================
Place malware samples here for analysis.

IMPORTANT SAFETY RULES:
  1. This VM should be NETWORK ISOLATED before executing samples.
  2. Start INetSim to simulate internet before running malware:
       sudo systemctl start inetsim
  3. Use 'strace' or 'ltrace' for dynamic analysis:
       strace -f -o /home/analyst/reports/<sample>.strace ./<sample>
  4. Use 'capa' for capability detection:
       capa <sample> -o /home/analyst/reports/<sample>-capa.txt
  5. Never execute samples on your host or production network.

Useful commands:
  file <sample>          — identify file type
  strings <sample>       — extract printable strings
  hexdump -C <sample>    — hex dump
  binwalk <sample>       — detect embedded files
  capa <sample>          — detect capabilities
  strace -f ./<sample>   — trace system calls
README
chmod 600 "${SAMPLES_DIR}/README.txt"
chown "${ANALYST_USER}:${ANALYST_USER}" "${SAMPLES_DIR}/README.txt"

cat > "${REPORTS_DIR}/report_template.md" <<'RPTEOF'
# Malware Analysis Report

**Analyst      :** analyst@scps.lab
**Date         :** $(date '+%Y-%m-%d')
**Lab          :** Lab 5 — Malware Analysis
**Sample Hash  :** (MD5/SHA256)
**Sample Name  :**

## Static Analysis

### File Type
- `file <sample>` output:

### Strings of Interest
-

### PE Header Info (if applicable)
- Compiler:
- Compile timestamp:
- Imports:
- Sections:

## Dynamic Analysis

### INetSim Observed Traffic
- DNS queries:
- HTTP requests:
- SMTP attempts:

### System Calls (strace)
- Files opened:
- Registry keys (if Wine):
- Network connections:

## CAPA Capabilities
-

## Indicators of Compromise (IOCs)
| Type | Value | Notes |
|------|-------|-------|
| MD5  |       |       |
| SHA256 |     |       |
| Domain |     |       |
| IP     |     |       |
| Mutex  |     |       |

## Conclusion
- Classification:
- Severity:
- Recommended actions:
RPTEOF
chmod 644 "${REPORTS_DIR}/report_template.md"
chown "${ANALYST_USER}:${ANALYST_USER}" "${REPORTS_DIR}/report_template.md"

success "Workspace directories created."

# =============================================================================
# SECTION 11: /etc/hosts — C2 DOMAIN PLACEHOLDERS
# =============================================================================
section "/etc/hosts C2 Domain Placeholders"

# Point common C2 domains and malware infrastructure to local INetSim
# This ensures malware "connects" to INetSim instead of real C2
cat >> /etc/hosts <<'HOSTSEOF'

# =============================================================================
# SCPS CyberLab REMnux — C2 domain placeholders for sandbox
# INetSim intercepts these when running. Analyst adds sample-specific domains.
# =============================================================================
127.0.0.1    c2.example.com
127.0.0.1    malware.example.com
127.0.0.1    update.example.com
127.0.0.1    beacon.example.com
127.0.0.1    download.example.com
127.0.0.1    exfil.example.com
127.0.0.1    pastebin.com
127.0.0.1    raw.githubusercontent.com.sandbox
127.0.0.1    api.telegram.org.sandbox
127.0.0.1    discord.com.sandbox
# Lab malware sample domains (add per-sample C2 domains below):
HOSTSEOF

success "/etc/hosts C2 placeholders configured."

# =============================================================================
# SECTION 12: NETWORK MANAGER STATIC IP PLACEHOLDER
# =============================================================================
section "Network Configuration"

NETPLAN_FILE="/etc/netplan/01-lab-config.yaml"

# Backup existing configs
for f in /etc/netplan/*.yaml; do
    [[ -f "$f" ]] && mv "$f" "${f}.bak.$(date +%s)" && info "Backed up: $f"
done

cat > "$NETPLAN_FILE" <<'NETPLANEOF'
# SCPS CyberLab — REMnux Network Configuration
# Replace CLASS_ID and ETH_IFACE before deployment
# This VM is ISOLATED — no default route to internet (analyst controls routing)
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 10.CLASS_ID.0.10/24
      # No default gateway — analyst adds routing when needed
      nameservers:
        addresses: [127.0.0.1]  # INetSim DNS
NETPLANEOF

chmod 600 "$NETPLAN_FILE"
warn "Update $NETPLAN_FILE: replace CLASS_ID and run: netplan apply"

success "Network configuration staged."

# =============================================================================
# SECTION 13: SHELL CONFIGURATION FOR ANALYST
# =============================================================================
section "Shell Configuration"

cat > /etc/profile.d/analyst-env.sh <<'PROFILE'
# SCPS CyberLab — REMnux analyst environment

alias ll='ls -lF --color=auto'
alias la='ls -laF --color=auto'
alias lah='ls -lahF --color=auto'
alias strings-clean='strings -a -n 8'
alias hexview='hexdump -C'
alias md5='md5sum'
alias sha256='sha256sum'
alias psaux='ps aux'
alias netstat='ss -tlnp'

# Analysis shortcuts
alias inetsim-start='sudo systemctl start inetsim && echo "INetSim started — DNS now points to localhost"'
alias inetsim-stop='sudo systemctl stop inetsim && echo "INetSim stopped"'
alias inetsim-logs='sudo tail -f /var/log/inetsim/inetsim_*.log'
alias pcap-all='sudo tcpdump -i any -w /home/analyst/reports/capture-$(date +%Y%m%d-%H%M%S).pcap'
alias analyze-pe='python3 -c "import pefile, sys; pe=pefile.PE(sys.argv[1]); pe.print_info()" '

export PS1='\[\033[01;35m\][REMNUX-ANALYST]\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\n\$ '
export PYTHONDONTWRITEBYTECODE=1

# PATH additions
export PATH=$PATH:/usr/local/bin:/opt/remnux/bin
PROFILE

chmod 644 /etc/profile.d/analyst-env.sh

# Tmux config for analysis sessions
cat > "${ANALYST_HOME}/.tmux.conf" <<'TMUXEOF'
# SCPS CyberLab — REMnux analyst tmux configuration
set -g mouse on
set -g history-limit 100000
set -g default-terminal "screen-256color"
set -g status-bg colour53
set -g status-fg colour255
set -g status-left '#[fg=colour220][REMNUX] #H '
set -g status-right '#[fg=colour120]%H:%M %Y-%m-%d'
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind r source-file ~/.tmux.conf \; display "Config reloaded"
TMUXEOF
chown "${ANALYST_USER}:${ANALYST_USER}" "${ANALYST_HOME}/.tmux.conf"

success "Shell and tmux configured for analyst."

# =============================================================================
# SECTION 14: SSH CONFIGURATION (HARDENED — ISOLATED VM)
# =============================================================================
section "SSH Configuration (Hardened)"

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — REMnux SSH Configuration (hardened, isolated VM)
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

LoginGraceTime 30s
PermitRootLogin no
StrictModes yes
MaxAuthTries 4
MaxSessions 5

PubkeyAuthentication yes
# Password auth allowed for lab access (analyst needs to connect easily)
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

AllowTcpForwarding no
X11Forwarding yes
AllowAgentForwarding no

SyslogFacility AUTH
LogLevel INFO

ClientAliveInterval 300
ClientAliveCountMax 2

Subsystem sftp /usr/lib/openssh/sftp-server

Banner /etc/ssh/sshd-banner
SSHEOF

cat > /etc/ssh/sshd-banner <<'BANNER'
*******************************************************************************
*        SCPS CyberLab — REMnux Malware Analysis Workstation (remnux-7.0)   *
*        Authorised access only. Malware samples may be present.             *
*        NEVER run samples without starting INetSim first.                   *
*******************************************************************************
BANNER

systemctl enable ssh
systemctl restart ssh
success "SSH configured."

# =============================================================================
# SECTION 15: FIREWALL (UFW — DENY ALL INBOUND, ALLOW SSH FROM MGMT)
# =============================================================================
section "Firewall (Deny All Inbound — Isolated Sandbox)"

ufw --force reset

# Default: deny all inbound, deny all forward
ufw default deny incoming
ufw default deny outgoing
ufw default deny forward

# Allow SSH only from lab management network
ufw allow in from "$LAB_MGMT_NETWORK" to any port 22 proto tcp \
    comment "SSH from lab management network only"

# Allow outbound for DNS to localhost (INetSim)
ufw allow out to 127.0.0.1 port 53
ufw allow out to 127.0.0.1

# Allow loopback
ufw allow in on lo
ufw allow out on lo

# Allow established connections
ufw allow in  on eth0 from any proto tcp match-set 2>/dev/null || \
    ufw allow in established 2>/dev/null || true

# When INetSim is running, malware needs to reach localhost services
# Outbound to self (INetSim) is handled by loopback rules above

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

warn "All inbound blocked except SSH from $LAB_MGMT_NETWORK"
warn "All outbound blocked except loopback (INetSim intercepts malware traffic)"
warn "Analysts: start INetSim before executing samples, and check logs in /var/log/inetsim/"

success "UFW firewall configured (isolated sandbox mode)."

# =============================================================================
# SECTION 16: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — REMnux 7 Malware Analysis Workstation (remnux-7.0)
  Role: Malware Analysis Platform — Lab 5 (IP: .10)

  *** ISOLATED NETWORK — No internet access by design ***

  Workspace:
    Samples  : ~/samples/     (place malware here)
    Reports  : ~/reports/     (analysis output)
    Tools    : ~/tools/       (extra tools)

  Before executing any sample:
    1. sudo systemctl start inetsim   (start network simulation)
    2. Start packet capture: pcap-all (alias)
    3. Run sample in isolated shell

  After analysis:
    1. sudo systemctl stop inetsim
    2. Review /var/log/inetsim/ for captured traffic

  Key tools: capa, strace, ltrace, binwalk, pefile, yara, mitmproxy

MOTD

# =============================================================================
# SECTION 17: DISABLE UNNECESSARY SERVICES
# =============================================================================
section "Disable Unnecessary Services"

DISABLE_SVCS=(
    bluetooth
    avahi-daemon
    cups
    cups-browsed
    ModemManager
    snapd
    multipathd
)

for svc in "${DISABLE_SVCS[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
        systemctl disable "$svc" 2>/dev/null || true
        systemctl stop "$svc" 2>/dev/null || true
        info "Disabled: $svc"
    fi
done

success "Unnecessary services disabled."

# =============================================================================
# SECTION 18: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
cat /dev/null > "${ANALYST_HOME}/.bash_history" 2>/dev/null || true

info "Removing SSH host keys (regenerated on first boot)..."
rm -f /etc/ssh/ssh_host_*

cat > /etc/systemd/system/ssh-keygen-firstboot.service <<'SVCEOF'
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_rsa_key

[Service]
Type=oneshot
ExecStart=/usr/sbin/dpkg-reconfigure openssh-server
ExecStartPost=/bin/systemctl restart ssh

[Install]
WantedBy=multi-user.target
SVCEOF
systemctl enable ssh-keygen-firstboot.service

info "Clearing machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

info "Clearing INetSim logs and reports..."
find /var/log/inetsim -type f -exec truncate -s 0 {} \; 2>/dev/null || true

info "Clearing samples directory (safety — ensure no malware in template)..."
find "$SAMPLES_DIR" -type f -not -name "README.txt" -delete 2>/dev/null || true

info "Truncating system logs..."
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true

apt-get clean
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

info "Zeroing free space..."
dd if=/dev/zero of=/zero.fill bs=1M status=progress 2>/dev/null || true
sync
rm -f /zero.fill
sync

success "Sysprep complete."

# =============================================================================
# FINAL SUMMARY
# =============================================================================
section "Build Complete — Credential Summary"

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME              ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}analyst OS password :${RESET} $ANALYST_PASS"
echo ""
echo -e "  ${YELLOW}Analysis Workspace:${RESET}"
echo -e "    Samples : $SAMPLES_DIR"
echo -e "    Reports : $REPORTS_DIR"
echo -e "    Tools   : $TOOLS_DIR"
echo ""
echo -e "  ${YELLOW}Key Tools:${RESET}"
echo -e "    capa, strace, ltrace, binwalk, pefile, yara-python"
echo -e "    mitmproxy, fakedns, inetsim, tshark, radare2"
echo ""
echo -e "  ${YELLOW}Post-deployment:${RESET}"
echo -e "    1. Replace CLASS_ID in $NETPLAN_FILE and run: netplan apply"
echo -e "    2. Place this VM on an ISOLATED Hyper-V vSwitch"
echo -e "    3. Verify: sudo systemctl start inetsim && systemctl status inetsim"
echo -e "    4. Configure ufw: update LAB_MGMT_NETWORK for your class subnet"
echo ""
echo -e "  ${YELLOW}Hyper-V Isolation Note:${RESET}"
echo -e "    Connect this VM's NIC to a PRIVATE vSwitch (no external access)."
echo -e "    Only SSH from the management network should be permitted."
echo ""
echo -e "  Credentials saved to: ${BOLD}$CREDENTIALS_FILE${RESET}"
echo -e "  Build log at        : ${BOLD}$LOGFILE${RESET}"
echo ""
echo -e "${YELLOW}  Hyper-V note: Store completed VHDX at${RESET}"
echo -e "${YELLOW}  C:\\CyberLab\\Templates\\${IMAGE_NAME}.vhdx${RESET}"
echo ""

info "Shutting down in 5 seconds..."
sleep 5
/sbin/poweroff
