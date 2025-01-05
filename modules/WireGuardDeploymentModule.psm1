<# 
.SYNOPSIS
Contains WireGuard deployment and configuration automation functions.
.DESCRIPTION
This script includes functions to automate the deployment and configuration of WireGuard servers and clients.
Functions are designed to be platform-agnostic, supporting both Windows and Linux.
#>

# Hashtable for OS-Specific Commands
$WireGuardCommands = @{
    "CheckInstallation" = @{
        "Windows" = "Get-Command wireguard.exe | Select-Object -ExpandProperty Source"
        "Linux"   = "which wg && which wg-quick"
    }
    "DownloadInstaller" = @{
        "Windows" = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
    }
    "RunInstaller" = @{
        "Windows" = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait -NoNewWindow"
    }
    "WriteConfig" = @{
        "Windows" = "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value ""@CONTENT@"" -Force"
        "Linux"   = "sudo bash -c 'echo ""@CONTENT@"" > /etc/wireguard/wg0.conf && chmod 600 /etc/wireguard/wg0.conf'"
    }
    "StartTunnel" = @{
        "Windows" = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        "Linux"   = "sudo wg-quick up wg0"
    }
}

# Function: Establish-SSHConnection
<#
.SYNOPSIS
Establishes an SSH connection to a remote machine.
.PARAMETER IP
The IP address of the remote machine.
.PARAMETER Username
The username for SSH login.
.PARAMETER Password
The password for SSH login.
.RETURNS
Returns an SSH session object if successful.
#>

function Establish-SSHConnection {
    param (
        [string]$IP,
        [string]$Username,
        [string]$Password
    )
    try {
        # Convert the password to a secure string
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object PSCredential ($Username, $SecurePassword)

        # Check if the Posh-SSH module is installed
        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Write-Host "Installing Posh-SSH module..." -ForegroundColor Yellow
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser -ErrorAction Stop
        }

        # Attempt to establish an SSH session
        Write-Host "Establishing SSH connection to $IP..." -ForegroundColor Cyan
        $Session = New-SSHSession -ComputerName $IP -Credential $Credential -ErrorAction Stop

        # Confirm the session was established successfully
        if ($Session) {
            Write-Host "SSH connection to $IP established successfully." -ForegroundColor Green
            return $Session
        } else {
            throw "Failed to establish an SSH session to $IP."
        }
    } catch {
        # Handle any errors and stop further execution
        Write-Error "Failed to connect to ${IP}: $($_.Exception.Message)"
        throw
    }
}

# Function: Remove-Session
<#
.SYNOPSIS
Closes an SSH session.
.PARAMETER SessionId
The ID of the SSH session to close.
#>


function Remove-Session {
    param (
        [int]$SessionId
    )
    try {
        # Attempt to close the SSH session
        Write-Host "Closing SSH session with ID: $SessionId..." -ForegroundColor Yellow
        Remove-SSHSession -SessionId $SessionId -ErrorAction Stop

        # Confirm successful closure
        Write-Host "SSH session with ID $SessionId closed successfully." -ForegroundColor Green
    } catch {
        # Handle any errors and provide detailed feedback
        Write-Error "Failed to close SSH session with ID ${SessionId}: $($_.Exception.Message)"
        throw
    }
}

# Function: Test-OperatingSystem
<#
.SYNOPSIS
Detects the operating system of a remote machine via SSH.
.PARAMETER SSHSession
The SSH session object for the remote machine.
.RETURNS
Returns "Windows", "Linux", or throws an error if detection fails.
#>

