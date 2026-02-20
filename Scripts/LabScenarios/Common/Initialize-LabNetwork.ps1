#Requires -Modules Hyper-V
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates Hyper-V virtual switches required by a CyberLab session.

.DESCRIPTION
    Run on the Hyper-V host before deploying any lab.  Based on the LabType
    and StudentCount parameters, this function creates a set of Private
    virtual switches (one per student per required network segment) plus any
    shared/monitor switches needed by the scenario.

    Switch naming convention:
        <segment>-C<ClassId>-S<StudentId>    per-student private switch
        shared-<segment>-C<ClassId>          class-wide shared switch

    Supported LabTypes and their network segments:
        RedTeamBlueTeam     : attack-net, corporate-net, dmz-net (per student)
                              shared-monitor-net (class-wide)
        WebAppPentest       : pentest-net (per student)
        SOCAnalyst          : soc-net (per student)
                              shared-soc-net (class-wide)
        NetworkAttackDefense: attack-net, internal-net (per student)
        MalwareAnalysis     : analysis-net (per student — fully isolated)

    MalwareAnalysis switches are Private only — no external switch is added
    so malware cannot reach the host network.

.PARAMETER ClassId
    Class identifier (1 or 2).  Supports two concurrent classes on the same
    Hyper-V host.

.PARAMETER LabType
    The lab scenario to deploy.  Must be one of:
        RedTeamBlueTeam | WebAppPentest | SOCAnalyst |
        NetworkAttackDefense | MalwareAnalysis

.PARAMETER StudentCount
    Number of students (1–15) who need individual lab environments.

.EXAMPLE
    $switches = Initialize-LabNetwork -ClassId 1 -LabType RedTeamBlueTeam -StudentCount 12
    # Creates 3 switches × 12 students + 1 shared = 37 switches total.
    # Returns a hashtable keyed by student ID then segment name.

.EXAMPLE
    Initialize-LabNetwork -ClassId 2 -LabType MalwareAnalysis -StudentCount 8 -Verbose
    # Creates 8 fully-isolated analysis-net switches for class 2.

.OUTPUTS
    [hashtable]  Keyed as $result[$StudentId][$NetworkName] = $SwitchName
                 Also includes $result['shared'] for class-wide switches.

.NOTES
    Requires the Hyper-V PowerShell module and must be run elevated.
    Log file: C:\CyberLab\Logs\network-init-<ClassId>-<timestamp>.log
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 2)]
    [int]$ClassId,

    [Parameter(Mandatory)]
    [ValidateSet('RedTeamBlueTeam', 'WebAppPentest', 'SOCAnalyst',
                 'NetworkAttackDefense', 'MalwareAnalysis')]
    [string]$LabType,

    [Parameter(Mandatory)]
    [ValidateRange(1, 15)]
    [int]$StudentCount
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────
$LogDir  = 'C:\CyberLab\Logs'
$LogFile = Join-Path $LogDir ("network-init-{0}-{1}.log" -f $ClassId,
                               (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ── Network segment definitions per LabType ───────────────────────────────────
$LabNetworkMap = @{
    'RedTeamBlueTeam'      = @{
        PerStudent = @('attack-net', 'corporate-net', 'dmz-net')
        Shared     = @('shared-monitor-net')
        Isolated   = $false
    }
    'WebAppPentest'        = @{
        PerStudent = @('pentest-net')
        Shared     = @()
        Isolated   = $false
    }
    'SOCAnalyst'           = @{
        PerStudent = @('soc-net')
        Shared     = @('shared-soc-net')
        Isolated   = $false
    }
    'NetworkAttackDefense' = @{
        PerStudent = @('attack-net', 'internal-net')
        Shared     = @()
        Isolated   = $false
    }
    'MalwareAnalysis'      = @{
        PerStudent = @('analysis-net')
        Shared     = @()
        Isolated   = $true   # Fully air-gapped — no external switch connectivity
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO'
    )
    $entry = "[{0}] [{1}]  {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $entry | Add-Content -Path $LogFile -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Error   $Message }
        'WARN'  { Write-Warning $Message }
        'OK'    { Write-Verbose "[OK]  $Message" }
        default { Write-Verbose "[INFO] $Message" }
    }
}

function Get-ExistingSwitchNames {
    <#
    .SYNOPSIS Returns a HashSet of existing Hyper-V switch names for collision detection.
    #>
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    Get-VMSwitch -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$names.Add($_.Name) }
    return $names
}

function New-LabSwitch {
    <#
    .SYNOPSIS
        Creates a single Private Hyper-V virtual switch with collision detection.
    .OUTPUTS
        [string] The name of the created (or already-existing) switch.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SwitchName,
        [switch]$ForceIsolated  # Alias for Private; documented intent for MalwareAnalysis
    )

    if ($ExistingSwitches.Contains($SwitchName)) {
        Write-Log "Switch '$SwitchName' already exists — skipping creation." -Level WARN
        return $SwitchName
    }

    if ($PSCmdlet.ShouldProcess($SwitchName, 'New-VMSwitch (Private)')) {
        try {
            New-VMSwitch -Name $SwitchName -SwitchType Private -ErrorAction Stop | Out-Null
            [void]$ExistingSwitches.Add($SwitchName)
            Write-Log "Created switch: $SwitchName (Private)" -Level OK
        }
        catch {
            Write-Log "Failed to create switch '$SwitchName': $_" -Level ERROR
            throw
        }
    }
    return $SwitchName
}

