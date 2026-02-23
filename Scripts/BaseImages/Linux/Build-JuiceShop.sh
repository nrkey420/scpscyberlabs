#!/usr/bin/env bash
# =============================================================================
# Build-JuiceShop.sh
# SCPS CyberLab — Base Image Builder
# Image  : juice-shop-host
# Purpose: Host running OWASP Juice Shop in Docker for Lab 2, IP .22
# Host path (Hyper-V): C:\CyberLab\Templates\juice-shop-host.vhdx
#
# WARNING: Juice Shop is intentionally vulnerable. SSH password auth is
#          enabled for lab convenience. Do not deploy on production networks.
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
IMAGE_NAME="juice-shop-host"
DOCKERADMIN_USER="dockeradmin"
JUICE_SHOP_IMAGE="bkimminich/juice-shop:latest"
JUICE_SHOP_PORT="3000"
NGINX_PORT="80"
HINTS_DIR="/root/challenge-hints"

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

DOCKERADMIN_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
DOCKERADMIN_USER=$DOCKERADMIN_USER
DOCKERADMIN_PASS=$DOCKERADMIN_PASS
JUICE_SHOP_URL=http://<IP>
JUICE_SHOP_DIRECT_URL=http://<IP>:3000
# NOTE: Juice Shop default admin: admin@juice-sh.op / admin123 (intentional)
# NOTE: SSH password auth enabled for lab convenience.
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
# SECTION 2: PREREQUISITE PACKAGES
# =============================================================================
section "Prerequisite Packages"

apt-get install -y \
    curl \
    wget \
    git \
    nginx \
    net-tools \
    vim \
    ca-certificates \
    gnupg \
    lsb-release \
    openssh-server \
    ufw \
    apt-transport-https \
    software-properties-common

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
# SECTION 4: DOCKER CE INSTALLATION
# =============================================================================
section "Docker CE Installation"

# Remove any old Docker installations
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

info "Installing Docker CE via official script..."
if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
    sh /tmp/get-docker.sh 2>&1 | tee -a "$LOGFILE"
    rm -f /tmp/get-docker.sh
else
    # Fallback: manual Docker CE installation
    warn "get.docker.com download failed — using manual Docker CE install."

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Verify
docker --version | tee -a "$LOGFILE"
success "Docker CE installed."

# =============================================================================
# SECTION 5: DOCKERADMIN USER
# =============================================================================
section "dockeradmin User"

if ! id "$DOCKERADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash -c "Docker Administrator" "$DOCKERADMIN_USER"
fi
echo "${DOCKERADMIN_USER}:${DOCKERADMIN_PASS}" | chpasswd
usermod -aG sudo,docker "$DOCKERADMIN_USER"

success "dockeradmin user configured and added to docker group."

# =============================================================================
# SECTION 6: PULL JUICE SHOP IMAGE
# =============================================================================
section "Juice Shop Docker Image"

info "Pulling Juice Shop image: $JUICE_SHOP_IMAGE"
docker pull "$JUICE_SHOP_IMAGE" 2>&1 | tee -a "$LOGFILE" || \
    error "Failed to pull Juice Shop image. Ensure internet access is available."

docker image ls | grep -i juice | tee -a "$LOGFILE"
success "Juice Shop image pulled."

# =============================================================================
# SECTION 7: JUICE SHOP SYSTEMD SERVICE
# =============================================================================
section "Juice Shop Systemd Service"

# First, ensure any old container is cleaned up
docker rm -f juice-shop 2>/dev/null || true

cat > /etc/systemd/system/juiceshop.service <<SVCEOF
[Unit]
Description=OWASP Juice Shop — SCPS CyberLab
Documentation=https://owasp.org/www-project-juice-shop/
After=docker.service network.target
Requires=docker.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=10
ExecStartPre=-/usr/bin/docker rm -f juice-shop
ExecStart=/usr/bin/docker run \
    --name juice-shop \
    --rm \
    -p ${JUICE_SHOP_PORT}:3000 \
    --restart=no \
    ${JUICE_SHOP_IMAGE}
ExecStop=/usr/bin/docker stop juice-shop
StandardOutput=journal
StandardError=journal
SyslogIdentifier=juiceshop

[Install]
WantedBy=multi-user.target
SVCEOF

# Alternative: docker-compose approach for --restart always behavior
# Using a systemd service with ExecStart is more reliable with --restart no
# and letting systemd handle restarts via Restart=on-failure

systemctl daemon-reload
systemctl enable juiceshop.service
systemctl start juiceshop.service

# Wait for Juice Shop to start
info "Waiting for Juice Shop to start (up to 90s)..."
ATTEMPTS=0
until curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${JUICE_SHOP_PORT}/" 2>/dev/null | grep -q "200"; do
    sleep 5
    ATTEMPTS=$((ATTEMPTS + 1))
    [[ $ATTEMPTS -ge 18 ]] && warn "Juice Shop not responding — check: journalctl -u juiceshop" && break
    info "Still waiting... (${ATTEMPTS}/18)"
done

success "Juice Shop service configured."

# =============================================================================
# SECTION 8: NGINX REVERSE PROXY (port 80 → 3000)
# =============================================================================
section "Nginx Reverse Proxy"

