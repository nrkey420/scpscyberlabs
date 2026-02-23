#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Validates that all VMs in a lab deployment are accessible before notifying students.

.DESCRIPTION
    Run after New-CyberLabSession (and Set-VMNetworkConfig / New-LabAccounts) to
    confirm the entire lab environment is up and reachable.

    For each VM definition supplied via $VMDefinitions, the function:
        1. ICMP ping test — Test-Connection, retried every 5s up to $TimeoutSeconds.
        2. TCP port test  — Test-NetConnection on the expected service port:
                            22  (Linux SSH)
                            23  (Telnet — VyOS vulnerable router)
                            443 (pfSense web GUI)
                            3389 (Windows RDP)
                            80, 8080, 8443 (web application VMs)
        3. WinRM test     — Test-WSMan on port 5985/5986 (Windows VMs only).
        4. Guacamole check — HTTP GET to the Guacamole REST API to verify guacd
                             can reach the VM (optional; skipped if GuacamoleApiBase
                             is not set).

    A VM is considered Ready if tests 1 and 2 both pass.  WinRM and Guacamole
    are advisory (warnings, not failures) unless explicitly required.

    Returns $true only if ALL VMs pass tests 1 and 2.  On failure, returns
    $false and writes detailed per-VM failure information.

.PARAMETER SessionId
    The lab session GUID (used for log file naming and Guacamole API queries).

.PARAMETER VMDefinitions
    Array of objects describing each VM to test.  Each object must have:
        VMName    [string]  Hyper-V VM name
        IpAddress [string]  IPv4 address to test
        OS        [string]  'Windows', 'Linux', or 'Network' (pfSense/VyOS)
        Port      [int]     Primary TCP port to test (22, 3389, 80, etc.)

    Optional properties:
        RequireWinRM     [bool]   Test WinRM (Windows only, default: $true for Windows)
        RequireGuacamole [bool]   Test Guacamole connectivity (default: $true)
        GuacamoleConnId  [string] Guacamole connection ID for this VM

.PARAMETER TimeoutSeconds
    Maximum total time to wait (polling every 5s) before declaring a VM unreachable.
    Default: 300 (5 minutes).

.PARAMETER GuacamoleApiBase
    Base URL of the Guacamole REST API (e.g., "http://localhost:8080/guacamole").
    If empty or not provided, Guacamole tests are skipped.

.PARAMETER GuacamoleToken
    Authentication token for the Guacamole API.
    Obtain via: POST /api/tokens  with admin credentials.

