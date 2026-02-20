# OWASP Juice Shop — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `juice-shop-host` |
| **VHDX path** | `C:\CyberLab\Templates\juice-shop-host.vhdx` |
| **Used in** | Lab 2 (Web App Pentest) |
| **Role** | Per-student OWASP Juice Shop challenge platform — Docker-based |
| **Build script** | None — Docker and the Juice Shop container are installed manually |
| **Resources** | 1 vCPU, 2 GB RAM, 20 GB dynamic VHDX |
| **Base OS** | Ubuntu Server 22.04 LTS |

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation](#3-os-installation)
4. [Installing Docker](#4-installing-docker)
5. [Deploying Juice Shop](#5-deploying-juice-shop)
6. [OWASP Juice Shop Challenges Relevant to Lab 2](#6-owasp-juice-shop-challenges-relevant-to-lab-2)
7. [Docker Management Commands](#7-docker-management-commands)
8. [Resetting Juice Shop Between Attempts](#8-resetting-juice-shop-between-attempts)
9. [Network Interfaces](#9-network-interfaces)
10. [Default Credentials After Build](#10-default-credentials-after-build)
11. [Verification Steps](#11-verification-steps)
12. [Snapshot and Storage](#12-snapshot-and-storage)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

- Ubuntu Server 22.04 LTS ISO
- Internet access from the VM during build (to download the Docker package and pull the Juice Shop image)
- Build time: approximately 20–25 minutes (plus Docker image pull time, which varies by connection speed)

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **2048 MB** |
| Dynamic Memory | Disabled |
| Virtual hard disk | **20 GB**, Dynamically expanding |
| Network adapter | External-Internet |

---

## 3. OS Installation

| Setting | Value |
|---------|-------|
| Server name | `juiceshop` |
| Username | `juiceadmin` |
| SSH | Install OpenSSH server |
| Snaps | None |

After reboot: `sudo -i`.

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
```

---

## 4. Installing Docker

Install Docker Engine from the official Docker apt repository:

```bash
# Install prerequisites
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable Docker at boot
systemctl enable docker
systemctl start docker

# Verify
docker --version
```

---

## 5. Deploying Juice Shop

Pull the Juice Shop image and create a systemd service to manage the container:

```bash
# Pull the Juice Shop image (this may take several minutes)
docker pull bkimminich/juice-shop:latest

# Record the image digest for reproducibility
docker inspect bkimminich/juice-shop:latest --format '{{.RepoDigests}}' >> /root/.lab-credentials

# Create a systemd service that runs the container at boot
cat > /etc/systemd/system/juice-shop.service << 'EOF'
[Unit]
Description=SCPS CyberLab — OWASP Juice Shop
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=120
Restart=on-failure
RestartSec=5

# Remove any existing container with this name before starting
ExecStartPre=-/usr/bin/docker rm -f juice-shop

# Run Juice Shop — bind to all interfaces on port 3000
ExecStart=/usr/bin/docker run --name juice-shop \
    --rm \
    -p 3000:3000 \
    bkimminich/juice-shop:latest

ExecStop=/usr/bin/docker stop juice-shop

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable juice-shop
systemctl start juice-shop

# Wait for Juice Shop to start
echo "Waiting 60 seconds for Juice Shop to initialise..."
sleep 60

curl -s -o /dev/null -w "Juice Shop HTTP status: %{http_code}\n" http://localhost:3000/
```

---

## 6. OWASP Juice Shop Challenges Relevant to Lab 2

Juice Shop contains over 100 challenges across all OWASP Top 10 categories. The following challenges are scoped to Lab 2 and represent a progression from easy to advanced. Instructors should pre-select these challenges and optionally hide others to reduce scope overwhelm.

### Tier 1 — Introductory (One Star)

| Challenge | Category | Hint for Instructors |
|-----------|---------|---------------------|
| **Finding the Score Board** | Security Misconfiguration | Students must discover the `/score-board` URL — it is not linked from the UI. Teaches enumeration. |
| **DOM XSS** | XSS | Inject `<iframe src="javascript:alert('xss')">` in the search bar. |
| **Confidential Document** | Sensitive Data Exposure | Access `/ftp` — the directory listing is accessible and contains confidential files. |
| **Error Handling** | Security Misconfiguration | Trigger an HTTP 500 error to see stack trace disclosure. |

### Tier 2 — Beginner (Two Stars)

| Challenge | Category | Hint for Instructors |
|-----------|---------|---------------------|
| **Login Admin** | Injection | SQL injection in the email field: `' OR 1=1--`. Logs in as the admin. |
| **View Basket** | Broken Access Control | Change the basket ID in the request to view another user's basket (IDOR). |
| **Five-Star Feedback** | Improper Input Validation | Post a 0-star review by manipulating the rating parameter. |
| **Password Strength** | Broken Authentication | Brute force or guess the admin's weak password after finding the email. |

### Tier 3 — Intermediate (Three Stars)

| Challenge | Category | Hint for Instructors |
|-----------|---------|---------------------|
| **Reflected XSS** | XSS | Inject a reflected XSS payload through the order tracking ID field. |
| **Upload Type** | Improper Input Validation | Upload a `.pdf` file disguised as an image to the profile picture endpoint. |
| **CSRF** | CSRF | Forge a request to change the admin's email address using a crafted HTML form. |
| **Retrieve Blueprint** | Sensitive Data Exposure | Find the CAD blueprint file in the product images directory. |

### Tier 4 — Advanced (Four Stars — Stretch Objectives)

| Challenge | Category | Hint for Instructors |
|-----------|---------|---------------------|
| **Forged Review** | Broken Access Control | Post a product review as another user by manipulating the author field in the API. |
| **Leaked Access Logs** | Security Misconfiguration | Find and access the Nginx access log exposed at a predictable URL. |
| **Server-Side XSS Protection** | XSS | Bypass CSP and inject a stored XSS payload that executes server-side. |

---

## 7. Docker Management Commands

All Juice Shop management is performed via Docker commands. The container name is `juice-shop`.

```bash
# Check if container is running
docker ps | grep juice-shop

# View container logs (Juice Shop application logs)
docker logs juice-shop
docker logs juice-shop -f   # Follow log output

# Inspect container resource usage
docker stats juice-shop --no-stream

# Stop the container (systemd will restart it unless stopped via systemctl)
systemctl stop juice-shop

# Start the container
systemctl start juice-shop

# Restart (clears all challenge progress — see Section 8)
systemctl restart juice-shop

# View Juice Shop Docker image details
docker image inspect bkimminich/juice-shop:latest

# List all downloaded Docker images
docker images
```

---

## 8. Resetting Juice Shop Between Attempts

Juice Shop stores all challenge progress in memory within the container. Restarting the container resets all state to the factory default — all challenges appear as unsolved and all user accounts are deleted.

### Reset via systemd

```bash
systemctl restart juice-shop
# Allow 30 seconds for the container to restart and Juice Shop to re-initialise
sleep 30
curl -s -o /dev/null -w "Reset status: %{http_code}\n" http://localhost:3000/
```

### Reset Between Student Attempts (Mid-Lab)

If a student's Juice Shop instance needs to be reset while other students continue their sessions, restart only that student's VM. Because each student has their own per-student VM (the container runs inside the per-student `juice-shop-host` VM), resetting one does not affect others.

### Persistent Challenges (If Required)

If the lab design requires persisting challenge progress across a restart (for example, for a multi-day lab), the Juice Shop container can be run with volume persistence. This requires modifying the systemd unit to mount a host directory:

```bash
# Modify ExecStart in juice-shop.service to add a volume:
# -v /opt/juice-shop-data:/juice-shop/data
# Re-run: systemctl daemon-reload && systemctl restart juice-shop
```

For standard Lab 2 use, in-memory state (no volume mount) is preferred because it makes reset trivial.

---

## 9. Network Interfaces

Single adapter (`eth0`). In Lab 2, connected to `pentest-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.22`.

Students access Juice Shop at: `http://10.{ClassId}.{StudentId}.22:3000`

---

## 10. Default Credentials After Build

Juice Shop creates no persistent accounts at image build time. The default admin credentials are seeded by Juice Shop on each startup:

| Account | Email | Password |
|---------|-------|----------|
| Admin | `admin@juice-sh.op` | `admin123` (Juice Shop default — intentionally weak) |

Students discover these credentials as part of the challenge progression. The admin password is one of the brute force targets.

The OS account `juiceadmin` has its password in `/root/.lab-credentials`.

---

## 11. Verification Steps

### Step 1 — Docker Running

```bash
systemctl is-active docker
# Expected: active

docker ps | grep juice-shop
# Expected: juice-shop container listed with port 0.0.0.0:3000->3000/tcp
```

### Step 2 — Juice Shop Web Interface

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/
# Expected: 200

curl -s http://localhost:3000/ | grep -i "juice"
# Expected: HTML content containing "OWASP Juice Shop"
```

### Step 3 — Score Board Accessible

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/#/score-board
# Expected: 200 (Juice Shop serves all routes from the SPA, so the score board is valid)
```

### Step 4 — API Responding

```bash
curl -s http://localhost:3000/api/Challenges | python3 -m json.tool | head -20
# Expected: JSON array of challenge objects
```

---

## 12. Snapshot and Storage

Before capturing the VHDX, verify the Juice Shop image is embedded (not relying on a registry at runtime):

```bash
docker images bkimminich/juice-shop
# The image should be listed with a SIZE value — confirming it is locally cached
```

```powershell
Stop-VM -Name "juiceshop-build" -Force
Move-Item "juiceshop-build.vhdx" "C:\CyberLab\Templates\juice-shop-host.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\juice-shop-host.vhdx" -Name IsReadOnly -Value $true
```

> **Note:** The Docker image layer cache is stored inside the VHDX at `/var/lib/docker/`. This is why the VHDX contains the full Juice Shop image — no internet access is required at deploy time.

---

## 13. Troubleshooting

### Container Exits Immediately on Start

**Symptom:** `docker ps` shows no `juice-shop` container; `systemctl status juice-shop` shows failed.

**Fix:**

```bash
# Check the container logs
docker logs juice-shop 2>&1 | tail -30
# Or check the service journal
journalctl -u juice-shop -n 50
```

Common cause: port 3000 is already in use by a previous container instance that was not cleaned up. The `ExecStartPre=-/usr/bin/docker rm -f juice-shop` in the service unit handles this, but if Docker itself was restarted ungracefully, use:

```bash
docker rm -f juice-shop
systemctl start juice-shop
```

### Juice Shop Not Accessible from Student VM

**Symptom:** Student's browser shows connection refused on port 3000.

**Cause:** UFW is blocking port 3000, or the container is not listening on all interfaces.

**Fix:**

```bash
# Check if port 3000 is listening on all interfaces
ss -tlnp | grep 3000
# Should show: 0.0.0.0:3000

# If UFW is active, allow port 3000
ufw allow 3000/tcp
ufw reload
```

### Docker Image Not Found After VM Boot

**Symptom:** `docker images` shows no Juice Shop image after VM deployment.

**Cause:** The image was not pre-pulled before the VHDX was captured, or the Docker storage was corrupted.

**Fix:** Re-pull the image on the running VM. This requires internet access and should not be needed if the build procedure was followed correctly.

```bash
docker pull bkimminich/juice-shop:latest
systemctl restart juice-shop
```
