#!/usr/bin/env bash
# =============================================================================
# Build-KaliLinux.sh
# SCPS CyberLab — Base Image Builder
# Image  : kali-linux-2024.1
# Purpose: Red team attacker VM used in Labs 1, 2, 4
# Host path (Hyper-V): C:\CyberLab\Templates\kali-linux-2024.1.vhdx
# Run inside the VM after Kali 2024.1 minimal OS installation.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
TOOLS_DIR="/opt/tools"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="kali-linux-2024.1"

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

# Initialise log and credentials files
touch "$LOGFILE"
chmod 600 "$LOGFILE"
touch "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

exec > >(tee -a "$LOGFILE") 2>&1

info "Build started: $BUILD_TIMESTAMP"
info "Image: $IMAGE_NAME"

# =============================================================================
# PASSWORD GENERATION
# =============================================================================
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 20
}

# Generate passwords for all accounts up front
KALI_USER_PASS="$(generate_password)"

# Persist credentials immediately
cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
KALI_USER=kali
KALI_PASS=$KALI_USER_PASS
EOF

success "Credentials file initialised at $CREDENTIALS_FILE"

# =============================================================================
# SECTION 1: SYSTEM UPDATE
# =============================================================================
section "System Update"

export DEBIAN_FRONTEND=noninteractive

info "Running apt update..."
apt-get update -y

info "Running full system upgrade..."
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
# SECTION 2: INSTALL KALI TOOLSET
# =============================================================================
section "Kali Toolset Installation"

info "Installing kali-tools-top10 metapackage..."
apt-get install -y kali-tools-top10

info "Installing additional red-team tools..."
# Tools grouped by category for readability
# Recon / web
apt-get install -y \
    ffuf \
    feroxbuster \
    gobuster \
    seclists \
    wordlists \
    nikto \
    curl \
    wget

# Active Directory / Windows attack
apt-get install -y \
    bloodhound \
    neo4j \
    crackmapexec \
    evil-winrm \
    responder

# Impacket (Kali package)
apt-get install -y python3-impacket impacket-scripts || \
    pip3 install impacket --break-system-packages

# Post-exploitation / tunnelling
apt-get install -y \
    pwncat \
    netcat-traditional \
    socat \
    proxychains4

# Nuclei — download latest binary if not in apt
if ! command -v nuclei &>/dev/null; then
    info "Installing nuclei from GitHub releases..."
    NUCLEI_VER="$(curl -sL https://api.github.com/repos/projectdiscovery/nuclei/releases/latest \
        | grep tag_name | cut -d'"' -f4)"
    NUCLEI_URL="https://github.com/projectdiscovery/nuclei/releases/download/${NUCLEI_VER}/nuclei_${NUCLEI_VER#v}_linux_amd64.zip"
    curl -sL "$NUCLEI_URL" -o /tmp/nuclei.zip
    unzip -q /tmp/nuclei.zip -d /tmp/nuclei-bin/
    mv /tmp/nuclei-bin/nuclei /usr/local/bin/nuclei
    chmod 755 /usr/local/bin/nuclei
    rm -rf /tmp/nuclei.zip /tmp/nuclei-bin/
fi

# Chisel — download latest binary
if ! command -v chisel &>/dev/null; then
    info "Installing chisel from GitHub releases..."
    CHISEL_VER="$(curl -sL https://api.github.com/repos/jpillora/chisel/releases/latest \
        | grep tag_name | cut -d'"' -f4)"
    CHISEL_URL="https://github.com/jpillora/chisel/releases/download/${CHISEL_VER}/chisel_${CHISEL_VER#v}_linux_amd64.gz"
    curl -sL "$CHISEL_URL" -o /tmp/chisel.gz
    gunzip -f /tmp/chisel.gz
    mv /tmp/chisel /usr/local/bin/chisel
    chmod 755 /usr/local/bin/chisel
fi