function Test-OperatingSystem {
    param (
        [Parameter(Mandatory)] [object]$SSHSession
    )
    try {
        Write-Host "Checking the remote system's operating system..." -ForegroundColor Cyan

        # Test for Windows using PowerShell
        $WindowsCommand = 'powershell -Command "(Get-CimInstance -ClassName Win32_OperatingSystem).Caption"'
        $WindowsResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WindowsCommand -ErrorAction Stop

        # Handle Windows result
        if ($WindowsResult -and [string]::Join("", $WindowsResult.Output).Trim() -match "Windows") {
            Write-Host "Operating system detected: Windows" -ForegroundColor Green
            return "Windows"
        }

        # Test for Linux using uname
        $LinuxCommand = 'uname -s'
        $LinuxResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $LinuxCommand -ErrorAction Stop

        # Handle Linux result
        if ($LinuxResult -and [string]::Join("", $LinuxResult.Output).Trim() -match "Linux") {
            Write-Host "Operating system detected: Linux" -ForegroundColor Green
            return "Linux"
        }

        # If neither test succeeds
        Write-Warning "Unable to detect the remote system's operating system. Returning 'Unknown'."
        throw "Operating system detection failed: Unknown OS type."
    } catch {
        # Handle any errors and stop execution if OS detection fails
        Write-Error "Error during OS detection: $($_.Exception.Message)"
        throw
    }
}

# Function: Invoke-CommandByOS
<#
.SYNOPSIS
Executes an OS-specific command over an SSH session.
.DESCRIPTION
This function retrieves a command template based on the provided OS and command key, replaces placeholders if necessary, and executes the command via SSH.
.PARAMETER CommandKey
The key corresponding to the command to execute, e.g., "StartTunnel" or "WriteConfig".
.PARAMETER OS
The operating system of the remote machine, either "Windows" or "Linux".
.PARAMETER SSHSession
The SSH session object for the remote machine.
.PARAMETER ConfigContent
Optional. Configuration content to replace placeholders in the command template.
.RETURNS
Returns the result of the executed SSH command.
.THROWS
Throws an error if the command key or OS is invalid, or if the command execution fails.
#>

function Invoke-CommandByOS {
    param (
        [Parameter(Mandatory)] [string]$CommandKey,
        [Parameter(Mandatory)] [string]$OS,
        [Parameter(Mandatory)] $SSHSession,
        [string]$ConfigContent = $null
    )
    try {
        # Retrieve the command template based on the OS and command key
        if (-not $WireGuardCommands.ContainsKey($CommandKey)) {
            throw "Invalid CommandKey '$CommandKey'. It does not exist in the command table."
        }

        if (-not $WireGuardCommands[$CommandKey].ContainsKey($OS)) {
            throw "Command '$CommandKey' is not defined for OS '$OS'."
        }

        $CommandTemplate = $WireGuardCommands[$CommandKey][$OS]
        $Command = if ($ConfigContent) { $CommandTemplate -replace "@CONTENT@", $ConfigContent } else { $CommandTemplate }

        Write-Host "Executing Command: $Command" -ForegroundColor Yellow

        # Execute the command via SSH
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $Command -ErrorAction Stop

        # Validate the result
        if (-not $Result) {
            throw "Command execution returned null. Possible SSH or execution issue."
        }

        Write-Host "Command Output: $($Result.Output)" -ForegroundColor Cyan
        Write-Host "Exit Status: $($Result.ExitStatus)" -ForegroundColor Cyan

        # Check for non-zero exit status
        if ($Result.ExitStatus -ne 0) {
            throw "Command '$CommandKey' failed with status $($Result.ExitStatus). Output: $($Result.Output)"
        }

        # Return the result if successful
        return $Result
    } catch {
        # Handle and rethrow the error to stop execution
        Write-Error "Exception during command execution for '$CommandKey' on OS '$OS': $($_.Exception.Message)"
        throw
    }
}

# function Update-AllowedIPs
<#
.SYNOPSIS
Updates the AllowedIPs configuration for WireGuard servers and clients.
.DESCRIPTION
This function collects all client and server addresses and dynamically updates the AllowedIPs field for each server and client.
.PARAMETER Config
The configuration object containing ServerConfigs and ClientConfigs.
.RETURNS
None.
.THROWS
Throws an error if the configuration object is invalid or if any server or client configuration is incomplete.
#>

