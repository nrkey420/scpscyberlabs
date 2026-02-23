#!/usr/bin/env bash
# =============================================================================
# Build-VyOS.sh
# SCPS CyberLab — Base Image Builder
# Image  : vyos-1.4-vulnerable
# Purpose: VyOS 1.4 LTS router with intentional misconfigurations for
#          Lab 4 (Network Attack & Defense).
#          IP: 10.<ClassId>.<StudentId>.2 on internal-net (LAN/eth1).
#          eth0 connects to attack-net (WAN side — students attack from here).
#
# Host path (Hyper-V): C:\CyberLab\Templates\vyos-1.4-vulnerable.vhdx
#
# HOW TO USE:
#   1. Install VyOS 1.4 LTS from the live ISO:
#        install image   (follow the installer prompts)
#   2. After reboot, log in as vyos / vyos (default credentials).
#   3. Transfer this script to the VM:
#        scp Build-VyOS.sh vyos@<vm-ip>:/tmp/
#   4. Run the script using vbash (VyOS shell):
#        vbash /tmp/Build-VyOS.sh
#      The script switches to configure mode internally — do NOT pre-enter
#      configure mode before running.
#
# INTENTIONAL VULNERABILITIES (Lab 4 learning objectives):
# ─────────────────────────────────────────────────────────────────────────────
#   VULN-1  Telnet enabled, SSH disabled by default
#           Students discover via nmap -sV and exploit via cleartext intercept.
#           CVE category: CWE-312 (Cleartext Storage of Sensitive Information)
#
#   VULN-2  SNMP v1/v2c with community "public" on all interfaces
#           Students use snmpwalk to extract routing tables, interface info,
#           and system details.  Demonstrates information disclosure.
#           CVE category: CWE-284 (Improper Access Control)
#
#   VULN-3  RIP routing with no MD5/SHA authentication
#           Students inject false routes (RIP spoofing) to redirect traffic.
#           Demonstrates CWE-345 (Insufficient Verification of Data Authenticity)
#
#   VULN-4  NTP no authentication — NTP amplification / reflection possible
#           Students run ntpdc monlist queries (if enabled in ntp daemon).
#           Demonstrates CVE-2013-5211 class vulnerabilities.
#
#   VULN-5  Weak admin password: vyos123
#           Students brute-force with hydra or crack with John/Hashcat.
#           Demonstrates CWE-521 (Weak Password Requirements)
#
#   VULN-6  No firewall rules — all traffic passes unrestricted
#           Students observe open ports and pivot through the router.
#           Demonstrates CWE-732 (Incorrect Permission Assignment)
#
#   VULN-7  DNS forwarding open to all sources — DNS amplification possible
#           Students can use the router as a DNS reflector.
#           Demonstrates CVE-2006-0987 class (open recursive resolver)
#
# RUN AS: vyos user (not root) — VyOS configure mode requires the vyos user.
# =============================================================================

# VyOS scripts must source this file to get access to configure mode functions.
# This provides: configure, set, commit, save, exit, etc.
source /opt/vyatta/etc/functions/script-template

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOGFILE="/var/log/lab-build-vyos.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
IMAGE_NAME="vyos-1.4-vulnerable"

log_info()    { echo "[INFO]  $*" | tee -a "$LOGFILE"; }
log_warn()    { echo "[WARN]  $*" | tee -a "$LOGFILE"; }
log_ok()      { echo "[OK]    $*" | tee -a "$LOGFILE"; }
log_section() { echo -e "\n=== $* ===" | tee -a "$LOGFILE"; }
log_error()   { echo "[ERROR] $*" | tee -a "$LOGFILE"; exit 1; }

touch "$LOGFILE"
chmod 600 "$LOGFILE"

log_info "Build started: $TIMESTAMP"
log_info "Image: $IMAGE_NAME"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if ! command -v vbash &>/dev/null && [[ "$(basename "$SHELL")" != "vbash" ]]; then
    log_warn "Not running under vbash — attempting to continue (configure mode functions should be sourced)."
fi

