#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Deploy Lab 04 — Network Attack and Defense

.DESCRIPTION
    Orchestrates the full deployment of the Network Attack and Defense lab.
    Students attack a multi-layer network through pfSense, discover and exploit
    an intentionally misconfigured VyOS router (Telnet, weak SNMP, weak passwords),
    then pivot to harden both the pfSense firewall and VyOS router as a defensive exercise.

    VMs Deployed (per student, up to 15 students)
    -----------------------------------------------
      - Kali Linux 2024.1      (attacker — on attack-net, outside pfSense WAN)
      - pfSense 2.7            (WAN=attack-net, LAN=internal-net — intentional firewall rules)
      - VyOS 1.4 Vulnerable    (router on internal-net — telnet, weak SNMP, weak password)
      - Ubuntu Server 22.04    (victim host on internal-net, routes via VyOS)
      - Windows Server 2019    (victim host on internal-net, routes via VyOS)

    Network Topology (ClassId=1, StudentId=7 example)
    --------------------------------------------------

    [Kali 10.1.7.10]
          |
    attack-net-C1-S7 (Private)
          |
    [pfSense WAN=10.1.7.1  LAN=10.1.7.1]
          |
    internal-net-C1-S7 (Private)
      |           |            |
    [VyOS .2] [Ubuntu .20] [WinSrv .21]
    (routes internal traffic)

    Attack path:
      Kali → attack pfSense (intentional WAN rules) → reach internal-net
           → Discover VyOS via Telnet (port 23) / SNMP community 'public'
           → VyOS credentials: vyos / vyos123 (intentionally weak)
           → Pivot to Ubuntu and Windows Server

    Defense exercise:
      - Harden pfSense: close overly permissive WAN rules, enable IDS
      - Harden VyOS: disable Telnet, change SNMP community, set strong password

    Start Order: pfSense → VyOS → Ubuntu + Windows Server → Kali

    Timing Estimates
    ----------------
    - Switch creation            :  ~20 seconds
    - Per-student parallel deploy:  ~10-15 minutes (ThrottleLimit=5)
    - Total (15 students)        :  ~20-30 minutes

.PARAMETER SessionId
    GUID identifying this class session.

.PARAMETER ClassId
    1 or 2. Maps to the second IP octet.

.PARAMETER StudentIds
    Array of student identifiers (1-15 entries).

.PARAMETER TimeoutMinutes
    Maximum deployment time in minutes. Default 120.

