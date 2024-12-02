# WireGuard Deployment and Configuration Script

This PowerShell script automates the deployment and configuration of WireGuard on a client machine. It connects via SSH, installs WireGuard if not present, sets up a configuration file, and starts the WireGuard tunnel service.

## Features

- **SSH Connection**: Establishes a secure SSH connection to the client machine.
- **WireGuard Installation**: Installs WireGuard if not already present.
- **Configuration Management**: Automates the creation of the WireGuard configuration file.
- **Service Management**: Starts and verifies the WireGuard tunnel service.
- **Error Handling**: Includes detailed logging and error messages for easy troubleshooting.

## Prerequisites

Before running the script, ensure the following:

1. **PowerShell**: This script requires PowerShell 5.1 or later.
2. **Modules**: The [Posh-SSH](https://www.powershellgallery.com/packages/Posh-SSH/) module must be installed. The script installs it automatically if not present.
3. **Configuration File**: Create a `.psd1` configuration file with the following structure:

    ```powershell
    @{
        ClientConfig = @{
            ClientIP       = "192.168.1.100"
            ClientUsername = "clientuser"
            ClientPassword = "clientpassword"
            ClientPrivateKey = "clientprivatekey"
            ClientAddress  = "10.0.0.2/32"
            AllowedIPs     = "0.0.0.0/0, ::/0"
        }
        ServerConfig = @{
            ServerEndpoint = "192.168.1.200:51820"
            ServerPublicKey = "serverpublickey"
        }
    }
    ```

4. **Client Machine**: Ensure SSH is enabled on the client machine, and credentials are correct.
5. **WireGuard Installer**: Ensure the client has access to download the WireGuard installer.

## Usage

1. Clone or download the script to your machine.
2. Prepare your `.psd1` configuration file as described above.
3. Run the script using PowerShell:

    ```powershell
    .\WireGuardDeployment.ps1
    ```

    Alternatively, you can provide a custom path to the `.psd1` configuration file:

    ```powershell
    .\WireGuardDeployment.ps1 -ConfigFilePath "path\to\config.psd1"
    ```

## Script Functions

The script is modularized into the following functions:

1. **`Import-Configuration`**:
   - Imports the `.psd1` configuration file.
   - Validates the presence of all required variables.

2. **`Establish-SSHConnection`**:
   - Connects to the client machine via SSH.

3. **`Check-WireGuardInstallation`**:
   - Verifies if WireGuard is installed on the client.

4. **`Install-WireGuard`**:
   - Downloads and installs WireGuard if not found.

5. **`Configure-WireGuard`**:
   - Creates the WireGuard configuration directory and writes the configuration file.

6. **`Start-WireGuardTunnel`**:
   - Installs, starts, and verifies the WireGuard tunnel service.

## Example Workflow

1. Ensure the `.psd1` file is present and contains valid data.
2. Run the script.
3. The script will:
   - Connect to the client.
   - Install WireGuard if necessary.
   - Write the configuration file.
   - Start the WireGuard tunnel service.
   - Verify the tunnel is active.

4. Monitor the script output for any errors or confirmation messages.

## Troubleshooting

- **SSH Connection Fails**: Ensure the IP address, username, and password in the configuration file are correct.
- **WireGuard Not Installed**: Check the client's internet connection and ensure the installer URL is accessible.
- **Tunnel Service Not Running**: Ensure the configuration file is correctly formatted and the WireGuard service has appropriate permissions.
