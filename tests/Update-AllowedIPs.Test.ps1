# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Update-AllowedIPs" {
    Context "When the configuration is valid" {
        It "Should update AllowedIPs for servers and clients" {
            # Arrange
            $Config = @{
                ServerConfigs = @(
                    @{
                        ServerName = "Server1"
                        ServerAddress = "10.0.0.1"
                        AllowedIPs = ""
                    },
                    @{
                        ServerName = "Server2"
                        ServerAddress = "10.0.0.2"
                        AllowedIPs = ""
                    }
                )
                ClientConfigs = @(
                    @{
                        ClientName = "Client1"
                        ClientAddress = "10.0.0.101"
                        AllowedIPs = ""
                    },
                    @{
                        ClientName = "Client2"
                        ClientAddress = "10.0.0.102"
                        AllowedIPs = ""
                    }
                )
            }

            # Act
            Update-AllowedIPs -Config $Config

            # Assert
            foreach ($Server in $Config.ServerConfigs) {
                $Server.AllowedIPs | Should -Be "10.0.0.101, 10.0.0.102"
            }
            foreach ($Client in $Config.ClientConfigs) {
                $Client.AllowedIPs | Should -Be "10.0.0.1, 10.0.0.2"
            }
        }
    }

    Context "When the configuration is missing ServerConfigs" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ClientConfigs = @(
                    @{
                        ClientName = "Client1"
                        ClientAddress = "10.0.0.101"
                    }
                )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "Configuration object is missing required keys 'ServerConfigs' or 'ClientConfigs'."
        }
    }

    Context "When the configuration is missing ClientConfigs" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ServerConfigs = @(
                    @{
                        ServerName = "Server1"
                        ServerAddress = "10.0.0.1"
                    }
                )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "Configuration object is missing required keys 'ServerConfigs' or 'ClientConfigs'."
        }
    }

    Context "When a ClientConfig is missing ClientAddress" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ServerConfigs = @(
                    @{
                        ServerName = "Server1"
                        ServerAddress = "10.0.0.1"
                    }
                )
                ClientConfigs = @(
                    @{
                        ClientName = "Client1"
                    }
                )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "One or more ClientConfigs are missing 'ClientAddress'."
        }
    }

    Context "When a ServerConfig is missing ServerAddress" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ServerConfigs = @(
                    @{
                        ServerName = "Server1"
                    }
                )
                ClientConfigs = @(
                    @{
                        ClientName = "Client1"
                        ClientAddress = "10.0.0.101"
                    }
                )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "One or more ServerConfigs are missing 'ServerAddress'."
        }
    }

    Context "When a ServerConfig entry is null" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ServerConfigs = @( $null )
                ClientConfigs = @(
                    @{
                        ClientName = "Client1"
                        ClientAddress = "10.0.0.101"
                    }
                )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "A ServerConfig entry is null or invalid."
        }
    }

    Context "When a ClientConfig entry is null" {
        It "Should throw an error" {
            # Arrange
            $Config = @{
                ServerConfigs = @(
                    @{
                        ServerName = "Server1"
                        ServerAddress = "10.0.0.1"
                    }
                )
                ClientConfigs = @( $null )
            }

            # Act & Assert
            { Update-AllowedIPs -Config $Config } | Should -Throw "A ClientConfig entry is null or invalid."
        }
    }
}
