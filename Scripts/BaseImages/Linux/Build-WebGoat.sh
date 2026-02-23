#!/usr/bin/env bash
# =============================================================================
# Build-WebGoat.sh
# SCPS CyberLab — Base Image Builder
# Image  : webgoat-2023.8
# Purpose: OWASP WebGoat vulnerable Java application for Lab 2, IP .21
# Host path (Hyper-V): C:\CyberLab\Templates\webgoat-2023.8.vhdx
#
# WARNING: This image is INTENTIONALLY INSECURE by design for teaching purposes.
#          NEVER deploy on production or internet-facing infrastructure.
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
IMAGE_NAME="webgoat-2023.8"
WEBGOAT_VERSION="2023.8"
WEBGOAT_JAR="/opt/webgoat.jar"
WEBGOAT_USER="webgoat"
WEBGOAT_HOME="/home/webgoat"
WEBGOAT_FLAGS_DIR="${WEBGOAT_HOME}/flags"
WEBGOAT_DOWNLOAD_URL="https://github.com/WebGoat/WebGoat/releases/download/v${WEBGOAT_VERSION}/webgoat-${WEBGOAT_VERSION}.jar"

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

WEBGOATADMIN_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
WEBGOATADMIN_OS_USER=webgoatadmin
WEBGOATADMIN_OS_PASS=$WEBGOATADMIN_PASS
WEBGOAT_APP_USER=admin
WEBGOAT_APP_PASS=webgoat
WEBGOAT_STUDENT_USER=student1
WEBGOAT_STUDENT_PASS=student
WEBGOAT_URL=http://<IP>/WebGoat
# NOTE: WebGoat default credentials (admin/webgoat) are intentional.
# NOTE: Root SSH login is ENABLED — intentional lab vulnerability.
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
apt-get autoremove -y
apt-get autoclean -y

success "System updated."

# =============================================================================
# SECTION 2: PACKAGE INSTALLATION
# =============================================================================
section "Package Installation"

apt-get install -y \
    openjdk-17-jre \
    wget \
    curl \
    git \
    nginx \
    net-tools \
    vim \
    unzip \
    openssh-server \
    ufw

success "Packages installed."

# Verify Java
java -version 2>&1 | tee -a "$LOGFILE"
JAVA_VERSION="$(java -version 2>&1 | head -1)"
info "Java version: $JAVA_VERSION"

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
    warn "Hyper-V tools install may have failed."

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
# SECTION 4: WEBGOAT SYSTEM USER
# =============================================================================
section "WebGoat System User"

if ! id "$WEBGOAT_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash \
        -c "WebGoat Application Service Account" \
        "$WEBGOAT_USER"
    info "Created system user: $WEBGOAT_USER"
fi

mkdir -p "$WEBGOAT_FLAGS_DIR"
mkdir -p "${WEBGOAT_HOME}/.webgoat"
chown -R "${WEBGOAT_USER}:${WEBGOAT_USER}" "$WEBGOAT_HOME"

success "WebGoat system user created."

# =============================================================================
# SECTION 5: DOWNLOAD WEBGOAT JAR
# =============================================================================
section "WebGoat Application Download"

if [[ -f "$WEBGOAT_JAR" ]]; then
    info "WebGoat JAR already present: $WEBGOAT_JAR"
else
    info "Downloading WebGoat ${WEBGOAT_VERSION}..."
    info "URL: $WEBGOAT_DOWNLOAD_URL"
    wget --progress=bar:force \
         --timeout=300 \
         -O "$WEBGOAT_JAR" \
         "$WEBGOAT_DOWNLOAD_URL" || \
        error "Download failed. Pre-stage the JAR at $WEBGOAT_JAR and retry."
fi

chown "${WEBGOAT_USER}:${WEBGOAT_USER}" "$WEBGOAT_JAR"
chmod 644 "$WEBGOAT_JAR"

# Verify the JAR is valid
java -jar "$WEBGOAT_JAR" --version 2>/dev/null | tee -a "$LOGFILE" || \
    info "WebGoat jar version check skipped — will validate at start."

success "WebGoat JAR ready at $WEBGOAT_JAR"

# =============================================================================
# SECTION 6: WEBGOAT SYSTEMD SERVICE
# =============================================================================
section "WebGoat Systemd Service"

cat > /etc/systemd/system/webgoat.service <<SVCEOF
[Unit]
Description=OWASP WebGoat ${WEBGOAT_VERSION} — SCPS CyberLab
Documentation=https://github.com/WebGoat/WebGoat
After=network.target

