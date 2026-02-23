#!/usr/bin/env sh
# =============================================================================
# Build-pfSense.sh
# SCPS CyberLab — Base Image Builder
# Image  : pfsense-2.7
# Purpose: pfSense 2.7 firewall/router used in Labs 1, 2, 4, 5.
#          Separates network segments per student:
#            Lab 1 (Red Team / Blue Team) : attack-net, corporate-net, dmz-net
#            Lab 2 (Web App Pentest)      : pentest-net
#            Lab 4 (Network Attack/Def)   : attack-net, internal-net
#            Lab 5 (Malware Analysis)     : analysis-net
#
# Host path (Hyper-V): C:\CyberLab\Templates\pfsense-2.7.vhdx
#
# HOW TO USE:
#   1. Install pfSense 2.7 from the official ISO onto a new VM/VHDX.
#      - WAN adapter  : first  virtual NIC (vtnet0 / hn0)
#      - LAN adapter  : second virtual NIC (vtnet1 / hn1)
#      - OPT1 adapter : third  virtual NIC (vtnet2 / hn2)  [optional/lab-specific]
#   2. Boot the freshly installed system and choose option 8
#      "Shell" from the pfSense console menu.
#   3. Run this script:
#        sh /tmp/Build-pfSense.sh
#      (Transfer the script via SCP or paste into the shell.)
#   4. The script configures the base template via:
#        - pfSense PHP shell (pfSsh.php playback) for system settings
#        - Direct writes to /conf/config.xml for network/firewall config
#   5. When the script completes it powers the VM off.
#      Use the VHDX as the parent disk for per-student differencing disks.
#
# IP PLACEHOLDERS (substituted at deploy time by Set-VMNetworkConfig.ps1):
#   LAN_IP_PLACEHOLDER   -> 10.<ClassId>.<StudentId>.1
#   WAN_IP_PLACEHOLDER   -> DHCP from Hyper-V external switch
#   CLASS_ID             -> 1 or 2
#   STUDENT_ID           -> 1-15
#
# FreeBSD note: this is /bin/sh, not bash.  No arrays, no [[ ]], no $().
# Use `expr`, backtick command substitution, and POSIX-only constructs.
# =============================================================================

# ---------------------------------------------------------------------------
# Logging helpers (POSIX sh — no colour codes; output goes to console + log)
# ---------------------------------------------------------------------------
LOGFILE="/var/log/lab-build-pfsense.log"
TIMESTAMP=`date '+%Y-%m-%d %H:%M:%S'`
IMAGE_NAME="pfsense-2.7"

log_info()    { printf '[INFO]  %s\n' "$*" | tee -a "$LOGFILE"; }
log_warn()    { printf '[WARN]  %s\n' "$*" | tee -a "$LOGFILE"; }
log_error()   { printf '[ERROR] %s\n' "$*" | tee -a "$LOGFILE"; exit 1; }
log_section() { printf '\n=== %s ===\n' "$*" | tee -a "$LOGFILE"; }
log_ok()      { printf '[OK]    %s\n' "$*" | tee -a "$LOGFILE"; }

# ---------------------------------------------------------------------------
# Prerequisite: must run as root inside the pfSense shell
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    log_error "Must be run as root (choose option 8 Shell from the pfSense menu)."
fi

touch "$LOGFILE"
chmod 600 "$LOGFILE"

log_info "Build started: $TIMESTAMP"
log_info "Image: $IMAGE_NAME"

# ---------------------------------------------------------------------------
# Verify pfSense-specific binaries are present
# ---------------------------------------------------------------------------
if [ ! -f /usr/local/sbin/pfSsh.php ]; then
    log_error "pfSsh.php not found — is this a pfSense installation?"
fi
if [ ! -d /conf ]; then
    log_error "/conf directory not found — is this a pfSense installation?"
fi

# ===========================================================================
# SECTION 1: STAGE THE CONFIG.XML TEMPLATE
# ===========================================================================
log_section "Stage config.xml"

# Back up any existing config first
if [ -f /conf/config.xml ]; then
    cp /conf/config.xml /conf/config.xml.pre-build-backup
    log_info "Backed up existing config.xml to config.xml.pre-build-backup"
fi

# Copy the pre-built template into place.
# pfSense-base-config.xml must be in the same directory as this script,
# or transferred to /tmp/pfSense-base-config.xml before running.
SCRIPT_DIR=`dirname "$0"`
TEMPLATE_SRC="$SCRIPT_DIR/pfSense-base-config.xml"

