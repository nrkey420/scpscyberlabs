#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Build script for windows-server-2019-ad base image (two-phase — handles own reboot).

.DESCRIPTION
    Image Name    : windows-server-2019-ad
    Purpose       : Intentionally vulnerable Windows Server 2019 with Active Directory.
                    Primary attack target in Labs 1 and 3.
                    Contains Kerberoastable accounts, weak passwords, AD CS ESC1 vulnerability,
                    GPP cpassword, ASREPRoastable accounts, and reversible encryption.
    Base OS       : Windows Server 2019 Standard/Datacenter
    Lab           : Lab 1 (Red Team), Lab 3 (SOC/Blue Team)
    Security Level: INTENTIONALLY VULNERABLE — educational use only
    Author        : SCPS CyberLab Build System
    Date          : 2024-01-01

    PHASE 1 — Installs AD DS, sets passwords, registers Phase 2 task, promotes to DC, reboots.
    PHASE 2 — Runs automatically after reboot as SYSTEM via scheduled task.
              Creates OU structure, users, groups, GPOs, AD CS (ESC1), GPP file, flags.

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    WARNING: INTENTIONALLY VULNERABLE — FOR EDUCATIONAL USE ONLY
    All AD misconfigurations are deliberate and documented.
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

.NOTES
    Run as Administrator after OS installation and Hyper-V integration services.
    The script will reboot the server once (DC promotion requires it).
    After reboot, Phase 2 runs automatically and the server shuts down.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Determine which phase to run
# ---------------------------------------------------------------------------
$labBuildDir  = 'C:\LabBuild'
$phaseMarker  = "$labBuildDir\phase2.marker"
$phase2Script = "$labBuildDir\Build-Phase2-AD.ps1"

if (-not (Test-Path $labBuildDir)) { New-Item -ItemType Directory -Path $labBuildDir -Force | Out-Null }

Start-Transcript -Path "$labBuildDir\build.log" -Append -Force

# ---------------------------------------------------------------------------
# Helper functions (shared by both phases — defined before the phase branch)
# ---------------------------------------------------------------------------
function New-RandomPassword {
    param([int]$Length = 20)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?'
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    return (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] }))
}

function Write-Status { param([string]$Message, [string]$Color = 'Green') Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color }
function Write-Warn   { param([string]$Message) Write-Status $Message 'Yellow' }
function Write-Err    { param([string]$Message) Write-Status $Message 'Red'    }

$credFile = "$labBuildDir\credentials.txt"

function Append-Credential { param([string]$Line) Add-Content -Path $credFile -Value $Line }