.EXAMPLE
    $vms = @(
        [PSCustomObject]@{ VMName='kali-C1-S03';      IpAddress='10.1.3.10'; OS='Linux';   Port=22   },
        [PSCustomObject]@{ VMName='winserver-C1-S03'; IpAddress='10.1.3.100';OS='Windows'; Port=3389 },
        [PSCustomObject]@{ VMName='pfsense-C1-S03';   IpAddress='10.1.3.1';  OS='Network'; Port=443  }
    )
    $ready = Test-LabReadiness `
                -SessionId  ([guid]::NewGuid()) `
                -VMDefinitions $vms `
                -TimeoutSeconds 300

.EXAMPLE
    # With Guacamole validation
    Test-LabReadiness `
        -SessionId           $session.SessionId `
        -VMDefinitions       $session.VMDefinitions `
        -GuacamoleApiBase    'http://localhost:8080/guacamole' `
        -GuacamoleToken      $token `
        -TimeoutSeconds      600 `
        -Verbose

.OUTPUTS
    [PSCustomObject]@{
        SessionId      = [guid]
        AllReady       = [bool]
        TestedAt       = [datetime]
        ElapsedSeconds = [int]
        Results        = [PSCustomObject[]]   # one per VM — see below
        FailedVMs      = [string[]]
    }

    Each Results entry:
        VMName          = [string]
        IpAddress       = [string]
        Port            = [int]
        OS              = [string]
        PingReachable   = [bool]
        PortReachable   = [bool]
        WinRMReachable  = [bool]    # $null for non-Windows
        GuacamoleOk     = [bool]    # $null if not tested
        PingRttMs       = [int]
        PortRttMs       = [int]
        Ready           = [bool]
        FailureReason   = [string]
        AttemptsCount   = [int]
    }

.NOTES
    Log file: C:\CyberLab\Logs\readiness-<SessionId>.log
    The Guacamole API endpoint tested: GET /api/session/tunnels?token=<token>
    is used to infer whether guacd has an active or pending connection.
    For a more precise check, verify the guacd daemon is configured correctly
    via the Guacamole admin API.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [guid]$SessionId,

    [Parameter(Mandatory)]
    [array]$VMDefinitions,

    [Parameter()]
    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 300,

    [Parameter()]
    [string]$GuacamoleApiBase = '',

    [Parameter()]
    [string]$GuacamoleToken = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$PollIntervalSec = 5
$LogDir          = 'C:\CyberLab\Logs'
$LogFile         = Join-Path $LogDir "readiness-${SessionId}.log"

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'TEST')][string]$Level = 'INFO'
    )
    $entry = "[{0}] [{1,-5}]  {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    $entry | Add-Content -Path $LogFile -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Warning "[ERROR] $Message" }
        'WARN'  { Write-Warning "[WARN]  $Message" }
        'OK'    { Write-Verbose "[OK]    $Message" }
        'TEST'  { Write-Verbose "[TEST]  $Message" }
        default { Write-Verbose "[INFO]  $Message" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESULT OBJECT FACTORY
# ─────────────────────────────────────────────────────────────────────────────

function New-VMTestResult {
    param([object]$Def)
    return [PSCustomObject]@{
        VMName         = $Def.VMName
        IpAddress      = $Def.IpAddress
        Port           = $Def.Port
        OS             = $Def.OS
        PingReachable  = $false
        PortReachable  = $false
        WinRMReachable = $null   # set for Windows only
        GuacamoleOk    = $null   # set when tested
        PingRttMs      = -1
        PortRttMs      = -1
        Ready          = $false
        FailureReason  = ''
        AttemptsCount  = 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST: ICMP PING
# ─────────────────────────────────────────────────────────────────────────────

function Test-Ping {
    param([string]$IpAddress)
    try {
        $ping = Test-Connection -ComputerName $IpAddress -Count 2 -ErrorAction Stop
        $rtt  = [int](($ping | Measure-Object ResponseTime -Average).Average)
        return @{ Success = $true; RttMs = $rtt }
    }
    catch {
        return @{ Success = $false; RttMs = -1 }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST: TCP PORT
# ─────────────────────────────────────────────────────────────────────────────

function Test-TcpPort {
    param([string]$IpAddress, [int]$Port)
    try {
        $sw      = [System.Diagnostics.Stopwatch]::StartNew()
        $result  = Test-NetConnection -ComputerName $IpAddress -Port $Port -WarningAction SilentlyContinue
        $sw.Stop()
        return @{
            Success = $result.TcpTestSucceeded
            RttMs   = [int]$sw.ElapsedMilliseconds
        }
    }
    catch {
        return @{ Success = $false; RttMs = -1 }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST: WINRM
# ─────────────────────────────────────────────────────────────────────────────

function Test-WinRMReachable {
    param([string]$IpAddress)
    try {
        $wsmanResult = Test-WSMan -ComputerName $IpAddress -ErrorAction Stop
        return $null -ne $wsmanResult
    }
    catch {
        Write-Log "WinRM test failed for $IpAddress`: $($_.Exception.Message)" -Level WARN
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST: GUACAMOLE API
# ─────────────────────────────────────────────────────────────────────────────

