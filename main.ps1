# main.ps1

# Import Configuration
# Import Configuration
try {
    $ConfigFilePath = "config.psd1"
    $Config = Import-PowerShellDataFile -Path $ConfigFilePath
    Write-Output "Configuration file imported successfully."

    # Resolve LogDirectory placeholder
    $Config.LogDirectory = $Config.LogDirectory -replace "USERPROFILE_PLACEHOLDER", $env:USERPROFILE
} catch {
    Write-Error "Failed to import configuration file: $_"
    exit
}

# Define Log Directory and File
$LogDirectory = $Config.LogDirectory
if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force
}
$LogFile = "$LogDirectory\WireGuardDeployment_$(Get-Date -Format 'dd-MM-yyyy_HH-mm-ss').log"

# Start Logging
Start-Transcript -Path $LogFile -Append
Write-Output "========================================="
Write-Output "WireGuard Deployment Log"
Write-Output "Execution Start Time: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')"
Write-Output "========================================="


# Import Modules
try {
    Import-Module -Name ".\modules\WireGuardDeploymentModule.psm1" -Force
    Write-Output "Modules successfully imported."
} catch {
    Write-Error "Failed to import modules: $_"
    exit
}

# Update AllowedIPs once before deployment
Update-AllowedIPs -Config $Config

# Deploy Servers
foreach ($Server in $Config.ServerConfigs) {
    try {
        Write-Output "`n--- Deploying Server: $($Server.ServerName) ---"
        $Session = Establish-SSHConnection -IP $Server.ServerIP -Username $Server.Username -Password $Server.Password
        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Server: $($Server.ServerName). Skipping..."
            continue
        }

        # Call the centralized deployment function from the module
        Deploy-WireGuard -Entity $Server -SSHSession $Session -EntityType "Server"
    } finally {
        if ($Session -and $Session.SessionId) {
            Remove-Session -SessionId $Session.SessionId
        }
    }
}

# Deploy Clients
foreach ($Client in $Config.ClientConfigs) {
    try {
        Write-Output "`n--- Deploying Client: $($Client.ClientName) ---"
        $Session = Establish-SSHConnection -IP $Client.ClientIP -Username $Client.Username -Password $Client.Password
        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Client: $($Client.ClientName). Skipping..."
            continue
        }

        # Call the centralized deployment function from the module
        Deploy-WireGuard -Entity $Client -SSHSession $Session -EntityType "Client"
    } finally {
        if ($Session -and $Session.SessionId) {
            Remove-Session -SessionId $Session.SessionId
        }
    }
}

# Log Completion
Write-Output "`n========================================="
Write-Output "WireGuard Deployment Completed Successfully"
Write-Output "Execution End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "========================================="
Stop-Transcript