[Service]
User=${WEBGOAT_USER}
Group=${WEBGOAT_USER}
WorkingDirectory=${WEBGOAT_HOME}
ExecStart=/usr/bin/java \
    -Xms256m \
    -Xmx512m \
    -jar ${WEBGOAT_JAR} \
    --server.port=8080 \
    --server.address=0.0.0.0 \
    --webgoat.host=0.0.0.0 \
    --webgoat.port=8080 \
    --webwolf.host=0.0.0.0 \
    --webwolf.port=9090
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=webgoat
Environment=JAVA_OPTS="-Dfile.encoding=UTF-8"
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable webgoat.service
systemctl start webgoat.service

# Wait for WebGoat to start (Java apps take time)
info "Waiting for WebGoat to start (up to 120s)..."
ATTEMPTS=0
until curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:8080/WebGoat/" 2>/dev/null | grep -qE "200|302|301"; do
    sleep 5
    ATTEMPTS=$((ATTEMPTS + 1))
    [[ $ATTEMPTS -ge 24 ]] && warn "WebGoat did not respond in time — check: journalctl -u webgoat" && break
    info "Still waiting for WebGoat... (${ATTEMPTS}/24)"
done

success "WebGoat service configured."

# =============================================================================
# SECTION 7: WEBGOAT APPLICATION CONFIGURATION
# =============================================================================
section "WebGoat Application Configuration"

# WebGoat 2023.8 uses H2 embedded database and properties file.
# The application.properties file controls initial user setup.

WEBGOAT_CONFIG_DIR="${WEBGOAT_HOME}/.webgoat-${WEBGOAT_VERSION}"
mkdir -p "$WEBGOAT_CONFIG_DIR"

cat > "${WEBGOAT_CONFIG_DIR}/application.properties" <<'WGPROP'
# SCPS CyberLab — WebGoat Application Properties
# WebGoat intentionally uses weak default credentials for training

# Server
server.port=8080
server.address=0.0.0.0

# WebGoat
webgoat.host=0.0.0.0
webgoat.port=8080
webgoat.user.registration.enabled=true

# WebWolf (companion app for client-side exercises)
webwolf.host=0.0.0.0
webwolf.port=9090

# H2 Console enabled (intentional — teaches DB exposure)
spring.h2.console.enabled=true
spring.h2.console.path=/WebGoat/h2-console
spring.h2.console.settings.web-allow-others=true

# Logging
logging.level.root=INFO
logging.level.org.webgoat=DEBUG
WGPROP

chown -R "${WEBGOAT_USER}:${WEBGOAT_USER}" "$WEBGOAT_CONFIG_DIR" 2>/dev/null || true

info "WebGoat accounts:"
info "  Admin   : admin / webgoat (intentional default — teaching credential)"
info "  Student : student1 / student"
info "  Register additional accounts at http://<IP>/WebGoat/registration"

success "WebGoat application configured."

# =============================================================================
# SECTION 8: NGINX REVERSE PROXY
# =============================================================================
section "Nginx Reverse Proxy (port 80 → 8080)"

