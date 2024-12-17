# WindowsDeployments.psm1
# PowerShell Module for Unified WireGuard Deployment on Windows Servers and Clients

# Hashtable for OS-Specific Commands
$WireGuardCommands = @{
    "CheckInstallation" = @{
        "Windows" = "Get-Command wireguard.exe | Select-Object -ExpandProperty Source"
        "Linux"   = "which wireguard"
    }
    "Install" = @{
        "Windows" = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'; Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
        "Linux"   = "apt-get update && apt-get install -y wireguard"
    }
    "WriteConfig" = @{
        "Windows" = "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @CONTENT@ -Force"
        "Linux"   = "echo '@CONTENT@' | tee /etc/wireguard/wg0.conf"
    }
    "StartTunnel" = @{
        "Windows" = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        "Linux"   = "wg-quick up wg0"
    }
}

function Invoke-CommandByOS {
    param (
        [Parameter(Mandatory)]
        [string]$CommandKey,

        [Parameter(Mandatory)]
        [string]$OS,

        [Parameter(Mandatory)]
        $SSHSession,

        [string]$ConfigContent = $null
    )
    try {
        # Get the correct command
        $CommandTemplate = $WireGuardCommands[$CommandKey][$OS]

        # Replace placeholder for configuration content if applicable
        if ($ConfigContent) {
            $Command = $CommandTemplate -replace "@CONTENT@", [regex]::Escape($ConfigContent)
        } else {
            $Command = $CommandTemplate
        }

        # Execute the command
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $Command
    } catch {
        Write-Host "Failed to execute command '$CommandKey': $_" -ForegroundColor Red
        exit
    }
}

function Update-AllowedIPs {
    param (
        [Parameter(Mandatory)] $Config
    )

    Write-Host "`n--- Updating AllowedIPs for Servers and Clients ---` " -ForegroundColor Cyan

    # Extract all Client and Server addresses
    $AllClientAddresses = $Config.ClientConfigs | ForEach-Object { $_.ClientAddress }
    $AllServerAddresses = $Config.ServerConfigs | ForEach-Object { $_.ServerAddress }

    # Update AllowedIPs for Servers
    foreach ($Server in $Config.ServerConfigs) {
        $Server.AllowedIPs = $AllClientAddresses -join ", "
    }

    # Update AllowedIPs for Clients
    foreach ($Client in $Config.ClientConfigs) {
        $Client.AllowedIPs = $AllServerAddresses -join ", "
    }

    Write-Output "AllowedIPs updated successfully for all servers and clients."
}