if [ ! -f "$TEMPLATE_SRC" ]; then
    # Fall back to /tmp
    TEMPLATE_SRC="/tmp/pfSense-base-config.xml"
fi

if [ ! -f "$TEMPLATE_SRC" ]; then
    log_error "pfSense-base-config.xml not found at '$TEMPLATE_SRC' or /tmp/. Transfer it to the VM first."
fi

cp "$TEMPLATE_SRC" /conf/config.xml
chmod 644 /conf/config.xml
log_ok "config.xml staged from $TEMPLATE_SRC"

# ===========================================================================
# SECTION 2: SET ADMIN PASSWORD VIA PHP SHELL
# ===========================================================================
log_section "Admin Password Configuration"

# The template uses ADMIN_BCRYPT_HASH as a placeholder.
# We generate a bcrypt hash of the known template password "LabAdmin2024!"
# At deploy time, New-LabAccounts.ps1 changes this to a per-student password.
#
# pfSense uses PHP's password_hash($pass, PASSWORD_BCRYPT, ['cost'=>11]).
# We call pfSsh.php to compute and inject the hash.

TEMPLATE_PASSWORD="LabAdmin2024!"

log_info "Generating bcrypt hash for template admin password..."

# Write a PHP playback file that sets the admin password in config.xml
cat > /tmp/set_admin_password.php << 'PHPEOF'
<?php
// pfSsh.php playback — set admin account password
// This runs inside the pfSense PHP environment with config already loaded.
global $config;

// Read the plaintext password from environment (set below via export)
$new_password = getenv('PFSENSE_ADMIN_PASS');
if (empty($new_password)) {
    echo "ERROR: PFSENSE_ADMIN_PASS environment variable not set.\n";
    exit(1);
}

// Compute bcrypt hash — same as pfSense UI does
$hash = password_hash($new_password, PASSWORD_BCRYPT, ['cost' => 11]);

// Find or create the admin user entry
$admin_found = false;
if (isset($config['system']['user']) && is_array($config['system']['user'])) {
    foreach ($config['system']['user'] as &$user) {
        if ($user['name'] === 'admin') {
            $user['password']   = $hash;
            $user['bcrypt-hash'] = 'yes';
            $admin_found = true;
            echo "Admin user found — password updated.\n";
            break;
        }
    }
    unset($user);
}

if (!$admin_found) {
    // Build a minimal admin user record
    $config['system']['user'][] = [
        'name'        => 'admin',
        'descr'       => 'System Administrator',
        'scope'       => 'system',
        'groupname'   => 'admins',
        'password'    => $hash,
        'bcrypt-hash' => 'yes',
        'uid'         => '0',
        'priv'        => ['page-all'],
    ];
    echo "Admin user created.\n";
}

write_config("SCPS CyberLab: set template admin password");
echo "Config written successfully.\n";
PHPEOF

# Export password so the PHP script can read it
export PFSENSE_ADMIN_PASS="$TEMPLATE_PASSWORD"

# Execute via pfSsh.php playback mode
pfSsh.php playback /tmp/set_admin_password.php
ADMIN_EXIT=$?

if [ $ADMIN_EXIT -ne 0 ]; then
    log_warn "pfSsh.php returned non-zero ($ADMIN_EXIT) for password set — check output above."
else
    log_ok "Admin password set to template default (will be changed at deploy time)."
fi

rm -f /tmp/set_admin_password.php
unset PFSENSE_ADMIN_PASS

# ===========================================================================
# SECTION 3: CONFIGURE INTERFACE ASSIGNMENTS VIA PHP SHELL
# ===========================================================================
log_section "Interface Assignment"

cat > /tmp/set_interfaces.php << 'PHPEOF'
<?php
// pfSsh.php playback — configure interface assignments
// Supports both KVM/QEMU virtio (vtnet0/vtnet1/vtnet2)
// and Hyper-V synthetic NICs (hn0/hn1/hn2).
global $config;

// Detect which driver is present
$avail = get_interface_list();
$drivers = array_keys($avail);

$wan_if = '';
$lan_if = '';
$opt1_if = '';