if [[ ! -f /opt/vyatta/etc/functions/script-template ]]; then
    log_error "VyOS script-template not found — is this a VyOS installation?"
fi

# ===========================================================================
# Enter configure mode
# All 'set' commands below are in VyOS configure mode.
# ===========================================================================
configure

log_section "System Identification"

# ── Hostname and domain ────────────────────────────────────────────────────
# Generic router name — will not hint at vulnerabilities to observant students.
set system host-name 'scps-router01'
set system domain-name 'lab.scps.local'
log_info "Hostname: scps-router01.lab.scps.local"

# ── Domain search ─────────────────────────────────────────────────────────
set system domain-search domain 'lab.scps.local'

log_section "Name Servers"

# ── VULN-4 (NTP) context: DNS goes to 8.8.8.8 — also exposed as open resolver
set system name-server '8.8.8.8'
set system name-server '8.8.4.4'
log_info "DNS: 8.8.8.8, 8.8.4.4"

# ===========================================================================
# NTP CONFIGURATION — INTENTIONALLY VULNERABLE
# ===========================================================================
log_section "NTP Configuration (VULN-4: No Authentication)"

# ── VULN-4: NTP with no authentication ────────────────────────────────────
# Impact: Router can be used as NTP amplification reflector.
#         Students learn to:
#           1. Query monlist via: ntpdc -c monlist <router-ip>
#           2. Measure amplification factor
#           3. Mitigate by enabling NTP authentication and rate limiting
# Intentional configuration: pool.ntp.org, no restrict, no auth.
set system ntp server 'pool.ntp.org'
set system ntp server '0.pool.ntp.org'
set system ntp server '1.pool.ntp.org'
# Note: intentionally omitting 'restrict' directives that would limit queries.
# A hardened config would add: set system ntp allow-clients address '127.0.0.1/8'
# We deliberately do NOT set that here.
log_warn "VULN-4: NTP configured without authentication or query restrictions."
log_warn "        Students should discover this is exploitable for NTP amplification."
log_info "NTP: pool.ntp.org (no auth — intentional)"

# ===========================================================================
# INTERFACE CONFIGURATION
# ===========================================================================
log_section "Interface Configuration"

# ── eth0: WAN / attack-net side ───────────────────────────────────────────
# Students attack from this side.  DHCP address from Hyper-V switch.
# No firewall rules between eth0 and eth1 (VULN-6).
set interfaces ethernet eth0 description 'WAN-attack-net'
set interfaces ethernet eth0 address 'dhcp'
log_info "eth0: WAN/attack-net side — DHCP address from Hyper-V external switch"

# ── eth1: internal-net / LAN side ─────────────────────────────────────────
# Fixed IP: 10.{CLASS_ID}.{STUDENT_ID}.2/24
# This placeholder is replaced at deploy time by Set-VMNetworkConfig.ps1.
# The .1 address is pfSense (the default gateway for this segment).
# The .2 address is this VyOS router (secondary network device on the segment).
set interfaces ethernet eth1 description 'LAN-internal-net'
set interfaces ethernet eth1 address '10.{CLASS_ID}.{STUDENT_ID}.2/24'
# PLACEHOLDER: 10.{CLASS_ID}.{STUDENT_ID}.2/24 -> e.g., 10.1.5.2/24
# The orchestration platform's Set-VMNetworkConfig.ps1 runs:
#   ssh vyos@<vm-ip> "vbash /opt/scps-lab/deploy-set-ip.sh 10.1.5.2 24"
# after cloning, substituting the actual values.
log_info "eth1: internal-net — 10.{CLASS_ID}.{STUDENT_ID}.2/24 (placeholder)"

# ===========================================================================
# ADMIN ACCOUNT — INTENTIONALLY WEAK PASSWORD (VULN-5)
# ===========================================================================
log_section "User Account (VULN-5: Weak Password)"

