#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates student or instructor accounts inside a running lab VM.

.DESCRIPTION
    Provisions a user account inside a running VM after deployment, using:
        Windows: PowerShell Direct (Invoke-Command -VMName) — no network needed.
        Linux:   SSH to push useradd / chpasswd / sudo group membership commands.

    A random 16-character password is generated for each account.
    The username is derived from the student's email address (the local part
    before @, truncated to 12 characters, lowercased).

    For Windows VMs the user is added to the 'Users' local group (student) or
    'Administrators' group (instructor) and RDP access is enabled.

    For Linux VMs the user is created with a home directory and bash shell.
    Instructors are added to the 'sudo' group.  A .ssh directory is created
    and permissions set to 700.

    Credentials (username + generated password) are returned as a typed object
    and must be persisted by the caller (typically to the CyberLab database via
    the LabOrchestrationService).

.PARAMETER VMName
    The Hyper-V VM name as returned by Get-VM.

.PARAMETER OS
    Target operating system: 'Windows' or 'Linux'.

.PARAMETER StudentId
    The student's Entra ID Object ID (OID).  Used for logging/tracking only —
    not used as the VM username.

.PARAMETER StudentEmail
    The student's Entra ID email address.  The local part (before @) is used
    to derive the VM username.  Examples:
        john.smith@scps.edu   -> john.smith   (12 chars max)
        alexandra.jones@...   -> alexandra.j  (truncated)

.PARAMETER AdminCredential
    PSCredential with administrator access to the VM (for PowerShell Direct
    on Windows, or SSH admin user on Linux).

.PARAMETER Role
    Account role: 'student' or 'instructor'.
    student    : normal user privileges (Users / no sudo)
    instructor : elevated privileges (Administrators / sudo)

.EXAMPLE
    $cred = Get-Credential -UserName 'administrator' -Message 'VM admin password'
    $account = New-LabAccounts `
        -VMName         'WinServer-C1-S03' `
        -OS             'Windows' `
        -StudentId      'aabbccdd-1122-3344-5566-aabbccddeeff' `
        -StudentEmail   'john.smith@scps.edu' `
        -AdminCredential $cred `
        -Role           'student'
    Write-Host "Created: $($account.Username) / $($account.Password)"

