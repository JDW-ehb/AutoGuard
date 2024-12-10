# Unified WireGuard Deployment Script with Loops

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
        return $null
    }
}

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

        Write-Host "WireGuard configuration written successfully." -ForegroundColor Green
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

# Import Configuration
try {
    $ConfigFilePath = "config.psd1"
    $Config = Import-Configuration -ConfigFilePath $ConfigFilePath
} catch {
    Write-Host "Failed to import configuration file: $_" -ForegroundColor Red
    exit
}

# Check for Empty Configurations
if (-not $Config.ServerConfigs) {
    Write-Host "No server configurations found in the config file." -ForegroundColor Yellow
}
if (-not $Config.ClientConfigs) {
    Write-Host "No client configurations found in the config file." -ForegroundColor Yellow
}

# Loop Through Servers
foreach ($Server in $Config.ServerConfigs) {
    Write-Host "`n--- Configuring WireGuard Server: $($Server.ServerName) ---`n" -ForegroundColor Green

    $ServerConfigContent = @"
[Interface]
PrivateKey = $($Server.ServerPrivateKey)
ListenPort = $($Server.ListenPort)
Address = $($Server.ServerAddress)

[Peer]
PublicKey = $($Server.ServerPublicKey)
AllowedIPs = $($Server.AllowedIPs)
"@

    try {
        $ServerSession = Establish-SSHConnection -IP $Server.ServerIP -Username $Server.Username -Password $Server.Password
        if (-not $ServerSession) {
            throw "Failed to establish SSH session to $($Server.ServerName) at $($Server.ServerIP)"
        }

        if (-not (Check-WireGuardInstallation -SSHSession $ServerSession)) {
            Install-WireGuard -SSHSession $ServerSession
        }
        Configure-WireGuard -SSHSession $ServerSession -ConfigContent $ServerConfigContent
        Start-WireGuardTunnel -SSHSession $ServerSession
    } catch {
        Write-Host "Error configuring WireGuard Server: $($Server.ServerName) - $_" -ForegroundColor Red
    } finally {
        if ($ServerSession) { Remove-SSHSession -SessionId $ServerSession.SessionId }
    }
}

# Loop Through Clients
foreach ($Client in $Config.ClientConfigs) {
    Write-Host "`n--- Configuring WireGuard Client: $($Client.ClientName) ---`n" -ForegroundColor Green

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

    try {
        $ClientSession = Establish-SSHConnection -IP $Client.ClientIP -Username $Client.ClientUsername -Password $Client.ClientPassword
        if (-not $ClientSession) {
            throw "Failed to establish SSH session to $($Client.ClientName) at $($Client.ClientIP)"
        }

        if (-not (Check-WireGuardInstallation -SSHSession $ClientSession)) {
            Install-WireGuard -SSHSession $ClientSession
        }
        Configure-WireGuard -SSHSession $ClientSession -ConfigContent $ClientConfigContent
        Start-WireGuardTunnel -SSHSession $ClientSession
    } catch {
        Write-Host "Error configuring WireGuard Client: $($Client.ClientName) - $_" -ForegroundColor Red
    } finally {
        if ($ClientSession) { Remove-SSHSession -SessionId $ClientSession.SessionId }
    }
}

Write-Host "`nWireGuard server and client deployment completed successfully." -ForegroundColor Green
