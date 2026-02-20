#!/usr/bin/env bash
# =============================================================================
# Build-SecurityOnion.sh
# SCPS CyberLab — Base Image Builder
# Image  : security-onion-2.4
# Purpose: Blue team SIEM/NSM platform, shared across all students in Labs 1, 3
# Host path (Hyper-V): C:\CyberLab\Templates\security-onion-2.4.vhdx
#
# PREREQUISITES:
#   - Security Onion 2.4 ISO must be installed via its official installer first.
#     The SO installer sets up the base OS (Ubuntu-based) and places so-setup
#     at /usr/sbin/so-setup.
#   - Two NICs required:
#       eth0  — Management interface (static IP, SSH access)
#       eth1  — Monitor/sniffing interface (promiscuous, no IP)
#
# HYPER-V NOTE:
#   The monitor NIC (eth1) requires Hyper-V Port Mirroring configured on the
#   virtual switch. In Hyper-V Manager: VM Settings → Network Adapter (eth1)
#   → Advanced Features → Port mirroring = Destination. The source VM(s) must
#   also be set to Port mirroring = Source on the same vSwitch.
#   Without this, Suricata and Zeek will see no traffic to analyse.
#
# Run this script AFTER the SO 2.4 ISO installation completes and you have
# booted into the installed OS for the first time.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="security-onion-2.4"

# Management interface static IP placeholder
# Replace CLASS_ID with the actual class subnet identifier before deployment
MGMT_INTERFACE="eth0"
MGMT_IP="10.CLASS_ID.0.50"
MGMT_NETMASK="255.255.255.0"
MGMT_GATEWAY="10.CLASS_ID.0.1"
MGMT_DNS="8.8.8.8"

# Monitor (sniffing) interface — no IP, promiscuous mode
MONITOR_INTERFACE="eth1"

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

# Verify Security Onion base installation
if [[ ! -f /etc/securityonion/securityonion.conf ]] && \
   [[ ! -d /opt/so ]]; then
    error "Security Onion base files not found. Run the SO 2.4 ISO installer first."
fi

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

SO_ADMIN_PASS="$(generate_password)"
SO_ANALYST_PASS="$(generate_password)"
BLUETEAM_PASS="$(generate_password)"
INSTRUCTOR_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
SO_ADMIN_USER=admin
SO_ADMIN_PASS=$SO_ADMIN_PASS
SO_ANALYST_USER=soanalyst
SO_ANALYST_PASS=$SO_ANALYST_PASS
BLUETEAM_USER=blueteam
BLUETEAM_PASS=$BLUETEAM_PASS
INSTRUCTOR_USER=instructor
INSTRUCTOR_PASS=$INSTRUCTOR_PASS
MGMT_IP=$MGMT_IP
MONITOR_IFACE=$MONITOR_INTERFACE
# NOTE: Replace CLASS_ID in MGMT_IP before deployment.
EOF

success "Credentials file initialised."

# =============================================================================
# SECTION 1: SYSTEM UPDATE
# =============================================================================
section "System Update"

export DEBIAN_FRONTEND=noninteractive

# Security Onion uses its own apt repos — update carefully
apt-get update -y 2>/dev/null || \
    warn "apt-get update had errors — SO may use custom mirrors, continuing."

apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>/dev/null || \
    warn "Some packages may not upgrade — SO locks some versions, continuing."

success "System update attempted."

# =============================================================================
# SECTION 2: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

# Security Onion is Ubuntu-based; standard Hyper-V tools apply
apt-get install -y \
    linux-tools-virtual \
    linux-cloud-tools-virtual 2>/dev/null || \
    apt-get install -y \
        linux-tools-generic \
        linux-cloud-tools-generic 2>/dev/null || \
    warn "Hyper-V tools install failed — may not match current kernel."

for mod in hv_vmbus hv_storvsc hv_blkvsc hv_netvsc hv_utils hv_balloon; do
    modprobe "$mod" 2>/dev/null || true
done

cat > /etc/modules-load.d/hyperv.conf <<'HVEOF'
hv_vmbus
hv_storvsc
hv_blkvsc
hv_netvsc
hv_utils
hv_balloon
HVEOF

success "Hyper-V integration configured."

# =============================================================================
# SECTION 3: NETWORK INTERFACE CONFIGURATION
# =============================================================================
section "Network Interface Configuration"

info "Configuring management interface ($MGMT_INTERFACE) with static IP placeholder..."

# Security Onion 2.4 uses netplan (Ubuntu base)
NETPLAN_FILE="/etc/netplan/01-lab-config.yaml"

