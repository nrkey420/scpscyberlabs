# Ubuntu Web Server — Base Image Build Guide (Intentionally Vulnerable)

| Field | Value |
|-------|-------|
| **Image name** | `ubuntu-server-22.04-web` |
| **VHDX path** | `C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team — DMZ target), Lab 3 (SOC Analyst — victim web server) |
| **Role** | Intentionally vulnerable Linux web server |
| **Build script** | `Scripts/BaseImages/Linux/Build-UbuntuWebServer.sh` |
| **Script runs** | Inside the VM as root, after OS installation |
| **Resources** | 1 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS (amd64) |

> **WARNING:** This VM contains intentional security vulnerabilities for educational purposes. Every weakness listed in this document is deliberate. Never expose this image to production networks, internet-facing infrastructure, or any environment where real data is present. It must be deployed only within isolated Hyper-V private virtual switches with no external routing.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Running the Build Script](#4-running-the-build-script)
5. [Intentional Vulnerabilities](#5-intentional-vulnerabilities)
6. [What the Script Configures](#6-what-the-script-configures)
7. [Network Interfaces](#7-network-interfaces)
8. [Default Credentials After Build](#8-default-credentials-after-build)
9. [Verification Steps](#9-verification-steps)
10. [Snapshot and Storage](#10-snapshot-and-storage)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

### ISO Download

Use the Ubuntu Server 22.04 LTS (Jammy Jellyfish) installer ISO. Do not use the Desktop ISO.

```
URL: https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso
SHA256: verify at https://releases.ubuntu.com/22.04/SHA256SUMS
```

Verify the checksum on the host:

```powershell
Get-FileHash -Algorithm SHA256 "ubuntu-22.04.5-live-server-amd64.iso"
```

### Host Requirements

- At least 30 GB free disk space for the build VM VHDX.
- Internet connectivity from the VM during build (for `apt`, GitHub clone of DVWA).
- The build takes approximately 30–45 minutes.

---

## 2. Hyper-V VM Creation

Create the build VM with these exact settings:

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Virtual switch | External-Internet (internet access required for apt and DVWA git clone) |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Installation media | Ubuntu Server 22.04 ISO |

Disable Secure Boot after creation:

```powershell
# Ubuntu Server supports Secure Boot, but disabling simplifies the build
# Either Secure Boot policy works; disabling is safer for compatibility
Set-VMFirmware -VMName "ubuntu-web-build" -EnableSecureBoot Off
```

Alternatively, if keeping Secure Boot enabled, change the template to **Microsoft UEFI Certificate Authority** in VM Settings > Security.

---

## 3. OS Installation

Work through the Ubuntu Server installer with these settings:

| Installer Step | Setting |
|---------------|---------|
| Language | English |
| Keyboard | Match your physical keyboard |
| Type of install | Ubuntu Server (minimal — not Ubuntu Server (minimized)) |
| Network | Accept DHCP on the management interface |
| Proxy | Leave blank unless your site requires a proxy |
| Mirror | Accept default or select a local mirror |
| Storage | Use entire disk; LVM not required; single partition |
| Server name | `ubuntu-web` (overridden at deploy) |
| Username | `webadmin` |
| Password | Set a temporary password (overwritten by build script) |
| SSH | Check **Install OpenSSH server** |
| Featured snaps | **Do not select any snaps** |

After reboot, log in as `webadmin`, then switch to root:

```bash
sudo -i
```

---

## 4. Running the Build Script

Transfer `Build-UbuntuWebServer.sh` to the VM and execute as root:

```bash
# From the host
scp Scripts/BaseImages/Linux/Build-UbuntuWebServer.sh webadmin@<VM-IP>:/home/webadmin/