# Ligolo-ng — download latest binary
if ! command -v ligolo-proxy &>/dev/null; then
    info "Installing ligolo-ng from GitHub releases..."
    LIGOLO_VER="$(curl -sL https://api.github.com/repos/nicocha30/ligolo-ng/releases/latest \
        | grep tag_name | cut -d'"' -f4)"
    LIGOLO_PROXY_URL="https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_proxy_${LIGOLO_VER#v}_linux_amd64.tar.gz"
    LIGOLO_AGENT_URL="https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_agent_${LIGOLO_VER#v}_linux_amd64.tar.gz"
    curl -sL "$LIGOLO_PROXY_URL" -o /tmp/ligolo-proxy.tar.gz
    curl -sL "$LIGOLO_AGENT_URL" -o /tmp/ligolo-agent.tar.gz
    tar -xzf /tmp/ligolo-proxy.tar.gz -C /usr/local/bin/ proxy
    tar -xzf /tmp/ligolo-agent.tar.gz -C /usr/local/bin/ agent
    mv /usr/local/bin/proxy /usr/local/bin/ligolo-proxy
    mv /usr/local/bin/agent /usr/local/bin/ligolo-agent
    chmod 755 /usr/local/bin/ligolo-proxy /usr/local/bin/ligolo-agent
    rm -f /tmp/ligolo-proxy.tar.gz /tmp/ligolo-agent.tar.gz
fi

success "Kali toolset installed."

# =============================================================================
# SECTION 3: DEVELOPMENT TOOLS
# =============================================================================
section "Development Tools"

info "Installing tmux, vim, python3-pip, golang..."
apt-get install -y \
    tmux \
    vim \
    python3-pip \
    python3-venv \
    golang-go \
    git \
    jq \
    unzip \
    net-tools \
    dnsutils \
    iputils-ping \
    ncat \
    screen

success "Development tools installed."

# =============================================================================
# SECTION 4: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

info "Installing hyperv-daemons and related packages..."
apt-get install -y hyperv-daemons || \
    apt-get install -y hv-kvp-daemon-init linux-tools-generic || \
    warn "hyperv-daemons may not be available for this kernel; check manually."

# Load Hyper-V kernel modules
for mod in hv_vmbus hv_storvsc hv_blkvsc hv_netvsc hv_utils hv_balloon; do
    modprobe "$mod" 2>/dev/null && info "Loaded module: $mod" || \
        warn "Module $mod not available (may be built-in)."
done

# Persist modules across reboots
MODULES_FILE="/etc/modules-load.d/hyperv.conf"
if [[ ! -f "$MODULES_FILE" ]]; then
    cat > "$MODULES_FILE" <<'EOF'
# Hyper-V integration modules
hv_vmbus
hv_storvsc
hv_blkvsc
hv_netvsc
hv_utils
hv_balloon
EOF
fi

success "Hyper-V integration services configured."

# =============================================================================
# SECTION 5: USER ACCOUNT CONFIGURATION
# =============================================================================
section "User Account Configuration"

# The 'kali' user should already exist on a Kali minimal install.
# Create it if missing (idempotent).
if ! id kali &>/dev/null; then
    info "Creating user 'kali'..."
    useradd -m -s /bin/bash -c "Kali Lab User" kali
fi

info "Setting password for user 'kali'..."
echo "kali:${KALI_USER_PASS}" | chpasswd

# Ensure kali is in sudo group
usermod -aG sudo kali

# Configure passwordless sudo for kali (lab convenience)
SUDOERS_KALI="/etc/sudoers.d/kali-lab"
if [[ ! -f "$SUDOERS_KALI" ]]; then
    echo "kali ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_KALI"
    chmod 440 "$SUDOERS_KALI"
fi

success "User 'kali' configured."

# =============================================================================
# SECTION 6: SSH CONFIGURATION
# =============================================================================
section "SSH Configuration"

# For Kali red-team attacker VM: SSH password auth is deliberately enabled
# so students can practice connecting and using SSH tunnels/port forwarding.

info "Installing and enabling OpenSSH server..."
apt-get install -y openssh-server
systemctl enable ssh

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — Kali Attacker SSH Configuration
# Password auth intentionally enabled for student practice
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
LoginGraceTime 2m
PermitRootLogin no
StrictModes yes
MaxAuthTries 6
MaxSessions 10

PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Lab features
AllowTcpForwarding yes
GatewayPorts yes
X11Forwarding yes

# Logging
SyslogFacility AUTH
LogLevel INFO

# SFTP
Subsystem sftp /usr/lib/openssh/sftp-server

# Banner
Banner /etc/ssh/lab-banner
SSHEOF