# ===========================================================================
if (-not (Test-Path $phaseMarker)) {
# ===========================================================================
# PHASE 1 — Install AD DS and promote to domain controller
# ===========================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SCPS CyberLab — Build-WindowsServer2019AD.ps1  [PHASE 1]" -ForegroundColor Cyan
Write-Host " Image  : windows-server-2019-ad" -ForegroundColor Cyan
Write-Host " WARNING: INTENTIONALLY VULNERABLE AD ENVIRONMENT" -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Cyan

# Initialise credentials file
New-Item -ItemType File -Path $credFile -Force | Out-Null
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" | Out-Null

Append-Credential "============================================================"
Append-Credential " SCPS CyberLab — windows-server-2019-ad credentials"
Append-Credential " Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Append-Credential " SECURITY LEVEL: INTENTIONALLY VULNERABLE (educational)"
Append-Credential "============================================================"
Append-Credential ""
Append-Credential "=== AD ACCOUNT PASSWORDS ==="
Append-Credential ""
Append-Credential "[INTENTIONAL-WEAK] john.smith       : Password1      (Kerberoastable — SPN set)"
Append-Credential "[INTENTIONAL-WEAK] jane.doe         : Summer2023!    (ASREPRoastable — pre-auth disabled)"
Append-Credential "[INTENTIONAL-WEAK] svc.backup       : Backup2024!   (Domain Admin — priv esc path)"
Append-Credential "[INTENTIONAL-WEAK] svc.sql          : SqlServer2019! (SPN: MSSQLSvc — Kerberoastable)"
Append-Credential "[INTENTIONAL-WEAK] bob.admin        : Admin@2024     (local admin on workstations)"
Append-Credential "[INTENTIONAL-WEAK] student01        : Student@2024"
Append-Credential "[INTENTIONAL-WEAK] student02        : Student@2024"
Append-Credential "[INTENTIONAL-WEAK] student03        : Student@2024"
Append-Credential "[INTENTIONAL-WEAK] student04        : Student@2024"
Append-Credential "[INTENTIONAL-WEAK] student05        : Student@2024"
Append-Credential ""

$safeModePass = New-RandomPassword -Length 20
$labAdminPass = New-RandomPassword -Length 20

Append-Credential "[SECURE] DSRM (Safe Mode Admin) : $safeModePass"
Append-Credential "[SECURE] labadmin               : $labAdminPass"
Append-Credential ""

# [1] Computer name
Write-Status "Setting computer name to SCPS-DC01..."
try {
    Rename-Computer -NewName 'SCPS-DC01' -Force -ErrorAction SilentlyContinue
    Write-Status "Computer name set to SCPS-DC01."
} catch { Write-Warn "Rename failed: $_" }

# [2] Install AD DS and DNS roles
Write-Status "Installing AD DS and DNS Server roles..."
try {
    Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-ADDS, RSAT-AD-AdminCenter, RSAT-ADDS-Tools `
        -IncludeManagementTools -ErrorAction Stop
    Write-Status "AD DS and DNS roles installed."
} catch { Write-Err "AD DS install failed: $_"; Stop-Transcript; exit 1 }

# [3] Register Phase 2 scheduled task to run after reboot
Write-Status "Writing Phase 2 script and scheduling post-reboot task..."
try {
    # Phase 2 runs the AD configuration after DC promotion reboot
    $phase2Content = Get-Content -Raw -Path $MyInvocation.MyCommand.Path
    # The phase marker will exist on reboot, so the same script file will branch to Phase 2
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $phase2Script -Force

    $existingTask = Get-ScheduledTask -TaskName 'SCPS-AD-Phase2' -ErrorAction SilentlyContinue
    if ($null -ne $existingTask) { Unregister-ScheduledTask -TaskName 'SCPS-AD-Phase2' -Confirm:$false }

    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$phase2Script`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 'PT2H'
    Register-ScheduledTask -TaskName 'SCPS-AD-Phase2' `
        -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
    Write-Status "Phase 2 task registered."
} catch { Write-Err "Phase 2 registration failed: $_"; Stop-Transcript; exit 1 }

# [4] Promote to domain controller
Write-Status "Promoting server to domain controller (domain: lab.scps.local)..."
Write-Warn "Server will reboot automatically after promotion. Phase 2 runs on next boot."
try {
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName                  'lab.scps.local' `
        -DomainNetbiosName           'SCPS' `
        -DomainMode                  'WinThreshold' `
        -ForestMode                  'WinThreshold' `
        -SafeModeAdministratorPassword (ConvertTo-SecureString $safeModePass -AsPlainText -Force) `
        -DatabasePath                'C:\Windows\NTDS' `
        -LogPath                     'C:\Windows\NTDS' `
        -SysvolPath                  'C:\Windows\SYSVOL' `
        -InstallDns                  $true `
        -CreateDnsDelegation         $false `
        -NoRebootOnCompletion        $false `
        -Force

    # Write the phase marker BEFORE reboot (the task runs after reboot and checks this)
    New-Item -ItemType File -Path $phaseMarker -Force | Out-Null
} catch { Write-Err "DC promotion failed: $_"; Stop-Transcript; exit 1 }

Stop-Transcript

} else {
# ===========================================================================
# PHASE 2 — Post-reboot: configure AD, users, GPOs, AD CS, flags
# ===========================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " SCPS CyberLab — Build-WindowsServer2019AD.ps1  [PHASE 2]" -ForegroundColor Cyan
Write-Host " Post-reboot Active Directory configuration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Wait for AD DS to be fully ready
Write-Status "Waiting for Active Directory services to start..."
$retries = 0
while ($retries -lt 20) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADDomain -ErrorAction Stop | Out-Null
        Write-Status "Active Directory is ready."
        break
    } catch {
        $retries++
        Write-Warn "AD not ready yet (attempt $retries/20) — waiting 30s..."
        Start-Sleep -Seconds 30
    }
}

$domainDN = 'DC=lab,DC=scps,DC=local'
$tempDir  = 'C:\Temp'
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

# -------------------------------------------------------------------------
# [A] OU Structure
# -------------------------------------------------------------------------
Write-Status "Creating OU structure..."
try {
    $ous = @(
        'OU=Students,DC=lab,DC=scps,DC=local',
        'OU=Instructors,DC=lab,DC=scps,DC=local',
        'OU=Servers,DC=lab,DC=scps,DC=local',
        'OU=ServiceAccounts,DC=lab,DC=scps,DC=local',
        'OU=Workstations,DC=lab,DC=scps,DC=local'
    )
    foreach ($ouDN in $ous) {
        $ouName   = ($ouDN -split ',')[0] -replace '^OU=', ''
        $ouParent = $ouDN -replace "^OU=$ouName,", ''
        $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $ouParent -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            New-ADOrganizationalUnit -Name $ouName -Path $ouParent -ProtectedFromAccidentalDeletion $false
            Write-Status "OU=$ouName created."
        } else {
            Write-Status "OU=$ouName already exists."
        }
    }
} catch { Write-Warn "OU creation error: $_" }