cat > /etc/nginx/sites-available/juiceshop <<'NGINXEOF'
# SCPS CyberLab — Nginx reverse proxy for Juice Shop
server {
    listen 80;
    server_name _;

    # Proxy all traffic to Juice Shop on 3000
    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300s;
        client_max_body_size 50M;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/juiceshop /etc/nginx/sites-enabled/juiceshop
rm -f /etc/nginx/sites-enabled/default

nginx -t 2>&1 | tee -a "$LOGFILE"
systemctl enable nginx
systemctl restart nginx

success "Nginx reverse proxy configured (port 80 → ${JUICE_SHOP_PORT})."

# =============================================================================
# SECTION 9: CHALLENGE HINTS
# =============================================================================
section "Challenge Hints"

mkdir -p "$HINTS_DIR"
chmod 700 "$HINTS_DIR"

cat > "${HINTS_DIR}/juice-shop-hints.txt" <<'HINTS'
SCPS CyberLab — OWASP Juice Shop Challenge Hints
=================================================
Image: juice-shop-host | Lab 2 | IP: .22

Getting Started:
  - Browse to http://<IP> or http://<IP>:3000
  - Register a user account at /#/register
  - Access the scoreboard at /#/score-board
  - Challenge list: /#/score-board (all challenges visible)

Key Challenges for Lab 2:
  1. SQL Injection (Login Bypass)
     Hint: Try ' OR 1=1-- in the email field on /#/login

  2. Broken Authentication (Admin Account)
     Hint: The admin email is admin@juice-sh.op
     Find the password via SQL injection or reset flow.

  3. XSS (DOM/Reflected)
     Hint: Find input fields that reflect back unsanitised values.
     Try: <script>alert('XSS')</script>

  4. Broken Access Control
     Hint: Change the basket ID in API calls (e.g., /rest/basket/1 → /rest/basket/2)

  5. Security Misconfiguration
     Hint: Check /ftp/ for exposed files.

  6. Sensitive Data Exposure
     Hint: Look at the /rest/user/whoami endpoint after injection.

  7. JWT Forgery
     Hint: Decode the JWT token in localStorage. Try alg=none.

  8. SSRF
     Hint: The image upload endpoint may follow external URLs.

Useful Juice Shop URLs:
  Scoreboard  : http://<IP>/#/score-board
  Admin panel : http://<IP>/#/administration (requires admin access)
  API docs    : http://<IP>/api-docs
  FTP         : http://<IP>/ftp/
HINTS

cat > "${HINTS_DIR}/flag_juiceshop.txt" <<'FLAG'
SCPS{ju1c3_sh0p_4dm1n_4cc3ss_ach13v3d}
You compromised the OWASP Juice Shop admin account!
Next: achieve server-side code execution or read sensitive data.
FLAG

cat > "${HINTS_DIR}/flag_ssrf.txt" <<'FLAG'
SCPS{ssrf_4nd_b4ck3nd_4cc3ss_v14_ju1c3sh0p}
You exploited SSRF in Juice Shop!
This flag confirms successful server-side request forgery.
FLAG

success "Challenge hints created at $HINTS_DIR"

# =============================================================================
# SECTION 10: INTENTIONALLY WEAK SSH
# =============================================================================
section "SSH Configuration (Password Auth Enabled)"

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — Juice Shop host SSH configuration
# Password authentication enabled for lab convenience.

Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

LoginGraceTime 30s
PermitRootLogin no
StrictModes yes
MaxAuthTries 6
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
SSHEOF

systemctl enable ssh
systemctl restart ssh
success "SSH configured (password auth enabled)."

# =============================================================================
# SECTION 11: FIREWALL (UFW)
# =============================================================================
section "Firewall Configuration"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp           comment "SSH"
ufw allow 80/tcp           comment "HTTP (Nginx)"
ufw allow "${JUICE_SHOP_PORT}/tcp" comment "Juice Shop direct"

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

success "UFW configured."

# =============================================================================
# SECTION 12: DOCKER DAEMON CONFIGURATION
# =============================================================================
section "Docker Daemon Configuration"

# Configure Docker logging and resource limits
cat > /etc/docker/daemon.json <<'DOCKERCONF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
DOCKERCONF

systemctl reload docker 2>/dev/null || systemctl restart docker

success "Docker daemon configured."

# =============================================================================
# SECTION 13: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — OWASP Juice Shop Host (juice-shop-host)
  Role: Docker-hosted Vulnerable Web App Target — Lab 2 (IP: .22)

  Juice Shop  : http://<IP>        (via Nginx)
  Direct      : http://<IP>:3000   (direct to container)
  Scoreboard  : http://<IP>/#/score-board
  Admin       : admin@juice-sh.op / admin123 (find it via SQLi!)

  Docker commands:
    docker ps                          — check container status
    sudo systemctl restart juiceshop   — restart Juice Shop
    sudo docker logs juice-shop        — view app logs

MOTD

# =============================================================================
# SECTION 14: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Stopping Juice Shop container for sysprep..."
docker stop juice-shop 2>/dev/null || true
systemctl stop juiceshop.service 2>/dev/null || true

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
cat /dev/null > /home/${DOCKERADMIN_USER}/.bash_history 2>/dev/null || true

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

# Clear Docker build cache
docker system prune -f 2>/dev/null || true

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
echo -e "  ${BOLD}dockeradmin OS password :${RESET} $DOCKERADMIN_PASS"
echo -e "  ${BOLD}Juice Shop admin login  :${RESET} admin@juice-sh.op / admin123  (find via SQLi)"
echo ""
echo -e "  ${YELLOW}URLs:${RESET}"
echo -e "    Juice Shop  : http://<IP>        (Nginx)"
echo -e "    Direct      : http://<IP>:3000"
echo -e "    Scoreboard  : http://<IP>/#/score-board"
echo ""
echo -e "  ${YELLOW}Post-deployment:${RESET}"
echo -e "    - Juice Shop starts automatically via systemd (juiceshop.service)"
echo -e "    - Challenge hints at $HINTS_DIR"
echo -e "    - Docker container: docker ps"
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
