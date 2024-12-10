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
    $CheckInstallCommand = "Get-Command wireguard.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    return -not [string]::IsNullOrEmpty($Result.Output)
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

# Import Configuration
$ConfigFilePath = "config.psd1"
$Config = Import-Configuration -ConfigFilePath $ConfigFilePath

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

    $ServerSession = Establish-SSHConnection -IP $Server.ServerIP -Username $Server.Username -Password $Server.Password
    if ($ServerSession) {
        try {
            if (-not (Check-WireGuardInstallation -SSHSession $ServerSession)) {
                Install-WireGuard -SSHSession $ServerSession
            }
            Configure-WireGuard -SSHSession $ServerSession -ConfigContent $ServerConfigContent
            Start-WireGuardTunnel -SSHSession $ServerSession
        } catch {
            Write-Host "Error configuring WireGuard Server: $($Server.ServerName) - $_" -ForegroundColor Red
        } finally {
            Remove-SSHSession -SessionId $ServerSession.SessionId
        }
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

    $ClientSession = Establish-SSHConnection -IP $Client.ClientIP -Username $Client.ClientUsername -Password $Client.ClientPassword
    if ($ClientSession) {
        try {
            if (-not (Check-WireGuardInstallation -SSHSession $ClientSession)) {
                Install-WireGuard -SSHSession $ClientSession
            }
            Configure-WireGuard -SSHSession $ClientSession -ConfigContent $ClientConfigContent
            Start-WireGuardTunnel -SSHSession $ClientSession
        } catch {
            Write-Host "Error configuring WireGuard Client: $($Client.ClientName) - $_" -ForegroundColor Red
        } finally {
            Remove-SSHSession -SessionId $ClientSession.SessionId
        }
    }
}

Write-Host "`nWireGuard server and client deployment completed successfully." -ForegroundColor Green