# ─────────────────────────────────────────────────────────────────────────────
# INITIALISATION
# ─────────────────────────────────────────────────────────────────────────────

try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    # Initialise log file
    $null = New-Item -Path $LogFile -ItemType File -Force
    Write-Log "Initialize-LabNetwork started."
    Write-Log "  ClassId      : $ClassId"
    Write-Log "  LabType      : $LabType"
    Write-Log "  StudentCount : $StudentCount"

    # Load network topology for this LabType
    if (-not $LabNetworkMap.ContainsKey($LabType)) {
        throw "Unsupported LabType '$LabType'.  Valid values: $($LabNetworkMap.Keys -join ', ')"
    }
    $topology    = $LabNetworkMap[$LabType]
    $perStudentSegs = $topology.PerStudent   # [string[]]
    $sharedSegs     = $topology.Shared       # [string[]]
    $isIsolated     = $topology.Isolated     # [bool]

    Write-Log ("Per-student segments : {0}" -f ($perStudentSegs -join ', '))
    Write-Log ("Shared segments      : {0}" -f (if ($sharedSegs.Count -gt 0) { $sharedSegs -join ', ' } else { '(none)' }))
    Write-Log ("Fully isolated       : $isIsolated")

    # Snapshot existing switches (for collision detection)
    $ExistingSwitches = Get-ExistingSwitchNames
    Write-Log ("Found {0} existing virtual switches on host." -f $ExistingSwitches.Count)

    # Calculate total switches to create
    $totalPerStudent = $perStudentSegs.Count * $StudentCount
    $totalShared     = $sharedSegs.Count
    $grandTotal      = $totalPerStudent + $totalShared
    Write-Log ("Switches to create: {0} per-student + {1} shared = {2} total" -f `
               $totalPerStudent, $totalShared, $grandTotal)

    # ── OUTPUT HASHTABLE ─────────────────────────────────────────────────────
    # $result[$studentId][$segmentName] = $switchName
    # $result['shared'][$segmentName]   = $switchName
    $result = @{}

    # ─────────────────────────────────────────────────────────────────────────
    # PER-STUDENT SWITCHES
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "Creating per-student switches..."

    for ($sid = 1; $sid -le $StudentCount; $sid++) {
        $studentKey = "S{0:D2}" -f $sid
        $result[$studentKey] = @{}

        foreach ($seg in $perStudentSegs) {
            # Name convention: <segment>-C<ClassId>-S<StudentId>
            # Example: attack-net-C1-S03
            $swName = "{0}-C{1}-S{2:D2}" -f $seg, $ClassId, $sid

            $createdName = New-LabSwitch -SwitchName $swName -ForceIsolated:$isIsolated
            $result[$studentKey][$seg] = $createdName
        }
        Write-Log ("Student {0}: {1} switch(es) created." -f $studentKey, $perStudentSegs.Count)
    }

    # ─────────────────────────────────────────────────────────────────────────
    # SHARED / CLASS-WIDE SWITCHES
    # ─────────────────────────────────────────────────────────────────────────
    if ($sharedSegs.Count -gt 0) {
        Write-Log "Creating shared class-wide switches..."
        $result['shared'] = @{}

        foreach ($seg in $sharedSegs) {
            # Name convention: shared-<segment>-C<ClassId>
            # Example: shared-monitor-net-C1
            $swName = "{0}-C{1}" -f $seg, $ClassId

            $createdName = New-LabSwitch -SwitchName $swName
            $result['shared'][$seg] = $createdName
        }
    }
    else {
        $result['shared'] = @{}
    }

    # ─────────────────────────────────────────────────────────────────────────
    # VERIFY ALL SWITCHES EXIST
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "Verifying all created switches..."
    $verifyFailed = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $result.Keys) {
        foreach ($seg in $result[$key].Keys) {
            $name = $result[$key][$seg]
            $sw   = Get-VMSwitch -Name $name -ErrorAction SilentlyContinue
            if ($null -eq $sw) {
                $verifyFailed.Add($name)
                Write-Log "Verification FAILED for switch: $name" -Level ERROR
            }
            else {
                Write-Log "Verified: $name ($($sw.SwitchType))" -Level OK
            }
        }
    }

    if ($verifyFailed.Count -gt 0) {
        throw "Verification failed for {0} switch(es): {1}" -f `
              $verifyFailed.Count, ($verifyFailed -join ', ')
    }

    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY LOG
    # ─────────────────────────────────────────────────────────────────────────
    Write-Log "===== NETWORK INITIALISATION COMPLETE ====="
    Write-Log ("LabType      : $LabType")
    Write-Log ("ClassId      : $ClassId")
    Write-Log ("StudentCount : $StudentCount")
    Write-Log ("Switches created/verified: $grandTotal")
    Write-Log ("Log file: $LogFile")

    Write-Verbose "Initialize-LabNetwork complete.  $grandTotal switch(es) ready."
    Write-Verbose "Log: $LogFile"

    # Return the switch name hashtable to caller
    return $result
}
catch {
    Write-Log "FATAL: $_" -Level ERROR
    throw
}
finally {
    Write-Log "Initialize-LabNetwork finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
}