// Prefer vtnet (virtio / QEMU).  Fall back to hn (Hyper-V).
foreach (['vtnet0','hn0'] as $candidate) {
    if (in_array($candidate, $drivers)) { $wan_if = $candidate; break; }
}
foreach (['vtnet1','hn1'] as $candidate) {
    if (in_array($candidate, $drivers)) { $lan_if = $candidate; break; }
}
foreach (['vtnet2','hn2'] as $candidate) {
    if (in_array($candidate, $drivers)) { $opt1_if = $candidate; break; }
}

if (empty($wan_if) || empty($lan_if)) {
    echo "ERROR: Could not detect WAN or LAN interface. Available: " . implode(', ', $drivers) . "\n";
    exit(1);
}

echo "WAN -> $wan_if\n";
echo "LAN -> $lan_if\n";
if (!empty($opt1_if)) { echo "OPT1 -> $opt1_if\n"; }

// WAN
$config['interfaces']['wan']['if']       = $wan_if;
$config['interfaces']['wan']['enable']   = true;
$config['interfaces']['wan']['descr']    = 'WAN';
$config['interfaces']['wan']['ipaddr']   = 'dhcp';    // Gets IP from Hyper-V external switch
$config['interfaces']['wan']['ipaddrv6'] = 'none';
$config['interfaces']['wan']['blockpriv'] = false;    // Allow RFC1918 on WAN (lab environment)
$config['interfaces']['wan']['blockbogons'] = false;

// LAN — placeholder IP substituted at deploy time
$config['interfaces']['lan']['if']       = $lan_if;
$config['interfaces']['lan']['enable']   = true;
$config['interfaces']['lan']['descr']    = 'LAN';
$config['interfaces']['lan']['ipaddr']   = '10.0.0.1';    // Template placeholder — overridden at deploy
$config['interfaces']['lan']['subnet']   = '24';
$config['interfaces']['lan']['ipaddrv6'] = 'none';

// OPT1 (third NIC — present in multi-segment labs)
if (!empty($opt1_if)) {
    $config['interfaces']['opt1']['if']       = $opt1_if;
    $config['interfaces']['opt1']['enable']   = true;
    $config['interfaces']['opt1']['descr']    = 'OPT1';
    $config['interfaces']['opt1']['ipaddr']   = '10.0.1.1';  // Template placeholder
    $config['interfaces']['opt1']['subnet']   = '24';
    $config['interfaces']['opt1']['ipaddrv6'] = 'none';
}

write_config("SCPS CyberLab: interface assignments");
echo "Interface assignments written.\n";
PHPEOF

pfSsh.php playback /tmp/set_interfaces.php
log_ok "Interface assignments configured."
rm -f /tmp/set_interfaces.php

# ===========================================================================
# SECTION 4: CONFIGURE DHCP, DNS, NAT, AND FIREWALL RULES VIA PHP SHELL
# ===========================================================================
log_section "DHCP / DNS / NAT / Firewall"

cat > /tmp/set_network_services.php << 'PHPEOF'
<?php
// pfSsh.php playback — DHCP, DNS, NAT, firewall rules
global $config;

// ── DHCP ──────────────────────────────────────────────────────────────────
// Disable DHCP server on LAN: students use static IPs assigned by platform.
// (The DHCP server block must not exist or must have 'enable' absent.)
if (isset($config['dhcpd']['lan'])) {
    unset($config['dhcpd']['lan']['enable']);
    echo "DHCP server on LAN: disabled (students use static IPs).\n";
}

// OPT1: also disable DHCP
if (isset($config['dhcpd']['opt1'])) {
    unset($config['dhcpd']['opt1']['enable']);
}

// ── DNS / SYSTEM ──────────────────────────────────────────────────────────
// Primary DNS servers via WAN (Google public — reliable in lab environment)
$config['system']['dnsserver']   = ['8.8.8.8', '8.8.4.4'];
// DNS forwarder listens on LAN only — so VMs on LAN can resolve names
$config['system']['dnslocalhost'] = true;

// DNS Resolver (Unbound) — enabled, listens on LAN and localhost
$config['unbound']['enable']        = true;
$config['unbound']['active_interface'] = 'lan';
$config['unbound']['outgoing_interface'] = 'wan';
$config['unbound']['dnssec']        = true;
$config['unbound']['forwarding']    = true;   // Forward to WAN DNS servers

echo "DNS resolver (Unbound) configured.\n";

// ── NAT — Automatic Outbound NAT for LAN ──────────────────────────────────
// Mode 2 = Automatic outbound NAT (masquerade LAN -> WAN)
$config['nat']['outbound']['mode'] = 'automatic';
// Manual outbound NAT rules are not needed when mode = automatic