function Check-WireGuardInstallation {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Checking if WireGuard is installed..." -ForegroundColor Cyan
    try {
        if ($OS -eq "Windows") {
            $Result = Invoke-CommandByOS -CommandKey "CheckInstallation" -OS $OS -SSHSession $SSHSession
        }
        elseif ($OS -eq "Linux") {
            $CheckCommand = "which wg && which wg-quick"
            $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckCommand

            if ($Result.ExitStatus -ne 0) {
                Write-Error "WireGuard binaries not found: $($Result.Output)"
                return $false
            }
        }
        return -not [string]::IsNullOrEmpty($Result.Output)
    } catch {
        Write-Host "Failed to check WireGuard installation: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}


function Install-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Installing WireGuard..." -ForegroundColor Cyan
    try {
        if ($OS -eq "Windows") {
            Invoke-CommandByOS -CommandKey "Install" -OS $OS -SSHSession $SSHSession
        }
        elseif ($OS -eq "Linux") {
            # Use sudo without password prompt, capture stdout and stderr
            $InstallCommand = @"
sudo -n apt-get update -y && sudo -n apt-get install -y wireguard 2>&1
"@
            Write-Host "Running installation command: $InstallCommand" -ForegroundColor Yellow
            $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand

            # Log the full output for debugging
            Write-Host "Install Command Output: $($Result.Output)" -ForegroundColor Cyan

            if ($Result.ExitStatus -ne 0) {
                Write-Error "WireGuard installation failed on Linux: $($Result.Output)"
                exit
            }
            Write-Host "WireGuard installation completed successfully." -ForegroundColor Green
        }
        else {
            Write-Error "Unsupported OS for installation: $OS"
            exit
        }
    } catch {
        Write-Host "Failed to install WireGuard: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}




function Configure-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS,
        [Parameter(Mandatory)] [string]$ConfigContent
    )
    try {
        Write-Host "Writing WireGuard configuration..." -ForegroundColor Cyan

        if ($OS -eq "Windows") {
            # Ensure the directory exists on Windows
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"

            # Write the configuration file
            $WriteConfigCommand = @"
Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$ConfigContent
'@ -Force
"@
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
        }
        elseif ($OS -eq "Linux") {
            # Ensure the directory exists on Linux
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "sudo mkdir -p /etc/wireguard"

            # Write the configuration file and sanitize filename
            $WriteConfigCommand = @"
sudo bash -c 'echo "$ConfigContent" > /etc/wireguard/wg0.conf && dos2unix /etc/wireguard/wg0.conf'
"@
            Write-Host "Running configuration command on Linux..." -ForegroundColor Yellow
            $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand

            # Check for errors
            if ($Result.ExitStatus -ne 0) {
                Write-Error "Failed to write WireGuard configuration file: $($Result.Output)"
                exit
            }

            # Set correct permissions
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "sudo chmod 600 /etc/wireguard/wg0.conf"
        }
        else {
            Write-Error "Unsupported operating system: $OS"
            return
        }

        Write-Host "Configuration file written successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to configure WireGuard: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}




function Start-WireGuardTunnel {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
    try {
        if ($OS -eq "Windows") {
            Invoke-CommandByOS -CommandKey "StartTunnel" -OS $OS -SSHSession $SSHSession
        }
        elseif ($OS -eq "Linux") {
            # Verify the configuration file exists
            $VerifyConfigCommand = "sudo test -f /etc/wireguard/wg0.conf && echo 'Config exists' || echo 'Config missing'"
            $VerifyResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyConfigCommand

            if ($VerifyResult.Output -notmatch "Config exists") {
                Write-Error "WireGuard configuration file missing on Linux client."
                exit
            }

            # Start WireGuard tunnel with sudo
            $StartCommand = "sudo wg-quick up wg0"
            $StartResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $StartCommand

            Write-Host "Tunnel Start Output: $($StartResult.Output)" -ForegroundColor Yellow

            if ($StartResult.ExitStatus -ne 0) {
                Write-Error "Failed to start WireGuard tunnel: $($StartResult.Output)"
                exit
            }
            Write-Host "WireGuard tunnel started successfully." -ForegroundColor Green
        }
        else {
            Write-Error "Unsupported OS: $OS"
        }
    } catch {
        Write-Host "Failed to start WireGuard tunnel: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}


function Deploy-WireGuardServer {
    param (
        $Server,
        $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "`n--- Deploying WireGuard Server: $($Server.ServerName) ---`n" -ForegroundColor Green

    # Detect OS
    $OS = Test-OperatingSystem -SSHSession $SSHSession

    if ($OS -eq "Unknown" -or -not $OS) {
        Write-Warning "OS detection failed or returned an unknown value for $($Entity.Name). Skipping deployment..."
        return
    }

    Write-Host "Detected Operating System: $OS" -ForegroundColor Green


    $ServerConfigContent = @"
[Interface]
PrivateKey = $($Server.ServerPrivateKey)
ListenPort = $($Server.ListenPort)
Address = $($Server.ServerAddress)

[Peer]
PublicKey = $($Client.ClientPublicKey)
AllowedIPs = $($Server.AllowedIPs)
"@

    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession -OS $OS)) {
        Install-WireGuard -SSHSession $SSHSession -OS $OS
    }
    Configure-WireGuard -SSHSession $SSHSession -OS $OS -ConfigContent $ServerConfigContent
    Start-WireGuardTunnel -SSHSession $SSHSession -OS $OS
}

function Deploy-WireGuardClient {
    param (
        $Client,
        $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "`n--- Deploying WireGuard Client: $($Client.ClientName) ---`n" -ForegroundColor Cyan

    $ClientConfigContent = @"
[Interface]
PrivateKey = $($Client.ClientPrivateKey)
Address = $($Client.ClientAddress)

[Peer]
PublicKey = $($Server.ServerPublicKey)
Endpoint = $($Client.ClientEndpoint)
AllowedIPs = $($Client.AllowedIPs)
PersistentKeepalive = 25
"@

    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession -OS $OS)) {
        Install-WireGuard -SSHSession $SSHSession -OS $OS
    }
    Configure-WireGuard -SSHSession $SSHSession -OS $OS -ConfigContent $ClientConfigContent
    Start-WireGuardTunnel -SSHSession $SSHSession -OS $OS
}

Export-ModuleMember -Function Update-AllowedIPs, Deploy-WireGuardServer, Deploy-WireGuardClient