function Update-AllowedIPs {
    param (
        [Parameter(Mandatory)] $Config
    )
    try {
        Write-Host "`n--- Updating AllowedIPs for Servers and Clients ---`n" -ForegroundColor Cyan

        # Validate Config structure
        if (-not $Config.ServerConfigs -or -not $Config.ClientConfigs) {
            throw "Configuration object is missing required keys 'ServerConfigs' or 'ClientConfigs'."
        }

        # Collect all client and server addresses
        $AllClientAddresses = $Config.ClientConfigs | ForEach-Object {
            if (-not $_.ClientAddress) {
                throw "One or more ClientConfigs are missing 'ClientAddress'."
            }
            $_.ClientAddress
        }

        $AllServerAddresses = $Config.ServerConfigs | ForEach-Object {
            if (-not $_.ServerAddress) {
                throw "One or more ServerConfigs are missing 'ServerAddress'."
            }
            $_.ServerAddress
        }

        # Update AllowedIPs for servers
        foreach ($Server in $Config.ServerConfigs) {
            if (-not $Server) {
                throw "A ServerConfig entry is null or invalid."
            }
            $Server.AllowedIPs = $AllClientAddresses -join ", "
        }

        # Update AllowedIPs for clients
        foreach ($Client in $Config.ClientConfigs) {
            if (-not $Client) {
                throw "A ClientConfig entry is null or invalid."
            }
            $Client.AllowedIPs = $AllServerAddresses -join ", "
        }

        Write-Output "AllowedIPs updated successfully for all servers and clients."
    } catch {
        # Handle and log the error, then rethrow to stop execution
        Write-Error "Error while updating AllowedIPs: $($_.Exception.Message)"
        throw
    }
}

# Function: Check-WireGuardInstallation
<#
.SYNOPSIS
Checks if WireGuard is installed on the target system.
.DESCRIPTION
This function verifies the installation of WireGuard on a remote system using OS-specific commands.
.PARAMETER SSHSession
The SSH session object for the remote system.
.PARAMETER OS
The operating system of the remote system, either "Windows" or "Linux".
.RETURNS
Returns `$true` if WireGuard is installed, `$false` otherwise.
.THROWS
Throws an error if the OS is unsupported or if the SSH command fails.
#>

function Check-WireGuardInstallation {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    try {
        Write-Host "Checking if WireGuard is installed on the $OS system..." -ForegroundColor Cyan

        # Validate OS input
        if ($OS -notin @("Windows", "Linux")) {
            throw "Unsupported OS '$OS'. Only 'Windows' and 'Linux' are supported."
        }

        # Invoke the command to check WireGuard installation
        $Result = Invoke-CommandByOS -CommandKey "CheckInstallation" -OS $OS -SSHSession $SSHSession

        # Validate the result
        if ($Result -and $Result.Output -match "wireguard.exe|/usr/bin/wg") {
            Write-Host "WireGuard is installed." -ForegroundColor Green
            return $true
        }

        Write-Host "WireGuard is not installed." -ForegroundColor Red
        return $false
    } catch {
        # Handle and log the error, then rethrow to stop execution
        Write-Error "Error while checking WireGuard installation on ${OS}: $($_.Exception.Message)"
        throw
    }
}

# Function: Install-WireGuard
<#
.SYNOPSIS
Installs WireGuard on the target system.
.DESCRIPTION
This function installs WireGuard on a remote system by downloading and running the installer. It supports both Windows and Linux.
.PARAMETER SSHSession
The SSH session object for the remote system.
.PARAMETER OS
The operating system of the remote system, either "Windows" or "Linux".
.RETURNS
Returns `$true` if the installation is successful.
.THROWS
Throws an error if the OS is unsupported, the download fails, or the installation fails.
#>

