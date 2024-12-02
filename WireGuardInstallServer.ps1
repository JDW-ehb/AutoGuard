# Load environment variables from .env file
$EnvFilePath = "serv.env"  # Path to your .env file
if (Test-Path $EnvFilePath) {
    $EnvVars = Get-Content $EnvFilePath | ForEach-Object {
        $KeyValue = $_ -split "="
        [PSCustomObject]@{Key = $KeyValue[0].Trim(); Value = $KeyValue[1].Trim()}
    }
    foreach ($EnvVar in $EnvVars) {
        Set-Variable -Name $EnvVar.Key -Value $EnvVar.Value -Scope Script
    }
} else {
    Write-Host ".env file not found. Please create it with the required variables." -ForegroundColor Red
    exit
}

# Access environment variables
$ServerIP = $SERVER_IP
$Username = $USERNAME
$Password = $PASSWORD

# Validate that required variables are loaded
if (-not $ServerIP -or -not $Username -or -not $Password) {
    Write-Host "One or more environment variables are missing. Check your .env file." -ForegroundColor Red
    exit
}

# Securely convert password to a secure string
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# Ensure Posh-SSH module is installed
if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
    Install-Module -Name Posh-SSH -Force -Scope CurrentUser
}

# Establish SSH session
Write-Host "Establishing SSH connection to $ServerIP..." -ForegroundColor Cyan
$SSHSession = New-SSHSession -ComputerName $ServerIP -Credential (New-Object PSCredential ($Username, $SecurePassword))

if ($SSHSession) {
    Write-Host "Connected to $ServerIP." -ForegroundColor Green

    # Check if WireGuard is already installed
    Write-Host "Checking if WireGuard is already installed..." -ForegroundColor Cyan
    $CheckInstallCommand = "if (Test-Path 'C:\Program Files\WireGuard\wireguard.exe') { 'WireGuard Installed' } else { 'WireGuard Not Installed' }"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CheckInstallCommand
    Write-Host "Check Install Output: $($Result.Output)" -ForegroundColor Yellow

    if ($Result.Output -contains 'WireGuard Installed') {
        Write-Host "WireGuard is already installed. Skipping installation." -ForegroundColor Green
    } else {
        # Download WireGuard installer
        Write-Host "Downloading WireGuard installer..." -ForegroundColor Cyan
        $DownloadCommand = "Invoke-WebRequest -Uri 'https://download.wireguard.com/windows-client/wireguard-installer.exe' -OutFile 'C:\WireGuard-Installer.exe'"
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $DownloadCommand
        Write-Host "Download Output: $($Result.Output)" -ForegroundColor Yellow
        if ($Result.ExitStatus -ne 0) {
            Write-Host "Download failed with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
            exit
        }

        # Install WireGuard silently
        Write-Host "Installing WireGuard..." -ForegroundColor Cyan
        $InstallCommand = "Start-Process -FilePath 'C:\WireGuard-Installer.exe' -ArgumentList '/S' -Wait"
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallCommand
        Write-Host "Install Output: $($Result.Output)" -ForegroundColor Yellow
        if ($Result.ExitStatus -ne 0) {
            Write-Host "Installation failed with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
            exit
        }
    }

   # Verify WireGuard installation
   Write-Host "Verifying WireGuard installation..." -ForegroundColor Cyan
   $VerifyInstallCommand = "if (Test-Path 'C:\Program Files\WireGuard\wireguard.exe') { 'WireGuard Installed' } else { 'WireGuard Not Installed' }"
   $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyInstallCommand
   Write-Host "Verification Output: $($Result.Output)" -ForegroundColor Yellow
   if ($Result.Output -eq 'WireGuard Not Installed') {
       Write-Host "WireGuard installation verification failed. File not found." -ForegroundColor Red
       $Result.Output
       exit
   }else{
       Write-Host "WireGuard installation verified." -ForegroundColor Green
       $Result.Output 
   }

    # Configure WireGuard
    Write-Host "Configuring WireGuard..." -ForegroundColor Cyan

    # Step 1: Define WireGuard configuration
Write-Host "Defining WireGuard configuration..." -ForegroundColor Cyan
$WireGuardConfig = @"
[Interface]
PrivateKey = cPsD6wexojPwpXgvPcxjYVsscsGt5ypx+kffJR/GB04=
Address = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey = 6cP9blLr039bmqawtd/K4oI5+Fs2ABA3hcwIDdcYWxo=
AllowedIPs = 10.99.0.2/32, 192.168.2.128/32
"@
Write-Host "WireGuard Configuration:" -ForegroundColor Yellow
Write-Host $WireGuardConfig

# Enable IP forwarding on the server
Write-Host "Enabling IP forwarding on the server..." -ForegroundColor Cyan
$EnableIPForwardingCommand = "reg add HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters /v IPEnableRouter /t REG_DWORD /d 1 /f"
$Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $EnableIPForwardingCommand
Write-Host "IP Forwarding Enabled Output: $($Result.Output)" -ForegroundColor Yellow

# Add static route to the client network
Write-Host "Adding a static route to the client network on the server..." -ForegroundColor Cyan
$AddRouteCommand = "route add 192.168.2.0 mask 255.255.255.0 10.99.0.2"
$Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $AddRouteCommand
Write-Host "Route Added Output: $($Result.Output)" -ForegroundColor Yellow


    # Step 2: Create the WireGuard configuration directory
    Write-Host "Creating WireGuard configuration directory..." -ForegroundColor Cyan
    $CreateDirCommand = "New-Item -Path 'C:\ProgramData\WireGuard' -ItemType Directory -Force"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $CreateDirCommand
    Write-Host "Create Directory Output: $($Result.Output)" -ForegroundColor Yellow
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to create WireGuard configuration directory with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }

# Step 3: Write the WireGuard configuration file
Write-Host "Writing WireGuard configuration file..." -ForegroundColor Cyan
$WriteConfigCommand = @"
@'
[Interface]
PrivateKey = cPsD6wexojPwpXgvPcxjYVsscsGt5ypx+kffJR/GB04=
Address = 10.99.0.1/24
ListenPort = 51820

[Peer]
PublicKey = 6cP9blLr039bmqawtd/K4oI5+Fs2ABA3hcwIDdcYWxo=
AllowedIPs = 10.99.0.2/32
'@ | Set-Content -Path 'C:\ProgramData\WireGuard\wg0.conf' -Force
"@
$Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WriteConfigCommand
Write-Host "Write Config Output: $($Result.Output)" -ForegroundColor Yellow
if ($Result.ExitStatus -ne 0) {
    Write-Host "Failed to write WireGuard configuration with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
    exit
}



    # Step 4: Verify the configuration file
    Write-Host "Verifying the WireGuard configuration file..." -ForegroundColor Cyan
    $VerifyConfigCommand = "Get-Content -Path 'C:\ProgramData\WireGuard\wg0.conf'"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyConfigCommand
    Write-Host "Configuration File Contents:" -ForegroundColor Yellow
    Write-Host $Result.Output

    # Step 5: Confirm configuration completion
    Write-Host "WireGuard configuration completed successfully." -ForegroundColor Green

    # Start WireGuard Service
    Write-Host "Starting WireGuard Service..." -ForegroundColor Cyan
    $StartServiceCommand = "Start-Service -Name WireGuardManager"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $StartServiceCommand
    Write-Host "Start Service Output: $($Result.Output)" -ForegroundColor Yellow
    if ($Result.ExitStatus -ne 0) {
        Write-Host "Failed to start WireGuard service with ExitStatus: $($Result.ExitStatus)" -ForegroundColor Red
        exit
    }



    # Verify WireGuard Service
    Write-Host "Verifying WireGuard Service..." -ForegroundColor Cyan
    $VerifyServiceCommand = "Get-Service -Name WireGuardManager | Select-Object -Property Status"
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $VerifyServiceCommand
    Write-Host "Service Status Output: $($Result.Output)" -ForegroundColor Yellow

    # Step 6: Install WireGuard tunnel as a Windows service
    Write-Host "Installing WireGuard tunnel as a Windows service..." -ForegroundColor Cyan
    $InstallTunnelCommand = '& "C:\Program Files\WireGuard\wireguard.exe" /installtunnelservice "C:\ProgramData\WireGuard\wg0.conf"'
    $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $InstallTunnelCommand
    Write-Host "Install Tunnel Output: $($Result.Output)" -ForegroundColor Yellow
  
    if ($Result.ExitStatus -ne 0 -or $Result.Output -eq $null) {
        Write-Host "Failed to install WireGuard tunnel service. Check the configuration file and permissions." -ForegroundColor Red
        exit
    }


    # Close the SSH session
    Remove-SSHSession -SessionId $SSHSession.SessionId
    Write-Host "Deployment completed and session closed." -ForegroundColor Green
} else {
    Write-Host "Failed to connect to $ServerIP." -ForegroundColor Red
}