.EXAMPLE
    New-LabAccounts `
        -VMName         'kali-C1-S03' `
        -OS             'Linux' `
        -StudentId      'aabbccdd-1122-3344-5566-aabbccddeeff' `
        -StudentEmail   'instructor@scps.edu' `
        -AdminCredential $sshCred `
        -Role           'instructor' `
        -Verbose

.OUTPUTS
    [PSCustomObject]@{
        VMName       = [string]
        OS           = [string]
        StudentId    = [string]
        StudentEmail = [string]
        Username     = [string]
        Password     = [string]   # plaintext — caller must store securely
        Role         = [string]
        Success      = [bool]
        ErrorMessage = [string]
    }

.NOTES
    The returned Password is plaintext and must be stored securely by the
    caller.  The LabOrchestrationService encrypts it before writing to the DB.

    SSH connectivity for Linux: the Hyper-V host must have ssh.exe on PATH
    and the VM must be reachable via its current (DHCP) IP address.
    Use Set-VMNetworkConfig.ps1 before New-LabAccounts.ps1 if the VM's
    static IP is not yet assigned.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [ValidateSet('Windows', 'Linux')]
    [string]$OS,

    [Parameter(Mandatory)]
    [string]$StudentId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$StudentEmail,

    [Parameter(Mandatory)]
    [PSCredential]$AdminCredential,

    [Parameter(Mandatory)]
    [ValidateSet('student', 'instructor')]
    [string]$Role
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT OBJECT
# ─────────────────────────────────────────────────────────────────────────────
$result = [PSCustomObject]@{
    VMName       = $VMName
    OS           = $OS
    StudentId    = $StudentId
    StudentEmail = $StudentEmail
    Username     = ''
    Password     = ''
    Role         = $Role
    Success      = $false
    ErrorMessage = ''
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function New-LabPassword {
    <#
    .SYNOPSIS Generates a random 16-character password with guaranteed complexity.
    Includes uppercase, lowercase, digit, and symbol characters.
    #>
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghjkmnpqrstuvwxyz'
    $digits  = '23456789'
    $symbols = '!@#$%&*'
    $allChars = $upper + $lower + $digits + $symbols

    # Guarantee at least one of each class
    $password = @(
        $upper[$($upper.Length   | Get-Random -Minimum 0)],
        $upper[$($upper.Length   | Get-Random -Minimum 0)],
        $lower[$($lower.Length   | Get-Random -Minimum 0)],
        $lower[$($lower.Length   | Get-Random -Minimum 0)],
        $digits[$($digits.Length | Get-Random -Minimum 0)],
        $digits[$($digits.Length | Get-Random -Minimum 0)],
        $symbols[$($symbols.Length | Get-Random -Minimum 0)]
    )

    # Fill remaining positions with random chars
    $needed = 16 - $password.Count
    for ($i = 0; $i -lt $needed; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }

    # Shuffle (Fisher-Yates)
    $arr = $password | ForEach-Object { $_ }
    for ($i = $arr.Count - 1; $i -gt 0; $i--) {
        $j = Get-Random -Maximum ($i + 1)
        $tmp = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $tmp
    }

    return -join $arr
}

function Get-LabUsername {
    <#
    .SYNOPSIS Derives a safe VM username from an email address.
    Rules: local part before @, lowercased, non-alphanumeric/dot chars removed,
    maximum 12 characters, must start with a letter.
    #>
    param([string]$Email)

    # Extract local part
    $local = $Email.Split('@')[0].ToLower()

    # Replace spaces, hyphens with dot; remove everything else except alnum and dot
    $local = $local -replace '[-\s]', '.'
    $local = $local -replace '[^a-z0-9\.]', ''

    # Ensure starts with a letter (prepend 'u' if it starts with digit/dot)
    if ($local -match '^[^a-z]') {
        $local = 'u' + $local
    }

    # Truncate to 12 characters
    if ($local.Length -gt 12) {
        $local = $local.Substring(0, 12)
    }

    # Remove trailing dots
    $local = $local.TrimEnd('.')

    return $local
}

function Invoke-SshLabCommand {
    <#
    .SYNOPSIS Runs a shell command on a Linux VM via ssh.exe.
    Returns stdout as a string.  Throws on non-zero exit code.
    #>
    param(
        [Parameter(Mandatory)][string]$SshHost,
        [Parameter(Mandatory)][string]$SshUser,
        [Parameter(Mandatory)][string]$Command
    )

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=20',
        '-o', 'LogLevel=ERROR',
        "${SshUser}@${SshHost}",
        $Command
    )

    Write-Verbose "SSH [$SshUser@$SshHost]: $Command"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = 'ssh.exe'
    $psi.Arguments              = ($sshArgs -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "SSH command failed (exit $($proc.ExitCode)): $($stderr.Trim())"
    }

    return $stdout.Trim()
}

function Get-LinuxSSHTarget {
    <#
    .SYNOPSIS Gets the current reachable IPv4 of a Linux VM via Hyper-V NICs.
    #>
    $vm   = Get-VM -Name $VMName -ErrorAction Stop
    $nics = Get-VMNetworkAdapter -VM $vm

    foreach ($nic in $nics) {
        $addr = $nic.IPAddresses | Where-Object {
            $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and
            -not ($_ -like '169.254.*')
        } | Select-Object -First 1
        if ($null -ne $addr) { return $addr }
    }
    throw "No reachable IPv4 address found on VM '$VMName'.  Ensure the VM is running."
}

# ─────────────────────────────────────────────────────────────────────────────
# WINDOWS ACCOUNT CREATION — PowerShell Direct
# ─────────────────────────────────────────────────────────────────────────────

function New-WindowsLabAccount {
    param([string]$Username, [string]$Password, [string]$UserRole)

    $guestScript = {
        param([string]$Uname, [string]$Pwd, [string]$URole)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Convert password to SecureString
        $securePwd = ConvertTo-SecureString -String $Pwd -AsPlainText -Force

        # Create local user if not already present
        $existingUser = Get-LocalUser -Name $Uname -ErrorAction SilentlyContinue
        if ($null -ne $existingUser) {
            Write-Output "User '$Uname' already exists — updating password."
            Set-LocalUser -Name $Uname -Password $securePwd -ErrorAction Stop
        }
        else {
            Write-Output "Creating local user '$Uname'..."
            New-LocalUser `
                -Name                  $Uname `
                -Password              $securePwd `
                -FullName              $Uname `
                -Description           'SCPS CyberLab student account' `
                -PasswordNeverExpires  `
                -UserMayNotChangePassword:$false `
                -AccountNeverExpires   `
                -ErrorAction           Stop | Out-Null
        }

        # Add to appropriate local group
        $group = if ($URole -eq 'instructor') { 'Administrators' } else { 'Users' }
        Write-Output "Adding '$Uname' to group '$group'..."
        try {
            Add-LocalGroupMember -Group $group -Member $Uname -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Commands.MemberExistsException] {
            Write-Output "Already a member of '$group' — skipping."
        }

        # Enable Remote Desktop access — add user to 'Remote Desktop Users' group
        Write-Output "Adding '$Uname' to Remote Desktop Users..."
        try {
            Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $Uname -ErrorAction Stop
        }
        catch [Microsoft.PowerShell.Commands.MemberExistsException] {
            Write-Output "Already in Remote Desktop Users — skipping."
        }

        # Ensure RDP is enabled on this machine (may already be set by build script)
        $rdpReg = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
        $fDenyTS = (Get-ItemProperty -Path $rdpReg -Name fDenyTSConnections -ErrorAction SilentlyContinue)?.fDenyTSConnections
        if ($fDenyTS -ne 0) {
            Write-Output "Enabling Remote Desktop..."
            Set-ItemProperty -Path $rdpReg -Name fDenyTSConnections -Value 0 -ErrorAction Stop
            Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
        }

        # Set password never expires at the policy level for this user
        # (belt-and-suspenders — already set via New-LocalUser flag above)
        $userObj = [ADSI]"WinNT://./$Uname,user"
        # ADS_UF_DONT_EXPIRE_PASSWD = 0x10000 = 65536
        $userObj.UserFlags = $userObj.UserFlags -bor 65536
        $userObj.SetInfo()

        Write-Output "Windows account '$Uname' ($URole) created successfully."
    }

    Write-Verbose "Creating Windows account '$Username' on '$VMName' via PowerShell Direct..."
    Invoke-Command `
        -VMName      $VMName `
        -Credential  $AdminCredential `
        -ScriptBlock $guestScript `
        -ArgumentList $Username, $Password, $UserRole `
        -ErrorAction Stop
}

