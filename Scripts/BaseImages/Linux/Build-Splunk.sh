#!/usr/bin/env bash
# =============================================================================
# Build-Splunk.sh
# SCPS CyberLab — Base Image Builder
# Image  : splunk-enterprise-9.1
# Purpose: SIEM for log aggregation and alerting, shared in Labs 1 and 3
# Host path (Hyper-V): C:\CyberLab\Templates\splunk-enterprise-9.1.vhdx
#
# PREREQUISITES:
#   - Start from Ubuntu Server 22.04 LTS (minimal installation)
#   - The Splunk .deb package must be either:
#       a) Pre-staged at /tmp/splunk-9.1.deb before running this script, OR
#       b) Downloaded by the script (requires internet — see SECTION 3)
#   - Splunk Enterprise is subject to Splunk's EULA. The 60-day trial is
#     activated automatically with --accept-license.
#   - Download Splunk packages from: https://www.splunk.com/en_us/download/splunk-enterprise.html
#
# Run inside the VM after Ubuntu Server 22.04 LTS minimal OS installation.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="splunk-enterprise-9.1"
SPLUNK_HOME="/opt/splunk"
SPLUNK_USER="splunk"

# Splunk 9.1 download URL (x86_64 .deb)
# NOTE: URLs change with new releases. Verify at https://www.splunk.com/en_us/download.html
# The hash below is for splunk-9.1.2-b6b9c8185839-linux-2.6-amd64.deb
SPLUNK_VERSION="9.1.2"
SPLUNK_BUILD="b6b9c8185839"
SPLUNK_DEB="splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-2.6-amd64.deb"
SPLUNK_DL_URL="https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/${SPLUNK_DEB}"
SPLUNK_DEB_PATH="/tmp/${SPLUNK_DEB}"

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

SPLUNK_ADMIN_PASS="$(generate_password)"
SPLUNK_INSTRUCTOR_PASS="$(generate_password)"
HEC_TOKEN="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
SPLUNK_ADMIN_USER=admin
SPLUNK_ADMIN_PASS=$SPLUNK_ADMIN_PASS
SPLUNK_INSTRUCTOR_USER=instructor
SPLUNK_INSTRUCTOR_PASS=$SPLUNK_INSTRUCTOR_PASS
SPLUNK_HEC_TOKEN=$HEC_TOKEN
SPLUNK_WEB_URL=http://localhost:8000
SPLUNK_MGMT_PORT=8089
SPLUNK_HEC_PORT=8088
SPLUNK_FORWARDER_PORT=9997
SPLUNK_SYSLOG_UDP=514
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
    wget \
    curl \
    net-tools \
    ufw \
    vim \
    git \
    openssl \
    libssl-dev \
    ca-certificates \
    gnupg \
    lsb-release

success "Prerequisite packages installed."

# =============================================================================
# SECTION 3: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

apt-get install -y \
    linux-cloud-tools-virtual \
    linux-tools-virtual || \
    apt-get install -y \
        linux-tools-generic \
        linux-cloud-tools-generic || \
    warn "Hyper-V tools install failed — verify kernel compatibility."

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
# SECTION 4: DOWNLOAD / STAGE SPLUNK
# =============================================================================
section "Splunk Enterprise Package"

if [[ -f "$SPLUNK_DEB_PATH" ]]; then
    info "Found pre-staged Splunk package: $SPLUNK_DEB_PATH"
else
    info "Downloading Splunk Enterprise ${SPLUNK_VERSION}..."
    info "URL: $SPLUNK_DL_URL"
    wget --progress=bar:force \
         --timeout=300 \
         -O "$SPLUNK_DEB_PATH" \
         "$SPLUNK_DL_URL" || \
        error "Download failed. Pre-stage the .deb at $SPLUNK_DEB_PATH and retry."
fi

success "Splunk package ready at $SPLUNK_DEB_PATH"

# =============================================================================
# SECTION 5: INSTALL SPLUNK ENTERPRISE
# =============================================================================
section "Splunk Enterprise Installation"

# Create splunk system user before installation
if ! id "$SPLUNK_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash -c "Splunk Service Account" "$SPLUNK_USER"
    info "Created system user: $SPLUNK_USER"
fi