# -------------------------------------------------------------------------
# [B] Intentionally vulnerable AD user accounts
# -------------------------------------------------------------------------
Write-Status "Creating intentionally vulnerable AD users..."

function New-LabADUser {
    param(
        [string]$SamAccountName,
        [string]$GivenName,
        [string]$Surname,
        [string]$Password,
        [string]$OU,
        [string]$Description = '',
        [bool]$PasswordNeverExpires = $true
    )
    $existing = Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-ADUser `
            -SamAccountName     $SamAccountName `
            -UserPrincipalName  "$SamAccountName@lab.scps.local" `
            -GivenName          $GivenName `
            -Surname            $Surname `
            -Name               "$GivenName $Surname" `
            -DisplayName        "$GivenName $Surname" `
            -Path               $OU `
            -AccountPassword    (ConvertTo-SecureString $Password -AsPlainText -Force) `
            -Enabled            $true `
            -PasswordNeverExpires $PasswordNeverExpires `
            -Description        $Description
        Write-Status "User $SamAccountName created."
    } else {
        Set-ADAccountPassword -Identity $SamAccountName `
            -NewPassword (ConvertTo-SecureString $Password -AsPlainText -Force) -Reset
        Write-Status "User $SamAccountName already exists — password reset."
    }
}

try {
    # john.smith — Kerberoastable (SPN set)
    New-LabADUser -SamAccountName 'john.smith' -GivenName 'John' -Surname 'Smith' `
        -Password 'Password1' -OU 'OU=Students,DC=lab,DC=scps,DC=local' `
        -Description 'INTENTIONAL VULN: Kerberoastable — SPN set, weak password'
    Set-ADUser -Identity 'john.smith' -ServicePrincipalNames @{Add='servicePrincipal/SCPS-DC01'}

    # jane.doe — ASREPRoastable (no pre-auth)
    New-LabADUser -SamAccountName 'jane.doe' -GivenName 'Jane' -Surname 'Doe' `
        -Password 'Summer2023!' -OU 'OU=Students,DC=lab,DC=scps,DC=local' `
        -Description 'INTENTIONAL VULN: ASREPRoastable — pre-auth disabled'
    Set-ADAccountControl -Identity 'jane.doe' -DoesNotRequirePreAuth $true

    # svc.backup — service account with Domain Admin (priv esc path)
    New-LabADUser -SamAccountName 'svc.backup' -GivenName 'Backup' -Surname 'Service' `
        -Password 'Backup2024!' -OU 'OU=ServiceAccounts,DC=lab,DC=scps,DC=local' `
        -Description 'INTENTIONAL VULN: Service account — member of Domain Admins (priv esc)'
    Add-ADGroupMember -Identity 'Domain Admins' -Members 'svc.backup'

    # svc.sql — Kerberoastable SQL service account
    New-LabADUser -SamAccountName 'svc.sql' -GivenName 'SQL' -Surname 'Service' `
        -Password 'SqlServer2019!' -OU 'OU=ServiceAccounts,DC=lab,DC=scps,DC=local' `
        -Description 'INTENTIONAL VULN: Kerberoastable — MSSQLSvc SPN, weak password'
    Set-ADUser -Identity 'svc.sql' -ServicePrincipalNames @{Add='MSSQLSvc/SCPS-DC01:1433'}

    # bob.admin — local admin on workstations
    New-LabADUser -SamAccountName 'bob.admin' -GivenName 'Bob' -Surname 'Admin' `
        -Password 'Admin@2024' -OU 'OU=Instructors,DC=lab,DC=scps,DC=local' `
        -Description 'INTENTIONAL VULN: Local admin on domain workstations via GPO'

    # labadmin — actual secure admin (random password)
    $labAdminPass = (Get-Content $credFile | Where-Object { $_ -match 'labadmin' } |
        ForEach-Object { ($_ -split ':')[1].Trim() } | Select-Object -First 1)
    if (-not $labAdminPass) { $labAdminPass = New-RandomPassword -Length 20 }
    New-LabADUser -SamAccountName 'labadmin' -GivenName 'Lab' -Surname 'Admin' `
        -Password $labAdminPass -OU 'OU=Instructors,DC=lab,DC=scps,DC=local' `
        -Description 'SECURE: Lab administration account — strong random password'
    Add-ADGroupMember -Identity 'Domain Admins' -Members 'labadmin' -ErrorAction SilentlyContinue

    # student01-student05
    1..5 | ForEach-Object {
        $num = $_.ToString('D2')
        New-LabADUser -SamAccountName "student$num" -GivenName "Student" -Surname "$num" `
            -Password 'Student@2024' -OU 'OU=Students,DC=lab,DC=scps,DC=local' `
            -Description "Lab student account $num"
    }

    Write-Status "All AD users created."
} catch { Write-Warn "AD user creation error: $_" }

