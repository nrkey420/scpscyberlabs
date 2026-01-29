#Requires -Modules Hyper-V
<#
.SYNOPSIS
    CyberLab Orchestration Platform - Hyper-V Lab Management Module
.DESCRIPTION
    Provides functions for provisioning, managing, and cleaning up
    cybersecurity lab sessions built on Hyper-V differencing disks.
#>

# ─── Module-scoped configuration ─────────────────────────────────────────────
$script:VMStoragePath      = 'C:\CyberLab\VMs'
$script:TemplateStoragePath = 'C:\CyberLab\Templates'
$script:TotalRAMGB         = 115
$script:TotalvCPU          = 22
$script:OverheadPct        = 0.10

# ─── Helper: generate random password ────────────────────────────────────────
function New-RandomPassword {
    param([int]$Length = 16)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

# ═══════════════════════════════════════════════════════════════════════════════
# New-CyberLabSession
# ═══════════════════════════════════════════════════════════════════════════════
function New-CyberLabSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$SessionId,
        [Parameter(Mandatory)][object]$TemplateDefinition,
        [Parameter(Mandatory)][string[]]$StudentIds,
        [Parameter(Mandatory)][string]$VirtualSwitchName
    )

    try {
        Write-Verbose "Creating lab session $SessionId"

        # Create session VM folder
        $sessionPath = Join-Path $script:VMStoragePath $SessionId.ToString()
        if (-not (Test-Path $sessionPath)) {
            New-Item -Path $sessionPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created session directory: $sessionPath"
        }

        # Create virtual switch
        New-LabVirtualSwitch -SwitchName $VirtualSwitchName -SwitchType Private
        Write-Verbose "Virtual switch '$VirtualSwitchName' ready"

        # Sort VM definitions by boot order
        $vmDefs = $TemplateDefinition.vmDefinitions | Sort-Object { $_.bootOrder }

        $vmDetails = @()
        foreach ($vmDef in $vmDefs) {
            $vmName = "$($vmDef.name)-$($SessionId.ToString().Substring(0,8))"
            Write-Verbose "Provisioning VM: $vmName"

            # Create differencing disk
            $parentDisk = Join-Path $script:TemplateStoragePath $vmDef.parentDisk
            $diffDiskPath = Join-Path $sessionPath "$vmName.vhdx"

            New-VHD -Path $diffDiskPath -ParentPath $parentDisk -Differencing -ErrorAction Stop | Out-Null
            Write-Verbose "Created differencing disk: $diffDiskPath"

            # Create VM
            $ramBytes = [int64]$vmDef.ramMB * 1MB
            $vm = New-VM -Name $vmName `
                         -MemoryStartupBytes $ramBytes `
                         -VHDPath $diffDiskPath `
                         -SwitchName $VirtualSwitchName `
                         -Generation 2 `
                         -ErrorAction Stop

            # Configure vCPU
            Set-VM -VM $vm -ProcessorCount $vmDef.vcpuCount -ErrorAction Stop

            # Generate credentials
            $password = New-RandomPassword
            $credential = [PSCredential]::new(
                $vmDef.adminUser,
                (ConvertTo-SecureString $password -AsPlainText -Force)
            )

            # Start VM and wait for heartbeat
            Start-LabVM -HyperVVMId $vm.VMId
            Write-Verbose "VM '$vmName' started and heartbeat detected"

            # Set credentials via PowerShell Direct
            Set-LabVMCredentials -HyperVVMId $vm.VMId -Credential $credential

            # Configure networking inside the guest if IP info supplied
            if ($vmDef.ipAddress) {
                Invoke-Command -VMId $vm.VMId -Credential $credential -ScriptBlock {
                    param($ip, $prefix, $gateway)
                    $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
                    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gateway -ErrorAction SilentlyContinue
                } -ArgumentList $vmDef.ipAddress, ($vmDef.prefixLength ?? 24), $vmDef.gateway -ErrorAction SilentlyContinue
            }

            # Create initial snapshot
            New-LabSnapshot -HyperVVMId $vm.VMId -SnapshotName 'InitialState'

            $vmDetails += @{
                VMName             = $vmName
                HyperVVMId         = $vm.VMId
                Role               = $vmDef.role
                DifferencingDisk   = $diffDiskPath
                RAMMB              = $vmDef.ramMB
                vCPUCount          = $vmDef.vcpuCount
                IPAddress          = $vmDef.ipAddress
                AdminUser          = $vmDef.adminUser
                AdminPassword      = $password
                Status             = 'Running'
            }
        }

        $result = @{
            SessionId          = $SessionId
            VirtualSwitchName  = $VirtualSwitchName
            StudentIds         = $StudentIds
            VMs                = $vmDetails
            CreatedAt          = [DateTimeOffset]::UtcNow
            Status             = 'Running'
        }

        Write-Verbose "Lab session $SessionId created with $($vmDetails.Count) VMs"
        return $result
    }
    catch {
        Write-Error "Failed to create lab session $SessionId : $_"
        # Best-effort cleanup on failure
        try { Remove-LabSession -SessionId $SessionId } catch { }
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Start-LabVM
# ═══════════════════════════════════════════════════════════════════════════════
function Start-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Starting VM '$($vm.Name)'"
        if ($vm.State -ne 'Running') {
            Start-VM -VM $vm -ErrorAction Stop
        }

        # Wait for heartbeat with 300-second timeout
        $timeout = 300
        $elapsed = 0
        $interval = 5
        while ($elapsed -lt $timeout) {
            $heartbeat = (Get-VM -Id $HyperVVMId).Heartbeat
            if ($heartbeat -eq 'OkApplicationsHealthy' -or $heartbeat -eq 'OkApplicationsUnknown') {
                Write-Verbose "Heartbeat detected for VM '$($vm.Name)' after ${elapsed}s"
                return
            }
            Start-Sleep -Seconds $interval
            $elapsed += $interval
        }
        throw "Heartbeat timeout (${timeout}s) reached for VM '$($vm.Name)'"
    }
    catch {
        Write-Error "Failed to start VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Stop-LabVM
# ═══════════════════════════════════════════════════════════════════════════════
function Stop-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId,
        [switch]$Force
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Stopping VM '$($vm.Name)' (Force=$Force)"

        if ($vm.State -eq 'Off') {
            Write-Verbose "VM '$($vm.Name)' is already off"
            return
        }

        if ($Force) {
            Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
        }
        else {
            Stop-VM -VM $vm -ErrorAction Stop
            # Wait for graceful shutdown up to 120 seconds
            $timeout = 120
            $elapsed = 0
            while ($elapsed -lt $timeout) {
                if ((Get-VM -Id $HyperVVMId).State -eq 'Off') {
                    Write-Verbose "VM '$($vm.Name)' shut down gracefully"
                    return
                }
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
            Write-Warning "Graceful shutdown timed out for '$($vm.Name)', forcing stop"
            Stop-VM -VM $vm -TurnOff -Force -ErrorAction Stop
        }
        Write-Verbose "VM '$($vm.Name)' stopped"
    }
    catch {
        Write-Error "Failed to stop VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Save-LabVM
# ═══════════════════════════════════════════════════════════════════════════════
function Save-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Saving state for VM '$($vm.Name)'"
        Save-VM -VM $vm -ErrorAction Stop
        Write-Verbose "VM '$($vm.Name)' state saved"
    }
    catch {
        Write-Error "Failed to save VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Remove-LabSession
# ═══════════════════════════════════════════════════════════════════════════════
function Remove-LabSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$SessionId
    )

    try {
        Write-Verbose "Removing lab session $SessionId"
        $sessionPath = Join-Path $script:VMStoragePath $SessionId.ToString()
        $suffix = $SessionId.ToString().Substring(0,8)

        # Find all VMs belonging to this session by naming convention
        $sessionVMs = Get-VM | Where-Object { $_.Name -like "*-$suffix" }

        foreach ($vm in $sessionVMs) {
            Write-Verbose "Stopping and removing VM '$($vm.Name)'"
            if ($vm.State -ne 'Off') {
                Stop-VM -VM $vm -TurnOff -Force -ErrorAction SilentlyContinue
            }
            # Remove all snapshots first
            Get-VMSnapshot -VM $vm -ErrorAction SilentlyContinue | Remove-VMSnapshot -ErrorAction SilentlyContinue
            Remove-VM -VM $vm -Force -ErrorAction Stop
        }

        # Delete differencing disks and session folder
        if (Test-Path $sessionPath) {
            Remove-Item -Path $sessionPath -Recurse -Force -ErrorAction Stop
            Write-Verbose "Deleted session directory: $sessionPath"
        }

        # Remove the virtual switch if it matches session naming convention
        $switchName = "LabSwitch-$suffix"
        $existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        if ($existingSwitch) {
            Remove-VMSwitch -Name $switchName -Force -ErrorAction Stop
            Write-Verbose "Removed virtual switch: $switchName"
        }

        Write-Verbose "Lab session $SessionId fully removed"
    }
    catch {
        Write-Error "Failed to remove lab session $SessionId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get-LabResourceUsage
# ═══════════════════════════════════════════════════════════════════════════════
function Get-LabResourceUsage {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Collecting resource usage"
        $runningVMs = Get-VM | Where-Object State -eq 'Running'

        $usedRAMGB  = ($runningVMs | Measure-Object -Property MemoryAssigned -Sum).Sum / 1GB
        $usedvCPU   = ($runningVMs | Measure-Object -Property ProcessorCount -Sum).Sum
        $totalVMs   = ($runningVMs | Measure-Object).Count

        # Disk usage of VM storage
        $diskUsedGB = 0
        if (Test-Path $script:VMStoragePath) {
            $diskUsedGB = [math]::Round(
                (Get-ChildItem -Path $script:VMStoragePath -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum / 1GB, 2)
        }

        $result = @{
            TotalRAMGB      = $script:TotalRAMGB
            UsedRAMGB       = [math]::Round($usedRAMGB, 2)
            AvailableRAMGB  = [math]::Round($script:TotalRAMGB - $usedRAMGB, 2)
            TotalvCPU       = $script:TotalvCPU
            UsedvCPU        = $usedvCPU
            AvailablevCPU   = $script:TotalvCPU - $usedvCPU
            RunningVMs      = $totalVMs
            DiskUsedGB      = $diskUsedGB
            CollectedAt     = [DateTimeOffset]::UtcNow
        }

        Write-Verbose "RAM: $($result.UsedRAMGB)/$($result.TotalRAMGB) GB  vCPU: $($result.UsedvCPU)/$($result.TotalvCPU)"
        return $result
    }
    catch {
        Write-Error "Failed to collect resource usage: $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test-ResourceAvailability
# ═══════════════════════════════════════════════════════════════════════════════
function Test-ResourceAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][double]$RequiredRAMGB,
        [Parameter(Mandatory)][int]$RequiredvCPU
    )

    try {
        Write-Verbose "Checking resource availability: ${RequiredRAMGB} GB RAM, ${RequiredvCPU} vCPU"
        $usage = Get-LabResourceUsage

        # Apply 10% overhead
        $effectiveRAM  = $usage.AvailableRAMGB  * (1 - $script:OverheadPct)
        $effectivevCPU = [math]::Floor($usage.AvailablevCPU * (1 - $script:OverheadPct))

        $ramOk  = $RequiredRAMGB -le $effectiveRAM
        $cpuOk  = $RequiredvCPU  -le $effectivevCPU

        $result = @{
            Available          = ($ramOk -and $cpuOk)
            RAMAvailable       = $ramOk
            vCPUAvailable      = $cpuOk
            EffectiveFreeRAMGB = [math]::Round($effectiveRAM, 2)
            EffectiveFreevCPU  = $effectivevCPU
            RequestedRAMGB     = $RequiredRAMGB
            RequestedvCPU      = $RequiredvCPU
        }

        Write-Verbose "Resources available: $($result.Available)"
        return $result
    }
    catch {
        Write-Error "Resource availability check failed: $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# New-LabSnapshot
# ═══════════════════════════════════════════════════════════════════════════════
function New-LabSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId,
        [Parameter(Mandatory)][string]$SnapshotName
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Creating snapshot '$SnapshotName' for VM '$($vm.Name)'"
        Checkpoint-VM -VM $vm -SnapshotName $SnapshotName -ErrorAction Stop
        Write-Verbose "Snapshot '$SnapshotName' created"
    }
    catch {
        Write-Error "Failed to create snapshot for VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Restore-LabSnapshot
# ═══════════════════════════════════════════════════════════════════════════════
function Restore-LabSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId,
        [string]$SnapshotName = 'InitialState'
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Restoring VM '$($vm.Name)' to snapshot '$SnapshotName'"
        $snapshot = Get-VMSnapshot -VM $vm -Name $SnapshotName -ErrorAction Stop
        Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false -ErrorAction Stop
        Write-Verbose "VM '$($vm.Name)' restored to '$SnapshotName'"
    }
    catch {
        Write-Error "Failed to restore snapshot for VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get-VMActivityLog
# ═══════════════════════════════════════════════════════════════════════════════
function Get-VMActivityLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId,
        [datetime]$StartTime = ([datetime]::UtcNow.AddHours(-24)),
        [datetime]$EndTime   = ([datetime]::UtcNow)
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Querying activity logs for VM '$($vm.Name)' from $StartTime to $EndTime"

        # Gather Hyper-V operational events for this VM
        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-Hyper-V-Worker-Admin">
    <Select Path="Microsoft-Windows-Hyper-V-Worker-Admin">
      *[System[TimeCreated[@SystemTime&gt;='$($StartTime.ToString('o'))' and @SystemTime&lt;='$($EndTime.ToString('o'))']]]
      and *[EventData[Data='$($vm.Name)']]
    </Select>
  </Query>
</QueryList>
"@

        $events = Get-WinEvent -FilterXml $filterXml -ErrorAction SilentlyContinue

        $logs = @()
        foreach ($event in $events) {
            $logs += @{
                TimeCreated = $event.TimeCreated
                EventId     = $event.Id
                Level       = $event.LevelDisplayName
                Message     = $event.Message
                VMName      = $vm.Name
                HyperVVMId  = $HyperVVMId
            }
        }

        Write-Verbose "Found $($logs.Count) log entries"
        return $logs
    }
    catch {
        Write-Error "Failed to retrieve activity logs for VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Set-LabVMCredentials
# ═══════════════════════════════════════════════════════════════════════════════
function Set-LabVMCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId,
        [Parameter(Mandatory)][PSCredential]$Credential
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Setting credentials for user '$($Credential.UserName)' on VM '$($vm.Name)' via PowerShell Direct"

        # Use PowerShell Direct to set the local user password
        $username  = $Credential.UserName
        $password  = $Credential.GetNetworkCredential().Password

        # Build a temporary admin credential to connect (assumes default admin account)
        Invoke-Command -VMId $HyperVVMId -Credential $Credential -ScriptBlock {
            param($user, $pass)
            $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
            $account = Get-LocalUser -Name $user -ErrorAction SilentlyContinue
            if ($account) {
                Set-LocalUser -Name $user -Password $secPass
            }
            else {
                New-LocalUser -Name $user -Password $secPass -FullName $user -Description 'CyberLab account' -AccountNeverExpires -PasswordNeverExpires
                Add-LocalGroupMember -Group 'Administrators' -Member $user -ErrorAction SilentlyContinue
            }
        } -ArgumentList $username, $password -ErrorAction Stop

        Write-Verbose "Credentials set for '$username' on VM '$($vm.Name)'"
    }
    catch {
        Write-Error "Failed to set credentials on VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# New-LabVirtualSwitch
# ═══════════════════════════════════════════════════════════════════════════════
function New-LabVirtualSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [ValidateSet('Private','Internal','External')]
        [string]$SwitchType = 'Private'
    )

    try {
        $existing = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Verbose "Virtual switch '$SwitchName' already exists"
            return $existing
        }

        Write-Verbose "Creating $SwitchType virtual switch '$SwitchName'"
        $switch = New-VMSwitch -Name $SwitchName -SwitchType $SwitchType -ErrorAction Stop
        Write-Verbose "Virtual switch '$SwitchName' created"
        return $switch
    }
    catch {
        Write-Error "Failed to create virtual switch '$SwitchName': $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get-VMConsoleConnection
# ═══════════════════════════════════════════════════════════════════════════════
function Get-VMConsoleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$HyperVVMId
    )

    try {
        $vm = Get-VM | Where-Object VMId -eq $HyperVVMId
        if (-not $vm) { throw "VM with ID $HyperVVMId not found" }

        Write-Verbose "Retrieving console connection details for VM '$($vm.Name)'"

        $hostName = [System.Net.Dns]::GetHostName()
        $vmConnect = Get-CimInstance -Namespace 'root\virtualization\v2' `
            -ClassName 'Msvm_ComputerSystem' |
            Where-Object { $_.Name -eq $HyperVVMId.ToString() } |
            Select-Object -First 1

        $rdpPort = 2179  # Default Hyper-V VM connection port

        $result = @{
            VMName          = $vm.Name
            HyperVVMId      = $HyperVVMId
            HostName        = $hostName
            State           = $vm.State.ToString()
            RdpPort         = $rdpPort
            ConnectionUri   = "vmconnect://$hostName/$($vm.Name)"
            EnhancedSession = $vm.EnhancedSessionTransportType -ne 'None'
        }

        Write-Verbose "Console URI: $($result.ConnectionUri)"
        return $result
    }
    catch {
        Write-Error "Failed to get console connection for VM $HyperVVMId : $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Start-InactivityMonitor
# ═══════════════════════════════════════════════════════════════════════════════
function Start-InactivityMonitor {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Starting inactivity monitor background job"

        $job = Start-Job -Name 'CyberLab-InactivityMonitor' -ScriptBlock {
            $inactivityThreshold = [TimeSpan]::FromMinutes(30)
            $checkInterval       = 60  # seconds

            while ($true) {
                try {
                    $runningVMs = Get-VM | Where-Object State -eq 'Running'

                    foreach ($vm in $runningVMs) {
                        # Check if the VM belongs to CyberLab (name contains GUID suffix)
                        if ($vm.Name -notmatch '-[0-9a-f]{8}$') { continue }

                        $uptime = $vm.Uptime
                        if ($uptime -lt $inactivityThreshold) { continue }

                        # Check heartbeat as activity indicator
                        $heartbeat = $vm.Heartbeat
                        if ($heartbeat -ne 'OkApplicationsHealthy' -and $heartbeat -ne 'OkApplicationsUnknown') {
                            Write-Output "[$(Get-Date -Format 'o')] VM '$($vm.Name)' has no heartbeat after $($uptime.TotalMinutes) min - saving state"
                            Save-VM -VM $vm -ErrorAction SilentlyContinue
                            continue
                        }

                        # Check CPU usage as a proxy for activity
                        $cpuUsage = (Get-Counter -Counter "\Hyper-V Hypervisor Virtual Processor($($vm.Name):*)\% Total Run Time" -ErrorAction SilentlyContinue).CounterSamples |
                            Measure-Object -Property CookedValue -Average |
                            Select-Object -ExpandProperty Average

                        if ($null -ne $cpuUsage -and $cpuUsage -lt 1.0) {
                            Write-Output "[$(Get-Date -Format 'o')] VM '$($vm.Name)' appears inactive (CPU $([math]::Round($cpuUsage,2))%) - saving state"
                            Save-VM -VM $vm -ErrorAction SilentlyContinue
                        }
                    }
                }
                catch {
                    Write-Output "[$(Get-Date -Format 'o')] InactivityMonitor error: $_"
                }

                Start-Sleep -Seconds $checkInterval
            }
        }

        Write-Verbose "Inactivity monitor started as job '$($job.Name)' (Id: $($job.Id))"
        return $job
    }
    catch {
        Write-Error "Failed to start inactivity monitor: $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Start-SessionCleanup
# ═══════════════════════════════════════════════════════════════════════════════
function Start-SessionCleanup {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Starting session cleanup background job"

        $vmStoragePath = $script:VMStoragePath

        $job = Start-Job -Name 'CyberLab-SessionCleanup' -ScriptBlock {
            param($storagePath)
            $cleanupInterval = 900  # 15 minutes
            $maxSessionAge   = [TimeSpan]::FromHours(4)

            while ($true) {
                try {
                    # Find session directories
                    $sessionDirs = Get-ChildItem -Path $storagePath -Directory -ErrorAction SilentlyContinue

                    foreach ($dir in $sessionDirs) {
                        $age = [DateTime]::UtcNow - $dir.CreationTimeUtc
                        if ($age -lt $maxSessionAge) { continue }

                        $suffix = $dir.Name.Substring(0, [math]::Min(8, $dir.Name.Length))
                        $sessionVMs = Get-VM | Where-Object { $_.Name -like "*-$suffix" }

                        Write-Output "[$(Get-Date -Format 'o')] Cleaning expired session: $($dir.Name) (age: $([math]::Round($age.TotalHours,1))h)"

                        foreach ($vm in $sessionVMs) {
                            if ($vm.State -ne 'Off') {
                                Stop-VM -VM $vm -TurnOff -Force -ErrorAction SilentlyContinue
                            }
                            Get-VMSnapshot -VM $vm -ErrorAction SilentlyContinue | Remove-VMSnapshot -ErrorAction SilentlyContinue
                            Remove-VM -VM $vm -Force -ErrorAction SilentlyContinue
                        }

                        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue

                        # Try to remove the associated switch
                        $switchName = "LabSwitch-$suffix"
                        Remove-VMSwitch -Name $switchName -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Output "[$(Get-Date -Format 'o')] SessionCleanup error: $_"
                }

                Start-Sleep -Seconds $cleanupInterval
            }
        } -ArgumentList $vmStoragePath

        Write-Verbose "Session cleanup started as job '$($job.Name)' (Id: $($job.Id))"
        return $job
    }
    catch {
        Write-Error "Failed to start session cleanup: $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get-LabHealthStatus
# ═══════════════════════════════════════════════════════════════════════════════
function Get-LabHealthStatus {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "Collecting lab health status"

        $usage = Get-LabResourceUsage

        $allVMs = Get-VM | Where-Object { $_.Name -match '-[0-9a-f]{8}$' }
        $vmsByState = $allVMs | Group-Object -Property State -AsHashTable -AsString

        # Check Hyper-V service
        $vmms = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
        $hyperVHealthy = $vmms -and $vmms.Status -eq 'Running'

        # Check disk space on VM drive
        $vmDrive = Split-Path $script:VMStoragePath -Qualifier
        $disk = Get-PSDrive -Name $vmDrive.TrimEnd(':') -ErrorAction SilentlyContinue
        $diskFreeGB = if ($disk) { [math]::Round($disk.Free / 1GB, 2) } else { -1 }

        # Background job status
        $monitorJob = Get-Job -Name 'CyberLab-InactivityMonitor' -ErrorAction SilentlyContinue
        $cleanupJob = Get-Job -Name 'CyberLab-SessionCleanup' -ErrorAction SilentlyContinue

        $result = @{
            OverallHealth       = if ($hyperVHealthy -and $usage.AvailableRAMGB -gt 0 -and $diskFreeGB -gt 10) { 'Healthy' }
                                  elseif ($hyperVHealthy) { 'Degraded' }
                                  else { 'Unhealthy' }
            HyperVService       = if ($hyperVHealthy) { 'Running' } else { 'Stopped' }
            Resources           = $usage
            DiskFreeGB          = $diskFreeGB
            TotalLabVMs         = $allVMs.Count
            RunningVMs          = ($vmsByState['Running'] | Measure-Object).Count
            StoppedVMs          = ($vmsByState['Off'] | Measure-Object).Count
            SavedVMs            = ($vmsByState['Saved'] | Measure-Object).Count
            InactivityMonitor   = if ($monitorJob) { $monitorJob.State.ToString() } else { 'NotStarted' }
            SessionCleanup      = if ($cleanupJob) { $cleanupJob.State.ToString() } else { 'NotStarted' }
            CheckedAt           = [DateTimeOffset]::UtcNow
        }

        Write-Verbose "Health: $($result.OverallHealth) | VMs: $($result.TotalLabVMs) | Free RAM: $($usage.AvailableRAMGB) GB"
        return $result
    }
    catch {
        Write-Error "Failed to collect health status: $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Export-LabTemplate
# ═══════════════════════════════════════════════════════════════════════════════
function Export-LabTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplateId,
        [Parameter(Mandatory)][string]$OutputPath
    )

    try {
        Write-Verbose "Exporting template '$TemplateId' to '$OutputPath'"

        $templateDir = Join-Path $script:TemplateStoragePath $TemplateId
        if (-not (Test-Path $templateDir)) {
            throw "Template directory not found: $templateDir"
        }

        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $exportDir = Join-Path $OutputPath $TemplateId
        New-Item -Path $exportDir -ItemType Directory -Force | Out-Null

        # Copy template disks
        $disks = Get-ChildItem -Path $templateDir -Filter '*.vhdx' -ErrorAction Stop
        foreach ($disk in $disks) {
            Write-Verbose "Copying disk: $($disk.Name)"
            Copy-Item -Path $disk.FullName -Destination $exportDir -Force
        }

        # Copy metadata files (JSON, XML)
        Get-ChildItem -Path $templateDir -Include '*.json','*.xml' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $exportDir -Force

        # Create manifest
        $manifest = @{
            TemplateId  = $TemplateId
            ExportedAt  = [DateTimeOffset]::UtcNow.ToString('o')
            Files       = (Get-ChildItem -Path $exportDir -File).Name
            TotalSizeMB = [math]::Round(
                (Get-ChildItem -Path $exportDir -File | Measure-Object -Property Length -Sum).Sum / 1MB, 2
            )
        }
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $exportDir 'manifest.json') -Encoding UTF8

        Write-Verbose "Template exported: $($manifest.Files.Count) files, $($manifest.TotalSizeMB) MB"
        return $exportDir
    }
    catch {
        Write-Error "Failed to export template '$TemplateId': $_"
        throw
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Import-LabTemplate
# ═══════════════════════════════════════════════════════════════════════════════
function Import-LabTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TemplatePath
    )

    try {
        Write-Verbose "Importing template from '$TemplatePath'"

        if (-not (Test-Path $TemplatePath)) {
            throw "Template path not found: $TemplatePath"
        }

        # Read manifest
        $manifestPath = Join-Path $TemplatePath 'manifest.json'
        if (-not (Test-Path $manifestPath)) {
            throw "No manifest.json found in '$TemplatePath'"
        }

        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        $templateId = $manifest.TemplateId

        $destDir = Join-Path $script:TemplateStoragePath $templateId
        if (Test-Path $destDir) {
            Write-Warning "Template '$templateId' already exists at '$destDir'. Overwriting."
            Remove-Item -Path $destDir -Recurse -Force
        }

        New-Item -Path $destDir -ItemType Directory -Force | Out-Null

        # Copy all files except the manifest itself
        Get-ChildItem -Path $TemplatePath -File | ForEach-Object {
            Write-Verbose "Importing file: $($_.Name)"
            Copy-Item -Path $_.FullName -Destination $destDir -Force
        }

        # Validate that VHDX files are present
        $vhdxFiles = Get-ChildItem -Path $destDir -Filter '*.vhdx' -ErrorAction SilentlyContinue
        if (-not $vhdxFiles) {
            Write-Warning "No .vhdx disk files found in imported template"
        }

        $result = @{
            TemplateId   = $templateId
            ImportedTo   = $destDir
            FileCount    = (Get-ChildItem -Path $destDir -File).Count
            DiskCount    = ($vhdxFiles | Measure-Object).Count
            ImportedAt   = [DateTimeOffset]::UtcNow
        }

        Write-Verbose "Template '$templateId' imported to '$destDir'"
        return $result
    }
    catch {
        Write-Error "Failed to import template from '$TemplatePath': $_"
        throw
    }
}

# ─── Module exports ──────────────────────────────────────────────────────────
Export-ModuleMember -Function @(
    'New-CyberLabSession'
    'Start-LabVM'
    'Stop-LabVM'
    'Save-LabVM'
    'Remove-LabSession'
    'Get-LabResourceUsage'
    'Test-ResourceAvailability'
    'New-LabSnapshot'
    'Restore-LabSnapshot'
    'Get-VMActivityLog'
    'Set-LabVMCredentials'
    'New-LabVirtualSwitch'
    'Get-VMConsoleConnection'
    'Start-InactivityMonitor'
    'Start-SessionCleanup'
    'Get-LabHealthStatus'
    'Export-LabTemplate'
    'Import-LabTemplate'
)
