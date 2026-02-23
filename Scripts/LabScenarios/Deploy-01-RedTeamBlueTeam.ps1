#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Deploy Lab 01 — Red Team / Blue Team Cyber Range

.DESCRIPTION
    Orchestrates the full deployment of the Red Team / Blue Team lab for a class session.
    Creates differencing disks from base templates, configures Hyper-V virtual networks,
    injects per-student credentials, and validates readiness before handing off to students.

    VMs Deployed
    ------------
    Per Student (up to 15 students):
      - Kali Linux 2024.1       (attacker workstation)
      - Windows 10 Workstation  (target — intentionally vulnerable)
      - Windows Server 2019 AD  (target — domain controller)
      - Ubuntu Linux Web Server (target — DMZ web server)
      - pfSense 2.7 Firewall    (network segmentation / routing)

    Per Class (shared, one set):
      - Security Onion 2.4      (blue team IDS/NSM platform)
      - Splunk Enterprise 9.1   (SIEM)

    Network Topology (per student, ClassId=1, StudentId=3 example)
    --------------------------------------------------------------
    Internet/WAN (not connected — all traffic stays on-host)

          [Kali 10.1.3.10]
                |
         attack-net-C1-S3
                |
    [pfSense WAN=.1  LAN(corp)=.1  LAN(dmz)=.1]
                |                        |
      corporate-net-C1-S3        dmz-net-C1-S3
        |           |                   |
    [Win10 .20] [WinAD .21]       [WebSrv .30]

    Shared monitoring (all students' traffic mirrored via pfSense span):
    shared-monitor-net-C1
      |              |
    [SecOnion .50]  [Splunk .51]

    Timing Estimates
    ----------------
    - Virtual switch creation  :  ~30 seconds
    - Shared VM deployment     :  ~5-8 minutes
    - Per-student (parallel)   :  ~8-15 minutes (ThrottleLimit=5)
    - Total (15 students)      :  ~20-30 minutes

.PARAMETER SessionId
    GUID identifying this class session. Used for VM naming and path scoping.

.PARAMETER ClassId
    1 or 2. Maps to the second octet of all IP addresses (10.{ClassId}.x.x).

.PARAMETER StudentIds
    Array of student identifiers (e.g. 'S01','S02',...,'S15'). Must be 1-15 entries.
    The position in this array (1-based) determines the third IP octet.

.PARAMETER TimeoutMinutes
    Maximum minutes to wait for the full deployment before aborting. Default 120.

.EXAMPLE
    .\Deploy-01-RedTeamBlueTeam.ps1 `
        -SessionId ([guid]::NewGuid()) `
        -ClassId 1 `
        -StudentIds @('alice','bob','carol') `
        -TimeoutMinutes 90

.NOTES
    Author  : SCPS CyberLab Orchestration System
    Lab     : 01 — Red Team / Blue Team
    Version : 1.0.0
    Requires: Windows Server 2022, Hyper-V role, Administrator rights
              SSH client (OpenSSH) on host for pfSense/Linux config
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [guid]$SessionId,

    [Parameter(Mandatory)]
    [ValidateRange(1, 2)]
    [int]$ClassId,

    [Parameter(Mandatory)]
    [ValidateCount(1, 15)]
    [string[]]$StudentIds,

    [int]$TimeoutMinutes = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Path constants ────────────────────────────────────────────────────────────
$TemplatePath  = 'C:\CyberLab\Templates'
$VMBasePath    = 'C:\CyberLab\VMs'
$LogPath       = 'C:\CyberLab\Logs'
$SessionsPath  = 'C:\CyberLab\Sessions'
$SessionIdStr  = $SessionId.ToString()
$ShortId       = $SessionIdStr.Substring(0, 8)
$LabNum        = '01'

# ── Transcript ────────────────────────────────────────────────────────────────
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$TranscriptFile = Join-Path $LogPath "Deploy-Lab${LabNum}-${ShortId}-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $TranscriptFile -Force

$DeployStart = Get-Date
Write-Host ('=' * 70) -ForegroundColor Cyan
Write-Host "  SCPS CyberLab — Deploy Lab 01: Red Team / Blue Team" -ForegroundColor Cyan
Write-Host "  Session  : $SessionIdStr" -ForegroundColor Cyan
Write-Host "  ClassId  : $ClassId" -ForegroundColor Cyan
Write-Host "  Students : $($StudentIds -join ', ')" -ForegroundColor Cyan
Write-Host "  Started  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ('=' * 70) -ForegroundColor Cyan

# ── Template definitions ──────────────────────────────────────────────────────
$Templates = @{
    Kali      = 'kali-linux-2024.1.vhdx'
    Win10     = 'windows-10-vulnerable.vhdx'
    WinAD     = 'windows-server-2019-ad.vhdx'
    WebSrv    = 'ubuntu-server-22.04-web.vhdx'
    PfSense   = 'pfsense-2.7.vhdx'
    SecOnion  = 'security-onion-2.4.vhdx'
    Splunk    = 'splunk-enterprise-9.1.vhdx'
}

# ── Credential accumulator ────────────────────────────────────────────────────
$sessionCredentials = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()

# Track all created resources for rollback
$createdSwitches = [System.Collections.Generic.List[string]]::new()
$createdVMs      = [System.Collections.Generic.List[string]]::new()
$createdDisks    = [System.Collections.Generic.List[string]]::new()

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function New-RandomPassword {
    param([int]$Length = 16)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*-_=+'
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new($Length)
    $rng.GetBytes($bytes)
    return -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Write-Step {
    param([string]$Message, [string]$Color = 'Green')
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function New-DifferencingDisk {
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$ChildPath
    )
    if (-not (Test-Path $ParentPath)) {
        throw "Parent VHDX not found: $ParentPath"
    }
    $dir = Split-Path $ChildPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    New-VHD -Path $ChildPath -ParentPath $ParentPath -Differencing -ErrorAction Stop | Out-Null
    Write-Step "  Differencing disk created: $(Split-Path $ChildPath -Leaf)"
    return $ChildPath
}

function New-LabVM {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$VHDXPath,
        [Parameter(Mandatory)][int]$MemoryMB,
        [Parameter(Mandatory)][int]$vCPU,
        [Parameter(Mandatory)][string[]]$SwitchNames
    )
    $ramBytes = [int64]$MemoryMB * 1MB

    # Remove existing VM if stale
    $existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    }

    $vm = New-VM -Name $VMName `
                 -MemoryStartupBytes $ramBytes `
                 -VHDPath $VHDXPath `
                 -SwitchName $SwitchNames[0] `
                 -Generation 2 `
                 -ErrorAction Stop

    Set-VM -Name $VMName `
           -ProcessorCount $vCPU `
           -DynamicMemory:$false `
           -ErrorAction Stop

    # Add additional NICs
    for ($i = 1; $i -lt $SwitchNames.Count; $i++) {
        Add-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchNames[$i] -ErrorAction Stop
    }

    # Secure boot — disable for Linux/FreeBSD VMs (caller sets if needed)
    Write-Step "  VM created: $VMName ($vCPU vCPU, ${MemoryMB}MB)"
    return $vm
}

