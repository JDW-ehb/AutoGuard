function Establish-SSHConnection {
    param (
        [string]$IP,
        [string]$Username,
        [string]$Password
    )
    try {
        $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $Credential = New-Object PSCredential ($Username, $SecurePassword)

        if (!(Get-Module -ListAvailable -Name Posh-SSH)) {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser
        }

        Write-Host "Establishing SSH connection to $IP..." -ForegroundColor Cyan
        return New-SSHSession -ComputerName $IP -Credential $Credential
    } catch {
        Write-Host "Failed to connect to ${IP}: $_" -ForegroundColor Red
        return $null
    }
}

function Remove-Session {
    param ([int]$SessionId)
    try {
        Write-Host "Closing SSH session with ID: $SessionId..." -ForegroundColor Yellow
        Remove-SSHSession -SessionId $SessionId
        Write-Host "SSH session closed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to close SSH session: $_" -ForegroundColor Red
    }
}

Export-ModuleMember -Function Establish-SSHConnection, Remove-Session
