# Unified WireGuard Deployment Script

function Import-Configuration {
    param ([string]$ConfigFilePath)
    try {
        if (Test-Path $ConfigFilePath) {
            return Import-PowerShellDataFile -Path $ConfigFilePath
        } else {
            throw "Configuration file not found at $ConfigFilePath."
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit
    }
}

function Establish-SSHConnection {
    param (
        [string]$IP,
        [string]$Username,
        [string]$Password
    )
    try {
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object PSCredential ($Username, $SecurePassword)

        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        }

        Write-Host "Establishing SSH connection to $IP..." -ForegroundColor Cyan
        return New-SSHSession -ComputerName $IP -Credential $Credential
    } catch {
        Write-Host "Failed to connect to ${IP}: $_" -ForegroundColor Red
        exit
    }
}

function Check-WireGuardInstallation {
    param ($SSHSession)
    try {
        $CheckInstallCommand = "Get-Command wireguard.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source"
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
        return -not [string]::IsNullOrEmpty($Result.Output)
    } catch {
        Write-Host "Error checking WireGuard installation: $_" -ForegroundColor Red
        return $false
    }
}

function Install-WireGuard {
    param ($SSHSession)
    Write-Host "Installing WireGuard..." -ForegroundColor Cyan
    $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand

    $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
}

function Configure-WireGuard {
    param (
        $SSHSession,
        [string]$ConfigContent
    )
    Write-Host "Writing WireGuard configuration..." -ForegroundColor Cyan
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$ConfigContent
'@ -Force"
}

function Start-WireGuardTunnel {
    param ($SSHSession)
    Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
    $InstallTunnelCommand = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand
}

# Import Configurations
$ConfigFilePath = "config.psd1"
$Config = Import-Configuration -ConfigFilePath $ConfigFilePath

# WireGuard Server Configuration
$ServerWireGuardConfig = @"
[Interface]
PrivateKey = $($Config.ServerConfig.ServerPrivateKey)
ListenPort = $($Config.ServerConfig.ListenPort)
Address = $($Config.ServerConfig.ServerAddress)

[Peer]
PublicKey = $($Config.ClientConfig.ClientPublicKey)
AllowedIPs = $($Config.ClientConfig.ClientAddress)
"@

# WireGuard Client Configuration
$ClientWireGuardConfig = @"
[Interface]
PrivateKey = $($Config.ClientConfig.ClientPrivateKey)
Address = $($Config.ClientConfig.ClientAddress)

[Peer]
PublicKey = $($Config.ServerConfig.ServerPublicKey)
Endpoint = $($Config.ServerConfig.ServerEndpoint)
AllowedIPs = $($Config.ClientConfig.AllowedIPs)
PersistentKeepalive = 25
"@

# Execute Commands for Server
Write-Host "`n--- Configuring WireGuard Server ---`n" -ForegroundColor Green
$ServerSession = Establish-SSHConnection -IP $Config.ServerConfig.ServerIP -Username $Config.ServerConfig.Username -Password $Config.ServerConfig.Password

if (-not (Check-WireGuardInstallation -SSHSession $ServerSession)) {
    Install-WireGuard -SSHSession $ServerSession
}

Configure-WireGuard -SSHSession $ServerSession -ConfigContent $ServerWireGuardConfig
Start-WireGuardTunnel -SSHSession $ServerSession
Remove-SSHSession -SessionId $ServerSession.SessionId

# Execute Commands for Client
Write-Host "`n--- Configuring WireGuard Client ---`n" -ForegroundColor Green
$ClientSession = Establish-SSHConnection -IP $Config.ClientConfig.ClientIP -Username $Config.ClientConfig.ClientUsername -Password $Config.ClientConfig.ClientPassword

if (-not (Check-WireGuardInstallation -SSHSession $ClientSession)) {
    Install-WireGuard -SSHSession $ClientSession
}

Configure-WireGuard -SSHSession $ClientSession -ConfigContent $ClientWireGuardConfig
Start-WireGuardTunnel -SSHSession $ClientSession
Remove-SSHSession -SessionId $ClientSession.SessionId

Write-Host "`nWireGuard server and client deployment completed successfully." -ForegroundColor Green