echo "NAT: automatic outbound NAT enabled.\n";

// ── FIREWALL RULES ────────────────────────────────────────────────────────
// pfSense rule structure:
//   source/destination specify 'network' or 'address' + 'subnet'
//   type: pass | block | reject
//   protocol: tcp | udp | tcp/udp | icmp | any
//   interface: lan | wan | opt1
//
// Rules are evaluated top-down per interface.

// Clear existing rules (template starting point)
$config['filter']['rule'] = [];

$rules = [];

// ── RULE 1: Allow all IPv4 LAN -> any (WAN NAT handles translation)
// This is the standard "LAN to WAN: allow all" rule.
$rules[] = [
    'type'        => 'pass',
    'interface'   => 'lan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'any',
    'source'      => ['network' => 'lan'],
    'destination' => ['any' => true],
    'descr'       => 'SCPS-LAB: LAN to WAN - Allow all IPv4 (NAT masquerade)',
    'log'         => false,
];

// ── RULE 2: Allow ICMP everywhere (troubleshooting / ping tests)
$rules[] = [
    'type'        => 'pass',
    'interface'   => 'lan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'icmp',
    'icmptype'    => 'any',
    'source'      => ['any' => true],
    'destination' => ['any' => true],
    'descr'       => 'SCPS-LAB: Allow ICMP everywhere (troubleshooting)',
    'log'         => false,
];

$rules[] = [
    'type'        => 'pass',
    'interface'   => 'wan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'icmp',
    'icmptype'    => 'any',
    'source'      => ['any' => true],
    'destination' => ['any' => true],
    'descr'       => 'SCPS-LAB: Allow ICMP on WAN (troubleshooting)',
    'log'         => false,
];

// ── RULE 3: Allow established/related return traffic (stateful — pfSense
//    handles this automatically with its stateful inspection engine; this
//    explicit rule documents the intent and covers edge cases.)
$rules[] = [
    'type'        => 'pass',
    'interface'   => 'wan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'tcp',
    'source'      => ['any' => true],
    'destination' => ['any' => true],
    'statetype'   => 'keep state',
    'tcpflags_any' => true,
    'descr'       => 'SCPS-LAB: WAN - Allow established/related return traffic',
    'log'         => false,
];

// ── RULE 4: WAN -> LAN block all (default deny inbound from WAN)
// pfSense blocks all unsolicited inbound WAN traffic by default;
// this explicit rule makes the intent visible in the config.
$rules[] = [
    'type'        => 'block',
    'interface'   => 'wan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'any',
    'source'      => ['any' => true],
    'destination' => ['network' => 'lan'],
    'descr'       => 'SCPS-LAB: WAN to LAN - Block all (default deny)',
    'log'         => true,
];

// ── RULE 5: LAN -> OPT1 block by default
// Students practice writing rules to permit specific traffic.
// This rule is the default-deny for inter-segment traffic.
$rules[] = [
    'type'        => 'block',
    'interface'   => 'lan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'any',
    'source'      => ['network' => 'lan'],
    'destination' => ['network' => 'opt1'],
    'descr'       => 'SCPS-LAB: LAN to OPT1 - Block by default (students add allow rules)',
    'log'         => true,
];

// ── RULE 6: OPT1 -> LAN block by default (symmetric)
$rules[] = [
    'type'        => 'block',
    'interface'   => 'opt1',
    'ipprotocol'  => 'inet',
    'protocol'    => 'any',
    'source'      => ['network' => 'opt1'],
    'destination' => ['network' => 'lan'],
    'descr'       => 'SCPS-LAB: OPT1 to LAN - Block by default',
    'log'         => true,
];

// ── RULE 7: pfSense management — allow SSH from LAN
$rules[] = [
    'type'        => 'pass',
    'interface'   => 'lan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'tcp',
    'source'      => ['network' => 'lan'],
    'destination' => ['address' => '10.0.0.1', 'subnet' => '32'],
    'destination_port' => '22',
    'descr'       => 'SCPS-LAB: Allow SSH to pfSense from LAN',
    'log'         => false,
];

// ── RULE 8: pfSense management — allow HTTPS web GUI from LAN
$rules[] = [
    'type'        => 'pass',
    'interface'   => 'lan',
    'ipprotocol'  => 'inet',
    'protocol'    => 'tcp',
    'source'      => ['network' => 'lan'],
    'destination' => ['address' => '10.0.0.1', 'subnet' => '32'],
    'destination_port' => '443',
    'descr'       => 'SCPS-LAB: Allow HTTPS to pfSense GUI from LAN',
    'log'         => false,
];