# Backup existing netplan configs
for f in /etc/netplan/*.yaml; do
    [[ -f "$f" ]] && mv "$f" "${f}.bak.$(date +%s)" && info "Backed up: $f"
done

cat > "$NETPLAN_FILE" <<NETPLANEOF
# SCPS CyberLab — Security Onion Network Configuration
# Replace CLASS_ID with actual class identifier before deployment
network:
  version: 2
  renderer: networkd
  ethernets:
    ${MGMT_INTERFACE}:
      dhcp4: false
      addresses:
        - ${MGMT_IP}/24
      routes:
        - to: default
          via: ${MGMT_GATEWAY}
      nameservers:
        addresses: [${MGMT_DNS}, 8.8.4.4]
    ${MONITOR_INTERFACE}:
      dhcp4: false
      # No IP on monitor interface — promiscuous mode only
      # Hyper-V port mirroring must be configured on this vNIC
NETPLANEOF

chmod 600 "$NETPLAN_FILE"

# Enable promiscuous mode on monitor interface at boot
cat > /etc/systemd/system/promisc-monitor.service <<PROMEOF
[Unit]
Description=Set ${MONITOR_INTERFACE} to promiscuous mode for packet capture
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set ${MONITOR_INTERFACE} promisc on
ExecStart=/sbin/ip link set ${MONITOR_INTERFACE} up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PROMEOF

systemctl enable promisc-monitor.service

warn "Network config written to $NETPLAN_FILE — replace CLASS_ID before deployment."
warn "Apply with: netplan apply"

success "Network interfaces configured."

# =============================================================================
# SECTION 4: SECURITY ONION SETUP (so-setup AUTOMATION)
# =============================================================================
section "Security Onion Setup"

# so-setup is the official Security Onion 2.x setup tool.
# It is interactive by design; we automate it using an answer file.
# The answer file approach works with so-setup --config-file in SO 2.4.

info "Checking for so-setup..."

if command -v so-setup &>/dev/null; then
    SO_ANSWER_FILE="/tmp/so-setup-answers.conf"

    cat > "$SO_ANSWER_FILE" <<SOANSEOF
# Security Onion 2.4 automated setup answer file
# Generated by SCPS CyberLab Build-SecurityOnion.sh

# Deployment type: standalone (single-node SIEM+NSM)
SETUP_TYPE=STANDALONE

# Management interface
MHOST=${MGMT_IP}
MGMT_INTERFACE=${MGMT_INTERFACE}
SNIFF_INTERFACE=${MONITOR_INTERFACE}

# Hostname
HOSTNAME=securityonion

# Admin account
ADMIN_USERNAME=admin
ADMIN_PASSWORD=${SO_ADMIN_PASS}
ADMIN_EMAIL=admin@scps.lab

# Services to enable
SERVICES_ENABLED=elastic,kibana,suricata,zeek,stenographer

# Suricata ruleset
SURICATA_RULESET=ETOPEN

# Zeek scripts: enable all standard
ZEEK_SCRIPTS=all

# Storage
ELASTIC_DATA_DIR=/nsm/elasticsearch
PCAP_DIR=/nsm/pcap

# NTP
NTP_SERVER=pool.ntp.org
SOANSEOF

    info "Running so-setup with answer file (this may take 15-30 minutes)..."
    so-setup --config-file "$SO_ANSWER_FILE" --yes 2>&1 | tee -a "$LOGFILE" || \
        warn "so-setup returned non-zero. Review $LOGFILE for details."

    rm -f "$SO_ANSWER_FILE"
else
    warn "so-setup not found — Security Onion may not be fully installed."
    warn "Manually run: so-setup after installation completes."
    warn "Continuing with post-install configuration steps..."
fi

success "Security Onion setup attempted."

# =============================================================================
# SECTION 5: ELASTIC HEAP SIZE TUNING
# =============================================================================
section "Elasticsearch Heap Size Tuning"

TOTAL_RAM_KB="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
# Elasticsearch recommendation: 50% of RAM, max 31GB
HEAP_MB=$((TOTAL_RAM_MB / 2))
if [[ $HEAP_MB -gt 31744 ]]; then
    HEAP_MB=31744
fi
if [[ $HEAP_MB -lt 512 ]]; then
    HEAP_MB=512
fi
HEAP_GB=$((HEAP_MB / 1024))
[[ $HEAP_GB -lt 1 ]] && HEAP_GB=1

info "Total RAM: ${TOTAL_RAM_MB}MB — setting Elasticsearch heap to ${HEAP_GB}g"

ES_JVM_OPTS="/etc/elasticsearch/jvm.options.d/heap.options"
if [[ -d /etc/elasticsearch/jvm.options.d ]]; then
    cat > "$ES_JVM_OPTS" <<JVMEOF
# SCPS CyberLab — Elasticsearch heap sizing (50% of VM RAM)
-Xms${HEAP_GB}g
-Xmx${HEAP_GB}g
JVMEOF
    success "Elasticsearch heap set to ${HEAP_GB}g."
elif [[ -d /opt/so/saltstack ]]; then
    # Security Onion manages ES via Salt
    info "Security Onion manages Elasticsearch via Salt; updating pillar..."
    SO_PILLAR="/opt/so/saltstack/local/pillar/minions/securityonion_standalone.sls"
    if [[ -f "$SO_PILLAR" ]]; then
        cat >> "$SO_PILLAR" <<PILLAREOF

# Elasticsearch heap override
elasticsearch:
  jvm:
    xms: ${HEAP_GB}g
    xmx: ${HEAP_GB}g
PILLAREOF
    fi
else
    warn "Elasticsearch config directory not found — heap size must be set manually."
fi

# =============================================================================
# SECTION 6: SURICATA RULES — ET OPEN
# =============================================================================
section "Suricata Rules — Emerging Threats Open"

if command -v suricata-update &>/dev/null; then
    info "Updating Suricata rules with suricata-update..."
    suricata-update --no-test 2>&1 | tee -a "$LOGFILE" || \
        warn "suricata-update failed — may require internet access at deployment."
    suricata-update enable-source et/open 2>/dev/null || true
    suricata-update 2>&1 | tee -a "$LOGFILE" || true
else
    warn "suricata-update not found — rules must be updated post-deployment."
fi

# Restart Suricata if running
systemctl restart suricata 2>/dev/null || \
    so-suricata-restart 2>/dev/null || \
    true

success "Suricata rules configured."

# =============================================================================
# SECTION 7: ZEEK CONFIGURATION
# =============================================================================
section "Zeek Configuration"

ZEEK_LOCAL="/opt/zeek/share/zeek/site/local.zeek"
if [[ -f "$ZEEK_LOCAL" ]]; then
    # Enable additional Zeek scripts
    cat >> "$ZEEK_LOCAL" <<'ZEEKEOF'

# SCPS CyberLab — Additional Zeek scripts
@load misc/loaded-scripts
@load tuning/defaults
@load frameworks/software/vulnerable
@load frameworks/software/version-changes
@load frameworks/notice/community-id
@load policy/protocols/conn/vlan-logging
@load policy/protocols/conn/mac-logging
@load policy/frameworks/notice/do-notice-policy
ZEEKEOF

    # Redeploy Zeek config
    zeekctl deploy 2>/dev/null || \
        so-zeek-restart 2>/dev/null || \
        true
    success "Zeek scripts configured."
else
    warn "Zeek local.zeek not found at expected path — configure manually."
fi

# =============================================================================
# SECTION 8: ADDITIONAL ANALYST ACCOUNTS
# =============================================================================
section "Analyst Account Creation"

# OS-level accounts
for user_entry in "soanalyst:${SO_ANALYST_PASS}" \
                  "blueteam:${BLUETEAM_PASS}" \
                  "instructor:${INSTRUCTOR_PASS}"; do
    uname="${user_entry%%:*}"
    upass="${user_entry##*:}"

    if ! id "$uname" &>/dev/null; then
        useradd -m -s /bin/bash -c "SOC Analyst" "$uname"
        info "Created OS user: $uname"
    fi
    echo "${uname}:${upass}" | chpasswd
    usermod -aG sudo "$uname"
done

# Security Onion web/API accounts (added via so-user if available)
if command -v so-user &>/dev/null; then
    info "Creating Security Onion web accounts..."

    so-user add --user soanalyst@scps.lab --password "$SO_ANALYST_PASS" \
        --role analyst 2>/dev/null || \
        warn "so-user failed for soanalyst — add manually via so-user after deployment."

    so-user add --user blueteam@scps.lab --password "$BLUETEAM_PASS" \
        --role analyst 2>/dev/null || \
        warn "so-user failed for blueteam — add manually after deployment."

    so-user add --user instructor@scps.lab --password "$INSTRUCTOR_PASS" \
        --role admin 2>/dev/null || \
        warn "so-user failed for instructor — add manually after deployment."
else
    warn "so-user not found. Web accounts must be created post-deployment."
    warn "Command: so-user add --user <email> --password <pass> --role [analyst|admin]"
fi

success "Analyst accounts configured."

# =============================================================================
# SECTION 9: KIBANA DEFAULT DASHBOARD
# =============================================================================
section "Kibana SOC Dashboard Configuration"

# The SOC dashboard in Security Onion Kibana is managed via so-dashboards.
# Configure it to load on default login.

if command -v so-dashboards &>/dev/null; then
    info "Loading Security Onion dashboards..."
    so-dashboards 2>/dev/null || \
        warn "so-dashboards failed — run post-deployment."
fi

# Set Kibana default space/index pattern if Kibana API is available
KIBANA_PORT=5601
if curl -s "http://localhost:${KIBANA_PORT}/api/status" -o /dev/null 2>/dev/null; then
    info "Setting Kibana default index pattern..."
    curl -s -X POST "http://localhost:${KIBANA_PORT}/api/saved_objects/index-pattern/so-*" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{"attributes":{"title":"so-*","timeFieldName":"@timestamp"}}' \
        2>/dev/null || warn "Kibana index pattern API call failed — set manually."
else
    warn "Kibana not reachable on port $KIBANA_PORT — dashboard config skipped."
    warn "Configure after deployment: so-kibana-start && so-dashboards"
fi

success "Kibana dashboard configuration attempted."

# =============================================================================
# SECTION 10: SERVICES CONFIGURATION
# =============================================================================
section "Security Onion Services"

# Enable SO services via systemctl or so-* wrappers
SO_SERVICES=(
    so-elastic
    so-kibana
    so-suricata
    so-zeek
    so-steno
    so-logstash
    so-redis
)

for svc in "${SO_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        systemctl enable "$svc" 2>/dev/null || true
        systemctl start  "$svc" 2>/dev/null || \
            warn "Could not start $svc — may start via so-start post-boot."
        success "Enabled service: $svc"
    else
        warn "Service not found: $svc (will be available after full SO setup)"
    fi
done

# Alternate: use so-start if available
if command -v so-start &>/dev/null; then
    info "Running so-start to enable all SO services..."
    so-start 2>/dev/null || warn "so-start returned non-zero — check logs."
fi

success "Security Onion services configured."

# =============================================================================
# SECTION 11: SSH CONFIGURATION
# =============================================================================
section "SSH Configuration"

# SO management access — key-based preferred, password allowed for lab access
cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — Security Onion SSH Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

LoginGraceTime 30s
PermitRootLogin no
StrictModes yes
MaxAuthTries 4
MaxSessions 10

PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

AllowTcpForwarding no
X11Forwarding no

SyslogFacility AUTH
LogLevel INFO

ClientAliveInterval 300
ClientAliveCountMax 2

Subsystem sftp /usr/lib/openssh/sftp-server

Banner /etc/ssh/sshd-banner
SSHEOF

cat > /etc/ssh/sshd-banner <<'BANNER'
*******************************************************************************
*        SCPS CyberLab — Security Onion 2.4 SIEM/NSM Platform               *
*        Authorised access only. All activity is monitored and logged.        *
*******************************************************************************
BANNER

systemctl restart ssh 2>/dev/null || true
success "SSH configured."

# =============================================================================
# SECTION 12: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<MOTDEOF

  SCPS CyberLab — Security Onion 2.4
  Role    : Blue Team SIEM/NSM Platform (Labs 1, 3)
  Kibana  : https://${MGMT_IP}
  SSH     : ${MGMT_IP}:22
  Monitor : ${MONITOR_INTERFACE} (promiscuous — Hyper-V port mirror required)

  Accounts:
    admin       — SO admin
    soanalyst   — SO analyst
    blueteam    — SO analyst
    instructor  — SO admin

  Credentials: sudo cat /root/.lab-credentials

MOTDEOF

# =============================================================================
# SECTION 13: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
for u in soanalyst blueteam instructor; do
    [[ -f "/home/${u}/.bash_history" ]] && cat /dev/null > "/home/${u}/.bash_history"
done

# NOTE: Per requirements — do NOT remove SSH host keys for Security Onion.
# It is a shared VM; key stability is needed so students' known_hosts stay valid.
warn "SSH host keys preserved (shared VM — stability requirement)."

info "Clearing machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

info "Truncating general logs (preserving SO NSM logs)..."
# Only clear OS logs, not SO sensor/NSM logs
find /var/log -maxdepth 1 -type f -exec truncate -s 0 {} \; 2>/dev/null || true
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
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME          ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}SO admin password       :${RESET} $SO_ADMIN_PASS"
echo -e "  ${BOLD}soanalyst password      :${RESET} $SO_ANALYST_PASS"
echo -e "  ${BOLD}blueteam password       :${RESET} $BLUETEAM_PASS"
echo -e "  ${BOLD}instructor password     :${RESET} $INSTRUCTOR_PASS"
echo ""
echo -e "  ${YELLOW}Post-deployment required:${RESET}"
echo -e "    1. Replace CLASS_ID in $NETPLAN_FILE and run: netplan apply"
echo -e "    2. Configure Hyper-V port mirroring on $MONITOR_INTERFACE"
echo -e "    3. Run: so-setup or verify services: so-status"
echo -e "    4. Set Elasticsearch heap: so-elastic-config"
echo ""
echo -e "  ${YELLOW}Hyper-V port mirroring note:${RESET}"
echo -e "    VM Settings → Network Adapter ($MONITOR_INTERFACE)"
echo -e "    → Advanced Features → Port mirroring mode: Destination"
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