# -------------------------------------------------------------------------
# [C] Security groups
# -------------------------------------------------------------------------
Write-Status "Creating security groups..."
try {
    $groups = @('SOC-Analysts', 'Red-Team', 'Blue-Team')
    foreach ($grp in $groups) {
        $existing = Get-ADGroup -Filter "Name -eq '$grp'" -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            New-ADGroup -Name $grp -GroupScope Global -GroupCategory Security `
                -Path "OU=Students,DC=lab,DC=scps,DC=local" `
                -Description "Lab security group: $grp"
            Write-Status "Group $grp created."
        }
    }
    # Populate groups
    1..5 | ForEach-Object {
        $num = $_.ToString('D2')
        Add-ADGroupMember -Identity 'SOC-Analysts' -Members "student$num" -ErrorAction SilentlyContinue
        Add-ADGroupMember -Identity 'Blue-Team'    -Members "student$num" -ErrorAction SilentlyContinue
    }
    Add-ADGroupMember -Identity 'Red-Team' -Members 'john.smith','jane.doe' -ErrorAction SilentlyContinue
    Write-Status "Security groups populated."
} catch { Write-Warn "Group creation error: $_" }

# -------------------------------------------------------------------------
# [D] Group Policy — disable Windows Defender domain-wide (INTENTIONAL VULN)
# -------------------------------------------------------------------------
Write-Status "Creating GPO to disable Windows Defender domain-wide (intentional)..."
try {
    Import-Module GroupPolicy -ErrorAction SilentlyContinue
    $gpoName = 'SCPS-Lab-DisableDefender'
    $existingGpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
    if ($null -eq $existingGpo) {
        $gpo = New-GPO -Name $gpoName -Comment 'INTENTIONAL VULN: Disable Defender domain-wide for red team lab'
    } else {
        $gpo = $existingGpo
    }
    # Set GPO registry keys to disable Defender
    Set-GPRegistryValue -Name $gpoName -Key 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender' `
        -ValueName 'DisableAntiSpyware' -Type DWord -Value 1
    Set-GPRegistryValue -Name $gpoName `
        -Key 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' `
        -ValueName 'DisableRealtimeMonitoring' -Type DWord -Value 1
    Set-GPRegistryValue -Name $gpoName `
        -Key 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' `
        -ValueName 'DisableBehaviorMonitoring' -Type DWord -Value 1
    # Enable SMBv1 via GPO
    Set-GPRegistryValue -Name $gpoName `
        -Key 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' `
        -ValueName 'SMB1' -Type DWord -Value 1
    # Link GPO to domain root
    New-GPLink -Name $gpoName -Target $domainDN -LinkEnabled Yes -ErrorAction SilentlyContinue
    Write-Status "Defender-disable GPO created and linked (intentional)."
} catch { Write-Warn "GPO creation error: $_" }

# -------------------------------------------------------------------------
# [E] GPP cpassword vulnerability (INTENTIONAL — Group Policy Preferences)
# -------------------------------------------------------------------------
Write-Status "Creating GPP cpassword vulnerability in SYSVOL (intentional)..."
try {
    # GPP passwords are encrypted with a published MS AES key — easily decrypted (MS14-025)
    # The cpassword below is the AES encryption of "Backup2024!" using the known MS key
    # Students use Get-GPPPassword or gpp-decrypt to find this.
    $gppXmlDir = "C:\Windows\SYSVOL\sysvol\lab.scps.local\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\Machine\Preferences\Groups"
    if (-not (Test-Path $gppXmlDir)) { New-Item -ItemType Directory -Path $gppXmlDir -Force | Out-Null }

    # cpassword is AES-encrypted with Microsoft's published key (intentional GPP vuln)
    # This cpassword value decrypts to "Backup2024!" using gpp-decrypt
    $cpassword = 'edBSHOwhZLTjt/QS9FeIcJ8zOlAHwMIyRPV5ZLVTSHl9GmE1P3JH5YUbkiPC5V2Y'

    Set-Content -Path "$gppXmlDir\Groups.xml" -Value @"
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
    <Group clsid="{6D4A79E4-529C-4481-ABD0-F5BD7EA93BA7}"
           name="Administrators (built-in)"
           image="2"
           changed="2024-01-01 00:00:00"
           uid="{DEA8A4B5-ACDB-4B43-AD73-BFDA4B9F0ABB}">
        <Properties action="U"
                    newName=""
                    description="INTENTIONAL VULN: GPP cpassword (MS14-025)"
                    deleteAllUsers="0"
                    deleteAllGroups="0"
                    removeAccounts="0"
                    groupSid="S-1-5-32-544"
                    groupName="Administrators (built-in)">
            <Members>
                <Member name="SCPS\svc.backup"
                        action="ADD"
                        sid=""
                        cpassword="$cpassword"
                        userName="svc.backup"/>
            </Members>
        </Properties>
    </Group>
</Groups>
"@
    Write-Status "GPP Groups.xml with cpassword created in SYSVOL (intentional MS14-025 vuln)."
} catch { Write-Warn "GPP cpassword setup error: $_" }