# ─────────────────────────────────────────────────────────────────────────────
# LINUX ACCOUNT CREATION — SSH
# ─────────────────────────────────────────────────────────────────────────────

function New-LinuxLabAccount {
    param([string]$Username, [string]$Password, [string]$UserRole)

    $sshTarget = Get-LinuxSSHTarget
    $sshUser   = $AdminCredential.UserName

    Write-Verbose "Creating Linux account '$Username' on '$VMName' ($sshTarget) via SSH..."

    # ── Create user with home directory and bash shell ────────────────────
    $checkCmd = "id '$Username' 2>/dev/null && echo exists || echo notfound"
    $exists   = Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $checkCmd

    if ($exists -eq 'exists') {
        Write-Verbose "User '$Username' already exists — resetting password."
        $passwdCmd = "echo '${Username}:${Password}' | sudo chpasswd"
        Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $passwdCmd
    }
    else {
        Write-Verbose "Creating user '$Username'..."
        $addCmd = "sudo useradd -m -s /bin/bash -c 'SCPS CyberLab student' '$Username'"
        Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $addCmd

        # Set password via chpasswd
        $passwdCmd = "echo '${Username}:${Password}' | sudo chpasswd"
        Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $passwdCmd
    }

    # ── Group membership ──────────────────────────────────────────────────
    if ($UserRole -eq 'instructor') {
        Write-Verbose "Adding '$Username' to sudo group (instructor)..."
        $sudoCmd = "sudo usermod -aG sudo '$Username'"
        Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $sudoCmd
    }

    # ── .ssh directory ────────────────────────────────────────────────────
    # Create ~/.ssh with correct permissions so students can later add
    # their own public keys for key-based auth (lab hardening exercise).
    $sshDirCmd = @(
        "sudo mkdir -p /home/$Username/.ssh",
        "sudo touch /home/$Username/.ssh/authorized_keys",
        "sudo chmod 700 /home/$Username/.ssh",
        "sudo chmod 600 /home/$Username/.ssh/authorized_keys",
        "sudo chown -R ${Username}:${Username} /home/$Username/.ssh"
    ) -join ' && '
    Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $sshDirCmd

    # ── Password expiry — disable for lab duration ─────────────────────
    $chageCmd = "sudo chage -M -1 '$Username'"  # -M -1 = never expires
    Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $chageCmd

    # ── Verify ────────────────────────────────────────────────────────────
    $verifyCmd = "id '$Username' && echo ACCOUNT_OK"
    $verifyOut = Invoke-SshLabCommand -SshHost $sshTarget -SshUser $sshUser -Command $verifyCmd
    if ($verifyOut -notmatch 'ACCOUNT_OK') {
        throw "Account verification failed for '$Username' on '$VMName'.  Output: $verifyOut"
    }

    Write-Verbose "Linux account '$Username' ($UserRole) created successfully on '$VMName'."
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────
try {
    # Derive username from email
    $username = Get-LabUsername -Email $StudentEmail
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw "Could not derive a valid username from email '$StudentEmail'."
    }

    # Generate password
    $password = New-LabPassword

    Write-Verbose "New-LabAccounts: VM=$VMName OS=$OS Role=$Role"
    Write-Verbose "  Username : $username"
    Write-Verbose "  Email    : $StudentEmail"
    Write-Verbose "  StudentId: $StudentId"

    $result.Username = $username
    $result.Password = $password

    switch ($OS) {
        'Windows' {
            New-WindowsLabAccount -Username $username -Password $password -UserRole $Role
        }
        'Linux' {
            New-LinuxLabAccount -Username $username -Password $password -UserRole $Role
        }
    }

    $result.Success = $true
    Write-Verbose "New-LabAccounts complete: $username created on $VMName."
}
catch {
    $result.ErrorMessage = $_.Exception.Message
    Write-Error ("New-LabAccounts failed for '{0}' on VM '{1}': {2}" -f
                 $StudentEmail, $VMName, $_.Exception.Message)
}

return $result
