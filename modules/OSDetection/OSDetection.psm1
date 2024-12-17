# OSDetection.psm1
function Test-OperatingSystem {
    param (
        [Parameter(Mandatory)] [object]$SSHSession
    )
    try {
        Write-Host "Checking the remote system's operating system..." -ForegroundColor Cyan

        # Test for Windows
        $WindowsCommand = 'powershell -Command "(Get-CimInstance Win32_OperatingSystem).Caption"'
        $WindowsResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $WindowsCommand

        # Clean up output and ensure it's a string
        $CleanWindowsResult = [string]::Join("", $WindowsResult.Output).Trim()

        Write-Host "Windows Command Result: '$CleanWindowsResult'" -ForegroundColor Yellow

        if ($CleanWindowsResult -match "Windows") {
            return "Windows"
        }

        # Test for Linux
        $LinuxCommand = 'uname -s'
        $LinuxResult = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $LinuxCommand

        # Clean up output and ensure it's a string
        $CleanLinuxResult = [string]::Join("", $LinuxResult.Output).Trim()

        Write-Host "Linux Command Result: '$CleanLinuxResult'" -ForegroundColor Yellow

        if ($CleanLinuxResult -match "Linux") {
            return "Linux"
        }

        # If neither Windows nor Linux is detected
        Write-Warning "Unable to detect the remote system's operating system. Returning 'Unknown'."
        return "Unknown"
    } catch {
        Write-Error "Error during OS detection: $_"
        return "Unknown"
    }
}





Export-ModuleMember -Function Test-OperatingSystem
