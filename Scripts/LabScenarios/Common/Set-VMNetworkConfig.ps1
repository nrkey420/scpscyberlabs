#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures static IP addressing inside a running lab VM.

.DESCRIPTION
    Applies IP address, subnet prefix, gateway, and DNS server settings to a
    running VM using the appropriate mechanism for its OS:

    Windows: PowerShell Direct (Invoke-Command -VMName) — no network required.
    Linux:   SSH (ssh -o StrictHostKeyChecking=no) to push either:
               - Ubuntu/Debian + netplan  -> /etc/netplan/99-lab.yaml + netplan apply
               - Debian/older Linux       -> /etc/network/interfaces + ifdown/ifup

    Both paths retry up to 3 times with a 10-second delay between attempts,
    to handle VMs that are still booting when this function is called.

.PARAMETER VMName
    The Hyper-V VM name as returned by Get-VM.

.PARAMETER HyperVVMId
    The Hyper-V VM GUID (for logging and PowerShell Direct identification).

.PARAMETER OS
    Target operating system: 'Windows' or 'Linux'.

.PARAMETER IpAddress
    IPv4 address to assign (e.g., "10.1.3.10").

.PARAMETER SubnetPrefix
    CIDR prefix length as a string (e.g., "24").

.PARAMETER Gateway
    IPv4 default gateway address (e.g., "10.1.3.1").

.PARAMETER DnsServer
    DNS server IPv4 address (e.g., "10.1.3.1" — typically the pfSense LAN IP).

.PARAMETER InterfaceName
    Network interface to configure.
    Windows: adapter name as shown in Get-NetAdapter (e.g., "Ethernet").
    Linux: interface name (e.g., "eth1", "ens3").

.PARAMETER Credential
    PSCredential used to authenticate to the VM.
    Windows: local administrator account.
    Linux:   SSH user (typically 'kali', 'vyos', 'ubuntu', or 'root').

.EXAMPLE
    $cred = Get-Credential
    Set-VMNetworkConfig `
        -VMName        'kali-C1-S03' `
        -HyperVVMId    'a1b2c3d4-...' `
        -OS            'Linux' `
        -IpAddress     '10.1.3.10' `
        -SubnetPrefix  '24' `
        -Gateway       '10.1.3.1' `
        -DnsServer     '10.1.3.1' `
        -InterfaceName 'eth0' `
        -Credential    $cred

.EXAMPLE
    Set-VMNetworkConfig `
        -VMName        'WinServer-C1-S03' `
        -HyperVVMId    'e5f6a7b8-...' `
        -OS            'Windows' `
        -IpAddress     '10.1.3.100' `
        -SubnetPrefix  '24' `
        -Gateway       '10.1.3.1' `
        -DnsServer     '10.1.3.1' `
        -InterfaceName 'Ethernet' `
        -Credential    $adminCred

.OUTPUTS
    [PSCustomObject]@{
        VMName        = [string]
        IpAddress     = [string]
        SubnetPrefix  = [string]
        Gateway       = [string]
        DnsServer     = [string]
        OS            = [string]
        Success       = [bool]
        AttemptCount  = [int]
        ErrorMessage  = [string]  # empty on success
    }

