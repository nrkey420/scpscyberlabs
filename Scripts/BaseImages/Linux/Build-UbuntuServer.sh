#!/usr/bin/env bash
# =============================================================================
# Build-UbuntuServer.sh
# SCPS CyberLab — Base Image Builder
# Image  : ubuntu-server-22.04
# Purpose: Generic hardened Ubuntu server, internal target in Lab 4
#          (Network Attack & Defense)
# Host path (Hyper-V): C:\CyberLab\Templates\ubuntu-server-22.04.vhdx
# Run inside the VM after Ubuntu Server 22.04 LTS installation.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="ubuntu-server-22.04"

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

SYSADMIN_PASS="$(generate_password)"
LABUSER_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
SYSADMIN_USER=sysadmin
SYSADMIN_PASS=$SYSADMIN_PASS
LABUSER_USER=labuser
LABUSER_PASS=$LABUSER_PASS
# NOTE: sysadmin requires SSH key auth. labuser allows password via lab config.
# Deploy sysadmin SSH public key post-deployment.
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
# SECTION 2: PACKAGE INSTALLATION
# =============================================================================
section "Package Installation"

apt-get install -y \
    openssh-server \
    ufw \
    fail2ban \
    net-tools \
    nmap \
    curl \
    wget \
    nginx \
    vim \
    git \
    htop \
    unzip \
    jq \
    dnsutils \
    iputils-ping \
    tcpdump \
    netcat-openbsd \
    auditd \
    libpam-pwquality \
    acl

success "Packages installed."

# =============================================================================
# SECTION 3: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

apt-get install -y \
    linux-cloud-tools-virtual \
    linux-tools-virtual || \
    apt-get install -y linux-tools-generic linux-cloud-tools-generic || \
    warn "Some Hyper-V tools may not be available."

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
# SECTION 4: USER ACCOUNTS
# =============================================================================
section "User Accounts"

# sysadmin — sudo user, SSH key auth only
if ! id sysadmin &>/dev/null; then
    useradd -m -s /bin/bash -c "System Administrator" sysadmin
fi
echo "sysadmin:${SYSADMIN_PASS}" | chpasswd
usermod -aG sudo sysadmin

# Prepare sysadmin SSH authorized_keys stub (key deployed post-template)
mkdir -p /home/sysadmin/.ssh
chmod 700 /home/sysadmin/.ssh
touch /home/sysadmin/.ssh/authorized_keys
chmod 600 /home/sysadmin/.ssh/authorized_keys
chown -R sysadmin:sysadmin /home/sysadmin/.ssh

cat > /home/sysadmin/.ssh/authorized_keys <<'AUTHEOF'
# SCPS CyberLab — Deploy the instructor/student public key here before use.
# Example: ssh-ed25519 AAAA... instructor@scps-lab
# This file is intentionally blank in the template.
AUTHEOF

# labuser — no sudo, password auth allowed via lab-access config
if ! id labuser &>/dev/null; then
    useradd -m -s /bin/bash -c "Lab User (limited)" labuser
fi
echo "labuser:${LABUSER_PASS}" | chpasswd
# Explicitly ensure labuser is NOT in sudo
gpasswd -d labuser sudo 2>/dev/null || true

success "User accounts configured."

# =============================================================================
# SECTION 5: SSH HARDENED CONFIGURATION
# =============================================================================
section "SSH Hardened Configuration"

# Main sshd_config — key-only, no root login
cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — Hardened SSH configuration (ubuntu-server-22.04)
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Hardened settings
LoginGraceTime 30s
PermitRootLogin no
StrictModes yes
MaxAuthTries 4
MaxSessions 10
MaxStartups 5:30:20

# Key auth only for default config
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Disable tunnelling on hardened path
AllowTcpForwarding no
X11Forwarding no
AllowAgentForwarding no

# Logging
SyslogFacility AUTH
LogLevel INFO

# Connection keepalive
ClientAliveInterval 300
ClientAliveCountMax 2

# SFTP
Subsystem sftp /usr/lib/openssh/sftp-server

