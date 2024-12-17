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
    $Result = Invoke-CommandByOS -CommandKey "CheckInstallation" -OS $OS -SSHSession $SSHSession
    return -not [string]::IsNullOrEmpty($Result.Output)
}

function Install-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Installing WireGuard..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "Install" -OS $OS -SSHSession $SSHSession
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

            # Write the configuration file using a Here-String
            $WriteConfigCommand = @"
Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$ConfigContent
'@ -Force
"@
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
        }
        elseif ($OS -eq "Linux") {
            # Ensure the directory exists on Linux
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "mkdir -p /etc/wireguard"

            # Write the configuration file using a Here-Document
            $WriteConfigCommand = @"
cat <<EOF > /etc/wireguard/wg0.conf
$ConfigContent
EOF
"@
            Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
        }
        else {
            Write-Error "Unsupported operating system: $OS"
            return
        }

        Write-Host "Configuration file written successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to configure WireGuard: $_" -ForegroundColor Red
        exit
    }
}



function Start-WireGuardTunnel {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "StartTunnel" -OS $OS -SSHSession $SSHSession
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
PublicKey = $($Server.ServerPublicKey)
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
PublicKey = $($Client.ClientPublicKey)
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
