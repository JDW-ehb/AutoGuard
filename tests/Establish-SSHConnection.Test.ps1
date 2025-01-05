# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Establish-SSHConnection" {
    Context "When the Posh-SSH module is installed and connection parameters are valid" {
        It "Should establish an SSH session successfully" {
            # Arrange
            $FakeSession = @{ SessionId = 1234 }
            $MockCredential = [PSCredential]::new("user", (ConvertTo-SecureString "password" -AsPlainText -Force))
            
            # Mock the required dependencies
            Mock -CommandName Get-Module -MockWith {
                return @{ Name = "Posh-SSH" }
            }
            Mock -CommandName New-SSHSession -MockWith {
                return $FakeSession
            }

            # Act
            $Result = Establish-SSHConnection -IP "192.168.1.100" -Username "user" -Password "password"

            # Assert
            Assert-MockCalled -CommandName New-SSHSession -Exactly 1 -Scope It
            $Result | Should -Be $FakeSession
        }
    }

    Context "When the Posh-SSH module is not installed" {
        It "Should install the Posh-SSH module and attempt to connect" {
            # Arrange
            Mock -CommandName Get-Module -MockWith {
                return $null
            }
            Mock -CommandName Install-Module -MockWith {}
            Mock -CommandName New-SSHSession -MockWith {
                return @{ SessionId = 1234 }
            }

            # Act
            $Result = Establish-SSHConnection -IP "192.168.1.100" -Username "user" -Password "password"

            # Assert
            Assert-MockCalled -CommandName Install-Module -Exactly 1 -Scope It
            Assert-MockCalled -CommandName New-SSHSession -Exactly 1 -Scope It
            $Result.SessionId | Should -Be 1234
        }
    }

    Context "When invalid credentials are provided" {
        It "Should throw an error" {
            # Arrange
            Mock -CommandName Get-Module -MockWith {
                return @{ Name = "Posh-SSH" }
            }
            Mock -CommandName New-SSHSession -MockWith {
                throw "Authentication failed."
            }

            # Act & Assert
            { Establish-SSHConnection -IP "192.168.1.100" -Username "user" -Password "wrongpassword" } | Should -Throw
        }
    }

    Context "When the connection fails for other reasons" {
        It "Should throw an error" {
            # Arrange
            Mock -CommandName Get-Module -MockWith {
                return @{ Name = "Posh-SSH" }
            }
            Mock -CommandName New-SSHSession -MockWith {
                throw "Network error."
            }

            # Act & Assert
            { Establish-SSHConnection -IP "192.168.1.100" -Username "user" -Password "password" } | Should -Throw
        }
    }
}