$config['filter']['rule'] = $rules;
echo "Firewall rules configured (" . count($rules) . " rules).\n";

write_config("SCPS CyberLab: DHCP/DNS/NAT/firewall configuration");
echo "Network services configuration written.\n";
PHPEOF

pfSsh.php playback /tmp/set_network_services.php
log_ok "DHCP / DNS / NAT / firewall rules configured."
rm -f /tmp/set_network_services.php

# ===========================================================================
# SECTION 5: ENABLE SSH AND CONSOLE SETTINGS VIA PHP SHELL
# ===========================================================================
log_section "SSH and Console Settings"

cat > /tmp/set_ssh_console.php << 'PHPEOF'
<?php
// pfSsh.php playback — enable SSH, configure admin access
global $config;

// ── SSH ───────────────────────────────────────────────────────────────────
// Enable SSH daemon on port 22 for student and instructor access.
$config['system']['enablesshd']    = true;
$config['system']['sshdkeyonly']   = 'disabled';   // Allow password + key auth
$config['system']['sshport']       = '22';

// ── CONSOLE ───────────────────────────────────────────────────────────────
// Keep console menu accessible — students need it for recovery/troubleshooting.
// Do NOT set 'noconsolemenu' — that would hide the menu.
if (isset($config['system']['noconsolemenu'])) {
    unset($config['system']['noconsolemenu']);
}
// Require password to access the console menu for security
$config['system']['consolemenu'] = 'enabled';

// ── WEBGUI ────────────────────────────────────────────────────────────────
// HTTPS only, port 443, no HTTP redirect required (lab environment)
$config['system']['webgui']['protocol']    = 'https';
$config['system']['webgui']['port']        = '443';
$config['system']['webgui']['ssl-certref'] = '';  // Uses auto-generated self-signed cert

// ── HOSTNAME AND DOMAIN ───────────────────────────────────────────────────
$config['system']['hostname'] = 'pfsense-template';
$config['system']['domain']   = 'lab.scps.local';

// ── TIMEZONE ─────────────────────────────────────────────────────────────
$config['system']['timezone'] = 'America/New_York';

// ── LANGUAGE / THEME ─────────────────────────────────────────────────────
$config['system']['language'] = 'en_US';
$config['system']['webgui']['loginautocomplete'] = false;

write_config("SCPS CyberLab: SSH, console, hostname, timezone");
echo "SSH enabled on port 22.\n";
echo "Console menu preserved (student recovery access).\n";
echo "Hostname: pfsense-template.lab.scps.local\n";
echo "Timezone: America/New_York\n";
PHPEOF

pfSsh.php playback /tmp/set_ssh_console.php
log_ok "SSH and console settings applied."
rm -f /tmp/set_ssh_console.php

# ===========================================================================
# SECTION 6: ENABLE SSHD SERVICE IMMEDIATELY (freebsd rc.conf)
# ===========================================================================
log_section "FreeBSD rc.conf — sshd"

# pfSsh.php enables sshd in the pfSense config, but we also need the
# FreeBSD-level sshd to be running in the base OS if pfSense restarts
# before the full GUI initialises.
if grep -q '^sshd_enable=' /etc/rc.conf 2>/dev/null; then
    sed -i '' 's/^sshd_enable=.*/sshd_enable="YES"/' /etc/rc.conf
else
    echo 'sshd_enable="YES"' >> /etc/rc.conf
fi

log_ok "sshd_enable=YES set in /etc/rc.conf"

# Ensure SSH host keys exist (they're generated on first boot by pfSense
# normally, but we want them available immediately for the template build).
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    log_info "Generating SSH host keys..."
    /usr/bin/ssh-keygen -A
    log_ok "SSH host keys generated."
fi

# ===========================================================================
# SECTION 7: PKG — ENSURE REQUIRED PACKAGES
# ===========================================================================
log_section "Package Verification"

# pfSense uses its own pkg repo.  We check for packages that the lab
# scenarios depend on and install them if missing.

log_info "Updating pkg repository..."
pkg update -f 2>/dev/null || log_warn "pkg update failed — continuing (may be an air-gapped environment)."

