@{
    ModuleVersion = '1.0'
    Author        = 'CODEZETA'
    Description   = 'A PowerShell module for WireGuard deployment both on windows and linux.'
    FunctionsToExport = @(
        'Import-Configuration',
        'Establish-SSHConnection',
        'Check-WireGuardInstallation',
        'Install-WireGuard',
        'Configure-WireGuard',
        'Start-WireGuardTunnel'
    )
    PowerShellVersion = '7.4.6'
}