.EXAMPLE
    .\Deploy-04-NetworkAttackDefense.ps1 `
        -SessionId ([guid]::NewGuid()) `
        -ClassId 2 `
        -StudentIds @('alice','bob','carol')

.NOTES
    Author  : SCPS CyberLab Orchestration System
    Lab     : 04 — Network Attack and Defense
    Version : 1.0.0

    INTENTIONAL VULNERABILITIES (educational purposes only):
      - VyOS: Telnet enabled (port 23), SNMP community 'public', password 'vyos123'
      - pfSense: overly permissive WAN-to-LAN rules allowing student attack paths
    These are deliberately configured for students to discover and then remediate.
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
$LabNum        = '04'

# ── Transcript ────────────────────────────────────────────────────────────────
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$TranscriptFile = Join-Path $LogPath "Deploy-Lab${LabNum}-${ShortId}-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $TranscriptFile -Force

$DeployStart = Get-Date
Write-Host ('=' * 70) -ForegroundColor Cyan
Write-Host "  SCPS CyberLab — Deploy Lab 04: Network Attack and Defense" -ForegroundColor Cyan
Write-Host "  Session  : $SessionIdStr" -ForegroundColor Cyan
Write-Host "  ClassId  : $ClassId" -ForegroundColor Cyan
Write-Host "  Students : $($StudentIds -join ', ')" -ForegroundColor Cyan
Write-Host "  Started  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host ('=' * 70) -ForegroundColor Cyan

# ── Templates ────────────────────────────────────────────────────────────────
$Templates = @{
    Kali    = 'kali-linux-2024.1.vhdx'
    PfSense = 'pfsense-2.7.vhdx'
    VyOS    = 'vyos-1.4-vulnerable.vhdx'
    Ubuntu  = 'ubuntu-server-22.04.vhdx'
    WinSrv  = 'windows-server-2019.vhdx'
}

$createdSwitches    = [System.Collections.Generic.List[string]]::new()
$createdVMs         = [System.Collections.Generic.List[string]]::new()
$sessionCredentials = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()

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
    param([Parameter(Mandatory)][string]$ParentPath, [Parameter(Mandatory)][string]$ChildPath)
    if (-not (Test-Path $ParentPath)) { throw "Parent VHDX not found: $ParentPath" }
    $dir = Split-Path $ChildPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    New-VHD -Path $ChildPath -ParentPath $ParentPath -Differencing -ErrorAction Stop | Out-Null
    Write-Step "  Differencing disk: $(Split-Path $ChildPath -Leaf)"
}

function New-LabVM {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$VHDXPath,
        [Parameter(Mandatory)][int]$MemoryMB,
        [Parameter(Mandatory)][int]$vCPU,
        [Parameter(Mandatory)][string[]]$SwitchNames,
        [bool]$SecureBoot = $false
    )
    $existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    }
    $vm = New-VM -Name $VMName -MemoryStartupBytes ([int64]$MemoryMB * 1MB) `
                 -VHDPath $VHDXPath -SwitchName $SwitchNames[0] -Generation 2 -ErrorAction Stop
    Set-VM -Name $VMName -ProcessorCount $vCPU -DynamicMemory:$false -ErrorAction Stop
    for ($i = 1; $i -lt $SwitchNames.Count; $i++) {
        Add-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchNames[$i] -ErrorAction Stop
    }
    Set-VMFirmware -VMName $VMName -EnableSecureBoot:$SecureBoot -ErrorAction SilentlyContinue
    Write-Step "  VM created: $VMName ($vCPU vCPU, ${MemoryMB}MB)"
    return $vm
}