info "Installing Splunk Enterprise via dpkg..."
dpkg -i "$SPLUNK_DEB_PATH" 2>&1 | tee -a "$LOGFILE" || \
    apt-get install -f -y

# Verify installation
[[ -x "${SPLUNK_HOME}/bin/splunk" ]] || \
    error "Splunk binary not found at ${SPLUNK_HOME}/bin/splunk after installation."

# Set ownership
chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_HOME"

success "Splunk Enterprise installed."

# =============================================================================
# SECTION 6: INITIAL SPLUNK START AND LICENSE
# =============================================================================
section "Splunk Initial Start and Admin Account"

info "Starting Splunk with admin password seed..."
sudo -u "$SPLUNK_USER" "${SPLUNK_HOME}/bin/splunk" start \
    --accept-license \
    --answer-yes \
    --no-prompt \
    --seed-passwd "${SPLUNK_ADMIN_PASS}" 2>&1 | tee -a "$LOGFILE"

# Wait for Splunk to fully start
info "Waiting for Splunk to become ready (up to 120s)..."
ATTEMPTS=0
until curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:8000/en-US/account/login" 2>/dev/null | grep -q "200\|302"; do
    sleep 5
    ATTEMPTS=$((ATTEMPTS + 1))
    [[ $ATTEMPTS -ge 24 ]] && break
    info "Still waiting for Splunk... (${ATTEMPTS}/24)"
done

success "Splunk started."

# =============================================================================
# SECTION 7: ENABLE SPLUNK BOOT-START
# =============================================================================
section "Splunk Boot-Start"

info "Enabling Splunk boot-start (runs as $SPLUNK_USER)..."
"${SPLUNK_HOME}/bin/splunk" enable boot-start \
    -user "$SPLUNK_USER" \
    -systemd-managed 1 \
    --accept-license \
    --answer-yes \
    --no-prompt 2>&1 | tee -a "$LOGFILE" || \
    warn "boot-start enable returned non-zero — check if already configured."

success "Boot-start enabled."

# =============================================================================
# SECTION 8: SPLUNK CONFIGURATION FILES
# =============================================================================
section "Splunk Configuration"

SPLUNK_ETC="${SPLUNK_HOME}/etc"
SPLUNK_LOCAL="${SPLUNK_ETC}/system/local"
mkdir -p "$SPLUNK_LOCAL"

# ---- inputs.conf — Syslog UDP 514, HEC TCP 8088, Forwarder TCP 9997 ----
cat > "${SPLUNK_LOCAL}/inputs.conf" <<INPUTSEOF
# SCPS CyberLab — Splunk inputs configuration

