# main.ps1

# Define Log File
$LogDirectory = ".\logs"
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
    Import-Module -Name ".\modules\SSH-Session\SSH-Session.psm1" -Force
    Import-Module -Name ".\modules\WireGuardDeploymentModule\WireGuardDeploymentModule.psm1" -Force
    Import-Module -Name ".\modules\OSDetection\OSDetection.psm1" -Force
    Write-Output "Modules successfully imported."
} catch {
    Write-Error "Failed to import modules: $_"
    exit
}

# Import Configuration
try {
    $ConfigFilePath = "config.psd1"
    $Config = Import-PowerShellDataFile -Path $ConfigFilePath
    Write-Output "Configuration file imported successfully."
} catch {
    Write-Error "Failed to import configuration file: $_"
    exit
}

# Update AllowedIPs once before deployment
Update-AllowedIPs -Config $Config

# Function to Deploy WireGuard based on OS
function Deploy-WireGuard {
    param (
        [Parameter(Mandatory)] $Entity,    # Server or Client config
        [Parameter(Mandatory)] $SSHSession,
        [string]$EntityType = "Server"     # Server or Client
    )
    Write-Output "`n--- Starting deployment for ${EntityType}: $($Entity.Name) ---"

    # Detect OS
    $OS = Test-OperatingSystem -SSHSession $SSHSession
    if (-not $OS) {
        Write-Warning "Could not detect OS. Skipping ${EntityType}: $($Entity.Name)"
        return
    }

    # Call appropriate deployment function
    if ($EntityType -eq "Server") {
        Deploy-WireGuardServer -Server $Entity -SSHSession $SSHSession -OS $OS
    } elseif ($EntityType -eq "Client") {
        Deploy-WireGuardClient -Client $Entity -SSHSession $SSHSession -OS $OS
    }

    Write-Output "$EntityType $($Entity.Name) deployed successfully."
}

# Deploy Servers
foreach ($Server in $Config.ServerConfigs) {
    try {
        $Session = Establish-SSHConnection -IP $Server.ServerIP -Username $Server.Username -Password $Server.Password
        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Server: $($Server.ServerName). Skipping..."
            continue
        }

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
        $Session = Establish-SSHConnection -IP $Client.ClientIP -Username $Client.Username -Password $Client.Password
        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Client: $($Client.ClientName). Skipping..."
            continue
        }

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
