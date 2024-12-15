# WindowsDeployments.psm1
# PowerShell Module for Unified WireGuard Deployment on Windows Servers and Clients

function Check-WireGuardInstallation {
    param ($SSHSession)
    try {
        Write-Host "Checking if WireGuard is installed..." -ForegroundColor Cyan
        $CheckInstallCommand = "Get-Command wireguard.exe | Select-Object -ExpandProperty Source"
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
        return -not [string]::IsNullOrEmpty($Result.Output)
    } catch {
        Write-Host "Failed to check WireGuard installation: $_" -ForegroundColor Red
        return $false
    }
}

function Install-WireGuard {
    param ($SSHSession)
    try {
        Write-Host "Installing WireGuard..." -ForegroundColor Cyan
        $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand

        $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand

        Write-Host "WireGuard installation completed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install WireGuard: $_" -ForegroundColor Red
        exit
    }
}

function Configure-WireGuard {
    param (
        $SSHSession,
        [string]$ConfigContent
    )
    try {
        Write-Host "Writing WireGuard configuration..." -ForegroundColor Cyan
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$ConfigContent
'@ -Force"
        Write-Host "Configuration file written successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to configure WireGuard: $_" -ForegroundColor Red
        exit
    }
}

function Start-WireGuardTunnel {
    param ($SSHSession)
    try {
        Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
        $InstallTunnelCommand = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand

        Write-Host "WireGuard tunnel started successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to start WireGuard tunnel: $_" -ForegroundColor Red
        exit
    }
}

function Deploy-WireGuardServer {
    param (
        $Server,
        $SSHSession
    )
    Write-Host "`n--- Deploying WireGuard Server: $($Server.ServerName) ---`n" -ForegroundColor Green

    $ServerConfigContent = @"
[Interface]
PrivateKey = $($Server.ServerPrivateKey)
ListenPort = $($Server.ListenPort)
Address = $($Server.ServerAddress)

[Peer]
PublicKey = $($Server.ServerPublicKey)
AllowedIPs = $($Server.AllowedIPs)
"@

    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession)) {
        Install-WireGuard -SSHSession $SSHSession
    }
    Configure-WireGuard -SSHSession $SSHSession -ConfigContent $ServerConfigContent
    Start-WireGuardTunnel -SSHSession $SSHSession
}

function Deploy-WireGuardClient {
    param (
        $Client,
        $SSHSession
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

    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession)) {
        Install-WireGuard -SSHSession $SSHSession
    }
    Configure-WireGuard -SSHSession $SSHSession -ConfigContent $ClientConfigContent
    Start-WireGuardTunnel -SSHSession $SSHSession
}

Export-ModuleMember -Function Deploy-WireGuardServer, Deploy-WireGuardClient