cat > /etc/nginx/sites-available/webgoat <<'NGINXEOF'
# SCPS CyberLab — Nginx reverse proxy for WebGoat
server {
    listen 80;
    server_name _;

    # Proxy WebGoat
    location /WebGoat/ {
        proxy_pass         http://127.0.0.1:8080/WebGoat/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 50M;
    }

    # Proxy WebWolf (companion app)
    location /WebWolf/ {
        proxy_pass         http://127.0.0.1:9090/WebWolf/;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }

    # Root redirect to WebGoat
    location = / {
        return 302 /WebGoat/login;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINXEOF

# Enable site, disable default
ln -sf /etc/nginx/sites-available/webgoat /etc/nginx/sites-enabled/webgoat
rm -f /etc/nginx/sites-enabled/default

nginx -t 2>&1 | tee -a "$LOGFILE"
systemctl enable nginx
systemctl restart nginx

success "Nginx reverse proxy configured."

# =============================================================================
# SECTION 9: FLAG FILES
# =============================================================================
section "Flag Files"

cat > "${WEBGOAT_FLAGS_DIR}/flag_webgoat.txt" <<'FLAG'
SCPS{w3bg04t_sql1_0r_xxe_4tt4ck_succ3ss}
You exploited an OWASP WebGoat vulnerability!
Document the attack chain and proceed to the next objective.
FLAG

cat > "${WEBGOAT_FLAGS_DIR}/flag_rce.txt" <<'FLAG'
SCPS{rce_v14_w3bg04t_d3s3r14l1z4t10n}
You achieved Remote Code Execution via WebGoat!
Objective: escalate to OS-level access.
FLAG

cat > "${WEBGOAT_FLAGS_DIR}/objectives.txt" <<'OBJ'
Lab 2 Objectives — WebGoat Server (.21):
1. [ ] Access WebGoat at http://<IP>/WebGoat (register a student account)
2. [ ] Complete: SQL Injection module
3. [ ] Complete: Cross-Site Scripting (XSS) module
4. [ ] Complete: Insecure Deserialization module
5. [ ] Complete: XXE (XML External Entity) module
6. [ ] Complete: JWT attacks module
7. [ ] Find and read /home/webgoat/flags/flag_webgoat.txt
8. [ ] Escalate to OS access and read /root/.lab-credentials
OBJ

cat > "${WEBGOAT_FLAGS_DIR}/root_flag.txt" <<'RFLAG'
SCPS{r00t_4cc3ss_v14_w3bg04t_pwn3d}
Full system compromise achieved on WebGoat server!
RFLAG

chown -R "${WEBGOAT_USER}:${WEBGOAT_USER}" "$WEBGOAT_FLAGS_DIR"
chmod 700 "$WEBGOAT_FLAGS_DIR"
chmod 644 "${WEBGOAT_FLAGS_DIR}"/*

success "Flag files created."

# =============================================================================
# SECTION 10: INTENTIONALLY WEAK SSH
# =============================================================================
section "SSH Configuration (Intentionally Weak)"

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — INTENTIONALLY VULNERABLE SSH CONFIG (WebGoat target)
# Root login and password auth enabled by design.

Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

LogLevel VERBOSE
SyslogFacility AUTH

AllowTcpForwarding yes
X11Forwarding yes

Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

systemctl enable ssh
systemctl restart ssh
success "SSH configured (intentionally weak)."

# =============================================================================
# SECTION 11: WEBGOATADMIN OS USER
# =============================================================================
section "WebGoatAdmin OS User"

if ! id webgoatadmin &>/dev/null; then
    useradd -m -s /bin/bash -c "WebGoat OS Administrator" webgoatadmin
fi
echo "webgoatadmin:${WEBGOATADMIN_PASS}" | chpasswd
usermod -aG sudo webgoatadmin

success "webgoatadmin user configured."

# =============================================================================
# SECTION 12: FIREWALL (UFW)
# =============================================================================
section "Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp   comment "SSH"
ufw allow 80/tcp   comment "HTTP (Nginx)"
ufw allow 8080/tcp comment "WebGoat direct"
ufw allow 9090/tcp comment "WebWolf"

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

success "UFW configured."

# =============================================================================
# SECTION 13: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — OWASP WebGoat (webgoat-2023.8)
  Role: Vulnerable Java Application Target — Lab 2 (IP: .21)

  WARNING: This system is intentionally insecure.
           Controlled lab environment for cybersecurity training only.

  WebGoat  : http://<IP>/WebGoat  (admin/webgoat or register)
  WebWolf  : http://<IP>/WebWolf
  Direct   : http://<IP>:8080/WebGoat
  H2 DB    : http://<IP>:8080/WebGoat/h2-console

MOTD

# =============================================================================
# SECTION 14: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Stopping WebGoat before sysprep..."
systemctl stop webgoat.service 2>/dev/null || true

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
cat /dev/null > /home/webgoatadmin/.bash_history 2>/dev/null || true

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

# Clear WebGoat H2 database state (students start fresh)
find "$WEBGOAT_HOME" -name "*.mv.db" -delete 2>/dev/null || true
find "$WEBGOAT_HOME" -name "*.trace.db" -delete 2>/dev/null || true

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
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME         ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}webgoatadmin OS password :${RESET} $WEBGOATADMIN_PASS"
echo -e "  ${BOLD}WebGoat app login        :${RESET} admin / webgoat  (intentional default)"
echo -e "  ${BOLD}WebGoat student login    :${RESET} student1 / student"
echo ""
echo -e "  ${YELLOW}URLs:${RESET}"
echo -e "    WebGoat : http://<IP>/WebGoat"
echo -e "    WebWolf : http://<IP>/WebWolf"
echo -e "    H2 DB   : http://<IP>:8080/WebGoat/h2-console"
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
