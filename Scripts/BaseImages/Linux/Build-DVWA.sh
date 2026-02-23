#!/usr/bin/env bash
# =============================================================================
# Build-DVWA.sh
# SCPS CyberLab — Base Image Builder
# Image  : dvwa-latest
# Purpose: Standalone DVWA server for Web App Pentest lab (Lab 2), IP .20
# Host path (Hyper-V): C:\CyberLab\Templates\dvwa-latest.vhdx
#
# WARNING: This image is INTENTIONALLY INSECURE by design for teaching purposes.
#          NEVER deploy on production or internet-facing infrastructure.
#          Root SSH login and MySQL external access are intentional vulnerabilities.
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
IMAGE_NAME="dvwa-latest"
WEB_ROOT="/var/www/html"
DVWA_DIR="${WEB_ROOT}/dvwa"

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

DVWAADMIN_PASS="$(generate_password)"
MYSQL_ROOT_PASS="$(generate_password)"
DVWA_DB_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
DVWAADMIN_USER=dvwaadmin
DVWAADMIN_PASS=$DVWAADMIN_PASS
MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS
DVWA_DB_USER=dvwa_user
DVWA_DB_PASS=$DVWA_DB_PASS
DVWA_DB_NAME=dvwa
DVWA_WEB_URL=http://<IP>/dvwa
# DVWA default login: admin / password
# NOTE: Root SSH login is ENABLED — intentional lab vulnerability.
# NOTE: MySQL is exposed on all interfaces — intentional lab vulnerability.
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
    apache2 \
    php8.1 \
    php8.1-mysql \
    php8.1-gd \
    php8.1-curl \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-zip \
    mysql-server \
    git \
    unzip \
    curl \
    wget \
    net-tools \
    vim \
    openssh-server

success "Packages installed."

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
    warn "Hyper-V tools install failed — verify kernel."

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
# SECTION 4: MYSQL CONFIGURATION
# =============================================================================
section "MySQL Configuration"

systemctl start mysql
systemctl enable mysql

info "Configuring MySQL root account and DVWA database..."
mysql -u root <<SQLEOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;

-- Create DVWA database
CREATE DATABASE IF NOT EXISTS dvwa;

-- Create DVWA user (local)
CREATE USER IF NOT EXISTS 'dvwa_user'@'localhost' IDENTIFIED BY '${DVWA_DB_PASS}';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa_user'@'localhost';

-- Intentional vulnerability: DVWA user accessible from any host
CREATE USER IF NOT EXISTS 'dvwa_user'@'%' IDENTIFIED BY '${DVWA_DB_PASS}';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa_user'@'%';

FLUSH PRIVILEGES;
SQLEOF

# Intentionally expose MySQL on all interfaces (teaching vulnerability)
info "Binding MySQL to 0.0.0.0 (intentional vulnerability — lab teaching)..."
sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' \
    /etc/mysql/mysql.conf.d/mysqld.cnf

systemctl restart mysql
success "MySQL configured (intentionally exposed on 0.0.0.0)."

# =============================================================================
# SECTION 5: APACHE CONFIGURATION
# =============================================================================
section "Apache Configuration"

# Enable required modules
a2enmod rewrite headers php8.1 2>/dev/null || true

# Set DocumentRoot and directory permissions
cat > /etc/apache2/sites-available/000-default.conf <<'VHOST'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    # Intentionally verbose error reporting
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
VHOST

# Intentionally insecure Apache settings (teaching)
cat > /etc/apache2/conf-available/insecure-lab.conf <<'INSEC'
# SCPS CyberLab — Intentionally insecure settings
ServerTokens Full
ServerSignature On
TraceEnable On
INSEC

a2enconf insecure-lab 2>/dev/null || true

systemctl enable apache2
systemctl restart apache2
success "Apache configured."

# =============================================================================
# SECTION 6: PHP CONFIGURATION
# =============================================================================
section "PHP Configuration (Intentionally Insecure)"

PHP_INI="/etc/php/8.1/apache2/php.ini"

# Settings required by DVWA + intentional vulnerabilities
sed -i 's/^allow_url_include\s*=.*/allow_url_include = On/' "$PHP_INI"
sed -i 's/^display_errors\s*=.*/display_errors = On/' "$PHP_INI"
sed -i 's/^display_startup_errors\s*=.*/display_startup_errors = On/' "$PHP_INI"
sed -i 's/^allow_url_fopen\s*=.*/allow_url_fopen = On/' "$PHP_INI"
sed -i 's/^expose_php\s*=.*/expose_php = On/' "$PHP_INI"

