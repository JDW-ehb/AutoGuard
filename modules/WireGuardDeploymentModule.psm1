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
    param($SSHSession, $OSType)
    try {
        Write-Output "Checking WireGuard installation on $OSType..."

        if ($OSType -eq "Linux") {
            # You need to implement this too
            $command = "which wg"
        }
        elseif ($OSType -eq "Windows") {
            $command = @'
if (Test-Path "C:\Program Files\WireGuard\wireguard.exe") {
    Write-Output "Installed"
} else {
    Write-Output "Not Installed"
}
'@
        } else {
            throw "Unsupported OS: $OSType"
        }

        $result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $command

        if ($result.Output -match "Installed") {
            return $true
        }

        return $false
    }
    catch {
        Write-Error "Error while checking WireGuard installation on {$OSType}: $_"
        return $false
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
    param($SSHSession, $OSType)
    try {
        Write-Output "Installing WireGuard on $OSType..."
        
        if ($OSType -eq "Linux") {
            # ... your existing Linux code ...
        }
        elseif ($OSType -eq "Windows") {
            $scriptBlock = {
                $tempPath = [System.IO.Path]::GetTempPath()
                $installerPath = Join-Path $tempPath "wireguard-latest.msi"
                
                # Download latest version directly
                $sourceUrl = "https://download.wireguard.com/windows-client/wireguard-amd64-latest.msi"
                Invoke-WebRequest -Uri $sourceUrl -OutFile $installerPath -UseBasicParsing
                
                # Silent install without reboot
                Start-Process "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn /norestart" -Wait
                
                # Allow time for installation to complete
                Start-Sleep -Seconds 30
                
                # Cleanup installer
                if (Test-Path $installerPath) {
                    Remove-Item $installerPath -Force
                }
            }
            Invoke-Command -Session $SSHSession -ScriptBlock $scriptBlock
        }
    }
    catch {
        Write-Error "Installation failed on $OSType`: $_"
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
    param($Entity, $EntityType, $SSHSession, $OSType)
    
    try {
        # Get proper name based on entity type
        $entityName = if ($EntityType -eq "Server") { 
            if ($Entity.ServerName) { $Entity.ServerName } else { "Unnamed_Server" }
        } else { 
            if ($Entity.ClientName) { $Entity.ClientName } else { "Unnamed_Client" }
        }
        
        Write-Output "--- Starting deployment for {$EntityType}: $entityName ---"
        
        # Detect OS if not specified
        if (-not $OSType) {
            $osResult = Invoke-SSHCommand -SSHSession $SSHSession -Command "uname -s"
            $OSType = if ($osResult.Output -like "*Linux*") { "Linux" } else { "Windows" }
        }
        Write-Output "Detected OS: $OSType"

        # Check and install
        $isInstalled = Check-WireGuardInstallation -SSHSession $SSHSession -OSType $OSType
        if (-not $isInstalled) {
            Write-Output "WireGuard not found. Installing..."
            Install-WireGuard -SSHSession $SSHSession -OSType $OSType
            
            # Verify installation
            Start-Sleep -Seconds 10
            if (-not (Check-WireGuardInstallation -SSHSession $SSHSession -OSType $OSType)) {
                throw "Post-install verification failed"
            }
        }
        else {
            Write-Output "WireGuard already installed."
        }

        # Generate configuration
        $configContent = @"
[Interface]
PrivateKey = $($Entity.ServerPrivateKey)
Address = $($Entity.ServerAddress)
ListenPort = $($Entity.ListenPort)

[Peer]
PublicKey = $($Config.ClientConfigs[0].ClientPublicKey)
AllowedIPs = $($Config.ClientConfigs[0].ClientAddress)
"@

        # Write configuration
        Set-Content -Path "wg0.conf" -Value $configContent
        Write-Output "Configuration generated" 
        
        # Start tunnel (simplified for example)
        Write-Output "Starting WireGuard tunnel..."
    }
    catch {
        Write-Error "Error while deploying $EntityType $entityName`: $_"
        throw
    }
}




Export-ModuleMember -Function Update-AllowedIPs, Deploy-WireGuard, Establish-SSHConnection, Remove-Session, Test-OperatingSystem
