function Import-Configuration {
    param (
        [string]$ConfigFilePath
    )
    if (Test-Path $ConfigFilePath) {
        return Import-PowerShellDataFile -Path $ConfigFilePath
    } else {
        Write-Host "Configuration file not found at $ConfigFilePath. Please create it with the required settings." -ForegroundColor Red
        exit
    }
}

function Establish-SSHConnection {
    param (
        [string]$ClientIP,
        [string]$ClientUsername,
        [string]$ClientPassword
    )
    $SecurePassword = ConvertTo-SecureString $ClientPassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential ($ClientUsername, $SecurePassword)

    # Ensure Posh-SSH module is installed
    if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
        Install-Module -Name Posh-SSH -Force -Scope CurrentUser
    }

    Write-Host "Establishing SSH connection to $ClientIP..." -ForegroundColor Cyan
    return New-SSHSession -ComputerName $ClientIP -Credential $Credential
}

function Check-WireGuardInstallation {
    param (
        $SSHSession
    )
    $CheckInstallCommand = "if (Test-Path 'C:\Program Files\WireGuard\wireguard.exe') { 'Installed' } else { 'Not Installed' }"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    Write-Host "WireGuard Check Output: $($Result.Output)" -ForegroundColor Yellow
    return $Result.Output -contains "Installed"
}

function Install-WireGuard {
    param (
        $SSHSession
    )
    Write-Host "Downloading and installing WireGuard..." -ForegroundColor Cyan
    $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand

    $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
    Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
}

function Configure-WireGuard {
    param (
        $SSHSession,
        [string]$ClientAddress,
        [string]$ServerEndpoint,
        [string]$AllowedIPs,
        [string]$ClientPrivateKey,
        [string]$ClientPublicKey
    )
    Write-Host "Defining and writing WireGuard configuration..." -ForegroundColor Cyan

    $WireGuardConfig = @"
[Interface]
PrivateKey = $ClientPrivateKey
Address = $ClientAddress

[Peer]
PublicKey = $ClientPublicKey
Endpoint = $ServerEndpoint
AllowedIPs = $AllowedIPs
PersistentKeepalive = 25
"@

    Write-Host "WireGuard Configuration:" -ForegroundColor Yellow
    Write-Host $WireGuardConfig

    # Create the configuration directory
    $CreateDirCommand = "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CreateDirCommand
    Write-Host "Create Directory Output: $($Result.Output)" -ForegroundColor Yellow

    # Write the configuration file
    $WriteConfigCommand = "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$WireGuardConfig
'@ -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
    Write-Host "Write Config Output: $($Result.Output)" -ForegroundColor Yellow
}

function Start-WireGuardTunnel {
    param (
        $SSHSession
    )

    Write-Host "Installing WireGuard tunnel as a Windows service..." -ForegroundColor Cyan
    $InstallTunnelCommand = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand
    Write-Host "Install Tunnel Output: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.ExitStatus -ne 0 -or $null -eq $Result.Output) {
        Write-Host "Failed to install WireGuard tunnel service. Check the configuration file and permissions." -ForegroundColor Red
        exit
    }

    # Verify if the tunnel is active
    Write-Host "Verifying if WireGuard tunnel is active..." -ForegroundColor Cyan
    $VerifyTunnelCommand = 'Get-Service -Name WireGuardTunnel$wg0 | Select-Object -ExpandProperty Status'
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyTunnelCommand
    Write-Host "Tunnel Status: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.Output -notmatch "Running") {
        Write-Host "WireGuard tunnel is not active. Please check the configuration." -ForegroundColor Red
        exit
    }

    Write-Host "WireGuard tunnel is active." -ForegroundColor Green
}


# Main Script
$ConfigFilePath = "config.psd1"
$Config = Import-Configuration -ConfigFilePath $ConfigFilePath

$ClientIP = $Config.ClientConfig.ClientIP
$ClientUsername = $Config.ClientConfig.ClientUsername
$ClientPassword = $Config.ClientConfig.ClientPassword
$ServerEndpoint = $Config.ServerConfig.ServerEndpoint
$ClientPrivateKey = $Config.ClientConfig.ClientPrivateKey
$ClientPublicKey = $Config.ClientConfig.ClientPublicKey
$ClientAddress = $Config.ClientConfig.ClientAddress
$AllowedIPs = $Config.ClientConfig.AllowedIPs

$SSHSession = Establish-SSHConnection -ClientIP $ClientIP -ClientUsername $ClientUsername -ClientPassword $ClientPassword

if ($SSHSession) {
    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession)) {
        Install-WireGuard -SSHSession $SSHSession
    }

    Configure-WireGuard -SSHSession $SSHSession `
                        -ClientAddress $ClientAddress `
                        -ServerEndpoint $ServerEndpoint `
                        -AllowedIPs $AllowedIPs `
                        -ClientPrivateKey $ClientPrivateKey `
                        -ClientPublicKey $ClientPublicKey

    Start-WireGuardTunnel -SSHSession $SSHSession
    Remove-SSHSession -SessionId $SSHSession.SessionId
    Write-Host "Deployment completed and session closed." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to $ClientIP." -ForegroundColor Red
}
