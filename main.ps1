# Import the module
Import-Module -Name ".\WindowsDeployments.psm1" -Force

Get-Command -Module WindowsDeployments

# Import Configuration
try {
    $ConfigFilePath = "config.psd1"
    $Config = Import-Configuration -ConfigFilePath $ConfigFilePath
} catch {
    Write-Host "Failed to import configuration file: $_" -ForegroundColor Red
    exit
}

# Check for Empty Configurations
if (-not $Config.ServerConfigs) { Write-Host "No server configurations found." -ForegroundColor Yellow }
if (-not $Config.ClientConfigs) { Write-Host "No client configurations found." -ForegroundColor Yellow }

# Deploy Servers
foreach ($Server in $Config.ServerConfigs) {
    Deploy-WireGuardServer -Server $Server
}

# Deploy Clients
foreach ($Client in $Config.ClientConfigs) {
    Deploy-WireGuardClient -Client $Client
}

Write-Host "`nWireGuard server and client deployment completed successfully." -ForegroundColor Green
