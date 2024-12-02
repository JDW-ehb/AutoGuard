# Load configuration from .psd1 file
$ConfigFilePath = "config.psd1"  # Path to your .psd1 file
if (Test-Path $ConfigFilePath) {
    $Config = Import-PowerShellDataFile -Path $ConfigFilePath
    $ClientIP = $Config.ClientConfig.ClientIP
    $ClientUsername = $Config.ClientConfig.ClientUsername
    $ClientPassword = $Config.ClientConfig.ClientPassword
    $ServerEndpoint = $Config.ServerConfig.ServerEndpoint
    $ClientPrivateKey = $Config.ClientConfig.ClientPrivateKey
    $ServerPublicKey = $Config.ServerConfig.ServerPublicKey
    $ClientAddress = $Config.ClientConfig.ClientAddress
    $AllowedIPs = $Config.ClientConfig.AllowedIPs
} else {
    Write-Host "Configuration file not found at $ConfigFilePath. Please create it with the required settings." -ForegroundColor Red
    exit
}

# Validate that required variables are loaded
if (-not $ClientIP -or -not $ClientUsername -or -not $ClientPassword -or -not $ServerEndpoint -or -not $ClientPrivateKey -or -not $ServerPublicKey -or -not $ClientAddress -or -not $AllowedIPs) {
    Write-Host "One or more required variables are missing in the configuration file. Check your .psd1 file." -ForegroundColor Red
    exit
}

# Establish SSH connection to the client VM
Write-Host "Establishing SSH connection to $ClientIP..." -ForegroundColor Cyan
$SecurePassword = ConvertTo-SecureString $ClientPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($ClientUsername, $SecurePassword)

# Ensure Posh-SSH is installed
if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
    Install-Module -Name Posh-SSH -Force -Scope CurrentUser
}

$SSHSession = New-SSHSession -ComputerName $ClientIP -Credential $Credential

if ($SSHSession) {
    Write-Host "Connected to $ClientIP." -ForegroundColor Green

    # Check if WireGuard is installed
    Write-Host "Checking if WireGuard is installed on the client..." -ForegroundColor Cyan
    $CheckInstallCommand = "if (Test-Path 'C:\Program Files\WireGuard\wireguard.exe') { 'Installed' } else { 'Not Installed' }"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    Write-Host "WireGuard Check Output: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.Output -contains "Installed") {
        Write-Host "WireGuard is already installed." -ForegroundColor Green
    } else {
        # Download and install WireGuard
        Write-Host "WireGuard not found. Installing..." -ForegroundColor Cyan
        $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand

        $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
        Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
    }

    # Step 1: Define WireGuard configuration
    Write-Host "Defining WireGuard configuration..." -ForegroundColor Cyan
    $WireGuardConfig = @"
[Interface]
PrivateKey = cPsD6wexojPwpXgvPcxjYVsscsGt5ypx+kffJR/GB04=
Address = $ClientAddress

[Peer]
PublicKey = 6cP9blLr039bmqawtd/K4oI5+Fs2ABA3hcwIDdcYWxo=
Endpoint = $ServerEndpoint
AllowedIPs = $AllowedIPs
PersistentKeepalive = 25
"@

    Write-Host "WireGuard Configuration:" -ForegroundColor Yellow
    Write-Host $WireGuardConfig

    # Step 2: Create the WireGuard configuration directory
    Write-Host "Creating WireGuard configuration directory..." -ForegroundColor Cyan
    $CreateDirCommand = "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CreateDirCommand
    Write-Host "Create Directory Output: $($Result.Output)" -ForegroundColor Yellow

    # Step 3: Write the WireGuard configuration file
    Write-Host "Writing WireGuard configuration file..." -ForegroundColor Cyan
    $WriteConfigCommand = "Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Value @'
$WireGuardConfig
'@ -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
    Write-Host "Write Config Output: $($Result.Output)" -ForegroundColor Yellow

    # Step 4: Verify the configuration file
    Write-Host "Verifying the WireGuard configuration file..." -ForegroundColor Cyan
    $VerifyConfigCommand = "Test-Path 'C:\ProgramData\WireGuard\wg0.conf'"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyConfigCommand
    Write-Host "Config File Exists: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.Output -contains "False") {
        Write-Host "Failed to verify WireGuard configuration file." -ForegroundColor Red
        exit
    }

    # Step 5: Install the WireGuard tunnel as a service
    Write-Host "Installing WireGuard tunnel as a service..." -ForegroundColor Cyan
    $InstallTunnelCommand = "& 'C:\Program Files\WireGuard\wireguard.exe' /installtunnelservice 'C:\ProgramData\WireGuard\wg0.conf'"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand
    Write-Host "Install Tunnel Output: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to install WireGuard tunnel service." -ForegroundColor Red
        exit
    }

    Write-Host "WireGuard tunnel installed and configured successfully." -ForegroundColor Green

    # Close SSH session
    Remove-SSHSession -SessionId $SSHSession.SessionId
    Write-Host "Disconnected from $ClientIP." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to $ClientIP." -ForegroundColor Red
}