function Wait-VMHeartbeat {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [int]$TimeoutSec = 180
    )
    Write-Step "  Waiting for heartbeat: $VMName (timeout ${TimeoutSec}s)..." 'Yellow'
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $hb = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).Heartbeat
        if ($hb -in @('OkApplicationsHealthy', 'OkApplicationsUnknown')) {
            Write-Step "  Heartbeat OK: $VMName (${elapsed}s)"
            return $true
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    Write-Warning "Heartbeat timeout for $VMName after ${TimeoutSec}s"
    return $false
}

function Set-WindowsVMConfig {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][PSCredential]$Cred,
        [Parameter(Mandatory)][hashtable]$Config
    )
    # Config keys: ComputerName, IPAddress, PrefixLength, Gateway, DNSServers, AdditionalCommands
    Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
        param($cfg)

        # Rename computer
        if ($cfg.ComputerName) {
            Rename-Computer -NewName $cfg.ComputerName -Force -ErrorAction SilentlyContinue
        }

        # Set static IP
        if ($cfg.IPAddress) {
            $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if ($adapter) {
                $existing = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                if ($existing) { Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue }
                $route = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
                if ($route) { Remove-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue }

                New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
                    -IPAddress $cfg.IPAddress `
                    -PrefixLength ($cfg.PrefixLength ?? 24) `
                    -DefaultGateway $cfg.Gateway `
                    -ErrorAction SilentlyContinue

                if ($cfg.DNSServers) {
                    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $cfg.DNSServers -ErrorAction SilentlyContinue
                }
            }
        }

        # Set local Administrator password
        if ($cfg.AdminPassword) {
            $secPwd = ConvertTo-SecureString $cfg.AdminPassword -AsPlainText -Force
            Set-LocalUser -Name 'Administrator' -Password $secPwd -ErrorAction SilentlyContinue
        }

        # Create student account
        if ($cfg.StudentUser -and $cfg.StudentPassword) {
            $sp = ConvertTo-SecureString $cfg.StudentPassword -AsPlainText -Force
            $u  = Get-LocalUser -Name $cfg.StudentUser -ErrorAction SilentlyContinue
            if (-not $u) {
                New-LocalUser -Name $cfg.StudentUser -Password $sp `
                    -FullName "Lab Student" -PasswordNeverExpires -ErrorAction SilentlyContinue
            } else {
                Set-LocalUser -Name $cfg.StudentUser -Password $sp -ErrorAction SilentlyContinue
            }
            Add-LocalGroupMember -Group 'Administrators' -Member $cfg.StudentUser -ErrorAction SilentlyContinue
        }

        # Run any additional inline commands
        if ($cfg.AdditionalCommands) {
            foreach ($cmd in $cfg.AdditionalCommands) {
                try { Invoke-Expression $cmd } catch { }
            }
        }
    } -ArgumentList $Config -ErrorAction Stop
}

function Set-LinuxVMConfig {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$IpAddress,
        [Parameter(Mandatory)][string]$Gateway,
        [hashtable]$AdditionalConfig = @{}
    )
    # Derive SSH target: use Hyper-V console IP or host-internal route
    # This function uses SSH via the management NIC or PowerShell Invoke-Command via VMName if Integration Services available
    # For Linux VMs without PS remoting: use plink/ssh.exe on the host
    $sshUser = $AdditionalConfig.SshUser ?? 'labadmin'
    $sshPass = $AdditionalConfig.SshPassword ?? ''
    $vmIp    = $AdditionalConfig.ManagementIp ?? '192.168.100.1'  # fallback management IP

    $netplanConfig = @"
