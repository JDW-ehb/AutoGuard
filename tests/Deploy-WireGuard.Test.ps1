# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Deploy-WireGuard" {
    Context "When deploying a server and all steps succeed" {
        It "Should deploy the server successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "Server1"
                ServerPrivateKey = "PrivateKey"
                ListenPort = "51820"
                ServerAddress = "10.0.0.1/24"
                ServerPublicKey = "PublicKey"
                AllowedIPs = "0.0.0.0/0"
            }
            Mock -CommandName Test-OperatingSystem -MockWith { "Linux" }
            Mock -CommandName Check-WireGuardInstallation -MockWith { $true }
            Mock -CommandName Install-WireGuard -MockWith {}
            Mock -CommandName Configure-WireGuard -MockWith {}
            Mock -CommandName Start-WireGuardTunnel -MockWith { $true }

            # Act
            Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "Server"

            # Assert
            Assert-MockCalled -CommandName Test-OperatingSystem -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Check-WireGuardInstallation -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Configure-WireGuard -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Start-WireGuardTunnel -Exactly 1 -Scope It
        }
    }

    Context "When deploying a client and all steps succeed" {
        It "Should deploy the client successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "Client1"
                ClientPrivateKey = "PrivateKey"
                ClientAddress = "10.0.0.2/32"
                ClientPublicKey = "PublicKey"
                ClientEndpoint = "10.0.0.1:51820"
                AllowedIPs = "0.0.0.0/0"
            }
            Mock -CommandName Test-OperatingSystem -MockWith { "Linux" }
            Mock -CommandName Check-WireGuardInstallation -MockWith { $true }
            Mock -CommandName Install-WireGuard -MockWith {}
            Mock -CommandName Configure-WireGuard -MockWith {}
            Mock -CommandName Start-WireGuardTunnel -MockWith { $true }

            # Act
            Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "Client"

            # Assert
            Assert-MockCalled -CommandName Test-OperatingSystem -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Check-WireGuardInstallation -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Configure-WireGuard -Exactly 1 -Scope It
            Assert-MockCalled -CommandName Start-WireGuardTunnel -Exactly 1 -Scope It
        }
    }

    Context "When the OS detection fails" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "Server1"
                ServerPrivateKey = "PrivateKey"
                ListenPort = "51820"
                ServerAddress = "10.0.0.1/24"
                ServerPublicKey = "PublicKey"
                AllowedIPs = "0.0.0.0/0"
            }
            Mock -CommandName Test-OperatingSystem -MockWith { $null }

            # Act & Assert
            { Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "Server" } | Should -Throw "Failed to detect OS. Skipping Server: Server1."
        }
    }

    Context "When an invalid EntityType is provided" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "UnknownEntity"
            }

            # Act & Assert
            { Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "UnknownType" } | Should -Throw "Invalid EntityType 'UnknownType'. Supported types are 'Server' and 'Client'."
        }
    }

    Context "When WireGuard installation is needed but fails" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "Server1"
                ServerPrivateKey = "PrivateKey"
                ListenPort = "51820"
                ServerAddress = "10.0.0.1/24"
                ServerPublicKey = "PublicKey"
                AllowedIPs = "0.0.0.0/0"
            }
            Mock -CommandName Test-OperatingSystem -MockWith { "Linux" }
            Mock -CommandName Check-WireGuardInstallation -MockWith { $false }
            Mock -CommandName Install-WireGuard -MockWith { throw "Installation failed." }

            # Act & Assert
            { Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "Server" } | Should -Throw "Installation failed."
        }
    }

    Context "When an unexpected error occurs" {
        It "Should throw the error with detailed feedback" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $Entity = @{
                Name = "Server1"
                ServerPrivateKey = "PrivateKey"
                ListenPort = "51820"
                ServerAddress = "10.0.0.1/24"
                ServerPublicKey = "PublicKey"
                AllowedIPs = "0.0.0.0/0"
            }
            Mock -CommandName Test-OperatingSystem -MockWith { throw "Unexpected error during OS detection." }

            # Act & Assert
            { Deploy-WireGuard -Entity $Entity -SSHSession $MockSSHSession -EntityType "Server" } | Should -Throw "Unexpected error during OS detection."
        }
    }
}
