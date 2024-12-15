# Define Log File
$LogDirectory = ".\logs"
if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force
}
$LogFile = "$LogDirectory\WireGuardDeployment_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Start Logging
Start-Transcript -Path $LogFile -Append
Write-Output "========================================="
Write-Output "WireGuard Deployment Log"
Write-Output "Execution Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "========================================="

# Import Modules
try {
    Import-Module -Name ".\modules\SSH-Session\SSH-Session.psm1" -Force
    Import-Module -Name ".\modules\Windows\WindowsDeployments.psm1" -Force
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

# Deploy Servers
foreach ($Server in $Config.ServerConfigs) {
    Write-Output "`n--- Starting deployment for Server: $($Server.ServerName) ---"
    $Session = $null
    try {
        # Establish SSH session
        Write-Output "Establishing SSH session for Server: $($Server.ServerName)..."
        $Session = Establish-SSHConnection -IP $Server.ServerIP -Username $Server.Username -Password $Server.Password

        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Server: $($Server.ServerName). Skipping..."
            continue
        }

        # OS Detection
        Write-Output "Detecting operating system for Server: $($Server.ServerName)..."
        if (Test-WindowsOperatingSystem -SSHSession $Session) {
            Write-Output "Operating System: Windows. Proceeding with deployment..."
            Deploy-WireGuardServer -Server $Server -SSHSession $Session
            Write-Output "Server $($Server.ServerName) deployed successfully."
        } else {
            Write-Warning "Server $($Server.ServerName) is not a Windows system. Skipping..."
        }
    } catch {
        Write-Error "Error deploying server $($Server.ServerName): $_"
    } finally {
        if ($Session -and $Session.SessionId) {
            Write-Output "Closing SSH session for Server: $($Server.ServerName)..."
            Remove-Session -SessionId $Session.SessionId
        }
    }
}

# Deploy Clients
foreach ($Client in $Config.ClientConfigs) {
    Write-Output "`n--- Starting deployment for Client: $($Client.ClientName) ---"
    $Session = $null
    try {
        # Establish SSH session
        Write-Output "Establishing SSH session for Client: $($Client.ClientName)..."
        $Session = Establish-SSHConnection -IP $Client.ClientIP -Username $Client.Username -Password $Client.Password

        if (-not $Session) {
            Write-Error "Failed to establish SSH session for Client: $($Client.ClientName). Skipping..."
            continue
        }

        # OS Detection
        Write-Output "Detecting operating system for Client: $($Client.ClientName)..."
        if (Test-WindowsOperatingSystem -SSHSession $Session) {
            Write-Output "Operating System: Windows. Proceeding with deployment..."
            Deploy-WireGuardClient -Client $Client -SSHSession $Session
            Write-Output "Client $($Client.ClientName) deployed successfully."
        } else {
            Write-Warning "Client $($Client.ClientName) is not a Windows system. Skipping..."
        }
    } catch {
        Write-Error "Error deploying client $($Client.ClientName): $_"
    } finally {
        if ($Session -and $Session.SessionId) {
            Write-Output "Closing SSH session for Client: $($Client.ClientName)..."
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