cat > /etc/ssh/lab-banner <<'BANNER'
*******************************************************************************
*       SCPS CyberLab — Kali Linux Attacker VM (kali-linux-2024.1)           *
*       Authorised lab use only. Activity is logged.                          *
*******************************************************************************
BANNER

systemctl restart ssh
success "SSH configured (password auth enabled for lab)."

# =============================================================================
# SECTION 7: FIREWALL (UFW)
# =============================================================================
section "Firewall Configuration"

info "Configuring ufw..."
apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"

# Enable without prompting
ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

success "UFW configured."

# =============================================================================
# SECTION 8: /etc/hosts LAB PLACEHOLDERS
# =============================================================================
section "/etc/hosts Lab Placeholders"

# Append lab hostname placeholders — instructors uncomment and fill in IPs
cat >> /etc/hosts <<'HOSTSEOF'

# =============================================================================
# SCPS CyberLab — Lab Host Placeholders (uncomment and set IPs before use)
# =============================================================================
# 10.CLASS_ID.0.10    remnux.lab          remnux
# 10.CLASS_ID.0.20    dvwa.lab            dvwa
# 10.CLASS_ID.0.21    webgoat.lab         webgoat
# 10.CLASS_ID.0.22    juiceshop.lab       juiceshop
# 10.CLASS_ID.0.30    ubuntuserver.lab    ubuntuserver
# 10.CLASS_ID.0.40    ubuntuweb.lab       ubuntuweb
# 10.CLASS_ID.0.50    securityonion.lab   securityonion
# 10.CLASS_ID.0.60    splunk.lab          splunk
# 10.CLASS_ID.0.100   winserver.lab       winserver
# 10.CLASS_ID.0.101   windc.lab           windc
HOSTSEOF

success "/etc/hosts placeholders added."

# =============================================================================
# SECTION 9: SHELL CONFIGURATION & ALIASES
# =============================================================================
section "Shell Configuration"

# Global bash configuration for all users
cat > /etc/profile.d/lab-aliases.sh <<'PROFILE'
# SCPS CyberLab — global aliases and PS1

alias ll='ls -lF --color=auto'
alias la='ls -laF --color=auto'
alias lah='ls -lahF --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias ports='ss -tlnp'
alias myip='ip -4 addr show scope global | grep -oP "(?<=inet )\d+\.\d+\.\d+\.\d+"'
alias update='apt-get update && apt-get upgrade -y'
alias py='python3'
alias pip='pip3'

# Coloured prompt showing IP address
export PS1='\[\033[01;31m\][\[\033[01;33m\]\u\[\033[01;37m\]@\[\033[01;32m\]\h \[\033[01;36m\]$(ip -4 addr show scope global 2>/dev/null | grep -oP "(?<=inet )\d+\.\d+\.\d+\.\d+" | head -1)\[\033[01;31m\]]\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\]\n\$ '

# Go path
export GOPATH=/root/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin:/opt/tools
PROFILE

chmod 644 /etc/profile.d/lab-aliases.sh

# Copy the same to kali's .bashrc
cat >> /home/kali/.bashrc <<'BASHRC'

# SCPS CyberLab additions
source /etc/profile.d/lab-aliases.sh

export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin:/opt/tools
BASHRC

success "Shell configuration applied."

# =============================================================================
# SECTION 10: /opt/tools DIRECTORY
# =============================================================================
section "Tools Directory Setup"

mkdir -p "$TOOLS_DIR"
chmod 755 "$TOOLS_DIR"

cat > "$TOOLS_DIR/README.sh" <<'TOOLSREADME'
#!/usr/bin/env bash
# /opt/tools — Post-deploy tool setup script
# Run this script after VM deployment to pull any tools that require
# live internet access (e.g., git clones from private repos, license-gated tools).
#
# USAGE:
#   sudo /opt/tools/README.sh
#
# Tools pre-installed by build script:
#   - bloodhound, neo4j, crackmapexec, evil-winrm, responder
#   - impacket, ffuf, feroxbuster, gobuster, nuclei, chisel, ligolo-ng
#   - seclists, wordlists
#
# Post-deploy tools to add (internet required):
#   1. BloodHound.py (remote ingestor)
#        pip3 install bloodhound
#   2. Certipy (AD CS attacks)
#        pip3 install certipy-ad
#   3. NetExec (cme successor)
#        pip3 install netexec
#   4. Sliver C2 (if licensed)
#        curl https://sliver.sh/install | sudo bash
#   5. Custom wordlists
#        wget -P /usr/share/wordlists/ <URL>

