function Import-Configuration {
    param (
        [string]$ConfigFilePath
    )
    try {
        if (Test-Path $ConfigFilePath) {
            return Import-PowerShellDataFile -Path $ConfigFilePath
        } else {
            throw "Configuration file not found at $ConfigFilePath. Please create it with the required settings."
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit
    }
}

function Establish-SSHConnection {
    param (
        [string]$ClientIP,
        [string]$ClientUsername,
        [string]$ClientPassword
    )
    try {
        $SecurePassword = ConvertTo-SecureString $ClientPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($ClientUsername, $SecurePassword)

        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        }

        Write-Host "Establishing SSH connection to $ClientIP..." -ForegroundColor Cyan
        $Session = New-SSHSession -ComputerName $ClientIP -Credential $Credential
        if (!$Session) { throw "SSH connection failed." }
        return $Session
    } catch {
        Write-Host "Failed to establish SSH session: $_" -ForegroundColor Red
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
        [string]$ClientAddress,
        [string]$ServerEndpoint,
        [string]$AllowedIPs,
        [string]$ClientPrivateKey,
        [string]$ClientPublicKey
    )
    try {
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

        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$WireGuardConfig
'@ -Force"
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
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand

        if ($Result.ExitStatus -ne 0 -or $null -eq $Result.Output) {
            throw "Failed to install WireGuard tunnel service."
        }

        Write-Host "Verifying if WireGuard tunnel is active..." -ForegroundColor Cyan
        $VerifyTunnelCommand = 'Get-Service -Name WireGuardTunnel$wg0 | Select-Object -ExpandProperty Status'
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyTunnelCommand

        if ($Result.Output -notmatch "Running") {
            throw "WireGuard tunnel is not active."
        }
        Write-Host "WireGuard tunnel is active." -ForegroundColor Green
    } catch {
        Write-Host "Failed to start WireGuard tunnel: $_" -ForegroundColor Red
        exit
    }
}

# Main Script
try {
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
    }
} catch {
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
