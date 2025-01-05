# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Start-WireGuardTunnel" {
    Context "When the OS is Linux and the command executes successfully" {
        It "Should start the WireGuard tunnel and return true" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                return @{ ExitStatus = 0 }
            }

            # Act
            $Result = Start-WireGuardTunnel -SSHSession $MockSSHSession -OS "Linux"

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 1 -Scope It -ParameterFilter { $CommandKey -eq "StartTunnel" -and $OS -eq "Linux" }
            $Result | Should -Be $true
        }
    }

    Context "When the OS is Windows and the WireGuard executable is missing" {
        It "Should write an error and return false" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Test-Path -MockWith { return $false }

            # Act
            $Result = Start-WireGuardTunnel -SSHSession $MockSSHSession -OS "Windows"

            # Assert
            Assert-MockCalled -CommandName Test-Path -Exactly 1 -Scope It -ParameterFilter { $_ -eq "C:\Program Files\WireGuard\wireguard.exe" }
            $Result | Should -Be $false
        }
    }

    Context "When the OS is Windows and the WireGuard executable is present" {
        It "Should start the WireGuard tunnel and return true" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Test-Path -MockWith { return $true }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                return @{ ExitStatus = 0 }
            }

            # Act
            $Result = Start-WireGuardTunnel -SSHSession $MockSSHSession -OS "Windows"

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 1 -Scope It -ParameterFilter { $CommandKey -eq "StartTunnel" -and $OS -eq "Windows" }
            $Result | Should -Be $true
        }
    }

    Context "When the command fails to start the tunnel" {
        It "Should write an error and return false" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                return @{ ExitStatus = 1; Output = "Failed to start tunnel." }
            }

            # Act
            $Result = Start-WireGuardTunnel -SSHSession $MockSSHSession -OS "Linux"

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 1 -Scope It -ParameterFilter { $CommandKey -eq "StartTunnel" -and $OS -eq "Linux" }
            $Result | Should -Be $false
        }
    }

    Context "When an unexpected error occurs" {
        It "Should throw the error with detailed feedback" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                throw "Unexpected SSH error."
            }

            # Act & Assert
            { Start-WireGuardTunnel -SSHSession $MockSSHSession -OS "Linux" } | Should -Throw "Unexpected SSH error."
        }
    }
}