# In the VM
sudo -i
chmod +x /home/webadmin/Build-UbuntuWebServer.sh
/home/webadmin/Build-UbuntuWebServer.sh
```

The script logs to `/var/log/lab-build.log`. All output also prints to the console. The VM powers off automatically when the build completes.

> **Do not interrupt the script.** If interrupted, the MySQL or DVWA configuration may be in a partial state. Reinstall the OS from the Ubuntu ISO and start over.

---

## 5. Intentional Vulnerabilities

This image is deliberately configured to be insecure. Each vulnerability is listed below with its educational rationale.

> **Instructor note:** Share this table with students only after they have completed the lab to avoid telegraphing attack paths. The lab guide for students does not list these vulnerabilities explicitly.

| Vulnerability | Technical Detail | Educational Purpose |
|--------------|-----------------|-------------------|
| **MySQL exposed on 0.0.0.0:3306** | `bind-address = 0.0.0.0` in `/etc/mysql/mysql.conf.d/mysqld.cnf`. The `dvwa` database user is also granted access from `'%'` (any host). | Teaches database exposure risks. Students discover open 3306 during `nmap` reconnaissance and can connect remotely: `mysql -u dvwa -p -h <IP>`. |
| **SSH root login enabled** | `PermitRootLogin yes` and `PasswordAuthentication yes` in `/etc/ssh/sshd_config`. | Teaches SSH hardening. Students can brute-force or use found credentials to SSH as root directly without privilege escalation. |
| **DVWA security level = low** | `$_DVWA['default_security_level'] = 'low'` in `/var/www/html/dvwa/config/config.inc.php`. | Enables the full range of DVWA attacks (SQL injection, XSS, file upload, command injection, CSRF) at maximum exploitability. |
| **PHP allow_url_include = On** | Set in `/etc/php/8.1/apache2/php.ini`. | Enables Remote File Inclusion (RFI) attacks. Students can load PHP code from a URL they control and achieve RCE. |
| **fail2ban installed but disabled** | Service is stopped and disabled; `jail.local` has `maxretry = 99999` and `enabled = false`. A dummy config exists to make it look present. | Teaches brute force prevention. Students run `systemctl status fail2ban` during enumeration and see it is inactive, confirming unrestricted brute force is possible. |
| **Permissive iptables rules** | Default policy ACCEPT on all chains; TCP 3306 explicitly allowed inbound. | Teaches firewall configuration. `nmap` shows all ports open with no filtering. |
| **Uploads directory world-writable and PHP-executable** | `/var/www/html/uploads/` has chmod 777 and an `.htaccess` that enables PHP engine in uploads. | Enables PHP web shell upload and execution. Students upload a `.php` file through the file upload form and trigger RCE. |
| **Verbose Apache headers** | `ServerTokens Full`, `ServerSignature On`, `TraceEnable On` in Apache config. | Teaches information disclosure. `curl -I http://<IP>` reveals the exact Apache and PHP versions, accelerating CVE lookups. |
| **Missing security headers** | X-Frame-Options, X-Content-Type-Options, X-XSS-Protection headers are unset. | Teaches browser security hardening and clickjacking/XSS risks. |
| **Credentials in /home/webadmin/.bash_history** | Build script plants a realistic shell history containing MySQL passwords, `cat /etc/shadow`, SSH key paths. | Post-compromise artifact. Students find the history after gaining initial shell access, demonstrating the value of clearing history and the risk of credential leakage. |
| **Planted SSH key in /root/.ssh/** | A 2048-bit RSA keypair is generated; the public key is added to `/root/.ssh/authorized_keys`. | Teaches SSH key mismanagement. The private key (`/root/.ssh/id_rsa`) is discoverable during post-exploitation. |
| **CTF flags in /secret/ and /root/flags/** | `flag1.txt` in the web-accessible `/secret/` directory; `root_flag.txt` accessible only after root escalation. | Provides structured objectives and validates student progress through the CyberLab platform. |
| **Custom PHP app with SQLi + XSS + unrestricted upload** | `index.php` in the web root contains all three vulnerabilities in addition to DVWA. | Gives students a custom target beyond DVWA to exploit, simulating a real-world application. |

---

## 6. What the Script Configures

### System Update (Section 1)

The system is fully updated before any configuration. This ensures the base OS is current while the intentional vulnerabilities are applied on top.

### Package Installation (Section 2)

Installed packages: `apache2`, `php8.1` (and modules: mysql, gd, curl, xml, mbstring), `mysql-server`, `git`, `curl`, `wget`, `python3`, `python3-pip`, `unzip`, `net-tools`, `vim`, `fail2ban`. The fail2ban package is intentionally installed but not activated.

### Hyper-V Integration Services (Section 3)

`linux-cloud-tools-virtual`, `linux-tools-virtual` (or fallback to generic variants) are installed. Hyper-V kernel modules are loaded and persisted in `/etc/modules-load.d/hyperv.conf`.

### MySQL Configuration (Section 4)

MySQL is started and configured: the root password is set (randomly generated and saved to `/root/.lab-credentials`). The `dvwa` database and `dvwa` user are created with both `localhost` and `%` grants. The `bind-address` in the MySQL config is changed from `127.0.0.1` to `0.0.0.0` — this is the intentional database exposure vulnerability.

### Apache Configuration (Section 5)

Apache modules `rewrite`, `headers`, and `php8.1` are enabled. A custom `lab-settings.conf` sets `ServerTokens Full`, `ServerSignature On`, `TraceEnable On`, and explicitly unsets security headers. The default virtual host allows `AllowOverride All` and `Options Indexes` in the web root.

### DVWA Deployment (Section 6)

DVWA is cloned from `https://github.com/digininja/DVWA` into `/var/www/html/dvwa/`. The configuration file is copied from the distributed template and patched with `sed`:

- Database credentials set to the generated `dvwa` user password.
- `default_security_level` set to `low`.
- reCAPTCHA keys left blank (allows CSRF and other captcha-protected attacks to work without an API key).

PHP settings patched: `allow_url_include = On`, `display_errors = On`, `allow_url_fopen = On`.

Permissions set: `dvwa/hackable/uploads/` is chmod 777 (world-writable — required by DVWA file upload module).

### Custom Vulnerable PHP Application (Section 7)

`/var/www/html/index.php` is a hand-crafted PHP application containing a SQL injection endpoint (`GET ?id=`), a reflected XSS endpoint (`GET ?search=`), and an unrestricted file upload form. The uploads directory at `/var/www/html/uploads/` has an `.htaccess` that enables PHP execution of uploaded files.

### Secret Directory and Flag Files (Section 8)

`/var/www/html/secret/` contains `flag1.txt` (directory enumeration objective) and `config.bak` (contains the DVWA database password in plaintext — simulates a configuration backup accidentally left on the web server). `/root/flags/root_flag.txt` is accessible only after privilege escalation to root.

### SSH Configuration — Intentionally Weak (Section 9)

`/etc/ssh/sshd_config` is written with `PermitRootLogin yes` and `PasswordAuthentication yes`. SSH logging is set to `VERBOSE` so Blue Team students can detect SSH brute force events in the auth log. TCP forwarding is enabled to allow the web server to serve as a pivot point.

### Planted Shell History (Section 10)

`/home/webadmin/.bash_history` is populated with commands including MySQL connections with passwords, `cat /etc/shadow`, `cat /root/.ssh/id_rsa`, and `wget` retrieving a web shell — all common post-exploitation discovery targets.

### User Accounts (Section 11)

`webadmin` is created with sudo privileges. The password is randomly generated and saved to the credentials file.

### Fail2ban — Intentionally Disabled (Section 12)

fail2ban is stopped and disabled. A `jail.local` with `maxretry = 99999` and `[sshd] enabled = false` is written to make the configuration look present but non-functional to students who inspect it.

### Firewall — Intentionally Permissive (Section 13)

iptables default policy is ACCEPT on all chains. Explicit ACCEPT rules are added for ports 22, 80, 443, 8080, and **3306** (MySQL exposed to all). Rules are saved to `/etc/iptables/rules.v4`.

### Sysprep (Section 15)

Root bash history is cleared. Webadmin's `.bash_history` is **intentionally preserved** because it is a planted teaching artifact. SSH host keys are removed with a firstboot regeneration service created. Machine-id is cleared. Logs are truncated. Free space is zeroed.

---

## 7. Network Interfaces

Single network adapter (`eth0`). In Lab 1, this is connected to `dmz-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.30`. In Lab 3, it is connected to the SOC class network and assigned an appropriate address as defined in `Templates/03-soc-analyst.json`.

---

## 8. Default Credentials After Build

| Account | Password | Privileges | Notes |
|---------|----------|-----------|-------|
| `webadmin` | Randomly generated, see `/root/.lab-credentials` | sudo | Deploy-time credentials override this |
| `root` (SSH) | Same as webadmin (password auth enabled) | Full | Intentional SSH root login enabled |
| MySQL `root` | Randomly generated, see `/root/.lab-credentials` | Full MySQL | Local socket auth |
| MySQL `dvwa` | Randomly generated, see `/root/.lab-credentials` | dvwa database | Remote access allowed (`%` grant) |

---

## 9. Verification Steps

### Step 1 — Web Application

From a browser or curl on the management network:

```bash
# DVWA setup page should return 200
curl -s -o /dev/null -w "%{http_code}" http://<VM-IP>/dvwa/setup.php
# Expected: 200

# Custom PHP app
curl -s -o /dev/null -w "%{http_code}" http://<VM-IP>/
# Expected: 200

# Secret directory
curl -s -o /dev/null -w "%{http_code}" http://<VM-IP>/secret/flag1.txt
# Expected: 200
```

### Step 2 — MySQL External Access

```bash
# From a separate VM on the same network
mysql -u dvwa -p<DVWA_DB_PASS> -h <VM-IP> dvwa -e "SHOW TABLES;"
# Should return DVWA table list, confirming external MySQL access
```

### Step 3 — SSH Root Login

```bash
ssh root@<VM-IP>
# Should succeed with the webadmin/root password from credentials file
```

### Step 4 — Confirm fail2ban is Inactive

```bash
# On the VM
systemctl status fail2ban
# Status should be: inactive (dead)
```

### Step 5 — Confirm PHP allow_url_include

```bash
php8.1 -r "echo ini_get('allow_url_include');"
# Should output: 1
```

---

## 10. Snapshot and Storage

After verification:

1. Shut down the VM.
2. Copy the VHDX to `C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx`.
3. Mark read-only:

```powershell
Set-ItemProperty -Path "C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx" -Name IsReadOnly -Value $true
```

4. Delete the build VM and its temporary VHDX.

> **Important:** Because this image contains intentional vulnerabilities, treat the template VHDX itself as a sensitive asset. Restrict access to `C:\CyberLab\Templates\` so that only Administrators and the App Pool identity can read the directory. Students must not have access to the host filesystem.

---

## 11. Troubleshooting

### DVWA Setup Page Shows Database Error

**Symptom:** Visiting `http://<IP>/dvwa/setup.php` shows "Could not connect to the database."

**Cause:** MySQL may not be running, or the `dvwa` database credentials in `config.inc.php` do not match the MySQL user.

**Fix:**

```bash
# On the VM
systemctl status mysql
systemctl start mysql

# Verify the credentials file matches config.inc.php
grep DVWA_DB /root/.lab-credentials
grep db_password /var/www/html/dvwa/config/config.inc.php
# The passwords should match
```

### Apache Not Starting

**Symptom:** Port 80 is not accessible; `systemctl status apache2` shows failed.

**Cause:** PHP module version mismatch, or the DVWA `.htaccess` has a syntax error.

**Fix:**

```bash
apache2ctl configtest
# Fix any reported syntax errors
systemctl restart apache2
```

### MySQL External Access Refused

**Symptom:** `mysql -u dvwa -h <IP>` returns "Connection refused."

**Cause:** The firewall rules were not applied, or `bind-address` was not changed to `0.0.0.0`.

**Fix:**

```bash
# On the VM
grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf
# Should show: bind-address = 0.0.0.0
# If not, edit and restart MySQL
systemctl restart mysql

# Check iptables
iptables -L INPUT -n | grep 3306
```
