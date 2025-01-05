# Import the module or script containing the function
Import-Module -Name ..\modules\WireGuardDeploymentModule.psm1 -Force

Describe "Remove-Session" {
    Context "When the session exists and is valid" {
        It "Should successfully close the session" {
            # Arrange
            $SessionId = 1234

            # Mock the Remove-SSHSession command
            Mock -CommandName Remove-SSHSession -MockWith {}

            # Act
            Remove-Session -SessionId $SessionId

            # Assert
            Assert-MockCalled -CommandName Remove-SSHSession -Exactly 1 -Scope It -ParameterFilter { $SessionId -eq 1234 }
        }
    }

    Context "When the session ID is invalid or session does not exist" {
        It "Should throw an error" {
            # Arrange
            $SessionId = 5678

            # Mock the Remove-SSHSession command to throw an error
            Mock -CommandName Remove-SSHSession -MockWith {
                throw "Session not found."
            }

            # Act & Assert
            { Remove-Session -SessionId $SessionId } | Should -Throw "Session not found."
        }
    }

    Context "When an unexpected error occurs" {
        It "Should throw the error with detailed feedback" {
            # Arrange
            $SessionId = 9012

            # Mock the Remove-SSHSession command to throw a generic error
            Mock -CommandName Remove-SSHSession -MockWith {
                throw "Unexpected error occurred."
            }

            # Act & Assert
            { Remove-Session -SessionId $SessionId } | Should -Throw "Unexpected error occurred."
        }
    }
}