function Wait-VMHeartbeat {
    param([Parameter(Mandatory)][string]$VMName, [int]$TimeoutSec = 180)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $hb = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).Heartbeat
        if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) {
            Write-Step "  Heartbeat OK: $VMName (${elapsed}s)"; return $true
        }
        Start-Sleep -Seconds 5; $elapsed += 5
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
    Invoke-Command -VMName $VMName -Credential $Cred -ScriptBlock {
        param($cfg)
        if ($cfg.IPAddress) {
            $adap = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if ($adap) {
                Get-NetIPAddress -InterfaceIndex $adap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $adap.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceIndex $adap.ifIndex -IPAddress $cfg.IPAddress -PrefixLength 24 `
                    -DefaultGateway $cfg.Gateway -ErrorAction SilentlyContinue
            }
        }
        if ($cfg.AdminPassword) {
            Set-LocalUser -Name 'Administrator' -Password (ConvertTo-SecureString $cfg.AdminPassword -AsPlainText -Force) -ErrorAction SilentlyContinue
        }
    } -ArgumentList $Config -ErrorAction SilentlyContinue
}

function Set-LinuxVMConfig {
    param(
        [Parameter(Mandatory)][string]$TargetIp,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Password,
        [string]$NewIp,
        [string]$Gateway,
        [string]$Hostname,
        [string[]]$ExtraCommands = @()
    )
    $allCmds = @()
    if ($Hostname) { $allCmds += "sudo hostnamectl set-hostname '${Hostname}'" }
    if ($NewIp -and $Gateway) {
        $yaml = "network:`n  version: 2`n  ethernets:`n    eth0:`n      addresses: [`"${NewIp}/24`"]`n      routes:`n        - to: default`n          via: ${Gateway}`n      nameservers:`n        addresses: [8.8.8.8]"
        $allCmds += "printf '${yaml}' | sudo tee /etc/netplan/50-lab.yaml && sudo netplan apply"
    }
    $allCmds += $ExtraCommands
    foreach ($cmd in $allCmds) {
        & sshpass -p $Password ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "${User}@${TargetIp}" $cmd 2>&1 | Out-Null
    }
}

function Invoke-EnsureVMSwitch {
    param([Parameter(Mandatory)][string]$SwitchName, [string]$SwitchType = 'Private')
    if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name $SwitchName -SwitchType $SwitchType -ErrorAction Stop | Out-Null
        $script:createdSwitches.Add($SwitchName)
        Write-Step "  Switch created: $SwitchName ($SwitchType)"
    }
}

function Remove-LabSessionResources {
    param([string]$Reason = 'Deployment failure')
    Write-Warning "ROLLBACK: $Reason"
    foreach ($vmName in $createdVMs) {
        try {
            Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
            Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue | Remove-VMSnapshot -Confirm:$false -ErrorAction SilentlyContinue
            Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        } catch { Write-Warning "Could not remove VM $vmName : $_" }
    }
    $sessionDir = Join-Path $VMBasePath $SessionIdStr
    if (Test-Path $sessionDir) { Remove-Item -Path $sessionDir -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($sw in $createdSwitches) {
        try { Remove-VMSwitch -Name $sw -Force -ErrorAction SilentlyContinue } catch { }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 0: PREREQUISITES VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 0: Validating prerequisites ===" 'Cyan'

$vmms = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
if (-not $vmms -or $vmms.Status -ne 'Running') { throw "Hyper-V vmms is not running." }

foreach ($tplKey in $Templates.Keys) {
    $p = Join-Path $TemplatePath $Templates[$tplKey]
    if (-not (Test-Path $p)) { throw "Missing template: $p" }
    Write-Step "  Template OK: $($Templates[$tplKey])"
}

$estimatedGB = $StudentIds.Count * 5 * 14
$vmDrive = Split-Path $VMBasePath -Qualifier
$disk    = Get-PSDrive -Name $vmDrive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($disk) {
    $freeGB = [math]::Round($disk.Free / 1GB, 1)
    Write-Step "  Disk free: ${freeGB}GB  Estimated needed: ~${estimatedGB}GB"
    if ($freeGB -lt $estimatedGB) { Write-Warning "Low disk space. Proceeding anyway." }
}

foreach ($dir in @($VMBasePath, $LogPath, $SessionsPath)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
$sessionRoot = Join-Path $VMBasePath $SessionIdStr
if (-not (Test-Path $sessionRoot)) { New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null }
Write-Step "Prerequisites validated." 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: VIRTUAL SWITCHES
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 1: Creating virtual switches ===" 'Cyan'

try {
    for ($idx = 0; $idx -lt $StudentIds.Count; $idx++) {
        $sid = $idx + 1
        Invoke-EnsureVMSwitch -SwitchName "attack-net-C${ClassId}-S${sid}"   -SwitchType Private
        Invoke-EnsureVMSwitch -SwitchName "internal-net-C${ClassId}-S${sid}" -SwitchType Private
    }
    Write-Step "All switches created." 'Green'
} catch {
    Remove-LabSessionResources -Reason "Switch creation failed: $_"
    Stop-Transcript; throw
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: PER-STUDENT DEPLOYMENT (PARALLEL)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 2: Per-student deployment (parallel, ThrottleLimit=5) ===" 'Cyan'

$studentArgs = for ($idx = 0; $idx -lt $StudentIds.Count; $idx++) {
    [PSCustomObject]@{
        StudentId    = $StudentIds[$idx]
        StudentNum   = $idx + 1
        ClassId      = $ClassId
        SessionId    = $SessionIdStr
        ShortId      = $ShortId
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

    $result = @{ StudentId=$student; StudentNum=$sid; Success=$false; Error=''; Credentials=@{}; VMNames=@() }

    try {
        $studentDir = Join-Path $vmBase "${sess}\${student}"
        if (-not (Test-Path $studentDir)) { New-Item -ItemType Directory -Path $studentDir -Force | Out-Null }

        $ipBase       = "10.${cid}.${sid}"
        $attackSwitch = "attack-net-C${cid}-S${sid}"
        $intSwitch    = "internal-net-C${cid}-S${sid}"

        $names = @{
            Kali    = "Lab04-Kali-C${cid}-S${sid}-${short}"
            PfSense = "Lab04-PfS-C${cid}-S${sid}-${short}"
            VyOS    = "Lab04-VyOS-C${cid}-S${sid}-${short}"
            Ubuntu  = "Lab04-Ubu-C${cid}-S${sid}-${short}"
            WinSrv  = "Lab04-WSrv-C${cid}-S${sid}-${short}"
        }

        # Credentials
        $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*'
        function GenPwd {
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $b   = [byte[]]::new(16); $rng.GetBytes($b)
            return -join ($b | ForEach-Object { $chars[$_ % $chars.Length] })
        }
        $creds = @{
            KaliStudent  = GenPwd
            PfSenseAdmin = GenPwd
            VyOSWeak     = 'vyos123'           # INTENTIONAL VULNERABILITY — for attack phase
            VyOSStrong   = GenPwd              # Used by students in defensive hardening phase
            UbuntuAdmin  = GenPwd
            WinSrvAdmin  = GenPwd
        }

        # VM definitions
        $vmDefs = @(
            @{ Role='PfSense'; Template='pfsense-2.7.vhdx';          Mem=2048; CPU=2; SB=$false; Switches=@($attackSwitch, $intSwitch) }
            @{ Role='VyOS';    Template='vyos-1.4-vulnerable.vhdx';   Mem=1024; CPU=1; SB=$false; Switches=@($intSwitch) }
            @{ Role='Ubuntu';  Template='ubuntu-server-22.04.vhdx';   Mem=2048; CPU=1; SB=$false; Switches=@($intSwitch) }
            @{ Role='WinSrv';  Template='windows-server-2019.vhdx';   Mem=4096; CPU=2; SB=$true;  Switches=@($intSwitch) }
            @{ Role='Kali';    Template='kali-linux-2024.1.vhdx';     Mem=4096; CPU=2; SB=$false; Switches=@($attackSwitch) }
        )

        # Create differencing disks
        $diskPaths = @{}
        foreach ($def in $vmDefs) {
            $role   = $def.Role
            $parent = Join-Path $tplPath $def.Template
            $child  = Join-Path $studentDir "$($names[$role]).vhdx"
            New-VHD -Path $child -ParentPath $parent -Differencing -ErrorAction Stop | Out-Null
            $diskPaths[$role] = $child
        }

        # Create Hyper-V VMs
        foreach ($def in $vmDefs) {
            $role   = $def.Role
            $vmName = $names[$role]
            $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($existing) {
                Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            }
            $vm = New-VM -Name $vmName -MemoryStartupBytes ([int64]$def.Mem * 1MB) `
                         -VHDPath $diskPaths[$role] -SwitchName $def.Switches[0] `
                         -Generation 2 -ErrorAction Stop
            Set-VM -Name $vmName -ProcessorCount $def.CPU -DynamicMemory:$false -ErrorAction Stop
            for ($i = 1; $i -lt $def.Switches.Count; $i++) {
                Add-VMNetworkAdapter -VMName $vmName -SwitchName $def.Switches[$i] -ErrorAction Stop
            }
            Set-VMFirmware -VMName $vmName -EnableSecureBoot:$def.SB -ErrorAction SilentlyContinue
            $result.VMNames += $vmName
        }

        # Start order: pfSense → VyOS → Ubuntu + Windows → Kali
        Start-VM -Name $names.PfSense -ErrorAction Stop
        Start-Sleep -Seconds 10
        Start-VM -Name $names.VyOS -ErrorAction Stop
        Start-Sleep -Seconds 5
        Start-VM -Name $names.Ubuntu -ErrorAction Stop
        Start-VM -Name $names.WinSrv -ErrorAction Stop
        Start-Sleep -Seconds 20
        Start-VM -Name $names.Kali -ErrorAction Stop

        # Wait for pfSense
        $elapsed = 0
        while ($elapsed -lt 120) {
            $hb = (Get-VM -Name $names.PfSense -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5; $elapsed += 5
        }

        # Configure pfSense via SSH
        # WAN face is attack-net (.1), LAN face is internal-net (.1)
        $pfWanIp = "${ipBase}.1"
        Start-Sleep -Seconds 30
        $pfCmds = @(
            "pfSsh.php playback changepassword admin $($creds.PfSenseAdmin)"
        )
        foreach ($cmd in $pfCmds) {
            & sshpass -p 'pfsense' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "admin@${pfWanIp}" $cmd 2>&1 | Out-Null
        }

        # Wait for VyOS heartbeat
        $elapsed = 0
        while ($elapsed -lt 120) {
            $hb = (Get-VM -Name $names.VyOS -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5; $elapsed += 5
        }

        # Configure VyOS via SSH (vbash)
        # The template ships with default vyos/vyos password
        $vyosIp = "${ipBase}.2"
        Start-Sleep -Seconds 30
        $sshReady = $false
        for ($a = 1; $a -le 8; $a++) {
            $r = & sshpass -p 'vyos' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "vyos@${vyosIp}" 'echo ssh_ok' 2>&1
            if ($r -match 'ssh_ok') { $sshReady = $true; break }
            Start-Sleep -Seconds 10
        }

        if ($sshReady) {
            # Configure VyOS using vbash commands — set interface IPs, enable Telnet, SNMP
            # INTENTIONAL VULNERABILITIES: Telnet port 23, SNMP community 'public', weak password
            $vyosConfig = @(
                "source /opt/vyatta/etc/functions/script-template",
                "configure",
                "set interfaces ethernet eth0 address '${vyosIp}/24'",
                "set interfaces ethernet eth0 description 'internal-net'",
                "set system host-name 'vyos-net-c${cid}-s${sid}'",
                # INTENTIONAL VULNERABILITY: set weak password
                "set system login user vyos authentication plaintext-password '${creds.VyOSWeak}'",
                # INTENTIONAL VULNERABILITY: enable Telnet (deprecated, cleartext)
                "set service telnet port 23",
                # INTENTIONAL VULNERABILITY: enable SNMP with public community
                "set service snmp community public authorization ro",
                "set service snmp community public network 0.0.0.0/0",
                "set service snmp listen-address ${vyosIp} port 161",
                "commit",
                "save",
                "exit"
            )
            $vyosConfigStr = $vyosConfig -join '; '
            & sshpass -p 'vyos' ssh -o StrictHostKeyChecking=no "vyos@${vyosIp}" "vbash -c '${vyosConfigStr}'" 2>&1 | Out-Null
        }

        # Wait for Windows Server and configure via PowerShell Direct
        $elapsed = 0
        while ($elapsed -lt 240) {
            $hb = (Get-VM -Name $names.WinSrv -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5; $elapsed += 5
        }

        $winSrvCred = [PSCredential]::new('Administrator',
            (ConvertTo-SecureString 'LabAdmin123!' -AsPlainText -Force))

        Invoke-Command -VMName $names.WinSrv -Credential $winSrvCred -ScriptBlock {
            param($ip, $gw, $adminPwd)
            $adap = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if ($adap) {
                Get-NetIPAddress -InterfaceIndex $adap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetRoute -InterfaceIndex $adap.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                New-NetIPAddress -InterfaceIndex $adap.ifIndex -IPAddress $ip -PrefixLength 24 `
                    -DefaultGateway $gw -ErrorAction SilentlyContinue
            }
            Set-LocalUser -Name 'Administrator' -Password (ConvertTo-SecureString $adminPwd -AsPlainText -Force) -ErrorAction SilentlyContinue
        } -ArgumentList "${ipBase}.21", "${ipBase}.2", $creds.WinSrvAdmin -ErrorAction SilentlyContinue

        # Configure Ubuntu via SSH
        $ubuntuIp = "${ipBase}.20"
        $elapsed = 0
        while ($elapsed -lt 180) {
            $hb = (Get-VM -Name $names.Ubuntu -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5; $elapsed += 5
        }
        Start-Sleep -Seconds 20

        $sshReady = $false
        for ($a = 1; $a -le 8; $a++) {
            $r = & sshpass -p 'labadmin' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "labadmin@${ubuntuIp}" 'echo ssh_ok' 2>&1
            if ($r -match 'ssh_ok') { $sshReady = $true; break }
            Start-Sleep -Seconds 10
        }

        if ($sshReady) {
            # Route through VyOS (.2), not pfSense (.1)
            $ubuntuCmds = @(
                "sudo hostnamectl set-hostname ubuntu-int-c${cid}-s${sid}",
                "printf 'network:\n  version: 2\n  ethernets:\n    eth0:\n      addresses: [\"${ubuntuIp}/24\"]\n      routes:\n        - to: default\n          via: ${ipBase}.2\n      nameservers:\n        addresses: [8.8.8.8]' | sudo tee /etc/netplan/50-lab.yaml && sudo netplan apply",
                "echo 'ubadmin:$($creds.UbuntuAdmin)' | sudo chpasswd",
                "sudo useradd -m -s /bin/bash ubadmin || true"
            )
            foreach ($cmd in $ubuntuCmds) {
                & sshpass -p 'labadmin' ssh -o StrictHostKeyChecking=no "labadmin@${ubuntuIp}" $cmd 2>&1 | Out-Null
            }
        }

        # Configure Kali
        $kaliIp = "${ipBase}.10"
        Start-Sleep -Seconds 10
        $elapsed = 0
        while ($elapsed -lt 180) {
            $hb = (Get-VM -Name $names.Kali -ErrorAction SilentlyContinue).Heartbeat
            if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { break }
            Start-Sleep -Seconds 5; $elapsed += 5
        }

        $sshReady = $false
        for ($a = 1; $a -le 8; $a++) {
            $r = & sshpass -p 'kali' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "kali@${kaliIp}" 'echo ssh_ok' 2>&1
            if ($r -match 'ssh_ok') { $sshReady = $true; break }
            Start-Sleep -Seconds 10
        }

        if ($sshReady) {
            $kaliCmds = @(
                "echo 'student:$($creds.KaliStudent)' | sudo chpasswd",
                "sudo useradd -m -s /bin/bash student || true",
                "sudo usermod -aG sudo student",
                "sudo hostnamectl set-hostname kali-attack-c${cid}-s${sid}",
                "printf 'network:\n  version: 2\n  ethernets:\n    eth0:\n      addresses: [\"${kaliIp}/24\"]\n      routes:\n        - to: default\n          via: ${ipBase}.1\n      nameservers:\n        addresses: [8.8.8.8]' | sudo tee /etc/netplan/50-lab.yaml && sudo netplan apply"
            )
            foreach ($cmd in $kaliCmds) {
                & sshpass -p 'kali' ssh -o StrictHostKeyChecking=no "kali@${kaliIp}" $cmd 2>&1 | Out-Null
            }
        }

        # Create InitialState checkpoints on all VMs
        foreach ($vmName in $result.VMNames) {
            Checkpoint-VM -Name $vmName -SnapshotName 'InitialState' -ErrorAction SilentlyContinue
        }

        $result.Credentials = @{
            StudentId = $student
            StudentNum = $sid
            Kali = @{
                VMName    = $names.Kali
                IPAddress = $kaliIp
                student   = @{ Username = 'student'; Password = $creds.KaliStudent; Auth = 'SSH password' }
                Network   = 'attack-net — can reach pfSense WAN'
            }
            pfSense = @{
                VMName    = $names.PfSense
                WANIp     = "${ipBase}.1"
                LANIp     = "${ipBase}.1"
                admin     = @{ Username = 'admin'; Password = $creds.PfSenseAdmin }
                Note      = 'Intentional WAN rules allow attack path — students harden in defense phase'
            }
            VyOS = @{
                VMName    = $names.VyOS
                IPAddress = $vyosIp
                AttackPhase = @{
                    Username = 'vyos'
                    Password = $creds.VyOSWeak
                    Note     = 'INTENTIONAL VULNERABILITY — weak password for attack practice'
                }
                DefensePhase = @{
                    StrongPassword = $creds.VyOSStrong
                    Note           = 'Students should apply this during defensive hardening'
                }
                IntentionalVulns = @(
                    'Telnet enabled on port 23'
                    "SNMP community 'public' — read-only — allows full MIB walk"
                    'Weak password: vyos123'
                )
            }
            Ubuntu = @{
                VMName    = $names.Ubuntu
                IPAddress = $ubuntuIp
                ubadmin   = @{ Username = 'ubadmin'; Password = $creds.UbuntuAdmin }
                Network   = 'internal-net — routes via VyOS (.2)'
            }
            WindowsServer = @{
                VMName        = $names.WinSrv
                IPAddress     = "${ipBase}.21"
                Administrator = @{ Username = 'Administrator'; Password = $creds.WinSrvAdmin }
                Network       = 'internal-net — routes via VyOS (.2)'
            }
        }

        $result.Success = $true
    } catch {
        $result.Error = $_.ToString()
    }
    return $result
}