# pfSense-pkg-openvpn-client-export is useful for Lab 1 / Lab 2 VPN exercises.
# Install only if available; don't fail the build if the repo is unreachable.
for PKG in pfSense-pkg-openvpn-client-export pfSense-pkg-nmap; do
    if pkg info "$PKG" > /dev/null 2>&1; then
        log_info "$PKG already installed."
    else
        log_info "Attempting to install $PKG..."
        pkg install -y "$PKG" 2>/dev/null && log_ok "$PKG installed." \
            || log_warn "$PKG not available in repo — skipping."
    fi
done

# ===========================================================================
# SECTION 8: WRITE /etc/hosts PLACEHOLDERS
# ===========================================================================
log_section "/etc/hosts Lab Placeholders"

cat >> /etc/hosts << 'HOSTSEOF'

# ===========================================================================
# SCPS CyberLab — Lab Host Placeholders
# Uncomment and fill in IPs after student network is provisioned.
# ===========================================================================
# 10.CLASS_ID.STUDENT_ID.10   kali.lab           kali
# 10.CLASS_ID.STUDENT_ID.20   winserver.lab      winserver
# 10.CLASS_ID.STUDENT_ID.30   ubuntu.lab         ubuntu
# 10.CLASS_ID.STUDENT_ID.40   dvwa.lab           dvwa
# 10.CLASS_ID.STUDENT_ID.50   securityonion.lab  securityonion
HOSTSEOF

log_ok "/etc/hosts placeholders written."

# ===========================================================================
# SECTION 9: WRITE DEPLOY-TIME CUSTOMISATION SCRIPT
# ===========================================================================
log_section "Deploy-Time Customisation Hook"

# This script is called by Set-VMNetworkConfig.ps1 via SSH after cloning
# to substitute the IP placeholders.  It should be idempotent.
mkdir -p /opt/scps-lab
cat > /opt/scps-lab/deploy-customise.sh << 'DEPLOYEOF'
#!/usr/bin/env sh
# =============================================================================
# deploy-customise.sh — Called by the orchestration platform at deploy time.
# Substitutes IP placeholders and applies per-student settings.
#
# Usage:
#   sh /opt/scps-lab/deploy-customise.sh \
#       --class-id 1 --student-id 3 \
#       --lan-ip 10.1.3.1 --wan-ip dhcp \
#       --admin-password "GeneratedPass!"
# =============================================================================

# Parse arguments
CLASS_ID=""
STUDENT_ID=""
LAN_IP=""
WAN_IP="dhcp"
ADMIN_PASS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --class-id)       CLASS_ID="$2";   shift 2 ;;
        --student-id)     STUDENT_ID="$2"; shift 2 ;;
        --lan-ip)         LAN_IP="$2";     shift 2 ;;
        --wan-ip)         WAN_IP="$2";     shift 2 ;;
        --admin-password) ADMIN_PASS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$CLASS_ID" ] || [ -z "$STUDENT_ID" ] || [ -z "$LAN_IP" ]; then
    echo "Usage: $0 --class-id N --student-id N --lan-ip X.X.X.X [--wan-ip dhcp|X.X.X.X] [--admin-password P]"
    exit 1
fi

HOSTNAME="pfsense-c${CLASS_ID}-s${STUDENT_ID}"

echo "[DEPLOY] Setting hostname: $HOSTNAME"
echo "[DEPLOY] LAN IP: $LAN_IP/24, WAN: $WAN_IP"

# Update config.xml via PHP shell
export DEPLOY_LAN_IP="$LAN_IP"
export DEPLOY_WAN_IP="$WAN_IP"
export DEPLOY_HOSTNAME="$HOSTNAME"
export DEPLOY_ADMIN_PASS="$ADMIN_PASS"

pfSsh.php playback /opt/scps-lab/apply-deploy-config.php

echo "[DEPLOY] Reloading filter/NAT..."
pfSsh.php playback /usr/local/etc/rc.d/filter_configure.php 2>/dev/null || true

echo "[DEPLOY] Restarting services..."
/etc/rc.restart_webgui 2>/dev/null || true

echo "[DEPLOY] Customisation complete for $HOSTNAME."
DEPLOYEOF

chmod 755 /opt/scps-lab/deploy-customise.sh

# Write the companion PHP playback script
cat > /opt/scps-lab/apply-deploy-config.php << 'APPLYEOF'
<?php
// pfSsh.php playback — apply per-student deploy-time configuration
// Called by deploy-customise.sh with environment variables set.
global $config;

