# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Install-WireGuard" {
    Context "When installing on Linux" {
        It "Should download and install the WireGuard installer successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                if ($CommandKey -eq "DownloadInstaller" -or $CommandKey -eq "RunInstaller") {
                    return @{ ExitStatus = 0 }
                }
            }

            # Act
            $Result = Install-WireGuard -SSHSession $MockSSHSession -OS "Linux"

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 2 -Scope It -ParameterFilter { $CommandKey -eq "DownloadInstaller" -or $CommandKey -eq "RunInstaller" }
            $Result | Should -Be $true
        }
    }

    Context "When installing on Windows" {
        It "Should download and install the WireGuard installer successfully" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                if ($CommandKey -eq "DownloadInstaller" -or $CommandKey -eq "RunInstaller") {
                    return @{ ExitStatus = 0 }
                }
            }

            # Act
            $Result = Install-WireGuard -SSHSession $MockSSHSession -OS "Windows"

            # Assert
            Assert-MockCalled -CommandName Invoke-CommandByOS -Exactly 2 -Scope It -ParameterFilter { $CommandKey -eq "DownloadInstaller" -or $CommandKey -eq "RunInstaller" }
            $Result | Should -Be $true
        }
    }

    Context "When the OS is unsupported" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }

            # Act & Assert
            { Install-WireGuard -SSHSession $MockSSHSession -OS "UnsupportedOS" } | Should -Throw "Unsupported OS 'UnsupportedOS'. Only 'Windows' and 'Linux' are supported."
        }
    }

    Context "When downloading the WireGuard installer fails" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                if ($CommandKey -eq "DownloadInstaller") {
                    return @{ ExitStatus = 1 }
                }
            }

            # Act & Assert
            { Install-WireGuard -SSHSession $MockSSHSession -OS "Linux" } | Should -Throw "Failed to download the WireGuard installer. Exit status: 1"
        }
    }

    Context "When running the WireGuard installer fails" {
        It "Should throw an error" {
            # Arrange
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-CommandByOS -MockWith {
                param ([string]$CommandKey, [string]$OS, $SSHSession)
                if ($CommandKey -eq "RunInstaller") {
                    return @{ ExitStatus = 1 }
                }
            }

            # Act & Assert
            { Install-WireGuard -SSHSession $MockSSHSession -OS "Windows" } | Should -Throw "Failed to execute the WireGuard installer. Exit status: 1"
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
            { Install-WireGuard -SSHSession $MockSSHSession -OS "Linux" } | Should -Throw "Unexpected SSH error."
        }
    }
}