# -------------------------------------------------------------------------
# [F] Reversible encryption password policy (INTENTIONAL VULNERABILITY)
# -------------------------------------------------------------------------
Write-Status "Enabling reversible encryption in domain password policy (intentional)..."
try {
    Set-ADDefaultDomainPasswordPolicy `
        -Identity 'lab.scps.local' `
        -ReversibleEncryptionEnabled $true `
        -MinPasswordLength 1 `
        -PasswordHistoryCount 0 `
        -ComplexityEnabled $false `
        -LockoutThreshold 0
    Write-Status "Domain password policy set to intentionally weak (reversible encryption, no complexity)."
} catch { Write-Warn "Password policy error: $_" }

# -------------------------------------------------------------------------
# [G] Install AD Certificate Services (ADCS) with ESC1 vulnerability
# -------------------------------------------------------------------------
Write-Status "Installing AD Certificate Services with ESC1 vulnerability (intentional)..."
try {
    Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment `
        -IncludeManagementTools -ErrorAction SilentlyContinue

    Import-Module ADCSDeployment -ErrorAction SilentlyContinue
    $caExisting = Get-Service -Name 'CertSvc' -ErrorAction SilentlyContinue
    if ($null -eq $caExisting) {
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseRootCa `
            -CaCommonName 'SCPS-Lab-CA' `
            -KeyLength 2048 `
            -HashAlgorithmName SHA256 `
            -ValidityPeriod Years `
            -ValidityPeriodUnits 5 `
            -Force
        Write-Status "ADCS Enterprise Root CA installed."
    } else {
        Write-Status "ADCS already installed."
    }

    # ESC1 — create vulnerable certificate template:
    # Allow enrollees to supply Subject Alternative Name (SAN) in request.
    # This allows any domain user to request a cert for any user (including Domain Admin).
    $templateName = 'SCPS-VulnerableUser'
    $configNC     = (Get-ADRootDSE).configurationNamingContext
    $templatePath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $existingTemplate = Get-ADObject -Filter "Name -eq '$templateName'" -SearchBase $templatePath -ErrorAction SilentlyContinue

    if ($null -eq $existingTemplate) {
        # Duplicate the User template and modify flags for ESC1
        # msPKI-Certificate-Name-Flag = 0x1 (ENROLLEE_SUPPLIES_SUBJECT) — the ESC1 flag
        $userTemplate = Get-ADObject -Filter "Name -eq 'User'" -SearchBase $templatePath `
            -Properties * -ErrorAction SilentlyContinue
        if ($null -ne $userTemplate) {
            $newTemplate = @{
                'distinguishedName'                = "CN=$templateName,$templatePath"
                'objectClass'                      = 'pKICertificateTemplate'
                'cn'                               = $templateName
                'displayName'                      = 'SCPS Vulnerable User (ESC1)'
                'msPKI-Certificate-Name-Flag'      = 0x1        # ENROLLEE_SUPPLIES_SUBJECT (ESC1)
                'msPKI-Enrollment-Flag'            = 0x40       # PUBLISH_TO_DS
                'msPKI-Private-Key-Flag'           = 0x10       # EXPORTABLE_KEY
                'msPKI-Minimal-Key-Size'           = 2048
                'msPKI-Template-Schema-Version'    = 2
                'msPKI-Template-Minor-Revision'    = 1
                'msPKI-Cert-Template-OID'          = $userTemplate.'msPKI-Cert-Template-OID'
                'pKIDefaultKeySpec'                = 1
                'pKIKeyUsage'                      = [byte[]](0x80,0x00)
                'pKIMaxIssuingDepth'               = 0
                'pKIDefaultCSPs'                   = '1,Microsoft RSA SChannel Cryptographic Provider'
                'revision'                         = 100
                'flags'                            = 131680
            }
            New-ADObject -Name $templateName -Path $templatePath -Type 'pKICertificateTemplate' `
                -OtherAttributes $newTemplate -ErrorAction SilentlyContinue

            # Grant Authenticated Users Enroll + AutoEnroll permissions
            $templateDN = "CN=$templateName,$templatePath"
            $acl = Get-Acl -Path "AD:$templateDN"
            $authenticatedUsers = [System.Security.Principal.NTAccount]'NT AUTHORITY\Authenticated Users'
            $enrollRight      = [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight
            $enrollGuid       = [guid]'0e10c968-78fb-11d2-90d4-00c04f79dc55'
            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $authenticatedUsers, $enrollRight,
                [System.Security.AccessControl.AccessControlType]::Allow, $enrollGuid)
            $acl.AddAccessRule($ace)
            Set-Acl -Path "AD:$templateDN" -AclObject $acl -ErrorAction SilentlyContinue

            # Add template to CA's IssuedTemplates
            certutil -setcatemplates "+$templateName" 2>&1 | Out-Null
            Write-Status "ESC1 vulnerable certificate template '$templateName' created (intentional)."
        }
    } else {
        Write-Status "ESC1 template already exists."
    }
} catch { Write-Warn "ADCS/ESC1 setup error: $_" }

# -------------------------------------------------------------------------
# [H] NETLOGON share with interesting files
# -------------------------------------------------------------------------
Write-Status "Placing interesting files in NETLOGON share..."
try {
    $netlogonPath = 'C:\Windows\SYSVOL\sysvol\lab.scps.local\scripts'
    if (-not (Test-Path $netlogonPath)) { New-Item -ItemType Directory -Path $netlogonPath -Force | Out-Null }
    Set-Content -Path "$netlogonPath\admin_creds.txt" -Value @"
# Admin credentials — used by backup script (DO NOT COMMIT)
BackupUser: svc.backup
Password:   Backup2024!
Server:     SCPS-DC01
Share:      \\SCPS-DC01\Backup
"@
    Set-Content -Path "$netlogonPath\map_drives.bat" -Value @"
@echo off
:: Map network drives at login
net use Z: \\SCPS-DC01\Data /persistent:yes
net use Y: \\SCPS-DC01\Backup /user:SCPS\svc.backup Backup2024! /persistent:yes
"@
    Write-Status "NETLOGON lure files placed."
} catch { Write-Warn "NETLOGON files error: $_" }

# -------------------------------------------------------------------------
# [I] DNS records for lab VMs
# -------------------------------------------------------------------------
Write-Status "Creating DNS records for lab VMs..."
try {
    $dnsZone = 'lab.scps.local'
    $labHosts = @{
        'SCPS-DC01'    = '10.CLASS_ID.0.10'
        'SCPS-WS01'    = '10.CLASS_ID.0.11'
        'SCPS-SRV01'   = '10.CLASS_ID.0.21'
        'SCPS-FLARE01' = '10.CLASS_ID.0.11'
        'SCPS-TARGET01'= '10.CLASS_ID.0.20'
        'splunk'       = '10.CLASS_ID.0.51'
        'kali'         = '10.CLASS_ID.0.30'
    }
    foreach ($hostEntry in $labHosts.GetEnumerator()) {
        Remove-DnsServerResourceRecord -ZoneName $dnsZone -Name $hostEntry.Key `
            -RRType A -Force -ErrorAction SilentlyContinue
        Add-DnsServerResourceRecordA -ZoneName $dnsZone `
            -Name $hostEntry.Key -IPv4Address $hostEntry.Value -ErrorAction SilentlyContinue
        Write-Status "DNS: $($hostEntry.Key) -> $($hostEntry.Value)"
    }
    Write-Status "DNS records created (NOTE: replace CLASS_ID with actual class subnet)."
} catch { Write-Warn "DNS record creation error: $_" }

# -------------------------------------------------------------------------
# [J] Install Sysmon
# -------------------------------------------------------------------------
Write-Status "Installing Sysmon on domain controller..."
try {
    $sysmonDir    = 'C:\Tools\Sysmon'
    $sysmonZip    = "$tempDir\Sysmon.zip"
    $sysmonConfig = "$sysmonDir\sysmonconfig.xml"
    $sysmonExe    = "$sysmonDir\Sysmon64.exe"
    if (-not (Test-Path $sysmonDir)) { New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null }
    if (-not (Test-Path $sysmonExe)) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' `
            -OutFile $sysmonZip -UseBasicParsing
        Expand-Archive -Path $sysmonZip -DestinationPath $sysmonDir -Force
    }
    if (-not (Test-Path $sysmonConfig)) {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml' `
            -OutFile $sysmonConfig -UseBasicParsing
    }
    $sysmonSvc = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($null -eq $sysmonSvc) {
        & $sysmonExe -accepteula -i $sysmonConfig 2>&1 | Out-Null
    } else {
        & $sysmonExe -c $sysmonConfig 2>&1 | Out-Null
    }
    Write-Status "Sysmon installed on DC."
} catch { Write-Warn "Sysmon install error: $_" }