$lan_ip   = getenv('DEPLOY_LAN_IP')    ?: '10.0.0.1';
$wan_ip   = getenv('DEPLOY_WAN_IP')    ?: 'dhcp';
$hostname = getenv('DEPLOY_HOSTNAME')  ?: 'pfsense-template';
$admin_pass = getenv('DEPLOY_ADMIN_PASS');

// Update LAN IP
$config['interfaces']['lan']['ipaddr'] = $lan_ip;
echo "LAN IP set to $lan_ip/24\n";

// Update WAN
if ($wan_ip === 'dhcp') {
    $config['interfaces']['wan']['ipaddr'] = 'dhcp';
    echo "WAN: DHCP\n";
} else {
    $config['interfaces']['wan']['ipaddr']  = $wan_ip;
    $config['interfaces']['wan']['subnet']  = '24';
    echo "WAN IP set to $wan_ip/24\n";
}

// Update hostname
$config['system']['hostname'] = $hostname;
echo "Hostname: $hostname\n";

// Update DNS server (self on LAN)
$config['system']['dnsserver'] = ['8.8.8.8', '8.8.4.4'];

// Update admin password if provided
if (!empty($admin_pass)) {
    $hash = password_hash($admin_pass, PASSWORD_BCRYPT, ['cost' => 11]);
    if (isset($config['system']['user']) && is_array($config['system']['user'])) {
        foreach ($config['system']['user'] as &$user) {
            if ($user['name'] === 'admin') {
                $user['password']    = $hash;
                $user['bcrypt-hash'] = 'yes';
                echo "Admin password updated.\n";
                break;
            }
        }
        unset($user);
    }
}

// Update DHCP server range if DNS resolver is enabled (uses LAN IP as base)
// e.g., LAN = 10.1.3.1 -> DHCP would be 10.1.3.100-10.1.3.199 (not used — static IPs)
// We leave DHCP disabled but record the range for documentation.

write_config("SCPS CyberLab: deploy-time customisation for $hostname");
echo "Deploy configuration applied.\n";
APPLYEOF

chmod 644 /opt/scps-lab/apply-deploy-config.php
log_ok "Deploy-time customisation scripts written to /opt/scps-lab/"

# ===========================================================================
# SECTION 10: SYSPREP — GENERALISE THE IMAGE
# ===========================================================================
log_section "Sysprep — Generalising Image"

log_info "Clearing shell history..."
history -c 2>/dev/null || true
: > /root/.history 2>/dev/null || true
: > /root/.sh_history 2>/dev/null || true

log_info "Removing SSH host keys (regenerated on first boot)..."
rm -f /etc/ssh/ssh_host_*
# pfSense regenerates them via /etc/rc.d/sshd on next boot

log_info "Clearing /tmp..."
rm -rf /tmp/* 2>/dev/null || true

log_info "Clearing var/log (pfSense regenerates on boot)..."
find /var/log -type f -name '*.log' -exec truncate -s 0 {} \; 2>/dev/null || true

# Remove the pre-build backup from /conf to keep the image clean
# (Keep the config.xml we just staged)
rm -f /conf/config.xml.pre-build-backup

log_info "Flushing filesystem..."
sync

log_ok "Sysprep complete."

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================
log_section "Build Complete"

printf '\n'
printf '=================================================================\n'
printf '  SCPS CyberLab — %s Base Image Build Complete\n' "$IMAGE_NAME"
printf '=================================================================\n'
printf '\n'
printf '  Template admin password : LabAdmin2024!\n'
printf '  (Changed at deploy time by Set-VMNetworkConfig.ps1)\n'
printf '\n'
printf '  Template LAN IP         : 10.0.0.1/24  (placeholder)\n'
printf '  Template WAN            : DHCP\n'
printf '  SSH                     : Enabled on port 22\n'
printf '  Web GUI                 : HTTPS on port 443\n'
printf '  Hostname                : pfsense-template.lab.scps.local\n'
printf '\n'
printf '  Deploy-time hook        : /opt/scps-lab/deploy-customise.sh\n'
printf '  Build log               : %s\n' "$LOGFILE"
printf '\n'
printf '  NEXT STEP: Shut down this VM and store the VHDX as:\n'
printf '  C:\\CyberLab\\Templates\\pfsense-2.7.vhdx\n'
printf '\n'
printf '=================================================================\n'

log_info "Shutting down in 5 seconds..."
sleep 5
/sbin/poweroff
