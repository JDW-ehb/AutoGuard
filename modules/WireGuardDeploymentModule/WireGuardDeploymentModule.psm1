# WireGuardDeployment.psm1

# Hashtable for OS-Specific Commands
$WireGuardCommands = @{
    "CheckInstallation" = @{
        "Windows" = "Get-Command wireguard.exe | Select-Object -ExpandProperty Source"
        "Linux"   = "which wg && which wg-quick"
    }
    "Install" = @{
        "Windows" = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'; Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait -Verb RunAs"
        "Linux"   = "sudo apt-get update && sudo apt-get install -y wireguard"
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

function Establish-SSHConnection {
    param (
        [Parameter(Mandatory)] [string]$IP,
        [Parameter(Mandatory)] [string]$Username,
        [string]$KeyPath = "$HOME\.ssh\id_rsa"  # Default path to the private key
    )
    try {
        # Ensure Posh-SSH module is installed
        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        }

        # Check if the key exists
        if (-not (Test-Path -Path $KeyPath)) {
            throw "SSH private key not found at $KeyPath"
        }

        Write-Host "Establishing SSH connection to $IP using key $KeyPath..." -ForegroundColor Cyan

        # Create a credential object with the username
        $Credential = New-Object -TypeName PSCredential -ArgumentList $Username, (ConvertTo-SecureString -String 'dummy' -AsPlainText -Force)

        # Establish the SSH session using the key
        $Session = New-SSHSession -ComputerName $IP -KeyFile $KeyPath -Credential $Credential

        if (-not $Session) {
            throw "SSH connection failed to $IP"
        }

        Write-Host "SSH connection to $IP established successfully." -ForegroundColor Green
        return $Session
    } catch {
        Write-Host "Failed to connect to ${IP}: $_" -ForegroundColor Red
        return $null
    }
}




function Remove-Session {
    param ([int]$SessionId)
    try {
        Write-Host "Closing SSH session with ID: $SessionId..." -ForegroundColor Yellow
        Remove-SSHSession -SessionId $SessionId
        Write-Host "SSH session closed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to close SSH session: $_" -ForegroundColor Red
    }
}

function Test-OperatingSystem {
    param (
        [Parameter(Mandatory)] [object]$SSHSession
    )
    try {
        Write-Host "Checking the remote system's operating system..." -ForegroundColor Cyan

        # Test for Windows
        $WindowsCommand = 'powershell -Command "(Get-CimInstance Win32_OperatingSystem).Caption"'
        $WindowsResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WindowsCommand

        # Clean up output and ensure it's a string
        $CleanWindowsResult = [string]::Join("", $WindowsResult.Output).Trim()

        Write-Host "Windows Command Result: '$CleanWindowsResult'" -ForegroundColor Yellow

        if ($CleanWindowsResult -match "Windows") {
            return "Windows"
        }

        # Test for Linux
        $LinuxCommand = 'uname -s'
        $LinuxResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $LinuxCommand

        # Clean up output and ensure it's a string
        $CleanLinuxResult = [string]::Join("", $LinuxResult.Output).Trim()

        Write-Host "Linux Command Result: '$CleanLinuxResult'" -ForegroundColor Yellow

        if ($CleanLinuxResult -match "Linux") {
            return "Linux"
        }

        # If neither Windows nor Linux is detected
        Write-Warning "Unable to detect the remote system's operating system. Returning 'Unknown'."
        return "Unknown"
    } catch {
        Write-Error "Error during OS detection: $_"
        return "Unknown"
    }
}

function Invoke-CommandByOS {
    param (
        [Parameter(Mandatory)] [string]$CommandKey,
        [Parameter(Mandatory)] [string]$OS,
        [Parameter(Mandatory)] $SSHSession,
        [string]$ConfigContent = $null
    )
    try {
        $CommandTemplate = $WireGuardCommands[$CommandKey][$OS]
        $Command = if ($ConfigContent) { $CommandTemplate -replace "@CONTENT@", $ConfigContent } else { $CommandTemplate }

        Write-Host "Executing Command: $Command" -ForegroundColor Yellow
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $Command

        Write-Host "Command Output: $($Result.Output)" -ForegroundColor Cyan
        Write-Host "Exit Status: $($Result.ExitStatus)" -ForegroundColor Cyan

        if ($Result.ExitStatus -ne 0) {
            Write-Error "Command '$CommandKey' failed: $($Result.Output)"
            return $null
        }

        return $Result
    } catch {
        Write-Warning "Failed to execute command: $($_.Exception.Message)"
        return $null
    }
}

function Update-AllowedIPs {
    param ([Parameter(Mandatory)] $Config)

    Write-Host "`n--- Updating AllowedIPs for Servers and Clients ---`n" -ForegroundColor Cyan

    $AllClientAddresses = $Config.ClientConfigs | ForEach-Object { $_.ClientAddress }
    $AllServerAddresses = $Config.ServerConfigs | ForEach-Object { $_.ServerAddress }

    foreach ($Server in $Config.ServerConfigs) { $Server.AllowedIPs = $AllClientAddresses -join ", " }
    foreach ($Client in $Config.ClientConfigs) { $Client.AllowedIPs = $AllServerAddresses -join ", " }

    Write-Output "AllowedIPs updated successfully for all servers and clients."
}

function Check-WireGuardInstallation {
    param ([Parameter(Mandatory)] $SSHSession, [Parameter(Mandatory)] [string]$OS)
    Write-Host "Checking if WireGuard is installed..." -ForegroundColor Cyan
    return Invoke-CommandByOS -CommandKey "CheckInstallation" -OS $OS -SSHSession $SSHSession
}

function Install-WireGuard {
    param ([Parameter(Mandatory)] $SSHSession, [Parameter(Mandatory)] [string]$OS)
    Write-Host "Installing WireGuard on $OS..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "Install" -OS $OS -SSHSession $SSHSession
    Write-Host "WireGuard installation completed successfully." -ForegroundColor Green
}

function Configure-WireGuard {
    param ([Parameter(Mandatory)] $SSHSession, [Parameter(Mandatory)] [string]$OS, [Parameter(Mandatory)] [string]$ConfigContent)
    Write-Host "Writing WireGuard configuration..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "WriteConfig" -OS $OS -SSHSession $SSHSession -ConfigContent $ConfigContent
}

function Start-WireGuardTunnel {
    param ([Parameter(Mandatory)] $SSHSession, [Parameter(Mandatory)] [string]$OS)
    Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "StartTunnel" -OS $OS -SSHSession $SSHSession
}

function Deploy-WireGuard {
    param (
        [Parameter(Mandatory)] $Entity,    # Server or Client config
        [Parameter(Mandatory)] $SSHSession,
        [string]$EntityType = "Server"     # Server or Client
    )
    Write-Host "`n--- Starting deployment for ${EntityType}: $($Entity.Name) ---`n" -ForegroundColor Cyan

    $OS = Test-OperatingSystem -SSHSession $SSHSession
    if (-not $OS) {
        Write-Warning "Could not detect OS. Skipping ${EntityType}: $($Entity.Name)"
        return
    }

    # Configuration for Server or Client
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
    }

    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession -OS $OS)) {
        Install-WireGuard -SSHSession $SSHSession -OS $OS
    }

    Configure-WireGuard -SSHSession $SSHSession -OS $OS -ConfigContent $ConfigContent
    Start-WireGuardTunnel -SSHSession $SSHSession -OS $OS
    Write-Output "${EntityType} $($Entity.Name) deployed successfully."
}

Export-ModuleMember -Function Update-AllowedIPs, Deploy-WireGuard, Deploy-WireGuardServer, Deploy-WireGuardClient, Establish-SSHConnection, Remove-Session, Test-OperatingSystem
