# WindowsDeployments.psm1
# PowerShell Module for Unified WireGuard Deployment on Windows Servers and Clients

# Hashtable for OS-Specific Commands
$WireGuardCommands = @{
    "CheckInstallation" = @{
        "Windows" = "Get-Command wireguard.exe | Select-Object -ExpandProperty Source"
        "Linux"   = "which wg && which wg-quick"
    }
    "Install" = @{
        "Windows" = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'; Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait -Verb RunAs"
        "Linux"   = "sudo apt-get update && sudo apt-get install -y wireguard"
    }
    "WriteConfig" = @{
        "Windows" = "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value ""@CONTENT@"" -Force"
        "Linux"   = "sudo bash -c 'echo ""@CONTENT@"" > /etc/wireguard/wg0.conf && dos2unix /etc/wireguard/wg0.conf && chmod 600 /etc/wireguard/wg0.conf'"
    }

    "VerifyConfig" = @{
        "Windows" = "Test-Path 'C:\ProgramData\WireGuard\wg0.conf'"
        "Linux"   = "sudo test -f /etc/wireguard/wg0.conf && echo 'Config exists' || echo 'Config missing'"
    }
    "StartTunnel" = @{
        "Windows" = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        "Linux"   = "sudo wg-quick up wg0"
    }
    "StopTunnel" = @{
        "Windows" = '& "C:\Program Files\WireGuard\wireguard.exe" /uninstalltunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        "Linux"   = "sudo wg-quick down wg0"
    }
    "RestartTunnel" = @{
        "Windows" = '& "C:\Program Files\WireGuard\wireguard.exe" /uninstalltunnelservice "C:\ProgramData\WireGuard\wg0.conf"; Start-Sleep -Seconds 2; & "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
        "Linux"   = "sudo wg-quick down wg0 && sudo wg-quick up wg0"
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
        # Fetch the command template
        $CommandTemplate = $WireGuardCommands[$CommandKey][$OS]

        # Replace @CONTENT@ placeholder if applicable
        if ($ConfigContent) {
            $Command = $CommandTemplate -replace "@CONTENT@", $ConfigContent
        } else {
            $Command = $CommandTemplate
        }

        Write-Host "Executing Command: $Command" -ForegroundColor Yellow
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $Command

        # Log both outputs
        Write-Host "Command Output: $($Result.Output)" -ForegroundColor Cyan
        Write-Host "Exit Status: $($Result.ExitStatus)" -ForegroundColor Cyan

        # Check for failure explicitly
        if ($Result.ExitStatus -ne 0) {
            Write-Error "Command '$CommandKey' failed with ExitStatus $($Result.ExitStatus): $($Result.Output)"
            return $null
        }

        return $Result
    } catch {
        Write-Warning "Command execution failed: $($_.Exception.Message)"
        return $null
    }
}




function Update-AllowedIPs {
    param (
        [Parameter(Mandatory)] $Config
    )

    Write-Host "`n--- Updating AllowedIPs for Servers and Clients ---` " -ForegroundColor Cyan

    $AllClientAddresses = $Config.ClientConfigs | ForEach-Object { $_.ClientAddress }
    $AllServerAddresses = $Config.ServerConfigs | ForEach-Object { $_.ServerAddress }

    foreach ($Server in $Config.ServerConfigs) {
        $Server.AllowedIPs = $AllClientAddresses -join ", "
    }
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
        Invoke-CommandByOS -CommandKey "CheckInstallation" -OS $OS -SSHSession $SSHSession
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

    Write-Host "Installing WireGuard on $OS..." -ForegroundColor Cyan
    try {
        # Invoke installation command based on OS
        $Result = Invoke-CommandByOS -CommandKey "Install" -OS $OS -SSHSession $SSHSession

        # Log the full output for debugging
        Write-Host "Install Command Output: $($Result.Output)" -ForegroundColor Cyan

        # Check if the installation command executed successfully
        if (-not $Result -or $Result.ExitStatus -ne 0) {
            Write-Error "WireGuard installation failed on $OS. Output: $($Result.Output)"
            exit
        }

        Write-Host "WireGuard installation completed successfully on $OS." -ForegroundColor Green
    } catch {
        Write-Host "Failed to install WireGuard on ${OS}: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}

function Configure-WireGuard {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS,
        [Parameter(Mandatory)] [string]$ConfigContent
    )
    Write-Host "Writing WireGuard configuration..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "WriteConfig" -OS $OS -SSHSession $SSHSession -ConfigContent $ConfigContent
    Write-Host "Configuration file written successfully." -ForegroundColor Green
}

function Start-WireGuardTunnel {
    param (
        [Parameter(Mandatory)] $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "Starting WireGuard tunnel..." -ForegroundColor Cyan
    Invoke-CommandByOS -CommandKey "StartTunnel" -OS $OS -SSHSession $SSHSession
    Write-Host "WireGuard tunnel started successfully." -ForegroundColor Green
}

function Deploy-WireGuardServer {
    param (
        $Server,
        $SSHSession,
        [Parameter(Mandatory)] [string]$OS
    )
    Write-Host "`n--- Deploying WireGuard Server: $($Server.ServerName) ---`n" -ForegroundColor Green

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