# ── VULN-5: Weak admin password ──────────────────────────────────────────
# Impact: Easily brute-forced with hydra, medusa, or ncrack.
# Students learn to:
#   1. Enumerate the telnet service on port 23
#   2. Brute-force with: hydra -l vyos -P /usr/share/wordlists/rockyou.txt telnet://<ip>
#   3. Log in and enumerate the router configuration
#   4. Remediate by setting a strong password and enabling SSH with key auth
# The username 'vyos' is the VyOS default and is well-known.
# The password 'vyos123' is a trivial variation of the default ('vyos').
set system login user vyos authentication plaintext-password 'vyos123'
# plaintext-password is stored as a hashed value by VyOS internally.
# It is intentionally weak for the brute-force exercise.
log_warn "VULN-5: Admin password set to 'vyos123' (intentionally weak)."
log_warn "        Students should discover this via brute-force (hydra/medusa)."
log_info "Admin user: vyos / vyos123"

# ===========================================================================
# TELNET SERVICE — INTENTIONALLY ENABLED, NO SSH (VULN-1)
# ===========================================================================
log_section "Service Configuration (VULN-1: Telnet, No SSH)"

# ── VULN-1: Telnet enabled ────────────────────────────────────────────────
# Impact: All credentials and commands transmitted in cleartext.
#         Students can intercept with Wireshark/tcpdump on the same segment.
# Students learn to:
#   1. Run nmap to discover port 23 open (telnet)
#   2. Notice port 22 (SSH) is CLOSED
#   3. Connect via telnet and see cleartext credentials
#   4. Use Wireshark to capture the telnet session
#   5. Remediate: enable SSH, disable telnet, use key auth
set service telnet port '23'
log_warn "VULN-1: Telnet service enabled on port 23."
log_warn "        SSH is deliberately NOT configured — students discover this."
log_info "Telnet: port 23 (SSH intentionally absent)"
# NOTE: We intentionally do NOT run: set service ssh port '22'
# This means SSH will be unavailable and students will notice via nmap.
# The orchestration platform uses a pre-SSH connection window (before this
# script runs on the template) to push files, then disables SSH as the
# final build step.

# ===========================================================================
# SNMP v1/v2c — INTENTIONALLY OPEN (VULN-2)
# ===========================================================================
log_section "SNMP Configuration (VULN-2: Community 'public', Open)"

# ── VULN-2: SNMP v2c with "public" community string ──────────────────────
# Impact: Anyone on the network can walk the full MIB tree, including:
#   - System description and contact info
#   - Interface names, MAC addresses, IP addresses
#   - Routing table (IP-MIB::ipRouteTable)
#   - Connected hosts (ARP cache — ipNetToMediaTable)
#   - Traffic counters per interface
# Students learn to:
#   1. Discover SNMP with: nmap -sU -p 161 <ip>
#   2. Enumerate with: snmpwalk -v2c -c public <ip>
#   3. Extract routing table: snmpwalk -v2c -c public <ip> ip.ipRouteTable
#   4. Identify that v3 with auth/priv should be used instead
#   5. Remediate: change community string, restrict to management IP, use v3

# Community 'public' with read-only access — no source restrictions
set service snmp community 'public' authorization 'ro'
# Intentionally allow from all networks (0.0.0.0/0)
set service snmp community 'public' network '0.0.0.0/0'

# System-level SNMP contact and location (reveals information about the environment)
set service snmp contact 'labadmin@scps.local'
set service snmp location 'SCPS CyberLab Rack 1'

# Listen on all interfaces (not just management — intentional exposure)
# VyOS listens on all interfaces when no listen-address is specified.

log_warn "VULN-2: SNMP v2c community 'public' open on all interfaces (0.0.0.0/0)."
log_warn "        Students should enumerate this with snmpwalk."
log_info "SNMP: v2c, community=public, ro, 0.0.0.0/0"

# ===========================================================================
# RIP ROUTING — INTENTIONALLY NO AUTHENTICATION (VULN-3)
# ===========================================================================
log_section "RIP Routing (VULN-3: No Authentication)"