network:
  version: 2
  ethernets:
    eth0:
      addresses: ["${IpAddress}/24"]
      routes:
        - to: default
          via: ${Gateway}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
"@

    $commands = @(
        "echo '$netplanConfig' | sudo tee /etc/netplan/50-lab.yaml > /dev/null",
        "sudo netplan apply"
    )

    if ($AdditionalConfig.Hostname) {
        $commands = @("sudo hostnamectl set-hostname '$($AdditionalConfig.Hostname)'") + $commands
    }

    foreach ($cmd in $commands) {
        $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10',
                     "${sshUser}@${vmIp}", $cmd)
        if ($sshPass) {
            # Use sshpass if available
            $sshpassExe = Get-Command 'sshpass' -ErrorAction SilentlyContinue
            if ($sshpassExe) {
                & sshpass -p $sshPass ssh @sshArgs 2>&1 | Out-Null
            } else {
                & ssh @sshArgs 2>&1 | Out-Null
            }
        } else {
            & ssh @sshArgs 2>&1 | Out-Null
        }
    }

    if ($AdditionalConfig.ExtraCommands) {
        foreach ($cmd in $AdditionalConfig.ExtraCommands) {
            $sshArgs = @('-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10',
                         "${sshUser}@${vmIp}", $cmd)
            & ssh @sshArgs 2>&1 | Out-Null
        }
    }
}

function Invoke-SshCommand {
    param(
        [Parameter(Mandatory)][string]$TargetIp,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Command,
        [int]$Port = 22
    )
    # Use the OpenSSH client bundled with Windows Server 2022
    $sshpassExe = 'sshpass'
    $sshArgs = @('-p', $Password, 'ssh',
                 '-o', 'StrictHostKeyChecking=no',
                 '-o', 'ConnectTimeout=15',
                 '-p', $Port.ToString(),
                 "${User}@${TargetIp}",
                 $Command)
    $result = & $sshpassExe @sshArgs 2>&1
    return $result
}

function Invoke-EnsureVMSwitch {
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [ValidateSet('Private', 'Internal', 'External')]
        [string]$SwitchType = 'Private'
    )
    $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-VMSwitch -Name $SwitchName -SwitchType $SwitchType -ErrorAction Stop | Out-Null
        $script:createdSwitches.Add($SwitchName)
        Write-Step "  Switch created: $SwitchName ($SwitchType)"
    }
}