$allStudentResults = @($studentJobs)
foreach ($r in $allStudentResults) {
    if ($r.Success) { $sessionCredentials["student_$($r.StudentId)"] = $r.Credentials }
    else { Write-Warning "Student $($r.StudentId) failed: $($r.Error)" }
}

Write-Step "Per-student deployment complete." 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: READINESS VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 3: Readiness validation ===" 'Cyan'

$readinessReport = @{}
$allLabVMs = Get-VM | Where-Object { $_.Name -like "*-${ShortId}" }
foreach ($vm in $allLabVMs) {
    $hb     = $vm.Heartbeat
    $status = if ($hb -in @('OkApplicationsHealthy','OkApplicationsUnknown')) { 'Ready' } else { "NotReady ($hb)" }
    $readinessReport[$vm.Name] = @{ State=$vm.State.ToString(); Heartbeat=$hb.ToString(); Status=$status }
    Write-Step "  $($vm.Name): $status" $(if ($status -eq 'Ready') { 'Green' } else { 'Red' })
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: EXPORT CREDENTIALS
# ═══════════════════════════════════════════════════════════════════════════════
Write-Step "=== STEP 4: Exporting credentials ===" 'Cyan'

if (-not (Test-Path $SessionsPath)) { New-Item -ItemType Directory -Path $SessionsPath -Force | Out-Null }

$credManifest = @{
    SessionId   = $SessionIdStr
    LabId       = 4
    LabName     = 'Network Attack and Defense'
    ClassId     = $ClassId
    GeneratedAt = (Get-Date -Format 'o')
    IntentionalVulnerabilities = @(
        'VyOS Telnet enabled (port 23) — cleartext credentials'
        "VyOS SNMP community 'public' — full MIB read access"
        'VyOS password: vyos123 — intentionally weak'
        'pfSense WAN rules: intentionally permissive to allow student attack path'
    )
    Credentials = $sessionCredentials
    Readiness   = $readinessReport
}

$credFile = Join-Path $SessionsPath "${SessionIdStr}-credentials.json"
($credManifest | ConvertTo-Json -Depth 10) | Set-Content -Path $credFile -Encoding UTF8
icacls $credFile /inheritance:r /grant "BUILTIN\Administrators:F" 2>&1 | Out-Null
Write-Step "Credentials written to: $credFile" 'Green'

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: DEPLOYMENT SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
$DeployEnd  = Get-Date
$Elapsed    = $DeployEnd - $DeployStart
$labVMs     = @(Get-VM | Where-Object { $_.Name -like "*-${ShortId}" })
$totalRAMMB = ($labVMs | Measure-Object -Property MemoryStartup -Sum).Sum / 1MB
$diskUsedGB = [math]::Round(
    (Get-ChildItem -Path (Join-Path $VMBasePath $SessionIdStr) -Recurse -File -ErrorAction SilentlyContinue |
     Measure-Object -Property Length -Sum).Sum / 1GB, 2)

Write-Host ''
Write-Host ('=' * 70) -ForegroundColor Green
Write-Host "  DEPLOYMENT SUMMARY — Lab 04 Network Attack and Defense" -ForegroundColor Green
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
Write-Host ''
Write-Host "  INTENTIONAL VULNERABILITIES DEPLOYED:" -ForegroundColor Yellow
Write-Host "  - VyOS Telnet (port 23) enabled — cleartext credential exposure" -ForegroundColor Yellow
Write-Host "  - VyOS SNMP community 'public' — full MIB read" -ForegroundColor Yellow
Write-Host "  - VyOS password: vyos123 — for brute-force/dict attack practice" -ForegroundColor Yellow
Write-Host "  - pfSense WAN rules: permissive to allow student attack path" -ForegroundColor Yellow
Write-Host ('=' * 70) -ForegroundColor Green

Stop-Transcript