# -------------------------------------------------------------------------
# [K] Enhanced audit policy on DC
# -------------------------------------------------------------------------
Write-Status "Configuring enhanced audit policy on DC..."
try {
    $auditCmds = @(
        'auditpol /set /subcategory:"Logon" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Logoff" /success:enable',
        'auditpol /set /subcategory:"Account Lockout" /failure:enable',
        'auditpol /set /subcategory:"Process Creation" /success:enable',
        'auditpol /set /subcategory:"Process Termination" /success:enable',
        'auditpol /set /subcategory:"Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Object Access" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Privilege Use" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Policy Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Special Logon" /success:enable',
        'auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Directory Service Changes" /success:enable',
        'auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable',
        'auditpol /set /subcategory:"Authentication Policy Change" /success:enable /failure:enable'
    )
    foreach ($cmd in $auditCmds) { Invoke-Expression $cmd 2>&1 | Out-Null }
    $procAuditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $procAuditPath)) { New-Item -Path $procAuditPath -Force | Out-Null }
    Set-ItemProperty -Path $procAuditPath -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord
    Write-Status "Enhanced audit policy configured on DC."
} catch { Write-Warn "Audit policy error: $_" }

# -------------------------------------------------------------------------
# [L] Install Splunk Universal Forwarder
# -------------------------------------------------------------------------
Write-Status "Installing Splunk Universal Forwarder..."
$splunkIndexerIP   = '10.CLASS_ID.0.51'
$splunkIndexerPort = '9997'
$splunkInstallDir  = 'C:\Program Files\SplunkUniversalForwarder'
$splunkMsi         = "$tempDir\splunkforwarder.msi"
try {
    if (-not (Test-Path "$splunkInstallDir\bin\splunk.exe")) {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -Uri 'https://download.splunk.com/products/universalforwarder/releases/9.2.1/windows/splunkforwarder-9.2.1-78803f08aabb-x64-release.msi' `
            -OutFile $splunkMsi -UseBasicParsing
        $splunkPass = New-RandomPassword -Length 20
        Append-Credential "[SECURE] SplunkForwarder admin : $splunkPass"
        Start-Process msiexec.exe -Wait -ArgumentList @(
            '/i', $splunkMsi,
            'INSTALLDIR="C:\Program Files\SplunkUniversalForwarder"',
            "SPLUNKUSERNAME=admin", "SPLUNKPASSWORD=$splunkPass",
            "RECEIVING_INDEXER=${splunkIndexerIP}:${splunkIndexerPort}",
            'WINEVENTLOG_SEC_ENABLE=1', 'WINEVENTLOG_SYS_ENABLE=1',
            'WINEVENTLOG_APP_ENABLE=1', 'WINEVENTLOG_FWD_ENABLE=1',
            'WINEVENTLOG_SET_ENABLE=1', 'AGREETOLICENSE=Yes', '/qn'
        )
    }
    $splunkLocalDir = "$splunkInstallDir\etc\system\local"
    if (-not (Test-Path $splunkLocalDir)) { New-Item -ItemType Directory -Path $splunkLocalDir -Force | Out-Null }
    Set-Content -Path "$splunkLocalDir\outputs.conf" -Value @"
[tcpout]
defaultGroup = scps_indexers

[tcpout:scps_indexers]
server = ${splunkIndexerIP}:${splunkIndexerPort}
compressed = true
"@
    Set-Content -Path "$splunkLocalDir\inputs.conf" -Value @"
[WinEventLog://Application]
disabled = 0
[WinEventLog://Security]
disabled = 0
[WinEventLog://System]
disabled = 0
[WinEventLog://Microsoft-Windows-Sysmon/Operational]
disabled = 0
renderXml = true
[WinEventLog://Directory Service]
disabled = 0
[WinEventLog://DNS Server]
disabled = 0
"@
    Start-Service -Name 'SplunkForwarder' -ErrorAction SilentlyContinue
    Write-Status "Splunk UF configured (→ $splunkIndexerIP:$splunkIndexerPort)."
} catch { Write-Warn "Splunk UF error: $_" }

# -------------------------------------------------------------------------
# [M] Place flags
# -------------------------------------------------------------------------
Write-Status "Placing flag files..."
try {
    $flagDir = 'C:\flags'
    if (-not (Test-Path $flagDir)) { New-Item -ItemType Directory -Path $flagDir -Force | Out-Null }
    Set-Content -Path "$flagDir\objective4_flag.txt" -Value "FLAG{domain_admin_achieved_8b7a}"
    Set-Content -Path "$flagDir\kerberoast_flag.txt"  -Value "FLAG{kerberoasting_success_7c3d}"
    Set-Content -Path "$flagDir\asrep_flag.txt"       -Value "FLAG{asrep_roast_compromised_2e5f}"
    Set-Content -Path "$flagDir\gpp_flag.txt"         -Value "FLAG{gpp_password_found_9a1b}"
    Set-Content -Path "$flagDir\esc1_flag.txt"        -Value "FLAG{adcs_esc1_cert_forged_3f8c}"
    Write-Status "Flags placed in $flagDir."
} catch { Write-Warn "Flag placement error: $_" }

# -------------------------------------------------------------------------
# [N] Finalize credentials file
# -------------------------------------------------------------------------
Append-Credential ""
Append-Credential "=== INTENTIONAL VULNERABILITIES SUMMARY ==="
Append-Credential "- Kerberoastable  : john.smith (SPN: servicePrincipal/SCPS-DC01)"
Append-Credential "                    svc.sql (SPN: MSSQLSvc/SCPS-DC01:1433)"
Append-Credential "- ASREPRoastable  : jane.doe (pre-auth disabled)"
Append-Credential "- Priv esc path   : svc.backup (Domain Admin + weak password)"
Append-Credential "- GPP cpassword   : SYSVOL\...\Groups.xml (MS14-025)"
Append-Credential "- AD CS ESC1      : Template 'SCPS-VulnerableUser' (SAN supply)"
Append-Credential "- Password policy : Reversible encryption, no complexity, no lockout"
Append-Credential "- Defender GPO    : Disabled domain-wide"
Append-Credential ""
Append-Credential "=== FLAGS ==="
Append-Credential "C:\flags\objective4_flag.txt : FLAG{domain_admin_achieved_8b7a}"
Append-Credential "C:\flags\kerberoast_flag.txt  : FLAG{kerberoasting_success_7c3d}"
Append-Credential "C:\flags\asrep_flag.txt       : FLAG{asrep_roast_compromised_2e5f}"
Append-Credential "C:\flags\gpp_flag.txt         : FLAG{gpp_password_found_9a1b}"
Append-Credential "C:\flags\esc1_flag.txt        : FLAG{adcs_esc1_cert_forged_3f8c}"
Write-Status "Credentials file updated."

# -------------------------------------------------------------------------
# [O] Cleanup Phase 2 task and markers
# -------------------------------------------------------------------------
Write-Status "Cleaning up Phase 2 artifacts..."
try {
    Unregister-ScheduledTask -TaskName 'SCPS-AD-Phase2' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -Path $phaseMarker  -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $phase2Script -Force -ErrorAction SilentlyContinue
    Write-Status "Phase 2 cleanup done."
} catch { Write-Warn "Phase 2 cleanup error: $_" }

# -------------------------------------------------------------------------
# [P] Final cleanup and shutdown (NO sysprep — DCs cannot be sysprepped)
# -------------------------------------------------------------------------
Write-Status "Clearing event logs and history..."
try {
    Clear-EventLog -LogName Application -ErrorAction SilentlyContinue
    Clear-EventLog -LogName System      -ErrorAction SilentlyContinue
    Clear-EventLog -LogName Security    -ErrorAction SilentlyContinue
    wevtutil cl 'Microsoft-Windows-PowerShell/Operational' 2>&1 | Out-Null
    wevtutil cl 'Microsoft-Windows-Sysmon/Operational'     2>&1 | Out-Null
    Remove-Item "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" `
        -Force -ErrorAction SilentlyContinue
    Clear-History -ErrorAction SilentlyContinue
} catch { Write-Warn "Cleanup error: $_" }

Write-Status "Zeroing free disk space..."
try { cipher /w:C:\ 2>&1 | Out-Null } catch { Write-Warn "cipher /w error: $_" }

Write-Host "============================================================" -ForegroundColor Green
Write-Host " Phase 2 complete. Domain controller image build finished." -ForegroundColor Green
Write-Host " NOTE: DO NOT sysprep a domain controller." -ForegroundColor Yellow
Write-Host " Shut down and capture disk snapshot as base image." -ForegroundColor Yellow
Write-Host " Shutting down in 10 seconds..." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green

Stop-Transcript
Start-Sleep -Seconds 10
Stop-Computer -Force

} # end phase 2 / else block