# Increase file upload size for file upload vuln exercises
sed -i 's/^upload_max_filesize\s*=.*/upload_max_filesize = 100M/' "$PHP_INI"
sed -i 's/^post_max_size\s*=.*/post_max_size = 100M/' "$PHP_INI"

success "PHP configured (intentionally insecure for DVWA)."

# =============================================================================
# SECTION 7: DEPLOY DVWA
# =============================================================================
section "DVWA Deployment"

if [[ -d "$DVWA_DIR/.git" ]]; then
    info "DVWA already cloned — pulling latest..."
    git -C "$DVWA_DIR" pull 2>/dev/null || true
else
    info "Cloning DVWA from GitHub..."
    git clone https://github.com/digininja/DVWA "$DVWA_DIR"
fi

# Configure DVWA
DVWA_CONFIG="${DVWA_DIR}/config/config.inc.php"
cp -f "${DVWA_DIR}/config/config.inc.php.dist" "$DVWA_CONFIG"

# Patch database settings
sed -i "s/\$_DVWA\[ 'db_server' \].*=.*/\$_DVWA[ 'db_server' ]   = '127.0.0.1';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_database' \].*=.*/\$_DVWA[ 'db_database' ] = 'dvwa';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_user' \].*=.*/\$_DVWA[ 'db_user' ]     = 'dvwa_user';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_password' \].*=.*/\$_DVWA[ 'db_password' ] = '${DVWA_DB_PASS}';/" "$DVWA_CONFIG"

# Security level: low (most vulnerable for training)
sed -i "s/\$_DVWA\[ 'default_security_level' \].*=.*/\$_DVWA[ 'default_security_level' ] = 'low';/" "$DVWA_CONFIG"

# Disable reCAPTCHA for lab
sed -i "s/\$_DVWA\[ 'recaptcha_public_key' \].*=.*/\$_DVWA[ 'recaptcha_public_key' ]  = '';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'recaptcha_private_key' \].*=.*/\$_DVWA[ 'recaptcha_private_key' ] = '';/" "$DVWA_CONFIG"

# Set permissions — uploads world-writable for file upload exploitation
chown -R www-data:www-data "$DVWA_DIR"
chmod -R 755 "$DVWA_DIR"
chmod 777 "${DVWA_DIR}/hackable/uploads/"
chmod 777 "${DVWA_DIR}/config/"

# Ensure DVWA external tmp dir exists
mkdir -p "${DVWA_DIR}/external/phpids/0.6/lib/IDS/tmp"
chmod 777 "${DVWA_DIR}/external/phpids/0.6/lib/IDS/tmp"
touch "${DVWA_DIR}/external/phpids/0.6/lib/IDS/tmp/phpids_log.txt"
chmod 666 "${DVWA_DIR}/external/phpids/0.6/lib/IDS/tmp/phpids_log.txt"

success "DVWA deployed."

# =============================================================================
# SECTION 8: FLAG FILES IN DVWA HACKABLE DIRECTORY
# =============================================================================
section "Flag Files"

# Hidden flags in hackable directory (accessible after exploitation)
cat > "${DVWA_DIR}/hackable/flag_rfi.txt" <<'FLAG'
SCPS{rfi_t0_rc3_v14_dvw4_upl04d}
You achieved Remote File Inclusion!
Objective: escalate to OS-level command execution.
FLAG

cat > "${DVWA_DIR}/hackable/uploads/.flag_upload.txt" <<'FLAG'
SCPS{f1l3_upl04d_byp4ss_3x3cut10n}
You uploaded a file to the server and executed it!
Objective: use the shell to read /root/flags/root_flag.txt
FLAG

# Root flags directory
mkdir -p /root/flags
chmod 700 /root/flags

cat > /root/flags/root_flag.txt <<'RFLAG'
SCPS{pr1v_3sc_dvw4_r00t_0wn3d}
You have achieved root access on the DVWA server!
Full compromise confirmed. Document your attack path.
RFLAG