function Install-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    try {
        Write-Host "Installing WireGuard on $OS..." -ForegroundColor Cyan

        # Validate OS input
        if ($OS -notin @("Windows", "Linux")) {
            throw "Unsupported OS '$OS'. Only 'Windows' and 'Linux' are supported."
        }

        # Step 1: Download the installer
        Write-Host "Downloading WireGuard installer..." -ForegroundColor Yellow
        $DownloadResult = Invoke-CommandByOS -CommandKey "DownloadInstaller" -OS $OS -SSHSession $SSHSession
        if (-not $DownloadResult -or $DownloadResult.ExitStatus -ne 0) {
            throw "Failed to download the WireGuard installer. Exit status: $($DownloadResult.ExitStatus)"
        }

        Write-Host "WireGuard installer downloaded successfully." -ForegroundColor Green

        # Step 2: Run the installer
        Write-Host "Running WireGuard installer..." -ForegroundColor Yellow
        $RunInstallerResult = Invoke-CommandByOS -CommandKey "RunInstaller" -OS $OS -SSHSession $SSHSession
        if (-not $RunInstallerResult -or $RunInstallerResult.ExitStatus -ne 0) {
            throw "Failed to execute the WireGuard installer. Exit status: $($RunInstallerResult.ExitStatus)"
        }

        Write-Host "WireGuard installation completed successfully." -ForegroundColor Green
        return $true
    } catch {
        # Handle and log the error, then rethrow to stop execution
        Write-Error "Error while installing WireGuard on ${OS}: $($_.Exception.Message)"
        throw
    }
}


# Function: Configure-WireGuard
<#
.SYNOPSIS
Configures WireGuard on the target system.
.DESCRIPTION
This function writes a WireGuard configuration file to the target system and sets the necessary permissions.
.PARAMETER SSHSession
The SSH session object for the remote system.
.PARAMETER OS
The operating system of the remote system, either "Windows" or "Linux".
.PARAMETER ConfigContent
The content of the WireGuard configuration file.
.RETURNS
None.
.THROWS
Throws an error if the OS is unsupported, the configuration content is invalid, or the configuration command fails.
#>

function Configure-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS,
        [Parameter(Mandatory)] [string]$ConfigContent
    )
    try {
        Write-Host "Writing WireGuard configuration on $OS..." -ForegroundColor Cyan

        # Validate OS input
        if ($OS -notin @("Windows", "Linux")) {
            throw "Unsupported OS '$OS'. Only 'Windows' and 'Linux' are supported."
        }

        # Ensure configuration content is not empty
        if (-not $ConfigContent) {
            throw "Configuration content cannot be null or empty."
        }

        # Execute the configuration command
        $Result = Invoke-CommandByOS -CommandKey "WriteConfig" -OS $OS -SSHSession $SSHSession -ConfigContent $ConfigContent

        # Validate the result
        if (-not $Result -or $Result.ExitStatus -ne 0) {
            throw "Failed to write WireGuard configuration. Exit status: $($Result.ExitStatus)"
        }

        Write-Host "WireGuard configuration written successfully on $OS." -ForegroundColor Green
    } catch {
        # Handle and log the error, then rethrow to stop execution
        Write-Error "Error while configuring WireGuard on ${OS}: $($_.Exception.Message)"
        throw
    }
}

# Function: Start-WireGuardTunnel
<#
.SYNOPSIS
Starts the WireGuard tunnel on the target system.
.DESCRIPTION
This function initiates a WireGuard tunnel on a remote system by executing the appropriate OS-specific command.
.PARAMETER SSHSession
The SSH session object for the remote system.
.PARAMETER OS
The operating system of the remote system, either "Windows" or "Linux".
.RETURNS
Returns `$true` if the tunnel starts successfully, `$false` otherwise.
.THROWS
Throws an error if the WireGuard executable is not found (on Windows) or if the tunnel fails to start.
#>
function Start-WireGuardTunnel {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Starting WireGuard tunnel on $OS..." -ForegroundColor Cyan

    if ($OS -eq "Windows" -and -not (Test-Path "C:\Program Files\WireGuard\wireguard.exe")) {
        Write-Error "WireGuard executable not found. Ensure installation was successful."
        return $false
    }

    $Result = Invoke-CommandByOS -CommandKey "StartTunnel" -OS $OS -SSHSession $SSHSession

    if ($Result -and $Result.ExitStatus -eq 0) {
        Write-Host "WireGuard tunnel started successfully." -ForegroundColor Green
        return $true
    }

    Write-Error "Failed to start WireGuard tunnel."
    return $false
}

