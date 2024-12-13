# Define Log File
$LogDirectory = ".\logs"
if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force
}
$LogFile = "$LogDirectory\WireGuardDeployment_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Start Transcript (Logging)
Start-Transcript -Path $LogFile -Append

# Log Script Execution Start
Write-Output "========================================="
Write-Output "WireGuard Deployment Log"
Write-Output "Execution Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "========================================="

# Import the module
try {
    Import-Module -Name ".\modules\Windows\WindowsDeployments.psm1" -Force
    Write-Output "Module 'WindowsDeployments' successfully imported."
} catch {
    Write-Error "Failed to import module: $_"
    exit
}

# Import Configuration
try {
    $ConfigFilePath = "config.psd1"
    $Config = Import-Configuration -ConfigFilePath $ConfigFilePath
    Write-Output "Configuration file imported successfully."
} catch {
    Write-Error "Failed to import configuration file: $_"
    exit
}

# Check for Empty Configurations
if (-not $Config.ServerConfigs) { 
    Write-Warning "No server configurations found." 
}
if (-not $Config.ClientConfigs) { 
    Write-Warning "No client configurations found." 
}

# Deploy Servers
foreach ($Server in $Config.ServerConfigs) {
    try {
        Write-Output "`n--- Starting deployment for Server: $($Server.ServerName) ---"
        Deploy-WireGuardServer -Server $Server
        Write-Output "Server $($Server.ServerName) deployed successfully."
    } catch {
        Write-Error "Error deploying server $($Server.ServerName): $_"
    }
}

# Deploy Clients
foreach ($Client in $Config.ClientConfigs) {
    try {
        Write-Output "`n--- Starting deployment for Client: $($Client.ClientName) ---"
        Deploy-WireGuardClient -Client $Client
        Write-Output "Client $($Client.ClientName) deployed successfully."
    } catch {
        Write-Error "Error deploying client $($Client.ClientName): $_"
    }
}

Write-Output "`nWireGuard server and client deployment completed successfully."
Write-Output "Execution End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Stop Transcript
Stop-Transcript
