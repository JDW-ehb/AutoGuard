# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Invoke-CommandByOS" {
    Context "When the command key and OS are valid" {
        It "Should execute the correct command and return the expected result" {
            # Arrange
            $CommandKey = "StartTunnel"
            $OS = "Linux"
            $MockSSHSession = @{ SessionId = 1234 }
            $MockResult = @{ ExitStatus = 0; Output = "Tunnel started successfully." }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                return $MockResult
            }
            $WireGuardCommands = @{
                StartTunnel = @{
                    Linux = "sudo wg-quick up wg0"
                    Windows = "wireguard.exe /installtunnelservice wg0.conf"
                }
            }

            # Act
            $Result = Invoke-CommandByOS -CommandKey $CommandKey -OS $OS -SSHSession $MockSSHSession

            # Assert
            Assert-MockCalled -CommandName Invoke-SSHCommand -Exactly 1 -Scope It
            $Result | Should -Be $MockResult
        }
    }

    Context "When the CommandKey is invalid" {
        It "Should throw an error" {
            # Arrange
            $CommandKey = "InvalidKey"
            $OS = "Linux"
            $MockSSHSession = @{ SessionId = 1234 }
            $WireGuardCommands = @{
                StartTunnel = @{
                    Linux = "sudo wg-quick up wg0"
                    Windows = "wireguard.exe /installtunnelservice wg0.conf"
                }
            }

            # Act & Assert
            { Invoke-CommandByOS -CommandKey $CommandKey -OS $OS -SSHSession $MockSSHSession } | Should -Throw "Invalid CommandKey 'InvalidKey'. It does not exist in the command table."
        }
    }

    Context "When the OS is unsupported for the CommandKey" {
        It "Should throw an error" {
            # Arrange
            $CommandKey = "StartTunnel"
            $OS = "UnsupportedOS"
            $MockSSHSession = @{ SessionId = 1234 }
            $WireGuardCommands = @{
                StartTunnel = @{
                    Linux = "sudo wg-quick up wg0"
                    Windows = "wireguard.exe /installtunnelservice wg0.conf"
                }
            }

            # Act & Assert
            { Invoke-CommandByOS -CommandKey $CommandKey -OS $OS -SSHSession $MockSSHSession } | Should -Throw "Command 'StartTunnel' is not defined for OS 'UnsupportedOS'."
        }
    }

    Context "When the SSH command fails" {
        It "Should throw an error" {
            # Arrange
            $CommandKey = "StartTunnel"
            $OS = "Linux"
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                throw "SSH command execution failed."
            }
            $WireGuardCommands = @{
                StartTunnel = @{
                    Linux = "sudo wg-quick up wg0"
                    Windows = "wireguard.exe /installtunnelservice wg0.conf"
                }
            }

            # Act & Assert
            { Invoke-CommandByOS -CommandKey $CommandKey -OS $OS -SSHSession $MockSSHSession } | Should -Throw "SSH command execution failed."
        }
    }

    Context "When the command execution returns a non-zero exit status" {
        It "Should throw an error" {
            # Arrange
            $CommandKey = "StartTunnel"
            $OS = "Linux"
            $MockSSHSession = @{ SessionId = 1234 }
            Mock -CommandName Invoke-SSHCommand -MockWith {
                return @{ ExitStatus = 1; Output = "Failed to start tunnel." }
            }
            $WireGuardCommands = @{
                StartTunnel = @{
                    Linux = "sudo wg-quick up wg0"
                    Windows = "wireguard.exe /installtunnelservice wg0.conf"
                }
            }

            # Act & Assert
            { Invoke-CommandByOS -CommandKey $CommandKey -OS $OS -SSHSession $MockSSHSession } | Should -Throw "Command 'StartTunnel' failed with status 1. Output: Failed to start tunnel."
        }
    }
}
