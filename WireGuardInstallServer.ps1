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
        [string]$ServerIP,
        [string]$Username,
        [string]$Password
    )
    try {
        Write-Host "Establishing SSH connection to $ServerIP..." -ForegroundColor Cyan
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object PSCredential ($Username, $SecurePassword)

        # Install Posh-SSH if not available
        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        }

        return New-SSHSession -ComputerName $ServerIP -Credential $Credential
    } catch {
        Write-Host "Failed to establish SSH connection: $_" -ForegroundColor Red
        exit
    }
}

function Check-WireGuardInstallation {
    param ($SSHSession)
    $CheckInstallCommand = "Get-Command wireguard.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    return -not [string]::IsNullOrEmpty($Result.Output)
}

function Install-WireGuard {
    param ($SSHSession)
    try {
        Write-Host "Downloading and installing WireGuard..." -ForegroundColor Cyan
        $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand

        $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
    } catch {
        Write-Host "WireGuard installation failed: $_" -ForegroundColor Red
        exit
    }
}

function Configure-WireGuard {
    param (
        $SSHSession,
        [string]$ConfigContent
    )
    try {
        Write-Host "Creating WireGuard configuration directory..." -ForegroundColor Cyan
        $CreateDirCommand = "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CreateDirCommand

        Write-Host "Writing WireGuard configuration file..." -ForegroundColor Cyan
        $WriteConfigCommand = @"
Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$ConfigContent
'@ -Force
"@
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
    } catch {
        Write-Host "Failed to configure WireGuard: $_" -ForegroundColor Red
        exit
    }
}

function Start-WireGuardTunnel {
    param ($SSHSession)
    try {
        Write-Host "Installing WireGuard tunnel as a Windows service..." -ForegroundColor Cyan
        $InstallTunnelCommand = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand

        Write-Host "Verifying if WireGuard tunnel is active..." -ForegroundColor Cyan
        $VerifyTunnelCommand = 'Get-Service -Name WireGuardTunnel$wg0 | Select-Object -ExpandProperty Status'
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyTunnelCommand
        Write-Host "Tunnel Status: $($Result.Output)" -ForegroundColor Green
    } catch {
        Write-Host "Failed to start WireGuard tunnel: $_" -ForegroundColor Red
        exit
    }
}

# Main Script
$ConfigFilePath = "config.psd1"
$Config = Import-Configuration -ConfigFilePath $ConfigFilePath

$ServerIP = $Config.ServerConfig.ServerIP
$Username = $Config.ServerConfig.Username
$Password = $Config.ServerConfig.Password
$ServerAddress = $Config.ServerConfig.ServerAddress
$AllowedIPs = $Config.ServerConfig.AllowedIPs
$ServerPrivateKey = $Config.ServerConfig.ServerPrivateKey
$ServerPublicKey = $Config.ServerConfig.ServerPublicKey
$ServerEndpoint = $Config.ServerConfig.ServerEndpoint
$ListenPort = $Config.serverConfig.ListenPort

$WireGuardConfig = @"
[Interface]
PrivateKey = $ServerPrivateKey
ListenPort = $ListenPort
Address = $ServerAddress

[Peer]
PublicKey = $ServerPublicKey
AllowedIPs = $AllowedIPs
"@

$SSHSession = Establish-SSHConnection -ServerIP $ServerIP -Username $Username -Password $Password
if ($SSHSession) {
    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession)) {
        Install-WireGuard -SSHSession $SSHSession
    }
    Configure-WireGuard -SSHSession $SSHSession -ConfigContent $WireGuardConfig
    Start-WireGuardTunnel -SSHSession $SSHSession

    Remove-SSHSession -SessionId $SSHSession.SessionId
    Write-Host "Deployment completed and session closed." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to $ServerIP." -ForegroundColor Red
}
