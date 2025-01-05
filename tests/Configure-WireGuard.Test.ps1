# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Configure-WireGuard" {
    Context "When the OS is Linux and configuration content is valid" {
        It "Should write the WireGuard configuration successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "Linux"
            $ConfigContent = "[Interface]`nPrivateKey = ABC123"
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession, $ConfigContent)
                return @{ ExitStatus = 0 }
            }

            # Act
            Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 1 -Scope It -ParameterFilter { $CommandKey -eq "WriteConfig" -and $OS -eq "Linux" -and $ConfigContent -eq $ConfigContent }
        }
    }

    Context "When the OS is Windows and configuration content is valid" {
        It "Should write the WireGuard configuration successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "Windows"
            $ConfigContent = "[Interface]`nPrivateKey = XYZ456"
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession, $ConfigContent)
                return @{ ExitStatus = 0 }
            }

            # Act
            Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 1 -Scope It -ParameterFilter { $CommandKey -eq "WriteConfig" -and $OS -eq "Windows" -and $ConfigContent -eq $ConfigContent }
        }
    }

    Context "When the OS is unsupported" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "UnsupportedOS"
            $ConfigContent = "[Interface]`nPrivateKey = ABC123"

            # Act & Assert
            { Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent } | Should -Throw "Unsupported OS 'UnsupportedOS'. Only 'Windows' and 'Linux' are supported."
        }
    }

    Context "When the configuration content is null or empty" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "Linux"
            $ConfigContent = ""

            # Act & Assert
            { Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent } | Should -Throw "Configuration content cannot be null or empty."
        }
    }

    Context "When writing the configuration fails" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "Linux"
            $ConfigContent = "[Interface]`nPrivateKey = ABC123"
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession, $ConfigContent)
                return @{ ExitStatus = 1; Output = "Failed to write configuration." }
            }

            # Act & Assert
            { Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent } | Should -Throw "Failed to write WireGuard configuration. Exit status: 1"
        }
    }

    Context "When an unexpected error occurs" {
        It "Should throw the error with detailed feedback" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            $OS = "Linux"
            $ConfigContent = "[Interface]`nPrivateKey = ABC123"
            Mock -CommandName Invoke-CommandByOS -MockWith {
                throw "Unexpected error during command execution."
            }

            # Act & Assert
            { Configure-WireGuard -SSHSession $MockSSHSession -OS $OS -ConfigContent $ConfigContent } | Should -Throw "Unexpected error during command execution."
        }
    }
}
