# CyberLab Orchestration Platform -- System Administrator Guide

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Installation](#2-installation)
3. [Entra ID App Registration](#3-entra-id-app-registration)
4. [Configuration Reference](#4-configuration-reference)
5. [IIS Deployment](#5-iis-deployment)
6. [Hyper-V Template Preparation](#6-hyper-v-template-preparation)
7. [Backup and Restore](#7-backup-and-restore)
8. [Monitoring](#8-monitoring)
9. [Troubleshooting](#9-troubleshooting)
10. [Security Hardening Checklist](#10-security-hardening-checklist)

---

## 1. Prerequisites

The CyberLab Orchestration Platform requires the following software and infrastructure to be in place before installation.

### Hardware Requirements

| Component       | Minimum           | Recommended        |
|-----------------|-------------------|--------------------|
| CPU             | 8 cores           | 16+ cores          |
| RAM             | 64 GB             | 128 GB             |
| Storage         | 500 GB SSD        | 2 TB NVMe          |
| Network         | 1 Gbps NIC        | 10 Gbps NIC        |

### Software Requirements

| Software                     | Version   | Purpose                                      |
|------------------------------|-----------|----------------------------------------------|
| Windows Server               | 2022      | Host OS with Hyper-V role                     |
| Hyper-V Role                 | Included  | Virtual machine hypervisor                    |
| PostgreSQL                   | 15+       | Application and Guacamole databases           |
| .NET SDK / Runtime           | 8.0       | Backend application runtime                   |
| Node.js                      | 20+ LTS   | Frontend build toolchain                      |
| Docker Desktop or Engine     | 24+       | Guacamole container deployment                |
| PowerShell                   | 7+        | Hyper-V orchestration module                  |
| Git                          | 2.40+     | Source control                                |

### Windows Server Roles and Features

Enable the following from Server Manager or PowerShell:

```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-WebSockets -IncludeManagementTools
```

### Verify Prerequisites

```powershell
# Hyper-V
Get-WindowsFeature Hyper-V | Select-Object Name, InstallState

# PostgreSQL
psql --version

# .NET
dotnet --version

# Node.js
node --version
npm --version

# Docker
docker --version
docker compose version

# PowerShell
$PSVersionTable.PSVersion
```

---

## 2. Installation

### 2.1 Database Setup

1. **Create the PostgreSQL database and role:**

```sql
CREATE ROLE cyberlab_admin WITH LOGIN PASSWORD 'YourStrongPasswordHere';
CREATE DATABASE cyberlab OWNER cyberlab_admin;
```

2. **Run the initialization script:**

```bash
psql -U cyberlab_admin -d cyberlab -f Database/init.sql
```

This creates all required tables (`lab_templates`, `lab_sessions`, `vm_instances`, `student_lab_assignments`, `lab_objectives`, `student_progress`, `activity_logs`, `system_config`, `resource_quotas`), indexes, and seed data.

3. **Verify the schema:**

```sql
\dt
-- Should list 9 tables
```

### 2.2 Application Build (.NET Backend)

```bash
cd CyberLabPlatform
dotnet restore
dotnet build --configuration Release
dotnet publish --configuration Release --output ../publish
```

### 2.3 Frontend Build (React/Vite)

```bash
cd CyberLabPlatform/CyberLabPlatform.Web/ClientApp
npm install
npm run build
```

The build output is placed in the `dist/` directory and is served by the .NET backend.

### 2.4 Apache Guacamole Deployment

Guacamole provides browser-based console access to lab VMs. It is deployed via Docker Compose.

1. **Create the environment file:**

```bash
cd Docker
cp .env.example .env
# Edit .env and set GUAC_DB_PASSWORD to a strong password
```

2. **Start the containers:**

```bash
docker compose up -d
```

This starts three services:

| Container              | Port | Description                         |
|------------------------|------|-------------------------------------|
| `cyberlab-guacd`       | 4822 | Guacamole connection proxy daemon   |
| `cyberlab-guacamole`   | 8080 | Guacamole web application           |
| `cyberlab-postgres`    | 5432 | Guacamole database (separate from app DB) |

3. **Verify Guacamole is running:**

```bash
curl http://localhost:8080/guacamole/
```

### 2.5 PowerShell Module Installation

Copy the orchestration module to a location accessible by the application:

```powershell
$modulePath = "C:\CyberLab\Modules"
New-Item -Path $modulePath -ItemType Directory -Force
Copy-Item -Path PowerShell\CyberLabOrchestration.psm1 -Destination $modulePath
```

Import and verify:

```powershell
Import-Module "$modulePath\CyberLabOrchestration.psm1" -Verbose
Get-Command -Module CyberLabOrchestration
```

---

## 3. Entra ID App Registration

CyberLab uses Microsoft Entra ID (Azure AD) for single sign-on (SSO) authentication.

### 3.1 Register the Application

1. Sign in to the [Azure Portal](https://portal.azure.com).
2. Navigate to **Microsoft Entra ID** > **App registrations** > **New registration**.
3. Configure the registration:

| Field                  | Value                                           |
|------------------------|-------------------------------------------------|
| Name                   | `CyberLab Orchestration Platform`               |
| Supported account types| Accounts in this organizational directory only   |
| Redirect URI (Web)     | `https://cyberlab.yourdomain.edu/signin-oidc`   |

4. Click **Register**.

### 3.2 Configure Authentication

1. Go to **Authentication** in the app registration.
2. Add the following redirect URIs:

```
https://cyberlab.yourdomain.edu/signin-oidc
https://cyberlab.yourdomain.edu/signout-callback-oidc
https://localhost:5001/signin-oidc        (development)
```

3. Under **Implicit grant and hybrid flows**, check:
   - **ID tokens**

4. Set **Front-channel logout URL** to `https://cyberlab.yourdomain.edu/signout-oidc`.

### 3.3 API Permissions

Add the following Microsoft Graph permissions (Delegated):

| Permission           | Type      | Purpose                          |
|----------------------|-----------|----------------------------------|
| `openid`             | Delegated | Sign-in                          |
| `profile`            | Delegated | Read user profile                |
| `email`              | Delegated | Read user email                  |
| `User.Read`          | Delegated | Read signed-in user profile      |
| `GroupMember.Read.All`| Delegated | Read group memberships for roles |

Click **Grant admin consent** after adding permissions.

### 3.4 Client Secret

1. Navigate to **Certificates & secrets** > **New client secret**.
2. Set a description (e.g., `CyberLab Production`) and expiration.
3. Copy the secret **Value** immediately -- it will not be shown again.

### 3.5 Record These Values

You will need these for `appsettings.json`:

| Value            | Location in Azure Portal                           |
|------------------|-----------------------------------------------------|
| Tenant ID        | Overview > Directory (tenant) ID                    |
| Client ID        | Overview > Application (client) ID                  |
| Client Secret    | Certificates & secrets > Value                      |
| Authority        | `https://login.microsoftonline.com/{TenantId}/v2.0` |

---

## 4. Configuration Reference

All application settings are managed in `appsettings.json`. The following sections document every configuration block.

### ConnectionStrings

```json
{
  "ConnectionStrings": {
    "CyberLabDb": "Host=localhost;Port=5432;Database=cyberlab;Username=cyberlab_admin;Password=REPLACE_ME;SSL Mode=Prefer"
  }
}
```

| Key          | Description                                |
|--------------|--------------------------------------------|
| `CyberLabDb` | PostgreSQL connection string for the app DB|

### AzureAd (Entra ID)

```json
{
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "TenantId": "YOUR_TENANT_ID",
    "ClientId": "YOUR_CLIENT_ID",
    "ClientSecret": "YOUR_CLIENT_SECRET",
    "CallbackPath": "/signin-oidc",
    "SignedOutCallbackPath": "/signout-callback-oidc"
  }
}
```

### HyperV

```json
{
  "HyperV": {
    "VMStoragePath": "C:\\CyberLab\\VMs",
    "TemplateStoragePath": "C:\\CyberLab\\Templates",
    "MaxTotalRAMGB": 115,
    "MaxTotalvCPUs": 22,
    "OverheadPercent": 10,
    "HeartbeatTimeoutSeconds": 300,
    "ModulePath": "C:\\CyberLab\\Modules\\CyberLabOrchestration.psm1"
  }
}
```

### Guacamole

```json
{
  "Guacamole": {
    "BaseUrl": "http://localhost:8080/guacamole",
    "AdminUser": "guacadmin",
    "AdminPassword": "REPLACE_ME",
    "DataSource": "postgresql"
  }
}
```

### Sessions

```json
{
  "Sessions": {
    "DefaultTimeoutMinutes": 240,
    "InactivityTimeoutMinutes": 30,
    "CleanupIntervalMinutes": 15,
    "MaxSnapshotsPerVM": 5,
    "SnapshotsEnabled": true
  }
}
```

### Logging (Serilog)

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      {
        "Name": "File",
        "Args": {
          "path": "C:\\CyberLab\\Logs\\cyberlab-.log",
          "rollingInterval": "Day",
          "retainedFileCountLimit": 90
        }
      }
    ]
  }
}
```

### Email

```json
{
  "Email": {
    "SmtpServer": "smtp.yourdomain.edu",
    "SmtpPort": 587,
    "UseSsl": true,
    "FromAddress": "cyberlab-noreply@yourdomain.edu",
    "FromName": "CyberLab Platform"
  }
}
```

### Hangfire

```json
{
  "Hangfire": {
    "DashboardPath": "/hangfire",
    "WorkerCount": 4
  }
}
```

---

## 5. IIS Deployment

### 5.1 Install the .NET Hosting Bundle

Download and install the [.NET 8 Hosting Bundle](https://dotnet.microsoft.com/download/dotnet/8.0) on the server. Restart IIS after installation:

```powershell
iisreset
```

### 5.2 Create the IIS Site

1. Open **IIS Manager**.
2. Right-click **Sites** > **Add Website**.
3. Configure:

| Field           | Value                              |
|-----------------|------------------------------------|
| Site name       | `CyberLab`                         |
| Physical path   | `C:\CyberLab\publish`             |
| Binding type    | `https`                            |
| Host name       | `cyberlab.yourdomain.edu`          |
| SSL certificate | Select your domain certificate     |
| Port            | `443`                              |

### 5.3 Configure the Application Pool

1. Navigate to **Application Pools** > select the `CyberLab` pool.
2. Set:

| Setting              | Value              |
|----------------------|--------------------|
| .NET CLR version     | No Managed Code    |
| Pipeline mode        | Integrated         |
| Start mode           | AlwaysRunning      |
| Idle timeout         | 0 (disabled)       |
| Identity             | Custom account with Hyper-V admin rights |

3. Under **Advanced Settings**, set:
   - **Load User Profile**: `True`
   - **Rapid-Fail Protection Enabled**: `True`

### 5.4 HTTPS Configuration

Ensure a valid TLS certificate is bound to the site. For internal deployments, you can use a certificate from an internal CA. For production, use a certificate from a trusted CA.

```powershell
# Verify binding
Get-WebBinding -Name "CyberLab"
```

### 5.5 web.config

The publish output includes a `web.config`. Verify these settings:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*"
             modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet"
                  arguments=".\CyberLabPlatform.Web.dll"
                  stdoutLogEnabled="true"
                  stdoutLogFile=".\logs\stdout"
                  hostingModel="InProcess">
        <environmentVariables>
          <environmentVariable name="ASPNETCORE_ENVIRONMENT" value="Production" />
        </environmentVariables>
      </aspNetCore>
    </system.webServer>
  </location>
</configuration>
```

---

## 6. Hyper-V Template Preparation

Lab templates require base VHDX disk images that serve as parent disks for differencing disk chains.

### 6.1 Creating a Base VHDX

1. **Create a Generation 2 VM** in Hyper-V Manager with the desired OS.
2. **Install the OS** and all required software for the lab scenario.
3. **Install Hyper-V Integration Services** (included in modern Windows; for Linux, install `hyperv-daemons`):

```bash
# Ubuntu/Debian
sudo apt install linux-tools-virtual linux-cloud-tools-virtual hyperv-daemons

# RHEL/CentOS
sudo yum install hyperv-daemons
```

4. **Prepare the image:**
   - Remove temporary files and caches.
   - For Windows, run `sysprep /generalize /oobe /shutdown` if cloning identities.
   - For Linux, clear machine IDs and SSH host keys:

```bash
sudo truncate -s 0 /etc/machine-id
sudo rm /etc/ssh/ssh_host_*
sudo cloud-init clean
```

5. **Shut down the VM** and copy the VHDX to the template storage path:

```powershell
Copy-Item "C:\Hyper-V\VMs\BaseVM\Virtual Hard Disks\disk.vhdx" `
          "C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx"
```

6. **Set the VHDX to read-only:**

```powershell
Set-ItemProperty -Path "C:\CyberLab\Templates\ubuntu-server-22.04-web.vhdx" `
                 -Name IsReadOnly -Value $true
```

### 6.2 Template VHDX Inventory

Maintain the following base images for the standard lab scenarios:

| Image Name                        | OS                   | Size (approx.) |
|-----------------------------------|----------------------|-----------------|
| `kali-linux-2024.1.vhdx`         | Kali Linux 2024.1    | 25 GB           |
| `windows-10-vulnerable.vhdx`     | Windows 10 Pro       | 30 GB           |
| `windows-server-2019-ad.vhdx`    | Windows Server 2019  | 30 GB           |
| `ubuntu-server-22.04-web.vhdx`   | Ubuntu Server 22.04  | 10 GB           |
| `pfsense-2.7.vhdx`               | pfSense 2.7          | 5 GB            |
| `security-onion-2.4.vhdx`        | Security Onion 2.4   | 40 GB           |
| `splunk-enterprise-9.1.vhdx`     | Splunk Enterprise    | 30 GB           |

### 6.3 Integration Services Checklist

Ensure these integration services are enabled on every template VM:

- Heartbeat
- Key-Value Pair Exchange
- Shutdown
- Time Synchronization
- Guest Services (for file copy)
- VSS (Windows only)

```powershell
Get-VMIntegrationService -VMName "TemplateVM" | Format-Table Name, Enabled
```

---

## 7. Backup and Restore

### 7.1 Database Backup

**Scheduled daily backup with pg_dump:**

```bash
pg_dump -U cyberlab_admin -d cyberlab -Fc -f /backups/cyberlab_$(date +%Y%m%d).dump
```

**Restore from backup:**

```bash
pg_restore -U cyberlab_admin -d cyberlab --clean --if-exists /backups/cyberlab_20260101.dump
```

### 7.2 VM Template Backup

Back up the entire template storage directory:

```powershell
robocopy "C:\CyberLab\Templates" "D:\Backups\Templates" /MIR /MT:8 /LOG:"D:\Backups\template_backup.log"
```

### 7.3 Configuration Backup

Back up the application configuration files:

```powershell
$backupDir = "D:\Backups\Config\$(Get-Date -Format 'yyyyMMdd')"
New-Item -Path $backupDir -ItemType Directory -Force
Copy-Item "C:\CyberLab\publish\appsettings.json" $backupDir
Copy-Item "C:\CyberLab\publish\appsettings.Production.json" $backupDir
Copy-Item "C:\CyberLab\Modules\CyberLabOrchestration.psm1" $backupDir
Copy-Item "Docker\.env" $backupDir
```

### 7.4 Recommended Backup Schedule

| Component        | Frequency | Retention |
|------------------|-----------|-----------|
| PostgreSQL DB    | Daily     | 30 days   |
| VM Templates     | Weekly    | 3 copies  |
| Configuration    | On change | 10 copies |
| Activity Logs    | Daily     | 90 days   |

---

## 8. Monitoring

### 8.1 Health Endpoints

The application exposes a health check endpoint:

```
GET /api/health
```

Response:

```json
{
  "status": "Healthy",
  "checks": {
    "database": "Healthy",
    "hyperv": "Healthy",
    "guacamole": "Healthy",
    "diskSpace": "Healthy"
  }
}
```

Use this endpoint with monitoring tools (Uptime Kuma, Nagios, PRTG) to alert on failures.

### 8.2 Hangfire Dashboard

Background jobs (session cleanup, inactivity monitoring, report generation) are managed by Hangfire. Access the dashboard at:

```
https://cyberlab.yourdomain.edu/hangfire
```

The dashboard shows:
- Active, scheduled, and failed jobs
- Retry history
- Processing servers

Access is restricted to users in the `Admin` role.

### 8.3 Serilog Logs

Application logs are written to:

```
C:\CyberLab\Logs\cyberlab-YYYYMMDD.log
```

Log levels:
- **Information** -- Normal operations (session created, VM started)
- **Warning** -- Non-critical issues (graceful shutdown timeout, resource threshold)
- **Error** -- Failures (VM creation failed, database connection lost)

**Tail logs in real-time:**

```powershell
Get-Content "C:\CyberLab\Logs\cyberlab-$(Get-Date -Format 'yyyyMMdd').log" -Tail 50 -Wait
```

### 8.4 PowerShell Health Check

Use the orchestration module to get a system health summary:

```powershell
Import-Module C:\CyberLab\Modules\CyberLabOrchestration.psm1
Get-LabHealthStatus
```

This returns Hyper-V service status, resource usage, VM counts by state, disk free space, and background job status.

### 8.5 Resource Usage Monitoring

```powershell
Get-LabResourceUsage
```

Returns current RAM, vCPU, disk, and running VM counts. Set up a scheduled task to log this periodically for trend analysis.

---

## 9. Troubleshooting

### 9.1 VM Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| VM fails to start | Insufficient RAM/CPU | Run `Test-ResourceAvailability` to check. Stop unused sessions. |
| VM has no heartbeat | Integration services not installed | Install `hyperv-daemons` (Linux) or verify Integration Services (Windows). |
| Differencing disk error | Parent disk moved or corrupted | Verify the parent disk path in `C:\CyberLab\Templates`. Re-copy from backup. |
| VM stuck in "Creating" state | PowerShell module error | Check `C:\CyberLab\Logs` for errors. Run `Remove-LabSession` to clean up. |
| Cannot connect to VM console | Guacamole misconfigured | Verify Guacamole containers are running (`docker ps`). Check Guacamole connection settings. |

### 9.2 Authentication Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| SSO login fails | Incorrect redirect URI | Verify URIs in Entra ID app registration match `appsettings.json`. |
| "AADSTS50011" error | Reply URL mismatch | Add the exact URL shown in the error to the app registration. |
| User has no role | Group membership not mapped | Verify the user is in the correct Entra ID security group. |
| Token expired errors | Clock skew | Ensure server time is synced via NTP. |

### 9.3 Networking Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| VMs cannot reach each other | Wrong virtual switch | Verify all VMs in a session use the same private switch. |
| No internet from VMs | Switch type is Private | By design -- labs use isolated Private switches. |
| Guacamole connection refused | Firewall blocking port 8080 | Allow TCP 8080 inbound from the web server. |
| RDP/SSH to VM fails via Guacamole | Wrong IP or credentials | Check `vm_instances` table for correct IP and credentials. |

### 9.4 Guacamole Issues

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| Guacamole returns 502 | guacd container down | Run `docker compose restart guacd`. |
| Login page not loading | Guacamole container unhealthy | Check `docker logs cyberlab-guacamole`. |
| Connection shows black screen | VM not fully booted | Wait for heartbeat. Check VM state in Hyper-V Manager. |
| Clipboard not working | Enhanced session not enabled | Enable enhanced session mode on the Hyper-V host. |

### 9.5 Database Issues

```bash
# Check PostgreSQL connectivity
psql -U cyberlab_admin -d cyberlab -c "SELECT 1;"

# Check active connections
SELECT * FROM pg_stat_activity WHERE datname = 'cyberlab';

# Check table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;
```

---

## 10. Security Hardening Checklist

### Server

- [ ] Windows Server is fully patched and on a regular update schedule
- [ ] Only required Windows features and roles are installed
- [ ] Remote Desktop is restricted to authorized admin IPs
- [ ] Windows Defender or endpoint protection is active and up to date
- [ ] Server is joined to the domain with Group Policy applied

### Network

- [ ] Lab VMs use Private virtual switches (no external network access)
- [ ] Windows Firewall is enabled with rules limited to required ports
- [ ] IIS is bound only to HTTPS (port 443); HTTP redirects to HTTPS
- [ ] Guacamole is accessible only from the IIS reverse proxy, not directly
- [ ] Network segmentation isolates the CyberLab server from student networks

### Application

- [ ] `appsettings.json` has restrictive file permissions (Administrators and App Pool identity only)
- [ ] Database passwords are stored in environment variables or a secrets manager, not in plaintext config
- [ ] Client secret for Entra ID is rotated at least annually
- [ ] Hangfire dashboard is restricted to Admin role
- [ ] CORS is configured to allow only the application origin
- [ ] Anti-forgery tokens are enabled for all form submissions
- [ ] Rate limiting is configured for API endpoints

### Database

- [ ] PostgreSQL listens only on localhost or a private network interface
- [ ] `pg_hba.conf` restricts connections to the application server IP
- [ ] Database role has minimal required permissions (no superuser)
- [ ] Connection uses SSL/TLS encryption
- [ ] Database backups are encrypted at rest

### Hyper-V

- [ ] Template VHDXs are read-only to prevent accidental modification
- [ ] VM storage paths have restricted NTFS permissions
- [ ] PowerShell remoting is limited to authorized service accounts
- [ ] Hyper-V Replica is disabled unless needed
- [ ] Resource quotas are configured to prevent resource exhaustion

### Guacamole

- [ ] Default `guacadmin` password is changed immediately after deployment
- [ ] Guacamole admin interface is accessible only to platform admins
- [ ] Docker containers run with minimal privileges
- [ ] Docker volumes use named volumes (not bind mounts to sensitive paths)
- [ ] Container images are pinned to specific versions (e.g., `guacamole/guacamole:1.5.4`)

### Logging and Auditing

- [ ] All authentication events are logged
- [ ] VM lifecycle events (create, start, stop, delete) are logged
- [ ] Log files are retained for at least 90 days
- [ ] Log files are backed up to a separate location
- [ ] Failed login attempts trigger alerts after a threshold
