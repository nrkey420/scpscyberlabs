# DVWA — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `dvwa-latest` |
| **VHDX path** | `C:\CyberLab\Templates\dvwa-latest.vhdx` |
| **Used in** | Lab 2 (Web App Pentest) exclusively |
| **Role** | Standalone DVWA instance — per-student web vulnerability target |
| **Build script** | None — DVWA is installed manually on a LAMP stack; this guide documents each step |
| **Resources** | 1 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS |

> **Note:** This image differs from the Ubuntu Web Server (`ubuntu-server-22.04-web`) in that it contains **only DVWA** — it does not include the custom vulnerable PHP app, planted shell history, or all the additional configurations. This gives Lab 2 students a cleaner, purpose-built DVWA target with controlled difficulty. The Ubuntu Web Server image is used in Labs 1 and 3 as a richer multi-vulnerability target.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Installing the LAMP Stack](#4-installing-the-lamp-stack)
5. [Deploying DVWA](#5-deploying-dvwa)
6. [DVWA Vulnerability Modules and Lab Objectives](#6-dvwa-vulnerability-modules-and-lab-objectives)
7. [Security Levels](#7-security-levels)
8. [MySQL Credentials and Database Reset](#8-mysql-credentials-and-database-reset)
9. [Network Interfaces](#9-network-interfaces)
10. [Default Credentials After Build](#10-default-credentials-after-build)
11. [Verification Steps](#11-verification-steps)
12. [Snapshot and Storage](#12-snapshot-and-storage)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

Download the Ubuntu Server 22.04 LTS ISO and the DVWA source code via `git` (performed during the build, so internet access is required).

Build time: approximately 25–30 minutes.

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Network adapter | External-Internet (for apt and git clone during build) |

Disable Secure Boot or use the Microsoft UEFI Certificate Authority template.

---

## 3. OS Installation

| Setting | Value |
|---------|-------|
| Server name | `dvwa` |
| Username | `dvwaadmin` |
| SSH | Install OpenSSH server |
| Snaps | None |

After reboot: `sudo -i`.

Update the system:

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
```

---

## 4. Installing the LAMP Stack

```bash
# Install Apache, PHP 8.1, and MySQL
apt-get install -y \
    apache2 \
    php8.1 php8.1-mysql php8.1-gd php8.1-curl php8.1-xml php8.1-mbstring \
    mysql-server \
    git curl wget unzip net-tools vim

# Enable Apache modules
a2enmod rewrite php8.1
systemctl enable apache2 mysql
systemctl start apache2 mysql

# Configure PHP for DVWA
PHP_INI="/etc/php/8.1/apache2/php.ini"
sed -i 's/^allow_url_include = .*/allow_url_include = On/' "$PHP_INI"
sed -i 's/^display_errors = .*/display_errors = On/' "$PHP_INI"
sed -i 's/^allow_url_fopen = .*/allow_url_fopen = On/' "$PHP_INI"

systemctl restart apache2
```

---

## 5. Deploying DVWA

```bash
# Generate MySQL credentials
DVWA_DB_PASS=$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 20)
MYSQL_ROOT_PASS=$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 20)

# Record credentials
cat > /root/.lab-credentials << EOF
IMAGE=dvwa-latest
MYSQL_ROOT_PASS=$MYSQL_ROOT_PASS
DVWA_DB_USER=dvwa
DVWA_DB_PASS=$DVWA_DB_PASS
DVWA_APP_USER=admin
DVWA_APP_PASS=password
EOF
chmod 600 /root/.lab-credentials

# Configure MySQL
mysql -u root << SQLEOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY '${DVWA_DB_PASS}';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

# Clone DVWA
git clone https://github.com/digininja/DVWA /var/www/html/dvwa

# Configure DVWA
DVWA_CONFIG="/var/www/html/dvwa/config/config.inc.php"
cp /var/www/html/dvwa/config/config.inc.php.dist "$DVWA_CONFIG"

sed -i "s/\$_DVWA\[ 'db_password' \] = .*/\$_DVWA[ 'db_password' ] = '${DVWA_DB_PASS}';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_user' \] = .*/\$_DVWA[ 'db_user' ] = 'dvwa';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'db_database' \] = .*/\$_DVWA[ 'db_database' ] = 'dvwa';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'default_security_level' \] = .*/\$_DVWA[ 'default_security_level' ] = 'low';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'recaptcha_public_key' \] = .*/\$_DVWA[ 'recaptcha_public_key' ] = '';/" "$DVWA_CONFIG"
sed -i "s/\$_DVWA\[ 'recaptcha_private_key' \] = .*/\$_DVWA[ 'recaptcha_private_key' ] = '';/" "$DVWA_CONFIG"

# Permissions
chown -R www-data:www-data /var/www/html/dvwa
chmod -R 755 /var/www/html/dvwa
chmod 777 /var/www/html/dvwa/hackable/uploads/
chmod 777 /var/www/html/dvwa/config/
chmod 666 /var/www/html/dvwa/external/phpids/0.6/lib/IDS/tmp/phpids_log.txt 2>/dev/null || true

# Set DVWA as the default web root
cat > /etc/apache2/sites-available/000-default.conf << 'APACHECONF'
<VirtualHost *:80>
    ServerAdmin admin@dvwa.lab
    DocumentRoot /var/www/html
    Redirect permanent / /dvwa/

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
APACHECONF

systemctl restart apache2
```

---

## 6. DVWA Vulnerability Modules and Lab Objectives

Each DVWA module maps directly to a Lab 2 objective. The table below lists every module present in DVWA, its connection to Lab 2, and notes for the instructor.

| DVWA Module | Lab 2 Objective | Objective Description | Notes for Instructors |
|-------------|:---:|---|---|
| **SQL Injection** | 1 | Extract user credentials from the database using SQL injection | Classic blind and error-based injection. At security level `low`, no protection is applied. Students should extract the `admin` password hash. |
| **SQL Injection (Blind)** | 1 | (Extension of Objective 1) | Boolean-based blind SQLi — used by advanced students who complete Objective 1 quickly |
| **XSS (Reflected)** | 2 | Execute a reflected XSS payload to steal a session cookie | At level `low`, no encoding is applied. Students inject `<script>alert(document.cookie)</script>`. |
| **XSS (Stored)** | 2 | Store a persistent XSS payload in the guestbook | At level `low`, script tags in the message field are stored verbatim and executed on each page load. |
| **File Upload** | 3 | Upload a PHP web shell and achieve remote code execution | At level `low`, only file size is checked — not MIME type or extension. Students upload a PHP shell and call it via the browser. |
| **Command Injection** | 4 | Inject OS commands through the ping form and read `/etc/passwd` | At level `low`, the input is passed directly to `shell_exec()`. Students chain commands with `; cat /etc/passwd`. |
| **CSRF** | 5 | Exploit a CSRF vulnerability to change the admin password | At level `low`, no token validation is performed. Students craft a malicious HTML page and trick a user (or manually trigger the request) to change the password. |
| **Brute Force** | Supplemental | Brute force the DVWA login page | Used if Objective 1 proves too difficult; gives students a foothold via Burp Suite + Intruder. |
| **File Inclusion** | Supplemental | Local and remote file inclusion via the `page` parameter | `allow_url_include = On` enables RFI. Students load PHP code from a URL they control. |
| **Insecure CAPTCHA** | Supplemental | Bypass the CAPTCHA on the password change form | reCAPTCHA keys are blank, making the captcha trivially bypassable. |

---

## 7. Security Levels

DVWA has four security levels that determine the strength of input validation applied to each module. The level is set globally for all modules.

| Level | Description | Lab Use |
|-------|-------------|---------|
| **Low** | No input sanitisation — all vulnerabilities fully exploitable | **Default for all Lab 2 deployments** |
| **Medium** | Partial sanitisation — most vulnerabilities still exploitable with evasion | Use for advanced students or challenge mode |
| **High** | Strong sanitisation — some modules no longer exploitable by standard techniques | Use for defensive analysis or demonstration |
| **Impossible** | Fully hardened — parameterised queries, CSP, token validation applied throughout | Use to demonstrate secure coding patterns |

### Changing the Security Level Mid-Lab (Instructor Only)

The instructor can change the security level without redeploying the VM:

**Option 1 — Via DVWA web interface:**

1. Log into DVWA at `http://<VM-IP>/dvwa/` with `admin` / `password`.
2. Navigate to **DVWA Security** in the left menu.
3. Select the desired level from the dropdown and click Submit.

**Option 2 — Via config file:**

```bash
# On the VM
sed -i "s/\$_DVWA\[ 'default_security_level' \] = .*/\$_DVWA[ 'default_security_level' ] = 'medium';/" \
    /var/www/html/dvwa/config/config.inc.php
# No Apache restart needed — config.inc.php is read on each request
```

Note: Changing `default_security_level` in `config.inc.php` only affects **new** user sessions. Students already logged in must log out and back in for the change to take effect.

---

## 8. MySQL Credentials and Database Reset

### Default DVWA Application Credentials

After DVWA's setup page (`/dvwa/setup.php`) creates the database, the default application login is:

| Username | Password |
|----------|---------|
| `admin` | `password` |
| `gordonb` | `abc123` |
| `1337` | `charley` |
| `pablo` | `letmein` |
| `smithy` | `password` |

These are DVWA default accounts stored in the `dvwa.users` table after database setup.

### MySQL Credentials (Database-Level)

| Account | Password |
|---------|----------|
| MySQL `root` | See `/root/.lab-credentials` |
| MySQL `dvwa` | See `/root/.lab-credentials` |

### Resetting the Database to a Clean State

If students have corrupted the DVWA database (e.g., by dropping tables via SQL injection), reset it using the DVWA setup page:

1. Navigate to `http://<VM-IP>/dvwa/setup.php`.
2. Click **Create / Reset Database**.
3. Log back in with `admin` / `password`.

Alternatively, from the command line on the VM:

```bash
# Drop and recreate the DVWA database
mysql -u root -p"${MYSQL_ROOT_PASS}" << 'SQLEOF'
DROP DATABASE IF EXISTS dvwa;
CREATE DATABASE dvwa;
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
# Then visit /dvwa/setup.php to recreate the tables
```

---

## 9. Network Interfaces

Single network adapter (`eth0`). In Lab 2, connected to `pentest-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.20`.

---

## 10. Default Credentials After Build

| Account | Credentials | Notes |
|---------|------------|-------|
| `dvwaadmin` (OS) | See `/root/.lab-credentials` | SSH access |
| DVWA app `admin` | `admin` / `password` | Web application login (set after running DVWA setup page) |
| MySQL `root` | See `/root/.lab-credentials` | Database root |
| MySQL `dvwa` | See `/root/.lab-credentials` | DVWA database user |

---

## 11. Verification Steps

### Step 1 — DVWA Setup Page

```bash
curl -s -o /dev/null -w "%{http_code}" http://<VM-IP>/dvwa/setup.php
# Expected: 200
```

### Step 2 — Database Setup

Visit `http://<VM-IP>/dvwa/setup.php` in a browser and click **Create / Reset Database**. The page should report all checks passed (PHP functions, MySQL, writable directories).

### Step 3 — Application Login

Navigate to `http://<VM-IP>/dvwa/` and log in as `admin` / `password`. The DVWA dashboard should load with the current security level shown as "Low".

### Step 4 — SQL Injection Module

Navigate to SQL Injection. Enter `1' OR '1'='1` in the User ID field. The application should return all users without a proper error — confirming the SQLi vulnerability is active.

### Step 5 — File Upload Module

Navigate to File Upload. Upload any file (e.g., a `.txt` file). The upload should succeed and display a link to the uploaded file. Confirm the upload directory path shown is `/var/www/html/dvwa/hackable/uploads/`.

---

## 12. Snapshot and Storage

Perform the database setup (click "Create / Reset Database" on the setup page) **before** shutting down and capturing the VHDX. This ensures the template already has the DVWA tables populated, so students do not need to run the setup step themselves.

After setup:

```powershell
# Shut down the VM first
Stop-VM -Name "dvwa-build" -Force

# Move VHDX to Templates
Move-Item "dvwa-build.vhdx" "C:\CyberLab\Templates\dvwa-latest.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\dvwa-latest.vhdx" -Name IsReadOnly -Value $true
```

---

## 13. Troubleshooting

### DVWA Setup Page Shows PHP Function Errors

**Symptom:** The setup page shows `allow_url_include: Disabled` or `allow_url_fopen: Disabled`.

**Fix:**

```bash
PHP_INI="/etc/php/8.1/apache2/php.ini"
grep allow_url_include "$PHP_INI"
# If it shows Off, fix it:
sed -i 's/^allow_url_include = .*/allow_url_include = On/' "$PHP_INI"
systemctl restart apache2
```

### MySQL Connection Refused

**Symptom:** DVWA setup page shows "Could not connect to the database service."

**Fix:**

```bash
systemctl status mysql
systemctl start mysql
# Verify the credentials in config.inc.php match .lab-credentials
grep db_password /var/www/html/dvwa/config/config.inc.php
cat /root/.lab-credentials | grep DVWA_DB_PASS
```

### SQL Injection Returns "Error: No results" Instead of User Data

**Symptom:** Entering `1` in the User ID field returns no results.

**Cause:** The DVWA database tables have not been created (setup page was not run).

**Fix:** Navigate to `/dvwa/setup.php` and click "Create / Reset Database."