function Remove-LabSessionResources {
    param([string]$Reason = 'Deployment failure')
    Write-Warning "ROLLBACK: $Reason — cleaning up session $SessionIdStr"
    foreach ($vmName in $createdVMs) {
        try {
            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
            Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            Write-Step "  Removed VM: $vmName" 'Yellow'
        } catch { Write-Warning "  Could not remove VM $vmName : $_" }
    }
    foreach ($disk in $createdDisks) {
        try {
            if (Test-Path $disk) {
                Remove-Item -Path $disk -Force -ErrorAction SilentlyContinue
                Write-Step "  Removed disk: $disk" 'Yellow'
            }
        } catch { Write-Warning "  Could not remove disk $disk : $_" }
    }
    foreach ($sw in $createdSwitches) {
        try {
            Remove-VMSwitch -Name $sw -Force -ErrorAction SilentlyContinue
            Write-Step "  Removed switch: $sw" 'Yellow'
        } catch { Write-Warning "  Could not remove switch $sw : $_" }
    }
    # Remove session VM directory
    $sessionDir = Join-Path $VMBasePath $SessionIdStr
    if (Test-Path $sessionDir) {
        Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Step "Rollback complete." 'Yellow'
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 0: PREREQUISITES VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 0: Validating prerequisites ===" 'Cyan'

# Check Hyper-V service
$vmms = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
if (-not $vmms -or $vmms.Status -ne 'Running') {
    throw "Hyper-V Virtual Machine Management service (vmms) is not running."
}

# Validate template VHDXs
foreach ($tplKey in $Templates.Keys) {
    $tplPath = Join-Path $TemplatePath $Templates[$tplKey]
    if (-not (Test-Path $tplPath)) {
        throw "Missing template VHDX: $tplPath"
    }
    Write-Step "  Template OK: $($Templates[$tplKey])"
}

# Check disk space — estimate 80GB per student slot + 200GB for shared
$studentCount     = $StudentIds.Count
$estimatedGBNeeded = ($studentCount * 5 * 16) + (2 * 30)  # differencing disks ~16GB initial each
$vmDrive = Split-Path $VMBasePath -Qualifier
$disk    = Get-PSDrive -Name $vmDrive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($disk) {
    $freeGB = [math]::Round($disk.Free / 1GB, 1)
    Write-Step "  Disk free: ${freeGB}GB  Estimated needed: ${estimatedGBNeeded}GB"
    if ($freeGB -lt $estimatedGBNeeded) {
        Write-Warning "Low disk space: ${freeGB}GB free, ~${estimatedGBNeeded}GB estimated needed. Continuing anyway."
    }
}

# Ensure directory structure
foreach ($dir in @($VMBasePath, $LogPath, $SessionsPath)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
$sessionRoot = Join-Path $VMBasePath $SessionIdStr
if (-not (Test-Path $sessionRoot)) { New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null }

Write-Step "Prerequisites validated." 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: CREATE VIRTUAL SWITCHES
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 1: Creating virtual switches ===" 'Cyan'

try {
    # Shared monitoring switch (one per class)
    Invoke-EnsureVMSwitch -SwitchName "shared-monitor-net-C${ClassId}" -SwitchType Private

    # Per-student switches
    for ($idx = 0; $idx -lt $StudentIds.Count; $idx++) {
        $sid = $idx + 1
        Invoke-EnsureVMSwitch -SwitchName "attack-net-C${ClassId}-S${sid}"    -SwitchType Private
        Invoke-EnsureVMSwitch -SwitchName "corporate-net-C${ClassId}-S${sid}" -SwitchType Private
        Invoke-EnsureVMSwitch -SwitchName "dmz-net-C${ClassId}-S${sid}"       -SwitchType Private
    }
    Write-Step "All virtual switches created." 'Green'
} catch {
    Remove-LabSessionResources -Reason "Switch creation failed: $_"
    Stop-Transcript
    throw
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: DEPLOY SHARED VMs (Security Onion + Splunk)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 2: Deploying shared VMs ===" 'Cyan'

try {
    # Security Onion
    $soName   = "Lab01-SecOnion-C${ClassId}-${ShortId}"
    $soDir    = Join-Path $sessionRoot "shared"
    if (-not (Test-Path $soDir)) { New-Item -ItemType Directory -Path $soDir -Force | Out-Null }
    $soDisk   = Join-Path $soDir "${soName}.vhdx"
    $soParent = Join-Path $TemplatePath $Templates.SecOnion

    New-DifferencingDisk -ParentPath $soParent -ChildPath $soDisk | Out-Null
    $createdDisks.Add($soDisk)

    $soVM = New-LabVM -VMName $soName -VHDXPath $soDisk `
                      -MemoryMB 8192 -vCPU 4 `
                      -SwitchNames @("shared-monitor-net-C${ClassId}")
    Set-VMFirmware -VMName $soName -EnableSecureBoot Off -ErrorAction SilentlyContinue
    $createdVMs.Add($soName)

    # Splunk
    $splunkName   = "Lab01-Splunk-C${ClassId}-${ShortId}"
    $splunkDisk   = Join-Path $soDir "${splunkName}.vhdx"
    $splunkParent = Join-Path $TemplatePath $Templates.Splunk

    New-DifferencingDisk -ParentPath $splunkParent -ChildPath $splunkDisk | Out-Null
    $createdDisks.Add($splunkDisk)

    $splunkVM = New-LabVM -VMName $splunkName -VHDXPath $splunkDisk `
                          -MemoryMB 8192 -vCPU 4 `
                          -SwitchNames @("shared-monitor-net-C${ClassId}")
    Set-VMFirmware -VMName $splunkName -EnableSecureBoot Off -ErrorAction SilentlyContinue
    $createdVMs.Add($splunkName)

    # Generate shared VM credentials
    $soAnalystPwd    = New-RandomPassword
    $soInstructorPwd = New-RandomPassword
    $splunkAdminPwd  = New-RandomPassword
    $splunkInstrPwd  = New-RandomPassword

    # Start shared VMs
    Write-Step "Starting shared VMs..."
    Start-VM -Name $soName -ErrorAction Stop
    Start-VM -Name $splunkName -ErrorAction Stop

    Wait-VMHeartbeat -VMName $soName    -TimeoutSec 240 | Out-Null
    Wait-VMHeartbeat -VMName $splunkName -TimeoutSec 240 | Out-Null

    $sharedIpBase = "10.${ClassId}.0"

    # Configure Security Onion via SSH
    $soIp = "${sharedIpBase}.50"
    Write-Step "  Configuring Security Onion ($soName)..."
    # Wait for SSH to be available
    $sshReady = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $test = Invoke-SshCommand -TargetIp $soIp -User 'analyst' -Password 'changeme' `
                                  -Command 'echo ssh_ok' -ErrorAction SilentlyContinue
        if ($test -match 'ssh_ok') { $sshReady = $true; break }
        Start-Sleep -Seconds 10
    }

    if ($sshReady) {
        Invoke-SshCommand -TargetIp $soIp -User 'analyst' -Password 'changeme' `
            -Command "echo 'analyst:${soAnalystPwd}' | sudo chpasswd"
        Invoke-SshCommand -TargetIp $soIp -User 'analyst' -Password $soAnalystPwd `
            -Command "sudo useradd -m -s /bin/bash instructor && echo 'instructor:${soInstructorPwd}' | sudo chpasswd && sudo usermod -aG sudo instructor"
    }

    # Configure Splunk via SSH
    $splunkIp = "${sharedIpBase}.51"
    Write-Step "  Configuring Splunk ($splunkName)..."
    $sshReady = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $test = Invoke-SshCommand -TargetIp $splunkIp -User 'splunkadmin' -Password 'changeme' `
                                  -Command 'echo ssh_ok' -ErrorAction SilentlyContinue
        if ($test -match 'ssh_ok') { $sshReady = $true; break }
        Start-Sleep -Seconds 10
    }

    if ($sshReady) {
        Invoke-SshCommand -TargetIp $splunkIp -User 'splunkadmin' -Password 'changeme' `
            -Command "/opt/splunk/bin/splunk edit user admin -password '${splunkAdminPwd}' -auth admin:changeme --accept-license --answer-yes"
        Invoke-SshCommand -TargetIp $splunkIp -User 'splunkadmin' -Password 'changeme' `
            -Command "/opt/splunk/bin/splunk add user instructor -password '${splunkInstrPwd}' -role admin -auth admin:${splunkAdminPwd}"
    }

    # Checkpoint shared VMs
    Checkpoint-VM -Name $soName     -SnapshotName 'InitialState' -ErrorAction SilentlyContinue
    Checkpoint-VM -Name $splunkName -SnapshotName 'InitialState' -ErrorAction SilentlyContinue

    $sessionCredentials['shared'] = @{
        SecurityOnion = @{
            VMName    = $soName
            IPAddress = $soIp
            soanalyst = @{ Username = 'soanalyst';  Password = $soAnalystPwd }
            instructor = @{ Username = 'instructor'; Password = $soInstructorPwd }
        }
        Splunk = @{
            VMName    = $splunkName
            IPAddress = $splunkIp
            admin      = @{ Username = 'admin';      Password = $splunkAdminPwd }
            instructor = @{ Username = 'instructor'; Password = $splunkInstrPwd }
        }
    }

    Write-Step "Shared VMs deployed and configured." 'Green'
} catch {
    Remove-LabSessionResources -Reason "Shared VM deployment failed: $_"
    Stop-Transcript
    throw
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: DEPLOY PER-STUDENT VMs IN PARALLEL
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 3: Deploying per-student VMs (parallel, ThrottleLimit=5) ===" 'Cyan'

# Build argument table for parallel jobs
$studentArgs = for ($idx = 0; $idx -lt $StudentIds.Count; $idx++) {
    [PSCustomObject]@{
        StudentId   = $StudentIds[$idx]
        StudentNum  = $idx + 1
        ClassId     = $ClassId
        SessionId   = $SessionIdStr
        ShortId     = $ShortId
        TemplatePath = $TemplatePath
        VMBasePath   = $VMBasePath
        Templates    = $Templates
    }
}

$studentJobs = $studentArgs | ForEach-Object -ThrottleLimit 5 -Parallel {
    $sa      = $_
    $sid     = $sa.StudentNum
    $student = $sa.StudentId
    $cid     = $sa.ClassId
    $sess    = $sa.SessionId
    $short   = $sa.ShortId
    $tplPath = $sa.TemplatePath
    $vmBase  = $sa.VMBasePath
    $tpls    = $sa.Templates

    $result = @{
        StudentId   = $student
        StudentNum  = $sid
        Success     = $false
        Error       = ''
        Credentials = @{}
        VMNames     = @()
    }

    try {
        # ── Paths ──────────────────────────────────────────────────────────
        $studentDir = Join-Path $vmBase "${sess}\${student}"
        if (-not (Test-Path $studentDir)) { New-Item -ItemType Directory -Path $studentDir -Force | Out-Null }

        $ipBase = "10.${cid}.${sid}"

        # ── VM names ───────────────────────────────────────────────────────
        $names = @{
            Kali    = "Lab01-Kali-C${cid}-S${sid}-${short}"
            Win10   = "Lab01-Win10-C${cid}-S${sid}-${short}"
            WinAD   = "Lab01-WinAD-C${cid}-S${sid}-${short}"
            WebSrv  = "Lab01-Web-C${cid}-S${sid}-${short}"
            PfSense = "Lab01-PfS-C${cid}-S${sid}-${short}"
        }

        # ── Credentials ────────────────────────────────────────────────────
        $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*'
        function GenPwd {
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $b   = [byte[]]::new(16)
            $rng.GetBytes($b)
            return -join ($b | ForEach-Object { $chars[$_ % $chars.Length] })
        }

        $creds = @{
            KaliStudent      = GenPwd
            Win10LabUser     = GenPwd
            Win10Admin       = GenPwd
            WinADAdmin       = GenPwd
            WebSrvAdmin      = GenPwd
            PfSenseAdmin     = GenPwd
        }

        # ── Differencing disks ──────────────────────────────────────────────
        $diskPaths = @{
            Kali    = Join-Path $studentDir "$($names.Kali).vhdx"
            Win10   = Join-Path $studentDir "$($names.Win10).vhdx"
            WinAD   = Join-Path $studentDir "$($names.WinAD).vhdx"
            WebSrv  = Join-Path $studentDir "$($names.WebSrv).vhdx"
            PfSense = Join-Path $studentDir "$($names.PfSense).vhdx"
        }

        $vmRoles = @{
            Kali    = @{ Template = 'kali-linux-2024.1.vhdx';         SecureBoot = $false }
            Win10   = @{ Template = 'windows-10-vulnerable.vhdx';     SecureBoot = $true  }
            WinAD   = @{ Template = 'windows-server-2019-ad.vhdx';    SecureBoot = $true  }
            WebSrv  = @{ Template = 'ubuntu-server-22.04-web.vhdx';   SecureBoot = $false }
            PfSense = @{ Template = 'pfsense-2.7.vhdx';               SecureBoot = $false }
        }

        foreach ($role in $diskPaths.Keys) {
            $parent = Join-Path $tplPath $vmRoles[$role].Template
            New-VHD -Path $diskPaths[$role] -ParentPath $parent -Differencing -ErrorAction Stop | Out-Null
        }

        # ── Create Hyper-V VMs ──────────────────────────────────────────────
        $switches = @{
            Attack    = "attack-net-C${cid}-S${sid}"
            Corporate = "corporate-net-C${cid}-S${sid}"
            DMZ       = "dmz-net-C${cid}-S${sid}"
        }

        $vmSpecs = @(
            @{ Role='PfSense'; Mem=2048; CPU=2; Switches=@($switches.Attack, $switches.Corporate, $switches.DMZ) }
            @{ Role='Win10';   Mem=4096; CPU=2; Switches=@($switches.Corporate) }
            @{ Role='WinAD';   Mem=4096; CPU=2; Switches=@($switches.Corporate) }
            @{ Role='WebSrv';  Mem=2048; CPU=1; Switches=@($switches.DMZ) }
            @{ Role='Kali';    Mem=4096; CPU=2; Switches=@($switches.Attack) }
        )

        $vmObjects = @{}
        foreach ($spec in $vmSpecs) {
            $role   = $spec.Role
            $vmName = $names[$role]
            $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($existing) {
                Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            }

            $vm = New-VM -Name $vmName `
                         -MemoryStartupBytes ([int64]$spec.Mem * 1MB) `
                         -VHDPath $diskPaths[$role] `
                         -SwitchName $spec.Switches[0] `
                         -Generation 2 `
                         -ErrorAction Stop

            Set-VM -Name $vmName -ProcessorCount $spec.CPU -DynamicMemory:$false -ErrorAction Stop

            for ($i = 1; $i -lt $spec.Switches.Count; $i++) {
                Add-VMNetworkAdapter -VMName $vmName -SwitchName $spec.Switches[$i] -ErrorAction Stop
            }

            if (-not $vmRoles[$role].SecureBoot) {
                Set-VMFirmware -VMName $vmName -EnableSecureBoot Off -ErrorAction SilentlyContinue
            }

            $vmObjects[$role] = $vm
            $result.VMNames += $vmName
        }

        # ── Start order: pfSense first, then targets, Kali last ─────────────
        Start-VM -Name $names.PfSense -ErrorAction Stop
        Start-Sleep -Seconds 5
        Start-VM -Name $names.Win10 -ErrorAction Stop
        Start-VM -Name $names.WinAD -ErrorAction Stop
        Start-VM -Name $names.WebSrv -ErrorAction Stop
        Start-Sleep -Seconds 15
        Start-VM -Name $names.Kali -ErrorAction Stop

        # ── Wait for pfSense (routing must be up before configuring targets) ─
        $elapsed = 0
        while ($elapsed -lt 120) {
            $hb = (Get-VM -Name $names.PfSense -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5
            $elapsed += 5
        }

        # ── Configure pfSense via SSH ────────────────────────────────────────
        # pfSense template ships with default admin/pfsense; we reset via SSH
        $pfIp = "${ipBase}.1"   # Management on first interface
        Start-Sleep -Seconds 30 # Give pfSense time to finish booting
        $sshCmds = @(
            # Set admin password
            "echo '${creds.PfSenseAdmin}' | /usr/local/bin/php -r `"require_once('config.inc'); require_once('functions.inc'); \$config['system']['password'] = password_hash(trim(file_get_contents('php://stdin')), PASSWORD_BCRYPT); write_config();`"",
            # Configure LAN interface IPs (each segment .1)
            "pfSsh.php playback changepassword admin ${creds.PfSenseAdmin}"
        )
        foreach ($cmd in $sshCmds) {
            $sshpassArgs = @('-p', 'pfsense', 'ssh', '-o', 'StrictHostKeyChecking=no',
                             '-o', 'ConnectTimeout=15', "admin@${pfIp}", $cmd)
            & sshpass @sshpassArgs 2>&1 | Out-Null
        }

        # ── Wait for Windows VMs (WinRM via PowerShell Direct) ───────────────
        foreach ($winRole in @('Win10','WinAD')) {
            $winName = $names[$winRole]
            $elapsed = 0
            while ($elapsed -lt 180) {
                $hb = (Get-VM -Name $winName -ErrorAction SilentlyContinue).Heartbeat
                if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
        }

        # ── Configure Windows 10 via PowerShell Direct ───────────────────────
        $win10Cred = [PSCredential]::new('Administrator',
            (ConvertTo-SecureString 'Password123!' -AsPlainText -Force))

        Invoke-Command -VMName $names.Win10 -Credential $win10Cred -ScriptBlock {
            param($ip, $gw, $adminPwd, $studentUser, $studentPwd, $compName)
            # Set static IP
            $adap = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if ($adap) {
                Get-NetIPAddress -InterfaceIndex $adap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $adap.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceIndex $adap.ifIndex -IPAddress $ip -PrefixLength 24 -DefaultGateway $gw -ErrorAction SilentlyContinue
            }
            # Update Administrator password
            Set-LocalUser -Name 'Administrator' -Password (ConvertTo-SecureString $adminPwd -AsPlainText -Force) -ErrorAction SilentlyContinue
            # Ensure labuser exists with session-specific password
            $u = Get-LocalUser -Name 'labuser' -ErrorAction SilentlyContinue
            if ($u) { Set-LocalUser -Name 'labuser' -Password (ConvertTo-SecureString $studentPwd -AsPlainText -Force) -ErrorAction SilentlyContinue }
            # Rename computer (requires reboot — do last)
            Rename-Computer -NewName $compName -Force -ErrorAction SilentlyContinue
        } -ArgumentList "${ipBase}.20", "${ipBase}.1", $creds.Win10Admin,
                         'labuser', $creds.Win10LabUser, "WS-C${cid}-S${sid}" -ErrorAction SilentlyContinue

        # ── Configure Windows Server AD via PowerShell Direct ────────────────
        $winADCred = [PSCredential]::new('Administrator',
            (ConvertTo-SecureString 'LabAdmin123!' -AsPlainText -Force))

        Invoke-Command -VMName $names.WinAD -Credential $winADCred -ScriptBlock {
            param($ip, $gw, $adminPwd, $compName)
            $adap = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if ($adap) {
                Get-NetIPAddress -InterfaceIndex $adap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $adap.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceIndex $adap.ifIndex -IPAddress $ip -PrefixLength 24 -DefaultGateway $gw -ErrorAction SilentlyContinue
                Set-DnsClientServerAddress -InterfaceIndex $adap.ifIndex -ServerAddresses '127.0.0.1' -ErrorAction SilentlyContinue
            }
            Set-LocalUser -Name 'Administrator' -Password (ConvertTo-SecureString $adminPwd -AsPlainText -Force) -ErrorAction SilentlyContinue
        } -ArgumentList "${ipBase}.21", "${ipBase}.1", $creds.WinADAdmin, "DC-C${cid}-S${sid}" -ErrorAction SilentlyContinue

        # ── Configure Linux Web Server via SSH ───────────────────────────────
        $webIp = "${ipBase}.30"
        Start-Sleep -Seconds 20
        $sshReady = $false
        for ($attempt = 1; $attempt -le 8; $attempt++) {
            $test = & sshpass -p 'labadmin' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "labadmin@${webIp}" 'echo ssh_ok' 2>&1
            if ($test -match 'ssh_ok') { $sshReady = $true; break }
            Start-Sleep -Seconds 10
        }

        if ($sshReady) {
            $netplanYaml = "network:`n  version: 2`n  ethernets:`n    eth0:`n      addresses: [`"${webIp}/24`"]`n      routes:`n        - to: default`n          via: ${ipBase}.1`n      nameservers:`n        addresses: [8.8.8.8]"
            & sshpass -p 'labadmin' ssh -o StrictHostKeyChecking=no "labadmin@${webIp}" "printf '%s\n' '$netplanYaml' | sudo tee /etc/netplan/50-lab.yaml; sudo netplan apply" 2>&1 | Out-Null
            & sshpass -p 'labadmin' ssh -o StrictHostKeyChecking=no "labadmin@${webIp}" "sudo hostnamectl set-hostname web-c${cid}-s${sid}; echo 'webadmin:$($creds.WebSrvAdmin)' | sudo chpasswd; sudo useradd -m -s /bin/bash webadmin || true" 2>&1 | Out-Null
        }

        # ── Configure Kali via SSH ───────────────────────────────────────────
        $kaliIp = "${ipBase}.10"
        Start-Sleep -Seconds 10
        $sshReady = $false
        for ($attempt = 1; $attempt -le 8; $attempt++) {
            $test = & sshpass -p 'kali' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "kali@${kaliIp}" 'echo ssh_ok' 2>&1
            if ($test -match 'ssh_ok') { $sshReady = $true; break }
            Start-Sleep -Seconds 10
        }

        if ($sshReady) {
            & sshpass -p 'kali' ssh -o StrictHostKeyChecking=no "kali@${kaliIp}" "sudo hostnamectl set-hostname kali-c${cid}-s${sid}; echo 'student:$($creds.KaliStudent)' | sudo chpasswd; sudo useradd -m -s /bin/bash student || true; sudo usermod -aG sudo student" 2>&1 | Out-Null
            # Set static IP on eth0
            $kaliNetplan = "network:`n  version: 2`n  ethernets:`n    eth0:`n      addresses: [`"${kaliIp}/24`"]`n      routes:`n        - to: default`n          via: ${ipBase}.1`n      nameservers:`n        addresses: [8.8.8.8]"
            & sshpass -p 'kali' ssh -o StrictHostKeyChecking=no "kali@${kaliIp}" "printf '%s\n' '$kaliNetplan' | sudo tee /etc/netplan/50-lab.yaml; sudo netplan apply" 2>&1 | Out-Null
        }

        # ── Create InitialState checkpoints ──────────────────────────────────
        foreach ($vmName in $result.VMNames) {
            Checkpoint-VM -Name $vmName -SnapshotName 'InitialState' -ErrorAction SilentlyContinue
        }

        # ── Collect credentials ───────────────────────────────────────────────
        $result.Credentials = @{
            StudentId = $student
            StudentNum = $sid
            Kali = @{
                VMName    = $names.Kali
                IPAddress = $kaliIp
                student   = @{ Username = 'student'; Password = $creds.KaliStudent; Auth = 'SSH password' }
            }
            Windows10 = @{
                VMName       = $names.Win10
                IPAddress    = "${ipBase}.20"
                Administrator = @{ Username = 'Administrator'; Password = $creds.Win10Admin }
                labuser       = @{ Username = 'labuser';       Password = $creds.Win10LabUser; Note = 'Intentionally weak template password also applies; session password set' }
            }
            WindowsAD = @{
                VMName        = $names.WinAD
                IPAddress     = "${ipBase}.21"
                Administrator = @{ Username = 'Administrator'; Password = $creds.WinADAdmin }
                ADUsers       = 'As pre-configured in template (jsmith, bjones, svc.backup, etc.)'
            }
            LinuxWebServer = @{
                VMName    = $names.WebSrv
                IPAddress = $webIp
                webadmin  = @{ Username = 'webadmin'; Password = $creds.WebSrvAdmin; Auth = 'SSH password' }
            }
            pfSense = @{
                VMName    = $names.PfSense
                IPAddress = "${ipBase}.1"
                admin     = @{ Username = 'admin'; Password = $creds.PfSenseAdmin; Auth = 'WebUI + SSH' }
            }
        }

        $result.Success = $true
    } catch {
        $result.Error = $_.ToString()
    }

    return $result
}

# Collect parallel job results
$allStudentResults = @($studentJobs)

$failedStudents = @($allStudentResults | Where-Object { -not $_.Success })
if ($failedStudents.Count -gt 0) {
    Write-Warning "$($failedStudents.Count) student deployment(s) failed:"
    foreach ($f in $failedStudents) {
        Write-Warning "  Student $($f.StudentId): $($f.Error)"
    }
}

foreach ($r in $allStudentResults) {
    if ($r.Success) {
        $sessionCredentials["student_$($r.StudentId)"] = $r.Credentials
    }
}

Write-Step "Per-student VM deployment complete." 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: READINESS VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 4: Validating lab readiness ===" 'Cyan'

$readinessReport = @{}
$allLabVMs = Get-VM | Where-Object { $_.Name -like "*-${ShortId}" }

foreach ($vm in $allLabVMs) {
    $hb     = $vm.Heartbeat
    $status = if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { 'Ready' } else { "NotReady ($hb)" }
    $readinessReport[$vm.Name] = @{
        State     = $vm.State.ToString()
        Heartbeat = $hb.ToString()
        Status    = $status
    }
    $color = if ($status -eq 'Ready') { 'Green' } else { 'Red' }
    Write-Step "  $($vm.Name): $status" $color
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: EXPORT CREDENTIAL MANIFEST
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 5: Exporting credentials ===" 'Cyan'

if (-not (Test-Path $SessionsPath)) { New-Item -ItemType Directory -Path $SessionsPath -Force | Out-Null }

$credManifest = @{
    SessionId   = $SessionIdStr
    LabId       = 1
    LabName     = 'Red Team / Blue Team'
    ClassId     = $ClassId
    GeneratedAt = (Get-Date -Format 'o')
    Credentials = $sessionCredentials
    Readiness   = $readinessReport
}

$credJson = $credManifest | ConvertTo-Json -Depth 10
$credFile = Join-Path $SessionsPath "${SessionIdStr}-credentials.json"
$credJson | Set-Content -Path $credFile -Encoding UTF8

# Restrict file permissions
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" 2>&1 | Out-Null

Write-Step "Credentials written to: $credFile" 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: DEPLOYMENT SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
$DeployEnd  = Get-Date
$Elapsed    = $DeployEnd - $DeployStart
$labVMs     = @(Get-VM | Where-Object { $_.Name -like "*-${ShortId}" })
$totalRAMMB = ($labVMs | Measure-Object -Property MemoryStartup -Sum).Sum / 1MB
$diskUsedGB = [math]::Round(
    (Get-ChildItem -Path (Join-Path $VMBasePath $SessionIdStr) -Recurse -File -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum / 1GB, 2)

Write-Host ""
Write-Host ('=' * 70) -ForegroundColor Green
Write-Host "  DEPLOYMENT SUMMARY — Lab 01 Red Team / Blue Team" -ForegroundColor Green
Write-Host ('=' * 70) -ForegroundColor Green
Write-Host "  Session ID      : $SessionIdStr"
Write-Host "  Class ID        : $ClassId"
Write-Host "  Students        : $($StudentIds.Count)"
Write-Host "  VMs Deployed    : $($labVMs.Count)"
Write-Host "  Total RAM Alloc : $([math]::Round($totalRAMMB / 1024, 1)) GB"
Write-Host "  Total Disk Used : ${diskUsedGB} GB"
Write-Host "  Time Elapsed    : $($Elapsed.ToString('hh\:mm\:ss'))"
Write-Host "  Credentials     : $credFile"
Write-Host "  Log             : $TranscriptFile"
Write-Host ('=' * 70) -ForegroundColor Green

Stop-Transcript