# ── VULN-3: RIP v2 with no MD5/SHA authentication ─────────────────────────
# Impact: Any host on the attached network can inject false routes by
#         sending forged RIP update packets.  This allows:
#   - Black-hole attacks (route traffic to /dev/null)
#   - Man-in-the-middle attacks (redirect traffic through attacker)
#   - Denial of service (routing loops, metric overflow)
# Students learn to:
#   1. Observe RIP broadcasts with Wireshark (UDP/520 multicast 224.0.0.9)
#   2. Inject false routes: use scapy or frr/quagga on Kali to send RIP updates
#      Example scapy one-liner:
#        from scapy.all import *
#        pkt = IP(dst="224.0.0.9")/UDP(sport=520,dport=520)/RIP()/
#              RIPEntry(AF=2,addr="10.99.0.0",mask="255.255.0.0",metric=1)
#        send(pkt, iface="eth1")
#   3. Observe the poisoned route: show ip route on the router
#   4. Remediate: enable MD5 authentication on RIP interfaces

# Enable RIP on eth1 (the internal segment students attack from eth0 through)
set protocols rip interface 'eth1'
# Advertise the entire 10.0.0.0/8 block (intentionally broad — exposes all lab subnets)
set protocols rip network '10.0.0.0/8'

# Version 2 (multicast — can be captured more easily than v1 broadcast)
set protocols rip parameters version '2'

# Intentionally NO authentication:
# A hardened config would add:
#   set protocols rip interface eth1 authentication md5 key-id 1 md5-key 'SecretKey123'
# We deliberately omit this.

# Passive interface NOT set on eth0 — so RIP also propagates to the attack side
# (allows students to observe and inject from the WAN side too)

log_warn "VULN-3: RIP v2 enabled on eth1 with NO authentication."
log_warn "        Students can inject false routes using scapy or quagga."
log_info "RIP: v2, network 10.0.0.0/8, no auth (intentional)"

# ===========================================================================
# DNS FORWARDING — INTENTIONALLY OPEN RESOLVER (VULN-7)
# ===========================================================================
log_section "DNS Forwarding (VULN-7: Open Recursive Resolver)"

# ── VULN-7: DNS forwarding open to all sources ────────────────────────────
# Impact: The router acts as an open recursive DNS resolver, enabling:
#   - DNS amplification/reflection DDoS (attacker spoofs victim's source IP
#     and sends small queries; router sends large responses to victim)
#   - DNS reconnaissance (students can query for internal names)
#   - Cache poisoning attacks (Kaminsky attack)
# Students learn to:
#   1. Identify open resolver: dig @<router-ip> google.com
#   2. Test amplification factor: compare request vs response size
#   3. Simulate reflection: use scapy to send spoofed DNS queries
#   4. Remediate: restrict allow-from to local subnets only, disable recursion
#                 for external queries

# Listen for DNS queries on the internal network interface
set service dns forwarding listen-on 'eth1'
# Also listen on eth0 — making it accessible from the attack-net side too
set service dns forwarding listen-on 'eth0'

# Intentionally allow DNS queries from ALL sources (0.0.0.0/0 = anyone)
set service dns forwarding allow-from '0.0.0.0/0'

# Forward to upstream resolvers
set service dns forwarding name-server '8.8.8.8'
set service dns forwarding name-server '8.8.4.4'

# Cache size (larger cache = more useful for amplification)
set service dns forwarding cache-size '10000'

# Note: In a hardened configuration you would set:
#   set service dns forwarding allow-from '10.0.0.0/8'
# and disable recursion for external queries.  We intentionally do NOT do this.

log_warn "VULN-7: DNS forwarding open to 0.0.0.0/0 on eth0 and eth1."
log_warn "        Students can use this as an open recursive resolver for amplification."
log_info "DNS forwarding: listen eth0+eth1, allow-from 0.0.0.0/0 (intentional)"

# ===========================================================================
# NO FIREWALL RULES — INTENTIONAL (VULN-6)
# ===========================================================================
log_section "Firewall (VULN-6: No Rules — Allow All)"

