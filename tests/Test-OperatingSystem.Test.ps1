# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Test-OperatingSystem" {
    Context "When the remote system is Windows" {
        It "Should detect and return 'Windows'" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                if ($args[1] -match "powershell -Command") {
                    return @{ Output = "Microsoft Windows 10 Pro" }
                }
                return $null
            }

            # Act
            $Result = Test-OperatingSystem -SSHSession $MockSSHSession

            # Assert
            Assert-MockCalled -CommandName Invoke-SSHCommand -Exactly 1 -Scope It -ParameterFilter { $args[1] -match "powershell -Command" }
            $Result | Should -Be "Windows"
        }
    }

    Context "When the remote system is Linux" {
        It "Should detect and return 'Linux'" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                if ($args[1] -match "uname -s") {
                    return @{ Output = "Linux" }
                }
                return $null
            }

            # Act
            $Result = Test-OperatingSystem -SSHSession $MockSSHSession

            # Assert
            Assert-MockCalled -CommandName Invoke-SSHCommand -Exactly 1 -Scope It -ParameterFilter { $args[1] -match "uname -s" }
            $Result | Should -Be "Linux"
        }
    }

    Context "When the operating system cannot be detected" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                return @{ Output = "" }
            }

            # Act & Assert
            { Test-OperatingSystem -SSHSession $MockSSHSession } | Should -Throw "Operating system detection failed: Unknown OS type."
        }
    }

    Context "When an unexpected error occurs" {
        It "Should throw the error with detailed feedback" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                throw "Unexpected SSH error."
            }

            # Act & Assert
            { Test-OperatingSystem -SSHSession $MockSSHSession } | Should -Throw "Unexpected SSH error."
        }
    }
}