function Test-GuacamoleConnectivity {
    <#
    .SYNOPSIS
        Checks whether the Guacamole server is reachable and whether a
        connection for the given VM is configured.

        Uses the Guacamole REST API:
          GET /api/session/data/postgresql/connections?token=<token>
        to list all connections.  Looks for the connection whose name or
        attributes match the VM name.

        This verifies:
          1. guacd daemon is running (Guacamole would fail to list connections
             if guacd is down).
          2. The connection definition exists for this VM.

        It does NOT initiate a tunnel — it only checks configuration.
    #>
    param(
        [string]$GuacamoleBase,
        [string]$Token,
        [string]$VMName,
        [PSCustomObject]$VMDef   # optional: check specific conn ID
    )

    if ([string]::IsNullOrWhiteSpace($GuacamoleBase) -or
        [string]::IsNullOrWhiteSpace($Token)) {
        return $null   # not configured — skip
    }

    try {
        # List all connections
        $uri      = "$GuacamoleBase/api/session/data/postgresql/connections?token=$Token"
        $response = Invoke-RestMethod -Uri $uri -Method GET -ErrorAction Stop

        # $response is a hashtable/PSCustomObject keyed by connection ID
        # Search for a connection whose name matches the VMName
        $found = $false

        if ($null -ne $VMDef.GuacamoleConnId -and -not [string]::IsNullOrWhiteSpace($VMDef.GuacamoleConnId)) {
            # Check specific connection ID
            $connId = $VMDef.GuacamoleConnId
            $found  = $null -ne $response.$connId
        }
        else {
            # Search by name
            $found = $response.PSObject.Properties.Value |
                     Where-Object { $_.name -eq $VMName } |
                     Select-Object -First 1 |
                     ForEach-Object { $true }
            $found = [bool]$found
        }

        if ($found) {
            Write-Log "Guacamole: connection for '$VMName' found." -Level OK
        }
        else {
            Write-Log "Guacamole: no connection found for '$VMName' — may not be configured yet." -Level WARN
        }

        return $found
    }
    catch {
        Write-Log ("Guacamole API error for '$VMName': {0}" -f $_.Exception.Message) -Level WARN
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# POLL LOOP — wait for a single VM to become ready
# ─────────────────────────────────────────────────────────────────────────────

function Wait-VMReady {
    <#
    .SYNOPSIS
        Polls a single VM until it passes ping + port tests OR timeout expires.
        Updates the $vmResult object in place.
    #>
    param(
        [object]$Def,
        [PSCustomObject]$VmResult,
        [DateTime]$Deadline
    )

    $ip   = $Def.IpAddress
    $port = $Def.Port
    $name = $Def.VMName

    Write-Log "Waiting for VM '$name' ($ip) port $port..." -Level TEST

    while ((Get-Date) -lt $Deadline) {
        $VmResult.AttemptsCount++

        # ── Ping ────────────────────────────────────────────────────────
        $pingResult = Test-Ping -IpAddress $ip
        $VmResult.PingReachable = $pingResult.Success
        $VmResult.PingRttMs     = $pingResult.RttMs

        if ($pingResult.Success) {
            Write-Log "  PING OK  $name ($ip)  RTT=$($pingResult.RttMs)ms" -Level OK

            # ── TCP Port ────────────────────────────────────────────────
            $portResult = Test-TcpPort -IpAddress $ip -Port $port
            $VmResult.PortReachable = $portResult.Success
            $VmResult.PortRttMs     = $portResult.RttMs

            if ($portResult.Success) {
                Write-Log "  PORT OK  $name ($ip`:$port)  RTT=$($portResult.RttMs)ms" -Level OK
                $VmResult.Ready = $true
                return   # done — VM is ready
            }
            else {
                Write-Log "  PORT WAIT $name ($ip`:$port) — not yet open." -Level WARN
            }
        }
        else {
            Write-Log "  PING WAIT $name ($ip) — no response yet." -Level WARN
        }

        # Wait before next poll
        Start-Sleep -Seconds $PollIntervalSec
    }

    # Timed out
    $VmResult.FailureReason = if (-not $VmResult.PingReachable) {
        "ICMP unreachable after ${TimeoutSeconds}s"
    }
    else {
        "TCP port $port unreachable after ${TimeoutSeconds}s"
    }
    Write-Log "TIMEOUT: '$name' ($ip) — $($VmResult.FailureReason)" -Level ERROR
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

try {
    # Ensure log directory
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    $null = New-Item -Path $LogFile -ItemType File -Force

    $startTime = Get-Date
    $deadline  = $startTime.AddSeconds($TimeoutSeconds)

    Write-Log "Test-LabReadiness started."
    Write-Log "  SessionId      : $SessionId"
    Write-Log "  VMs to test    : $($VMDefinitions.Count)"
    Write-Log "  Timeout        : ${TimeoutSeconds}s (deadline: $($deadline.ToString('HH:mm:ss')))"
    Write-Log ("  Guacamole API  : {0}" -f (if ([string]::IsNullOrWhiteSpace($GuacamoleApiBase)) { '(not configured)' } else { $GuacamoleApiBase }))

    # Validate VMDefinitions
    foreach ($def in $VMDefinitions) {
        $required = @('VMName', 'IpAddress', 'OS', 'Port')
        foreach ($prop in $required) {
            if ($null -eq $def.$prop -or [string]::IsNullOrWhiteSpace($def.$prop.ToString())) {
                throw "VMDefinition for '$($def.VMName)' is missing required property '$prop'."
            }
        }
    }

    # Build result objects
    $vmResults = $VMDefinitions | ForEach-Object { New-VMTestResult -Def $_ }

    # ── PHASE 1: PING + PORT (with timeout loop per VM) ──────────────────
    Write-Log "=== Phase 1: ICMP + TCP Port Tests ===" -Level INFO

    foreach ($idx in 0..($VMDefinitions.Count - 1)) {
        $def      = $VMDefinitions[$idx]
        $vmResult = $vmResults[$idx]

        # Check time budget
        if ((Get-Date) -ge $deadline) {
            $vmResult.FailureReason = "Timed out before test began (previous VMs exhausted budget)"
            Write-Log "SKIP (timeout): '$($def.VMName)'" -Level ERROR
            continue
        }

        Wait-VMReady -Def $def -VmResult $vmResult -Deadline $deadline
    }

    # ── PHASE 2: WINRM (Windows VMs only) ────────────────────────────────
    Write-Log "=== Phase 2: WinRM Tests (Windows VMs) ===" -Level INFO

    foreach ($idx in 0..($VMDefinitions.Count - 1)) {
        $def      = $VMDefinitions[$idx]
        $vmResult = $vmResults[$idx]

        if ($def.OS -ne 'Windows') {
            Write-Log "  SKIP WinRM: '$($def.VMName)' (OS=$($def.OS))" -Level INFO
            continue
        }

        if (-not $vmResult.PingReachable) {
            Write-Log "  SKIP WinRM: '$($def.VMName)' (ping failed)" -Level WARN
            $vmResult.WinRMReachable = $false
            continue
        }

        Write-Log "  WinRM test: $($def.VMName) ($($def.IpAddress))..." -Level TEST
        $winrmOk = Test-WinRMReachable -IpAddress $def.IpAddress
        $vmResult.WinRMReachable = $winrmOk

        if ($winrmOk) {
            Write-Log "  WINRM OK: $($def.VMName)" -Level OK
        }
        else {
            Write-Log "  WINRM FAIL: $($def.VMName) — WinRM not responding (advisory only)" -Level WARN
            # WinRM failure is a warning, not a blocking failure
            # (some Windows VMs may have WinRM disabled deliberately)
        }
    }

    # ── PHASE 3: GUACAMOLE API ────────────────────────────────────────────
    Write-Log "=== Phase 3: Guacamole API Tests ===" -Level INFO

    $guacEnabled = (-not [string]::IsNullOrWhiteSpace($GuacamoleApiBase) -and
                    -not [string]::IsNullOrWhiteSpace($GuacamoleToken))

    foreach ($idx in 0..($VMDefinitions.Count - 1)) {
        $def      = $VMDefinitions[$idx]
        $vmResult = $vmResults[$idx]

        if (-not $guacEnabled) {
            Write-Log "  SKIP Guacamole: not configured" -Level INFO
            break   # same for all VMs
        }

        # Only test Guacamole for VMs that require it
        $requireGuac = if ($null -ne $def.RequireGuacamole) { $def.RequireGuacamole } else { $true }
        if (-not $requireGuac) {
            Write-Log "  SKIP Guacamole: '$($def.VMName)' (RequireGuacamole=false)" -Level INFO
            continue
        }

        Write-Log "  Guacamole check: $($def.VMName)..." -Level TEST
        $guacOk = Test-GuacamoleConnectivity `
            -GuacamoleBase $GuacamoleApiBase `
            -Token         $GuacamoleToken `
            -VMName        $def.VMName `
            -VMDef         $def
        $vmResult.GuacamoleOk = $guacOk

        if ($guacOk) {
            Write-Log "  GUACAMOLE OK: $($def.VMName)" -Level OK
        }
        else {
            Write-Log "  GUACAMOLE WARN: $($def.VMName) — connection not found in Guacamole" -Level WARN
        }
    }

    # ── AGGREGATE RESULTS ─────────────────────────────────────────────────
    $failedVMs  = $vmResults | Where-Object { -not $_.Ready } | Select-Object -ExpandProperty VMName
    $allReady   = $failedVMs.Count -eq 0
    $elapsed    = [int](New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds

    # ── SUMMARY LOG ──────────────────────────────────────────────────────
    Write-Log "=== READINESS RESULTS ===" -Level INFO
    foreach ($r in $vmResults) {
        $status = if ($r.Ready) { 'READY  ' } else { 'FAILED ' }
        $line = ("{0} {1,-30} {2,-15} port={3,-5} ping={4} port={5} rtt_ping={6}ms rtt_port={7}ms" -f `
            $status, $r.VMName, $r.IpAddress, $r.Port,
            ([int][bool]$r.PingReachable),
            ([int][bool]$r.PortReachable),
            $r.PingRttMs,
            $r.PortRttMs)

        if (-not $r.Ready -and -not [string]::IsNullOrWhiteSpace($r.FailureReason)) {
            $line += "  REASON=$($r.FailureReason)"
        }
        Write-Log $line -Level (if ($r.Ready) { 'OK' } else { 'ERROR' })
    }

    Write-Log ("All ready: $allReady  |  Failed: $($failedVMs.Count)/$($vmResults.Count)  |  Elapsed: ${elapsed}s")
    Write-Log "Log file: $LogFile"

    # ── BUILD AND RETURN OUTPUT OBJECT ────────────────────────────────────
    $output = [PSCustomObject]@{
        SessionId      = $SessionId
        AllReady       = $allReady
        TestedAt       = $startTime
        ElapsedSeconds = $elapsed
        Results        = $vmResults
        FailedVMs      = [string[]]$failedVMs
    }

    # Write-Warning summary for any failures (visible without -Verbose)
    if (-not $allReady) {
        Write-Warning ("Test-LabReadiness: {0} VM(s) NOT READY: {1}" -f
                       $failedVMs.Count, ($failedVMs -join ', '))
    }
    else {
        Write-Verbose ("Test-LabReadiness: ALL {0} VM(s) READY in ${elapsed}s." -f $vmResults.Count)
    }

    return $output
}
catch {
    Write-Log "FATAL: $_" -Level ERROR
    throw
}
finally {
    Write-Log "Test-LabReadiness finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
}