echo "Review /opt/tools/README.sh for post-deploy tool instructions."
TOOLSREADME

chmod 755 "$TOOLS_DIR/README.sh"

# Pre-stage a tmux config
cat > /root/.tmux.conf <<'TMUXCONF'
# SCPS CyberLab tmux config
set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
set -g status-bg colour235
set -g status-fg colour136
set -g status-left-length 40
set -g status-left '#[fg=green]#H #[fg=yellow]#(ip -4 addr show scope global | grep -oP "(?<=inet )[\d.]+" | head -1) '
set -g status-right '#[fg=cyan]%Y-%m-%d %H:%M'
bind | split-window -h
bind - split-window -v
TMUXCONF

cp /root/.tmux.conf /home/kali/.tmux.conf
chown kali:kali /home/kali/.tmux.conf

success "/opt/tools directory created."

# =============================================================================
# SECTION 11: MOTD / LOGIN BANNER
# =============================================================================
section "MOTD Configuration"

cat > /etc/motd <<'MOTD'

  ██████╗ ███████╗██████╗     ████████╗███████╗ █████╗ ███╗   ███╗
  ██╔══██╗██╔════╝██╔══██╗    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
  ██████╔╝█████╗  ██║  ██║       ██║   █████╗  ███████║██╔████╔██║
  ██╔══██╗██╔══╝  ██║  ██║       ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
  ██║  ██║███████╗██████╔╝       ██║   ███████╗██║  ██║██║ ╚═╝ ██║
  ╚═╝  ╚═╝╚══════╝╚═════╝        ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝

  SCPS CyberLab — Kali Linux Attacker VM (kali-linux-2024.1)
  Role  : Red Team Attacker (Labs 1, 2, 4)
  Hint  : 'cat /root/.lab-credentials' for account passwords
  Tools : Run '/opt/tools/README.sh' for post-deploy setup

  Authorised lab use only. All activity is logged.

MOTD

success "MOTD configured."

# =============================================================================
# SECTION 12: NEO4J / BLOODHOUND PRE-CONFIGURATION
# =============================================================================
section "Neo4j / BloodHound Pre-configuration"

if systemctl list-unit-files | grep -q neo4j; then
    info "Setting Neo4j to start on boot (BloodHound dependency)..."
    systemctl enable neo4j 2>/dev/null || true
    # Neo4j default creds are changed on first BloodHound login
    info "Neo4j enabled. Students change default creds (neo4j/neo4j) on first run."
fi

success "BloodHound/Neo4j pre-configured."

# =============================================================================
# SECTION 13: DISABLE UNNECESSARY SERVICES
# =============================================================================
section "Disable Unnecessary Services"

SERVICES_TO_DISABLE=(
    bluetooth
    avahi-daemon
    cups
    cups-browsed
    ModemManager
    wpa_supplicant
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        systemctl disable "$svc" 2>/dev/null || true
        systemctl stop "$svc" 2>/dev/null || true
        info "Disabled service: $svc"
    fi
done

success "Unnecessary services disabled."

# =============================================================================
# SECTION 14: SYSPREP — GENERALISE THE IMAGE
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history for all users..."
# Root
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
# Kali user
cat /dev/null > /home/kali/.bash_history 2>/dev/null || true

info "Removing SSH host keys (regenerated on first boot)..."
rm -f /etc/ssh/ssh_host_*
# systemd-firstboot or sshd will regenerate on next start

# Ensure SSH host key regeneration on first boot via rc.local or systemd
if [[ ! -f /etc/systemd/system/ssh-keygen-firstboot.service ]]; then
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
fi

info "Clearing machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

info "Truncating system logs..."
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
journalctl --rotate 2>/dev/null || true
journalctl --vacuum-time=1s 2>/dev/null || true

info "Removing temporary files..."
apt-get clean
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

info "Zeroing free space (this may take several minutes)..."
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
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME          ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}kali user password :${RESET} $KALI_USER_PASS"
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