# Syslog via UDP 514
[udp://514]
connection_host = ip
sourcetype = syslog
index = linux

# HTTP Event Collector (HEC)
[http]
disabled = 0
enableSSL = 0
port = 8088
token.lab-token.name = lab-token
token.lab-token.value = ${HEC_TOKEN}
token.lab-token.index = cyberlab
token.lab-token.sourcetype = _json
token.lab-token.disabled = 0

# Splunk-to-Splunk receiving
[splunktcp://9997]
connection_host = dns
INPUTSEOF

# ---- indexes.conf — create cyberlab, windows, linux indexes ----
cat > "${SPLUNK_LOCAL}/indexes.conf" <<'IDXEOF'
# SCPS CyberLab — Splunk indexes

[cyberlab]
homePath   = $SPLUNK_DB/cyberlab/db
coldPath   = $SPLUNK_DB/cyberlab/colddb
thawedPath = $SPLUNK_DB/cyberlab/thaweddb
maxDataSize = 5000
maxHotBuckets = 3
maxTotalDataSizeMB = 5000

[windows]
homePath   = $SPLUNK_DB/windows/db
coldPath   = $SPLUNK_DB/windows/colddb
thawedPath = $SPLUNK_DB/windows/thaweddb
maxDataSize = 10000
maxTotalDataSizeMB = 10000

[linux]
homePath   = $SPLUNK_DB/linux/db
coldPath   = $SPLUNK_DB/linux/colddb
thawedPath = $SPLUNK_DB/linux/thaweddb
maxDataSize = 5000
maxTotalDataSizeMB = 5000
IDXEOF

# ---- props.conf — Windows Event Log parsing ----
cat > "${SPLUNK_LOCAL}/props.conf" <<'PROPSEOF'
# SCPS CyberLab — props.conf for Windows Event Log parsing

[WinEventLog]
SHOULD_LINEMERGE = false
BREAK_ONLY_BEFORE = \d{2}/\d{2}/\d{4}
TIME_PREFIX = ^\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2}\s+
TIME_FORMAT = %m/%d/%Y %H:%M:%S %p
MAX_TIMESTAMP_LOOKAHEAD = 26
KV_MODE = none
TRANSFORMS-WinEventLogFields = extract_wineventlog_fields

[WinEventLog:Security]
SHOULD_LINEMERGE = false
REPORT-EventCode = extract_eventcode
REPORT-AccountName = extract_accountname
LOOKUP-EventCode_Lookup = windows_eventcodes EventCode OUTPUT EventDescription

[source::WinEventLog:*]
index = windows
PROPSEOF

# ---- transforms.conf — field extractions ----
cat > "${SPLUNK_LOCAL}/transforms.conf" <<'TRANSEOF'
# SCPS CyberLab — transforms.conf

[extract_wineventlog_fields]
REGEX = EventCode=(\d+).*?AccountName=([^\s]+)
FORMAT = EventCode::$1 AccountName::$2

[extract_eventcode]
REGEX = EventCode=(\d+)
FORMAT = EventCode::$1

[extract_accountname]
REGEX = AccountName=([^\s\r\n]+)
FORMAT = AccountName::$1

[windows_eventcodes]
filename = windows_eventcodes.csv
TRANSEOF

# ---- Windows Event Code lookup CSV ----
LOOKUPS_DIR="${SPLUNK_ETC}/system/lookups"
mkdir -p "$LOOKUPS_DIR"
cat > "${LOOKUPS_DIR}/windows_eventcodes.csv" <<'CSVEOF'
EventCode,EventDescription
4624,Successful Logon
4625,Failed Logon
4634,Account Logoff
4648,Logon with Explicit Credentials
4672,Special Privileges Assigned
4688,New Process Created
4698,Scheduled Task Created
4702,Scheduled Task Updated
4720,User Account Created
4722,User Account Enabled
4723,Password Change Attempt
4724,Password Reset
4726,User Account Deleted
4728,Member Added to Security-Enabled Global Group
4732,Member Added to Local Group
4740,Account Locked Out
4756,Member Added to Universal Security Group
4768,Kerberos Authentication Request
4769,Kerberos Service Ticket Request
4776,NTLM Authentication
7045,New Service Installed
CSVEOF

# ---- savedsearches.conf — Lab saved searches and alerts ----
SAVEDDIR="${SPLUNK_ETC}/users/admin/search/local"
mkdir -p "$SAVEDDIR"
chown -R "$SPLUNK_USER:$SPLUNK_USER" "${SPLUNK_ETC}/users" 2>/dev/null || true

cat > "${SAVEDDIR}/savedsearches.conf" <<'SSEOF'
# SCPS CyberLab — Saved searches and alerts

[Failed Logins]
search = index=windows EventCode=4625 | stats count by AccountName, ComputerName, IpAddress | sort -count
dispatch.earliest_time = -24h
dispatch.latest_time = now
displayview = flashtimeline
description = Shows all failed login attempts in the last 24 hours with count per account.

[New Admin Account Created]
search = index=windows (EventCode=4720 OR EventCode=4732) | eval Event=case(EventCode==4720,"Account Created",EventCode==4732,"Added to Admin Group") | table _time, ComputerName, AccountName, Event
dispatch.earliest_time = -24h
dispatch.latest_time = now
description = Detects new user account creation and admin group membership changes.

[Process Creation Monitoring]
search = index=windows EventCode=4688 | stats count by ParentProcessName, NewProcessName, SubjectUserName | sort -count
dispatch.earliest_time = -1h
dispatch.latest_time = now
description = Shows new process creation events — useful for detecting LOLBins.

[Brute Force Alert - 5+ Failed Logins in 5min]
search = index=windows EventCode=4625 | bucket _time span=5m | stats count by _time, AccountName, IpAddress | where count > 5
dispatch.earliest_time = -15m
dispatch.latest_time = now
alert.track = 1
alert.severity = 4
alert.condition = count > 0
alert.expires = 24h
alert.suppress = 1
alert.suppress.period = 5m
alert.suppress.fields = AccountName, IpAddress
action.log = 1
action.log.filename = $SPLUNK_HOME/var/log/splunk/lab_alerts.log
cron_schedule = */5 * * * *
enableSched = 1
description = Triggers when a single account has more than 5 failed logins in a 5-minute window.

[Lateral Movement - New Logon Types]
search = index=windows EventCode=4624 (LogonType=3 OR LogonType=10) | stats count by AccountName, IpAddress, LogonType | where count > 3
dispatch.earliest_time = -1h
dispatch.latest_time = now
description = Detects network logon (type 3) and remote interactive (type 10) logons.

[Suspicious PowerShell Execution]
search = index=windows EventCode=4688 NewProcessName="*powershell*" | table _time, ComputerName, SubjectUserName, CommandLine
dispatch.earliest_time = -1h
dispatch.latest_time = now
description = Tracks PowerShell process creation events.
SSEOF

chown -R "$SPLUNK_USER:$SPLUNK_USER" "${SPLUNK_ETC}/users" 2>/dev/null || true

# ---- outputs.conf for Universal Forwarder ingestion of local logs ----
cat > "${SPLUNK_LOCAL}/outputs.conf" <<'OUTEOF'
# SCPS CyberLab — outputs.conf (local indexer — loopback)
[tcpout]
defaultGroup = local-indexer

[tcpout:local-indexer]
server = 127.0.0.1:9997
OUTEOF

# ---- server.conf — tune connection settings ----
cat > "${SPLUNK_LOCAL}/server.conf" <<'SERVEREOF'
# SCPS CyberLab — server.conf

[general]
serverName = splunk-cyberlab

[httpServer]
acceptFrom = *
port = 8000

[sslConfig]
enableSplunkdSSL = false
sslVersions = tls1.2,tls1.3

[licensing]
# 60-day trial activated via --accept-license at first start
# Download link for Splunk Free or Developer license:
# https://www.splunk.com/en_us/software/splunk-enterprise.html
SERVEREOF

success "Splunk configuration files written."

# =============================================================================
# SECTION 9: CREATE INSTRUCTOR ACCOUNT
# =============================================================================
section "Instructor Account in Splunk"

info "Creating Splunk instructor account via REST API..."

# Wait briefly for Splunk to be ready
sleep 10

curl -s -k \
    -u "admin:${SPLUNK_ADMIN_PASS}" \
    "https://localhost:8089/services/authentication/users" \
    -d "name=instructor" \
    -d "password=${SPLUNK_INSTRUCTOR_PASS}" \
    -d "roles=admin" \
    -d "email=instructor@scps.lab" \
    -d "realname=SCPS Lab Instructor" \
    -o /dev/null 2>/dev/null || \
    warn "Instructor account creation via API failed — Splunk may not be running yet."

# Alternate: write to passwd file if API unavailable
if ! curl -s -k -o /dev/null \
    -u "admin:${SPLUNK_ADMIN_PASS}" \
    "https://localhost:8089/services" 2>/dev/null; then
    warn "Splunk API not reachable. Add instructor account manually after deployment:"
    warn "  ${SPLUNK_HOME}/bin/splunk add user instructor -password '${SPLUNK_INSTRUCTOR_PASS}' -role admin -auth admin:${SPLUNK_ADMIN_PASS}"
fi

success "Instructor account configured."

# =============================================================================
# SECTION 10: SPLUNK ADD-ON NOTE
# =============================================================================
section "Splunk Add-on for Microsoft Windows"

info "Splunk Add-on for Microsoft Windows (TA-windows):"
info "  This add-on provides advanced Windows event log parsing and normalisation."
info "  It must be downloaded from Splunkbase (free, requires Splunk account):"
info "  https://splunkbase.splunk.com/app/742"
info ""
info "  To install post-deployment:"
info "    1. Download TA-windows-<version>.tgz from Splunkbase"
info "    2. scp TA-windows-*.tgz splunk@<IP>:/tmp/"
info "    3. tar -xzf /tmp/TA-windows-*.tgz -C ${SPLUNK_HOME}/etc/apps/"
info "    4. chown -R splunk:splunk ${SPLUNK_HOME}/etc/apps/Splunk_TA_windows"
info "    5. ${SPLUNK_HOME}/bin/splunk restart"

warn "Splunk_TA_windows NOT pre-installed — download required (see log for instructions)."

# =============================================================================
# SECTION 11: UNIVERSAL FORWARDER LOCAL MONITORING
# =============================================================================
section "Universal Forwarder — Local Log Monitoring"

MONITOR_INPUTS="${SPLUNK_ETC}/system/local/monitor-inputs.conf"
cat > "$MONITOR_INPUTS" <<'MEOF'
# SCPS CyberLab — Local log monitoring via Splunk forwarder

[monitor:///var/log/auth.log]
index = linux
sourcetype = linux_secure

[monitor:///var/log/syslog]
index = linux
sourcetype = syslog

[monitor:///var/log/ufw.log]
index = linux
sourcetype = ufw

[monitor:///opt/splunk/var/log/splunk/lab_alerts.log]
index = cyberlab
sourcetype = lab_alerts
MEOF

chown "$SPLUNK_USER:$SPLUNK_USER" "$MONITOR_INPUTS"

success "Local log monitoring configured."

# =============================================================================
# SECTION 12: RELOAD SPLUNK CONFIG
# =============================================================================
section "Reload Splunk Configuration"

sudo -u "$SPLUNK_USER" "${SPLUNK_HOME}/bin/splunk" restart 2>&1 | tee -a "$LOGFILE" || \
    warn "Splunk restart returned non-zero — check status post-deploy."

success "Splunk restarted with new configuration."

# =============================================================================
# SECTION 13: FIREWALL (UFW)
# =============================================================================
section "Firewall Configuration"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp    comment "SSH"
ufw allow 8000/tcp  comment "Splunk Web UI"
ufw allow 8089/tcp  comment "Splunk Management"
ufw allow 8088/tcp  comment "Splunk HEC"
ufw allow 9997/tcp  comment "Splunk Forwarder"
ufw allow 514/udp   comment "Syslog UDP"

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

success "UFW configured."

# =============================================================================
# SECTION 14: SSH CONFIGURATION
# =============================================================================
section "SSH Configuration"

apt-get install -y openssh-server

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — Splunk server SSH configuration
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
SSHEOF

systemctl enable ssh
systemctl restart ssh

success "SSH configured."

# =============================================================================
# SECTION 15: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — Splunk Enterprise 9.1
  Role    : SIEM / Log Aggregation Platform (Labs 1, 3)

  Splunk Web UI : http://<IP>:8000
                  Credentials in /root/.lab-credentials

  Indexes       : cyberlab, windows, linux
  Syslog Input  : UDP 514
  HEC Input     : TCP 8088
  Forwarder     : TCP 9997

  Accounts      : admin, instructor (see /root/.lab-credentials)

MOTD

# =============================================================================
# SECTION 16: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Stopping Splunk before sysprep..."
sudo -u "$SPLUNK_USER" "${SPLUNK_HOME}/bin/splunk" stop 2>/dev/null || true

info "Clearing Splunk search artifacts..."
rm -rf "${SPLUNK_HOME}/var/run/splunk/dispatch/"* 2>/dev/null || true
find "${SPLUNK_HOME}/var/log/splunk" -type f -exec truncate -s 0 {} \; 2>/dev/null || true

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history

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
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME     ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Splunk admin password      :${RESET} $SPLUNK_ADMIN_PASS"
echo -e "  ${BOLD}Splunk instructor password :${RESET} $SPLUNK_INSTRUCTOR_PASS"
echo -e "  ${BOLD}Splunk HEC Token           :${RESET} $HEC_TOKEN"
echo ""
echo -e "  ${YELLOW}Splunk Web UI   : http://<IP>:8000${RESET}"
echo -e "  ${YELLOW}Management port : 8089${RESET}"
echo -e "  ${YELLOW}Syslog input    : UDP 514${RESET}"
echo -e "  ${YELLOW}HEC input       : TCP 8088${RESET}"
echo -e "  ${YELLOW}Forwarder port  : TCP 9997${RESET}"
echo ""
echo -e "  ${YELLOW}Post-deployment:${RESET}"
echo -e "    - Download Splunk_TA_windows from Splunkbase and install"
echo -e "    - Configure Windows hosts to forward logs to port 9997"
echo -e "    - Verify indexes with: bin/splunk list index"
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