# ── VULN-6: No firewall rules configured ─────────────────────────────────
# Impact: All traffic between eth0 (attack-net) and eth1 (internal-net)
#         passes unrestricted.  Students can:
#   - Scan all ports on internal hosts without obstruction
#   - Pivot through the router to reach internal-net hosts
#   - Observe that even a "router" device needs explicit ACLs
# Students learn to:
#   1. Confirm no ACLs: show firewall (shows empty output)
#   2. Pivot through the router using SSH tunnels or as a hop point
#   3. Write firewall rules to restrict traffic flow
#   4. Implement least-privilege ACLs

# Intentionally: do NOT configure any firewall rules.
# In VyOS, 'set firewall ...' commands would go here for a hardened config.
# Example of what should be here but is intentionally absent:
#   set firewall name WAN_IN default-action 'drop'
#   set firewall name WAN_IN rule 10 action 'accept'
#   set firewall name WAN_IN rule 10 state established 'enable'
#   set interfaces ethernet eth0 firewall in name 'WAN_IN'

log_warn "VULN-6: NO firewall rules configured — all traffic passes unrestricted."
log_warn "        Students should discover this via nmap and port scanning."
log_info "Firewall: NONE (intentional)"

# ===========================================================================
# STATIC ROUTES — Default route via eth0 DHCP gateway
# ===========================================================================
log_section "Static Routes"

# Default route — rely on DHCP-assigned gateway from eth0.
# VyOS with eth0 set to DHCP will automatically install a default route.
# We explicitly set a static fallback in case DHCP hasn't fired yet.
# 0.0.0.0/0 via the WAN gateway — instructors configure the actual IP.
# (The orchestration platform adds the real gateway at deploy time.)
set protocols static route '0.0.0.0/0' next-hop '10.0.0.1'
# PLACEHOLDER: 10.0.0.1 will be overwritten at deploy time with the
# actual pfSense WAN-side IP or Hyper-V external switch gateway.

log_info "Default route: 0.0.0.0/0 via 10.0.0.1 (placeholder — updated at deploy)"

# ===========================================================================
# LOGGING — Send logs to local syslog (students can observe via CLI)
# ===========================================================================
log_section "System Logging"

set system syslog global facility all level 'info'
set system syslog global facility protocols level 'debug'
log_info "Syslog: local, all facilities, info level"

# ===========================================================================
# MOTD — Reveals some system info (intentional — adds to realism)
# ===========================================================================
log_section "MOTD Banner"

# The banner hints at the system's purpose without naming specific vulns.
# Students who read carefully gain clues about what to look for.
set system login banner pre-login "
*******************************************************************************
*  SCPS Network Infrastructure Router — scps-router01.lab.scps.local         *
*  Authorised access only.  All sessions are monitored.                       *
*  Contact: labadmin@scps.local  |  Location: Server Room A                  *
*******************************************************************************
"

set system login banner post-login "
Welcome to scps-router01.
Last login: Use 'show log' to view system messages.
Running VyOS 1.4 LTS
"

log_info "Login banners configured."

# ===========================================================================
# HARDWARE COMPATIBILITY — Hyper-V offloading
# ===========================================================================
log_section "Hyper-V Hardware Compatibility"

# Disable checksum offloading for better Hyper-V compatibility.
# These are VyOS ethtool-style options applied at boot.
set interfaces ethernet eth0 offload sg 'disable'
set interfaces ethernet eth0 offload tso 'disable'
set interfaces ethernet eth0 offload gso 'disable'
set interfaces ethernet eth1 offload sg 'disable'
set interfaces ethernet eth1 offload tso 'disable'
set interfaces ethernet eth1 offload gso 'disable'
log_info "Hyper-V offloading disabled on eth0 and eth1."

# ===========================================================================
# COMMIT AND SAVE
# ===========================================================================
log_section "Committing Configuration"

commit
COMMIT_EXIT=$?

if [ $COMMIT_EXIT -ne 0 ]; then
    log_warn "commit returned non-zero ($COMMIT_EXIT) — check for validation errors above."
    log_warn "Attempting to save anyway..."
fi

save
log_ok "Configuration committed and saved to /config/config.boot"

exit    # Exit configure mode

# ===========================================================================
# WRITE DEPLOY-TIME IP CUSTOMISATION SCRIPT
# ===========================================================================
log_section "Deploy-Time IP Script"

