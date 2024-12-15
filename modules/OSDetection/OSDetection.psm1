function Test-WindowsOperatingSystem {
    param (
        [object]$SSHSession
    )
    try {
        Write-Host "Checking if the remote system is Windows..." -ForegroundColor Cyan
        $Command = 'powershell -Command "(Get-CimInstance Win32_OperatingSystem).Caption"'
        $Result = Invoke-SSHCommand -SessionId $SSHSession.SessionId -Command $Command

        if ($Result.Output -match "Windows") {
            Write-Output "os=windows"
            return $true
        } else {
            Write-Host "Remote system is not Windows." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "Failed to check the operating system: $_" -ForegroundColor Red
        return $false
    }
}

Export-ModuleMember -Function Test-WindowsOperatingSystem