# Include drop-in configs (lab-access.conf loaded here)
Include /etc/ssh/sshd_config.d/*.conf

# Banner
Banner /etc/ssh/sshd-banner
SSHEOF

cat > /etc/ssh/sshd-banner <<'BANNER'
*******************************************************************************
*        SCPS CyberLab — Internal Server (ubuntu-server-22.04)               *
*        Authorised access only. All sessions are monitored and logged.       *
*        Unauthorised access is a violation of policy and applicable law.     *
*******************************************************************************
BANNER

# Lab-access drop-in: allows password auth for labuser specifically
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/lab-access.conf <<'LABSSH'
# SCPS CyberLab — Lab teaching override
# Allows password authentication for 'labuser' only.
# This models a common misconfiguration students should audit.
# Toggle: set PasswordAuthentication no to harden.

Match User labuser
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    ForceCommand /bin/bash
LABSSH

chmod 644 /etc/ssh/sshd_config.d/lab-access.conf

systemctl enable ssh
systemctl restart ssh
success "SSH configured (hardened; labuser password via drop-in)."

# =============================================================================
# SECTION 6: FIREWALL (UFW)
# =============================================================================
section "Firewall Configuration"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# Allow SSH
ufw allow 22/tcp comment "SSH"

# Allow web services
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Rate-limit SSH to mitigate brute force
ufw limit 22/tcp comment "SSH rate limit"

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

success "UFW configured."

# =============================================================================
# SECTION 7: FAIL2BAN CONFIGURATION
# =============================================================================
section "Fail2ban Configuration"

cat > /etc/fail2ban/jail.local <<'F2BEOF'
# SCPS CyberLab — fail2ban configuration for ubuntu-server-22.04
[DEFAULT]
bantime  = 600
findtime = 300
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 4
bantime  = 900

[nginx-http-auth]
enabled  = true

[nginx-noscript]
enabled  = true
F2BEOF

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2ban configured and enabled."

# =============================================================================
# SECTION 8: NGINX DEPLOYMENT
# =============================================================================
section "Nginx — Internal Server Page"

cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Internal Server — Authorized Access Only</title>
    <style>
        body { background: #1a1a2e; color: #e0e0e0; font-family: monospace;
               display: flex; justify-content: center; align-items: center;
               height: 100vh; margin: 0; }
        .container { text-align: center; border: 1px solid #16213e;
                     padding: 40px; border-radius: 8px; background: #16213e; }
        h1 { color: #e94560; }
        .badge { background: #0f3460; padding: 5px 15px; border-radius: 4px;
                 display: inline-block; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Internal Server</h1>
        <p>Authorized Access Only</p>
        <div class="badge">SCPS CyberLab — Lab 4: Network Attack &amp; Defense</div>
        <p><small>Server: ubuntu-server-22.04 | Services: SSH, HTTP, HTTPS</small></p>
    </div>
</body>
</html>
HTML

# Harden Nginx
sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf || true

cat > /etc/nginx/conf.d/security-headers.conf <<'NGINXSEC'
# SCPS CyberLab — Nginx security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer" always;
NGINXSEC

systemctl enable nginx
systemctl restart nginx
success "Nginx deployed."

# =============================================================================
# SECTION 9: AUDITD CONFIGURATION
# =============================================================================
section "Auditd Configuration"

cat > /etc/audit/rules.d/lab.rules <<'AUDITEOF'
# SCPS CyberLab — Audit rules for Lab 4 (Network Attack & Defense)

# Log all authentication events
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group  -p wa -k identity

# Log sudo usage
-w /var/log/sudo.log -p wa -k sudo_log
-w /etc/sudoers -p wa -k sudoers

# Log SSH authentication
-w /var/log/auth.log -p wa -k authentication

# Log network connections
-a always,exit -F arch=b64 -S connect -k network_connect

# Log privilege escalation
-a always,exit -F arch=b64 -S setuid -k privilege_escalation
AUDITEOF

systemctl enable auditd
systemctl restart auditd 2>/dev/null || true
success "Auditd configured."

# =============================================================================
# SECTION 10: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  ┌─────────────────────────────────────────────────────────────┐
  │   SCPS CyberLab — Internal Server (ubuntu-server-22.04)    │
  │   Role: Internal Target — Lab 4: Network Attack & Defense   │
  │                                                             │
  │   This system is monitored. Authorised use only.           │
  │                                                             │
  │   Accounts:                                                 │
  │     sysadmin  — SSH key auth required                       │
  │     labuser   — password auth (limited shell)               │
  └─────────────────────────────────────────────────────────────┘

MOTD

# Disable the default Ubuntu dynamic MOTD components
chmod -x /etc/update-motd.d/* 2>/dev/null || true

success "MOTD configured."

# =============================================================================
# SECTION 11: KERNEL HARDENING
# =============================================================================
section "Kernel Hardening (sysctl)"

cat > /etc/sysctl.d/99-lab-hardening.conf <<'SYSCTL'
# SCPS CyberLab — Kernel hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_ra = 0
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
fs.suid_dumpable = 0
SYSCTL

sysctl --system > /dev/null
success "Kernel hardening applied."

# =============================================================================
# SECTION 12: DISABLE UNNECESSARY SERVICES
# =============================================================================
section "Disable Unnecessary Services"

DISABLE_SVCS=(
    bluetooth
    avahi-daemon
    cups
    cups-browsed
    ModemManager
    snapd
    lxd
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
# SECTION 13: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
cat /dev/null > /home/sysadmin/.bash_history 2>/dev/null || true
cat /dev/null > /home/labuser/.bash_history 2>/dev/null || true

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

info "Truncating logs..."
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
echo -e "  ${BOLD}sysadmin password :${RESET} $SYSADMIN_PASS"
echo -e "  ${BOLD}labuser password  :${RESET} $LABUSER_PASS"
echo ""
echo -e "  ${YELLOW}Post-deployment:${RESET}"
echo -e "    - Deploy SSH public key to /home/sysadmin/.ssh/authorized_keys"
echo -e "    - Update /etc/hosts with lab IP assignments"
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