cat > /root/flags/objectives.txt <<'OBJ'
Lab 2 Objectives — DVWA Server (.20):
1. [ ] Scan target with nmap to enumerate services
2. [ ] Access DVWA at http://<IP>/dvwa (login: admin/password)
3. [ ] Exploit SQL Injection to dump the users table
4. [ ] Exploit Command Injection to achieve RCE
5. [ ] Bypass file upload restrictions to upload a PHP shell
6. [ ] Access /hackable/uploads/ to execute your shell
7. [ ] Escalate privileges to root
8. [ ] Capture /root/flags/root_flag.txt
OBJ

chown -R www-data:www-data "${DVWA_DIR}/hackable/"
chmod 755 /root/flags
success "Flag files created."

# =============================================================================
# SECTION 9: ROOT INDEX PAGE — REDIRECT TO DVWA
# =============================================================================
section "Root Index Page"

cat > "${WEB_ROOT}/index.html" <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0;url=/dvwa/setup.php">
<title>SCPS CyberLab — DVWA</title>
</head>
<body>
<p>Redirecting to <a href="/dvwa/setup.php">DVWA Setup</a>...</p>
<p><a href="/dvwa/">Go to DVWA</a></p>
</body>
</html>
HTML

success "Root index configured."

# =============================================================================
# SECTION 10: INTENTIONALLY WEAK SSH
# =============================================================================
section "SSH Configuration (Intentionally Weak)"

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — INTENTIONALLY VULNERABLE SSH CONFIG (DVWA target)
# Root login and password authentication are ENABLED by design.
# This simulates a misconfigured production server.

Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# INTENTIONAL MISCONFIGURATIONS
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# No login banner (teaches students to check for banners)
# Banner none

# Verbose logging for blue team analysis
LogLevel VERBOSE
SyslogFacility AUTH

AllowTcpForwarding yes
GatewayPorts yes
X11Forwarding yes

Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

systemctl enable ssh
systemctl restart ssh
success "SSH configured (intentionally weak — root login allowed)."

# =============================================================================
# SECTION 11: USER ACCOUNTS
# =============================================================================
section "User Accounts"

if ! id dvwaadmin &>/dev/null; then
    useradd -m -s /bin/bash -c "DVWA Administrator" dvwaadmin
fi
echo "dvwaadmin:${DVWAADMIN_PASS}" | chpasswd
usermod -aG sudo dvwaadmin

success "User accounts configured."

# =============================================================================
# SECTION 12: FIREWALL (UFW — Intentionally Permissive)
# =============================================================================
section "Firewall (Intentionally Permissive)"

apt-get install -y ufw

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Intentionally allow MySQL externally (lab teaching point)
ufw allow 22/tcp   comment "SSH"
ufw allow 80/tcp   comment "HTTP"
ufw allow 3306/tcp comment "MySQL — intentionally exposed"

ufw --force enable
ufw status verbose | tee -a "$LOGFILE"

warn "MySQL (3306) intentionally exposed — lab teaching vulnerability."
success "UFW configured."

# =============================================================================
# SECTION 13: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — DVWA Server (dvwa-latest)
  Role: Web Application Pentest Target — Lab 2 (IP: .20)

  WARNING: This system is intentionally insecure.
           Controlled lab environment for cybersecurity training only.

  DVWA   : http://<IP>/dvwa (admin / password)
  Setup  : http://<IP>/dvwa/setup.php
  MySQL  : Port 3306 (exposed — intentional)

MOTD

# =============================================================================
# SECTION 14: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
cat /dev/null > /home/dvwaadmin/.bash_history 2>/dev/null || true

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
echo -e "${BOLD}${GREEN}║         SCPS CyberLab — $IMAGE_NAME           ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}dvwaadmin OS password :${RESET} $DVWAADMIN_PASS"
echo -e "  ${BOLD}MySQL root password   :${RESET} $MYSQL_ROOT_PASS"
echo -e "  ${BOLD}DVWA DB password      :${RESET} $DVWA_DB_PASS"
echo -e "  ${BOLD}DVWA web login        :${RESET} admin / password  (intentional default)"
echo ""
echo -e "  ${YELLOW}Intentional vulnerabilities:${RESET}"
echo -e "    - Root SSH login enabled"
echo -e "    - SSH password auth enabled"
echo -e "    - MySQL exposed on 0.0.0.0:3306"
echo -e "    - PHP allow_url_include=On"
echo -e "    - File upload: no type validation"
echo -e "    - DVWA security level: low"
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