# Function: Deploy-WireGuard
<#
.SYNOPSIS
Deploys and configures WireGuard for a server or client.
.DESCRIPTION
This function automates the deployment process of WireGuard on a remote system. It includes detecting the operating system, installing WireGuard if necessary, writing configuration files, and starting the WireGuard tunnel.
.PARAMETER Entity
The configuration object for the server or client being deployed.
.PARAMETER SSHSession
The SSH session object for the remote system.
.PARAMETER EntityType
Specifies whether the entity is a "Server" or "Client". Default is "Server".
.RETURNS
None.
.THROWS
Throws an error if any step in the deployment process fails, such as OS detection, installation, configuration, or tunnel startup.
#>
function Deploy-WireGuard {
    param (
        [Parameter(Mandatory)] $Entity,
        [Parameter(Mandatory)] $SSHSession,
        [string]$EntityType = "Server"
    )
    try {
        # Determine entity name for logging
        $EntityName = if ($Entity.Name) { $Entity.Name } else { "Unnamed Entity" }
        Write-Host "`n--- Starting deployment for ${EntityType}: $EntityName ---`n" -ForegroundColor Cyan

        # Detect the operating system
        $OS = Test-OperatingSystem -SSHSession $SSHSession
        if (-not $OS) {
            throw "Failed to detect OS. Skipping ${EntityType}: $EntityName."
        }

        # Build the configuration content based on the entity type
        $ConfigContent = if ($EntityType -eq "Server") {
            @"
[Interface]
PrivateKey = $($Entity.ServerPrivateKey)
ListenPort = $($Entity.ListenPort)
Address = $($Entity.ServerAddress)

[Peer]
PublicKey = $($Entity.ServerPublicKey)
AllowedIPs = $($Entity.AllowedIPs)
"@
        } elseif ($EntityType -eq "Client") {
            @"
[Interface]
PrivateKey = $($Entity.ClientPrivateKey)
Address = $($Entity.ClientAddress)

[Peer]
PublicKey = $($Entity.ClientPublicKey)
Endpoint = $($Entity.ClientEndpoint)
AllowedIPs = $($Entity.AllowedIPs)
PersistentKeepalive = 25
"@
        } else {
            throw "Invalid EntityType '$EntityType'. Supported types are 'Server' and 'Client'."
        }

        # Check if WireGuard is installed, install if necessary
        if (-not (Check-WireGuardInstallation -SSHSession $SSHSession -OS $OS)) {
            Install-WireGuard -SSHSession $SSHSession -OS $OS
        }

        # Configure WireGuard
        Configure-WireGuard -SSHSession $SSHSession -OS $OS -ConfigContent $ConfigContent

        # Start the WireGuard tunnel
        Start-WireGuardTunnel -SSHSession $SSHSession -OS $OS

        # Confirm successful deployment
        Write-Host "${EntityType} $EntityName deployed successfully." -ForegroundColor Green
    } catch {
        # Handle and log the error, then rethrow to stop execution
        Write-Error "Error while deploying ${EntityType}: $EntityName. Details: $($_.Exception.Message)"
        throw
    }
}


Export-ModuleMember -Function Update-AllowedIPs, Deploy-WireGuard, Establish-SSHConnection, Remove-Session, Test-OperatingSystem
