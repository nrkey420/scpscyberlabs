# WebGoat — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `webgoat-2023.8` |
| **VHDX path** | `C:\CyberLab\Templates\webgoat-2023.8.vhdx` |
| **Used in** | Lab 2 (Web App Pentest) |
| **Role** | Per-student intentionally vulnerable Java web application for guided learning |
| **Build script** | None — WebGoat is installed as a systemd service running a Spring Boot JAR |
| **Resources** | 1 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Installing Java](#4-installing-java)
5. [Deploying WebGoat as a systemd Service](#5-deploying-webgoat-as-a-systemd-service)
6. [WebGoat Lesson Modules Relevant to Lab 2](#6-webgoat-lesson-modules-relevant-to-lab-2)
7. [Java Process Management](#7-java-process-management)
8. [Network Interfaces](#8-network-interfaces)
9. [Default Credentials After Build](#9-default-credentials-after-build)
10. [Verification Steps](#10-verification-steps)
11. [Snapshot and Storage](#11-snapshot-and-storage)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

### Download WebGoat

WebGoat is distributed as an executable JAR file. Download the 2023.8 release from the official GitHub repository:

```
URL: https://github.com/WebGoat/WebGoat/releases/tag/v2023.8
File: webgoat-2023.8.jar
```

Or use `curl` during the VM build:

```bash
curl -L -o /opt/webgoat/webgoat.jar \
    "https://github.com/WebGoat/WebGoat/releases/download/v2023.8/webgoat-2023.8.jar"
```

### Java Requirement

WebGoat 2023.8 requires Java 17+. Use the OpenJDK 17 package from Ubuntu's apt repository.

### Build Time

Approximately 20–25 minutes.

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Network adapter | External-Internet (for apt and JAR download) |

---

## 3. OS Installation

| Setting | Value |
|---------|-------|
| Server name | `webgoat` |
| Username | `webgoatadmin` |
| SSH | Install OpenSSH server |
| Snaps | None |

After reboot: `sudo -i`.

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
```

---

## 4. Installing Java

```bash
apt-get install -y openjdk-17-jre-headless curl wget net-tools vim

# Verify Java version
java -version
# Expected: openjdk version "17.x.x"
```

---

## 5. Deploying WebGoat as a systemd Service

```bash
# Create the WebGoat user (no login shell — service account only)
useradd -r -s /bin/false -d /opt/webgoat webgoat

# Create directories
mkdir -p /opt/webgoat
mkdir -p /var/log/webgoat

# Download WebGoat JAR
curl -L -o /opt/webgoat/webgoat.jar \
    "https://github.com/WebGoat/WebGoat/releases/download/v2023.8/webgoat-2023.8.jar"

chown -R webgoat:webgoat /opt/webgoat /var/log/webgoat
chmod 750 /opt/webgoat
chmod 640 /opt/webgoat/webgoat.jar

# Create systemd service unit
cat > /etc/systemd/system/webgoat.service << 'EOF'
[Unit]
Description=SCPS CyberLab — WebGoat 2023.8
Documentation=https://github.com/WebGoat/WebGoat
After=network.target

[Service]
Type=simple
User=webgoat
Group=webgoat
WorkingDirectory=/opt/webgoat

# Bind WebGoat to all interfaces on port 8080
# --server.address=0.0.0.0 makes it accessible from the lab network
ExecStart=/usr/bin/java -jar /opt/webgoat/webgoat.jar \
    --server.port=8080 \
    --server.address=0.0.0.0 \
    --webgoat.host=0.0.0.0 \
    --webwolf.host=0.0.0.0 \
    --webwolf.port=9090

StandardOutput=append:/var/log/webgoat/webgoat.log
StandardError=append:/var/log/webgoat/webgoat.log

Restart=on-failure
RestartSec=10
TimeoutStartSec=120

# Security hardening for the service process
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/opt/webgoat /var/log/webgoat /home/webgoat

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable webgoat
systemctl start webgoat

# Wait for WebGoat to start (Spring Boot takes 30-60 seconds on first run)
echo "Waiting 90 seconds for WebGoat to start..."
sleep 90

# Verify the service started
systemctl status webgoat
```

### WebWolf

WebGoat 2023.8 includes WebWolf — a companion service on port 9090 used for simulating attacker-controlled servers (receives webhooks, hosts landing pages, etc.). WebWolf is started automatically on port 9090 by the same JAR with `--webwolf.port=9090`.

---

## 6. WebGoat Lesson Modules Relevant to Lab 2

The following WebGoat modules align directly with the Lab 2 (Web App Pentest) learning objectives. Instructors should direct students to complete these modules in this order.

| Module Path in WebGoat | Topic | Lab 2 Connection |
|----------------------|-------|-----------------|
| **Introduction > HTTP Basics** | HTTP request/response fundamentals | Foundation for all web attacks |
| **Introduction > HTTP Proxies** | Configuring Burp Suite as an intercepting proxy | Required before other modules — students set up Burp |
| **A1 — Injection > SQL Injection (intro)** | Basic SQL injection syntax and error-based extraction | Objective 1 preparation |
| **A1 — Injection > SQL Injection (advanced)** | UNION-based injection, extracting multi-table data | Objective 1 depth |
| **A2 — Broken Authentication > Authentication Bypasses** | Bypassing login via parameter manipulation | Session management concepts |
| **A3 — Sensitive Data Exposure > Insecure Login** | Intercepting unencrypted credentials | Objective for network sniffing section |
| **A7 — XSS > Cross-Site Scripting** | Reflected and DOM-based XSS | Objective 2 preparation |
| **A7 — XSS > XSS (stored)** | Stored XSS and session hijacking | Objective 2 core |
| **A8 — Insecure Deserialization** | Java deserialization attacks | Advanced students |
| **A10 — Server-Side Request Forgery** | SSRF concepts and exploitation | Lab 2 stretch objective |

---

## 7. Java Process Management

WebGoat runs as a Spring Boot application inside the `webgoat` systemd service. Use the following commands for all management tasks.

### Service Control

```bash
# Start WebGoat
systemctl start webgoat

# Stop WebGoat
systemctl stop webgoat

# Restart WebGoat (clears all in-memory session data; enrolled lesson progress is reset)
systemctl restart webgoat

# Check service status and last 50 log lines
systemctl status webgoat -l

# View live log output
journalctl -u webgoat -f
# Or directly from the log file:
tail -f /var/log/webgoat/webgoat.log
```

### Verify WebGoat is Listening

```bash
ss -tlnp | grep -E '8080|9090'
# Expected:
# LISTEN  0  100  0.0.0.0:8080  ...  java
# LISTEN  0  100  0.0.0.0:9090  ...  java
```

### Check the Java Process

```bash
ps aux | grep webgoat
# Shows the java process with --server.port=8080 and --webwolf.port=9090 arguments
```

### Student Progress Reset

WebGoat stores lesson progress in a local database within the service's working directory. To reset all student progress without redeploying the VM (for repeated lab runs):

```bash
systemctl stop webgoat
rm -rf /opt/webgoat/.webgoat/
systemctl start webgoat
# Allow 60-90 seconds for Spring Boot to reinitialise
```

---

## 8. Network Interfaces

Single adapter (`eth0`). In Lab 2, connected to `pentest-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.21`.

Students access WebGoat at: `http://10.{ClassId}.{StudentId}.21:8080/WebGoat`

Students access WebWolf at: `http://10.{ClassId}.{StudentId}.21:9090/WebWolf`

---

## 9. Default Credentials After Build

WebGoat does not have pre-seeded user accounts. Students register their own accounts at first access. The registration endpoint is open — any user can create an account during the lab session.

| Service | URL | Credentials |
|---------|-----|------------|
| WebGoat | `http://<IP>:8080/WebGoat` | Student self-registers |
| WebWolf | `http://<IP>:9090/WebWolf` | Same credentials as WebGoat registration |
| OS (`webgoatadmin`) | SSH port 22 | See `/root/.lab-credentials` |

---

## 10. Verification Steps

### Step 1 — Service Running

```bash
systemctl is-active webgoat
# Expected: active
```

### Step 2 — Web Interface

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/WebGoat/login
# Expected: 200
```

### Step 3 — WebWolf

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/WebWolf/login
# Expected: 200
```

### Step 4 — Register a Test Account

From a browser, navigate to `http://<VM-IP>:8080/WebGoat` and register a test account. Confirm the main lesson menu loads after registration. Delete the test account before capturing the VHDX.

---

## 11. Snapshot and Storage

```powershell
Stop-VM -Name "webgoat-build" -Force
Move-Item "webgoat-build.vhdx" "C:\CyberLab\Templates\webgoat-2023.8.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\webgoat-2023.8.vhdx" -Name IsReadOnly -Value $true
```

---

## 12. Troubleshooting

### WebGoat Fails to Start — Port Already in Use

```bash
ss -tlnp | grep 8080
# If another service is on 8080, stop it
# Or change the WebGoat port in the systemd unit and restart
```

### WebGoat Starts But Returns 404 for /WebGoat

**Cause:** Spring Boot takes 60–90 seconds to start. The service may show as `active` before the HTTP server is ready.

**Fix:** Wait and retry:

```bash
sleep 30
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/WebGoat/login
```

If it still fails, check the log:

```bash
tail -100 /var/log/webgoat/webgoat.log | grep -i "started\|error\|exception"
```

### Out of Memory During WebGoat Startup

**Symptom:** `java.lang.OutOfMemoryError` in the log.

**Cause:** The VM has insufficient heap space. WebGoat requires approximately 512 MB heap.

**Fix:** Add JVM heap flags to the ExecStart in the systemd unit:

```
ExecStart=/usr/bin/java -Xms256m -Xmx1g -jar /opt/webgoat/webgoat.jar ...
```

```bash
systemctl daemon-reload
systemctl restart webgoat
```