.NOTES
    For Linux VMs: the SSH client (ssh.exe) must be on the Hyper-V host PATH.
    Windows 10/11 and Server 2019+ include OpenSSH client by default.
    The function detects netplan vs ifupdown by checking for /usr/sbin/netplan.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$HyperVVMId,

    [Parameter(Mandatory)]
    [ValidateSet('Windows', 'Linux')]
    [string]$OS,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$IpAddress,

    [Parameter(Mandatory)]
    [ValidateRange(8, 30)]
    [string]$SubnetPrefix,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$Gateway,

    [Parameter(Mandatory)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$DnsServer,

    [Parameter(Mandatory)]
    [string]$InterfaceName,

    [Parameter(Mandatory)]
    [PSCredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$MaxRetries    = 3
$RetryDelaySec = 10

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT OBJECT TEMPLATE
# ─────────────────────────────────────────────────────────────────────────────
$result = [PSCustomObject]@{
    VMName       = $VMName
    IpAddress    = $IpAddress
    SubnetPrefix = $SubnetPrefix
    Gateway      = $Gateway
    DnsServer    = $DnsServer
    OS           = $OS
    Success      = $false
    AttemptCount = 0
    ErrorMessage = ''
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-WithRetry {
    <#
    .SYNOPSIS Runs a scriptblock up to $MaxRetries times with delay on failure.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$Description = 'operation'
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $result.AttemptCount = $attempt
        try {
            Write-Verbose "Attempt $attempt/$MaxRetries: $Description"
            & $Action
            Write-Verbose "Attempt $attempt succeeded."
            return   # success — exit the retry loop
        }
        catch {
            Write-Warning ("Attempt $attempt/$MaxRetries failed for '$Description': {0}" -f $_.Exception.Message)
            if ($attempt -lt $MaxRetries) {
                Write-Verbose "Waiting ${RetryDelaySec}s before retry..."
                Start-Sleep -Seconds $RetryDelaySec
            }
            else {
                # All retries exhausted — rethrow
                throw
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS — POWERSHELL DIRECT
# ─────────────────────────────────────────────────────────────────────────────

function Set-WindowsNetworkConfig {
    Write-Verbose "Configuring Windows VM '$VMName' via PowerShell Direct..."

    # Scriptblock to run inside the guest VM
    $guestScript = {
        param(
            [string]$Ip,
            [int]   $Prefix,
            [string]$Gw,
            [string]$Dns,
            [string]$IfaceName
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Locate the adapter — match by name (exact or wildcard)
        $adapter = Get-NetAdapter -Name $IfaceName -ErrorAction SilentlyContinue
        if ($null -eq $adapter) {
            # Try partial match
            $adapter = Get-NetAdapter | Where-Object { $_.Name -like "*$IfaceName*" } |
                       Select-Object -First 1
        }
        if ($null -eq $adapter) {
            throw "Network adapter '$IfaceName' not found.  Available: " +
                  ((Get-NetAdapter | Select-Object -ExpandProperty Name) -join ', ')
        }

        $ifIndex = $adapter.InterfaceIndex
        Write-Output "Adapter: $($adapter.Name) (index $ifIndex)"

        # Remove any existing IP configuration on this interface
        $existingIps = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        foreach ($existing in $existingIps) {
            Write-Output "Removing existing IP: $($existing.IPAddress)"
            Remove-NetIPAddress -InputObject $existing -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Remove any existing default gateway on this interface
        $existingRoutes = Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        foreach ($route in $existingRoutes) {
            Write-Output "Removing existing default route via $($route.NextHop)"
            Remove-NetRoute -InputObject $route -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Assign static IP with gateway
        Write-Output "Assigning $Ip/$Prefix gateway $Gw..."
        New-NetIPAddress `
            -InterfaceIndex  $ifIndex `
            -IPAddress       $Ip `
            -PrefixLength    $Prefix `
            -DefaultGateway  $Gw `
            -ErrorAction Stop | Out-Null

        # Set DNS server
        Write-Output "Setting DNS server: $Dns"
        Set-DnsClientServerAddress `
            -InterfaceIndex  $ifIndex `
            -ServerAddresses @($Dns) `
            -ErrorAction Stop

        # Disable DHCP on this adapter (ensure it stays static after reboot)
        Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue

        Write-Output "Windows network configuration applied: $Ip/$Prefix gw $Gw dns $Dns"
    }

    Invoke-WithRetry -Description "PowerShell Direct to '$VMName'" -Action {
        Invoke-Command `
            -VMName      $VMName `
            -Credential  $Credential `
            -ScriptBlock $guestScript `
            -ArgumentList $IpAddress, [int]$SubnetPrefix, $Gateway, $DnsServer, $InterfaceName `
            -ErrorAction Stop
    }

    Write-Verbose "Windows network configuration complete for '$VMName'."
}

# ─────────────────────────────────────────────────────────────────────────────
# LINUX — SSH + NETPLAN or IFUPDOWN
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-SshCommand {
    <#
    .SYNOPSIS Runs a command on the Linux VM via ssh.exe.
    Returns the combined stdout+stderr as a string.
    Throws on non-zero exit code.
    #>
    param(
        [Parameter(Mandatory)][string]$SshHost,
        [Parameter(Mandatory)][string]$SshUser,
        [Parameter(Mandatory)][string]$Command,
        [string]$PrivateKeyPath = '',   # optional key file
        [switch]$Sudo
    )

    # Build SSH arguments
    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'BatchMode=yes',               # no interactive prompts
        '-o', 'ConnectTimeout=15',
        '-o', 'LogLevel=ERROR'
    )

    if (-not [string]::IsNullOrWhiteSpace($PrivateKeyPath)) {
        $sshArgs += '-i', $PrivateKeyPath
    }

    $remoteCommand = if ($Sudo) { "sudo sh -c '$Command'" } else { $Command }
    $sshArgs += "${SshUser}@${SshHost}", $remoteCommand

    Write-Verbose "SSH: $SshUser@$SshHost -> $Command"

    # Use SSHPASS or sshpass-equivalent via Credential.GetNetworkCredential().Password
    # On Windows, passing password to SSH is done via SSH_ASKPASS or a key.
    # For lab environments we use key-based auth; password is fallback.
    $env:SSHPASS = $Credential.GetNetworkCredential().Password

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = 'ssh.exe'
    $psi.Arguments = ($sshArgs | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    # If password auth is needed, try sshpass wrapper (available via Git for Windows or WSL)
    # Alternatively, expect a pre-shared key in $Credential (key path in Password field).
    # Lab recommendation: use pre-provisioned SSH key; set key path in $PrivateKeyPath.

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $env:SSHPASS = $null

    $combined = ($stdout + $stderr).Trim()
    if ($proc.ExitCode -ne 0) {
        throw "SSH command failed (exit $($proc.ExitCode)): $combined"
    }
    Write-Verbose "SSH result: $combined"
    return $combined
}

function Set-LinuxNetworkConfig {
    param([string]$SshHost)

    Write-Verbose "Configuring Linux VM '$VMName' ($SshHost) via SSH..."

    $sshUser = $Credential.UserName

    Invoke-WithRetry -Description "SSH connectivity to $SshHost" -Action {
        # ── Detect network manager (netplan or ifupdown) ──────────────────
        $hasNetplan = Invoke-SshCommand -SshHost $SshHost -SshUser $sshUser `
                          -Command 'test -f /usr/sbin/netplan && echo yes || echo no' `
                          -ErrorAction Stop

        if ($hasNetplan.Trim() -eq 'yes') {
            Write-Verbose "Detected netplan (Ubuntu/Debian modern) on $VMName"
            Set-LinuxNetplanConfig -SshHost $SshHost -SshUser $sshUser
        }
        else {
            Write-Verbose "Detected ifupdown (Debian classic) on $VMName"
            Set-LinuxIfupdownConfig -SshHost $SshHost -SshUser $sshUser
        }
    }

    Write-Verbose "Linux network configuration complete for '$VMName'."
}

function Set-LinuxNetplanConfig {
    param([string]$SshHost, [string]$SshUser)

    # Compose the netplan YAML.  Heredoc-safe: no single-quotes in values.
    # netplan requires consistent indentation (2-space).
    $netplanYaml = @"
# SCPS CyberLab — generated by Set-VMNetworkConfig.ps1
# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
network:
  version: 2
  renderer: networkd
  ethernets:
    ${InterfaceName}:
      dhcp4: false
      dhcp6: false
      addresses:
        - ${IpAddress}/${SubnetPrefix}
      routes:
        - to: default
          via: ${Gateway}
      nameservers:
        addresses:
          - ${DnsServer}
          - 8.8.8.8
"@

    # Escape single quotes in the YAML for the shell heredoc
    $escapedYaml = $netplanYaml -replace "'", "'\"'\"'"

    # Write the file via SSH using a printf heredoc approach
    # We base64-encode the YAML to avoid quoting issues entirely
    $yamlBytes   = [System.Text.Encoding]::UTF8.GetBytes($netplanYaml)
    $yamlBase64  = [Convert]::ToBase64String($yamlBytes)

    $writeCmd = @"
echo '$yamlBase64' | base64 -d | sudo tee /etc/netplan/99-lab.yaml > /dev/null
"@
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser -Command $writeCmd

    # Set correct permissions (netplan requires 600)
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser `
        -Command 'sudo chmod 600 /etc/netplan/99-lab.yaml'

    # Remove any conflicting netplan files that set this interface to DHCP
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser `
        -Command ("sudo find /etc/netplan -name '*.yaml' ! -name '99-lab.yaml' " +
                  "-exec grep -l '$InterfaceName' {} \; | " +
                  "xargs -r sudo rm -f")

    # Apply the configuration
    Write-Verbose "Applying netplan on $VMName..."
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser `
        -Command 'sudo netplan apply 2>&1'

    Write-Verbose "netplan applied: $IpAddress/$SubnetPrefix gw $Gateway dns $DnsServer"
}

function Set-LinuxIfupdownConfig {
    param([string]$SshHost, [string]$SshUser)

    # Compute network mask from prefix length
    $prefixInt   = [int]$SubnetPrefix
    $maskBinary  = ('1' * $prefixInt).PadRight(32, '0')
    $maskOctets  = @(
        [Convert]::ToInt32($maskBinary.Substring(0,  8), 2),
        [Convert]::ToInt32($maskBinary.Substring(8,  8), 2),
        [Convert]::ToInt32($maskBinary.Substring(16, 8), 2),
        [Convert]::ToInt32($maskBinary.Substring(24, 8), 2)
    )
    $netmask = $maskOctets -join '.'

    $ifupdownStanza = @"
# SCPS CyberLab — ${InterfaceName} — generated by Set-VMNetworkConfig.ps1
# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
auto ${InterfaceName}
iface ${InterfaceName} inet static
    address   ${IpAddress}
    netmask   ${netmask}
    gateway   ${Gateway}
    dns-nameservers ${DnsServer} 8.8.8.8
"@

    $ifBytes  = [System.Text.Encoding]::UTF8.GetBytes($ifupdownStanza)
    $ifBase64 = [Convert]::ToBase64String($ifBytes)

    # Write stanza to a per-interface file (cleaner than editing /etc/network/interfaces directly)
    $writeCmd = @"
echo '$ifBase64' | base64 -d | sudo tee /etc/network/interfaces.d/${InterfaceName}.cfg > /dev/null
"@
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser -Command $writeCmd

    # Ensure /etc/network/interfaces sources interfaces.d
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser `
        -Command "grep -q 'source /etc/network/interfaces.d' /etc/network/interfaces || " +
                 "echo 'source /etc/network/interfaces.d/*' | sudo tee -a /etc/network/interfaces"

    # Bring the interface down (if up) and bring it back up with new config
    Write-Verbose "Applying ifdown/ifup on $VMName ($InterfaceName)..."
    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser `
        -Command "sudo ifdown '$InterfaceName' 2>/dev/null; sudo ifup '$InterfaceName' 2>&1" `
        -ErrorAction SilentlyContinue  # ifdown may fail if interface wasn't up — acceptable

    # Also set via ip command immediately (in case ifup didn't fire)
    $ipCmds = @(
        "sudo ip addr flush dev '$InterfaceName' 2>/dev/null",
        "sudo ip addr add '$IpAddress/$SubnetPrefix' dev '$InterfaceName'",
        "sudo ip link set '$InterfaceName' up",
        "sudo ip route replace default via '$Gateway' dev '$InterfaceName'",
        "echo 'nameserver $DnsServer' | sudo tee /etc/resolv.conf"
    ) -join '; '

    Invoke-SshCommand -SshHost $SshHost -SshUser $SshUser -Command $ipCmds

    Write-Verbose "ifupdown applied: $IpAddress/$SubnetPrefix gw $Gateway dns $DnsServer"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
try {
    Write-Verbose "Set-VMNetworkConfig: $VMName ($OS) -> $IpAddress/$SubnetPrefix gw $Gateway dns $DnsServer"

    switch ($OS) {
        'Windows' {
            Set-WindowsNetworkConfig
        }
        'Linux' {
            # For Linux, resolve the VM's current IP via Hyper-V (used as SSH target).
            # The VM may have a DHCP address from a management switch at this point.
            # Callers can also pass the known management IP as $IpAddress of a _different_
            # interface; we SSH to the VM's existing reachable address.
            # Convention: SSH target = current DHCP IP on management switch.
            # We use Hyper-V to get the guest IP via VMNetworkAdapter.
            $vmObj = Get-VM -Name $VMName -ErrorAction Stop
            $nics  = Get-VMNetworkAdapter -VM $vmObj

            # Find the first adapter with a non-placeholder IP (any IPv4 not starting with 169)
            $sshTarget = $null
            foreach ($nic in $nics) {
                $ipv4 = $nic.IPAddresses | Where-Object {
                    $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and
                    -not ($_ -like '169.254.*')
                } | Select-Object -First 1
                if ($null -ne $ipv4) {
                    $sshTarget = $ipv4
                    break
                }
            }

            if ($null -eq $sshTarget) {
                throw "Cannot determine SSH target IP for '$VMName'.  " +
                      "No reachable IPv4 address found on any adapter.  " +
                      "Ensure the VM is running and has a DHCP management address."
            }

            Write-Verbose "SSH target for '$VMName': $sshTarget"
            Set-LinuxNetworkConfig -SshHost $sshTarget
        }
    }

    $result.Success = $true
    Write-Verbose "Set-VMNetworkConfig succeeded for '$VMName'."
}
catch {
    $result.ErrorMessage = $_.Exception.Message
    Write-Error ("Set-VMNetworkConfig failed for '{0}': {1}" -f $VMName, $_.Exception.Message)
}

return $result
