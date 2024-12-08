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
        [string]$ServerIP,
        [string]$Username,
        [string]$Password
    )
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $Credential = New-Object PSCredential ($Username, $SecurePassword)

    # Ensure Posh-SSH module is installed
    if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
        Install-Module -Name Posh-SSH -Force -Scope CurrentUser
    }

    Write-Host "Establishing SSH connection to $ServerIP..." -ForegroundColor Cyan
    return New-SSHSession -ComputerName $ServerIP -Credential $Credential
}

function Check-WireGuardInstallation {
    param (
        $SSHSession
    )
    $CheckInstallCommand = "if (Test-Path 'C:\Program Files\WireGuard\wireguard.exe') { 'WireGuard Installed' } else { 'WireGuard Not Installed' }"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    Write-Host "Check Install Output: $($Result.Output)" -ForegroundColor Yellow
    return $Result.Output -contains 'WireGuard Installed'
}

function Install-WireGuard {
    param (
        $SSHSession
    )
    Write-Host "Downloading WireGuard installer..." -ForegroundColor Cyan
    $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Download failed with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }

    Write-Host "Installing WireGuard..." -ForegroundColor Cyan
    $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Installation failed with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }
}

function Configure-WireGuard {
    param (
        $SSHSession
    )

    Write-Host "Creating WireGuard configuration directory..." -ForegroundColor Cyan
    $CreateDirCommand = "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CreateDirCommand
    Write-Host "Create Directory Output: $($Result.Output)" -ForegroundColor Yellow
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to create WireGuard configuration directory with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }

    Write-Host "Writing WireGuard configuration file..." -ForegroundColor Cyan
    $WriteConfigCommand = @"
@'
[Interface]
PrivateKey = EByRIuougCQfrXI8iDhd6NIdcPdrbhvGQ69nOC7cSX0=
Address = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey = no6SVRcOvfpmHn6Ne5ESX8FQ2cppKvxB5iiGY/tTAWg=
AllowedIPs = 10.99.0.2/32
'@ | Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Force
"@
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
    Write-Host "Write Config Output: $($Result.Output)" -ForegroundColor Yellow
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to write WireGuard configuration with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }
}

function Start-WireGuardService {
    param (
        $SSHSession
    )
    Write-Host "Starting WireGuard Service..." -ForegroundColor Cyan
    $StartServiceCommand = "Start-Service -Name WireGuardManager"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $StartServiceCommand
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to start WireGuard service with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }
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
$ServerIP = $Config.ServerConfig.ServerIP
$Username = $Config.ServerConfig.Username
$Password = $Config.ServerConfig.Password

$SSHSession = Establish-SSHConnection -ServerIP $ServerIP -Username $Username -Password $Password
if ($SSHSession) {
    if (-not (Check-WireGuardInstallation -SSHSession $SSHSession)) {
        Install-WireGuard -SSHSession $SSHSession
    }

    Configure-WireGuard -SSHSession $SSHSession
    Start-WireGuardService -SSHSession $SSHSession
    Start-WireGuardTunnel -SSHSession $SSHSession
    Remove-SSHSession -SessionId $SSHSession.SessionId
    Write-Host "Deployment completed and session closed." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to $ServerIP." -ForegroundColor Red
}