# Write the script that Set-VMNetworkConfig.ps1 calls via SSH to set the
# actual student IP address at deployment time.
sudo mkdir -p /opt/scps-lab
sudo tee /opt/scps-lab/deploy-set-ip.sh > /dev/null << 'DEPLOYEOF'
#!/usr/bin/env bash
# =============================================================================
# deploy-set-ip.sh — Sets the eth1 IP address at deploy time.
# Called by the orchestration platform after VM clone.
#
# Usage:
#   vbash /opt/scps-lab/deploy-set-ip.sh <ip-address> <prefix-len> [gateway]
#
# Example:
#   vbash /opt/scps-lab/deploy-set-ip.sh 10.1.5.2 24 10.1.5.1
# =============================================================================
source /opt/vyatta/etc/functions/script-template

IP_ADDR="${1:?Usage: $0 <ip> <prefix> [gateway]}"
PREFIX="${2:?}"
GATEWAY="${3:-}"

configure

# Remove old placeholder IP if present
delete interfaces ethernet eth1 address '10.{CLASS_ID}.{STUDENT_ID}.2/24' 2>/dev/null || true

# Set new IP
set interfaces ethernet eth1 address "${IP_ADDR}/${PREFIX}"

# Update static default route if gateway provided
if [[ -n "$GATEWAY" ]]; then
    delete protocols static route '0.0.0.0/0' 2>/dev/null || true
    set protocols static route '0.0.0.0/0' next-hop "$GATEWAY"
fi

commit
save
exit

echo "eth1 set to ${IP_ADDR}/${PREFIX}"
[[ -n "$GATEWAY" ]] && echo "Default route: 0.0.0.0/0 via $GATEWAY"
DEPLOYEOF

sudo chmod 755 /opt/scps-lab/deploy-set-ip.sh
log_ok "Deploy-time IP script written to /opt/scps-lab/deploy-set-ip.sh"

# ===========================================================================
# SYSPREP — Clear history and prepare for imaging
# ===========================================================================
log_section "Sysprep"

log_info "Clearing bash history..."
history -c 2>/dev/null || true
: > /home/vyos/.bash_history 2>/dev/null || true
: > /root/.bash_history 2>/dev/null || true

log_info "Clearing tmp files..."
sudo rm -rf /tmp/* 2>/dev/null || true

log_info "Clearing logs..."
sudo find /var/log -type f -name '*.log' -exec truncate -s 0 {} \; 2>/dev/null || true

log_info "Flushing filesystem..."
sync

log_ok "Sysprep complete."

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================
log_section "Build Complete — Vulnerability Summary"

echo ""
echo "================================================================="
echo "  SCPS CyberLab — $IMAGE_NAME Build Complete"
echo "================================================================="
echo ""
echo "  Admin credentials : vyos / vyos123"
echo "  eth0 (WAN)        : DHCP (attack-net side)"
echo "  eth1 (LAN)        : 10.{CLASS_ID}.{STUDENT_ID}.2/24 (placeholder)"
echo ""
echo "  INTENTIONAL VULNERABILITIES:"
echo "  VULN-1  Telnet on port 23, SSH absent"
echo "  VULN-2  SNMP v2c community 'public' open to 0.0.0.0/0"
echo "  VULN-3  RIP v2 with no authentication on eth1"
echo "  VULN-4  NTP with no authentication or query restrictions"
echo "  VULN-5  Weak password: vyos / vyos123"
echo "  VULN-6  No firewall rules (all traffic passes)"
echo "  VULN-7  DNS open recursive resolver on eth0 + eth1"
echo ""
echo "  Deploy hook       : /opt/scps-lab/deploy-set-ip.sh"
echo "  Build log         : $LOGFILE"
echo ""
echo "  NEXT STEP: Shut down and store VHDX as:"
echo "  C:\\CyberLab\\Templates\\vyos-1.4-vulnerable.vhdx"
echo ""
echo "================================================================="

log_info "Shutting down in 5 seconds..."
sleep 5
sudo /sbin/poweroff
