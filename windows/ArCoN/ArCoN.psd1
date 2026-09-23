@{
    RootModule        = 'ArCoN.psm1'
    ModuleVersion     = '3.0.0'
    GUID              = '2f4c9d1e-7a3b-4c5d-9e8f-1b2c3d4e5f60'
    Author            = 'MrFedai'
    CompanyName       = 'ArCoN'
    Copyright         = '(c) MrFedai. MIT licensed.'
    Description       = 'ArCoN v3.0 Windows implementation: winget package management, hardware detection, security reporting and system optimization with dry-run, resume and rollback support.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-ArCoN',
        'Get-ArConHardware', 'Get-ArConWindowsTier', 'Test-ArConAdmin', 'Get-ArConCimInstance',
        'Read-ArConConfFile', 'Initialize-ArConConfig', 'Get-ArConConfig', 'Set-ArConConfig',
        'Get-ArConConfigBool', 'Get-ArConConfigList', 'Test-ArConConfigListHas', 'Test-ArConConfig',
        'Get-ArConCatalog', 'Resolve-ArConPackageSet', 'Get-ArConPackageManager', 'Install-ArConPackageSet',
        'Initialize-ArConLog', 'Get-ArConLogFile', 'Write-ArConInfo', 'Write-ArConWarn', 'Write-ArConError',
        'Write-ArConDebug', 'Write-ArConResult',
        'Initialize-ArConState', 'New-ArConRun', 'Get-ArConCurrentRun', 'Open-ArConRun', 'Get-ArConRunList',
        'Save-ArConState', 'Import-ArConState', 'Invoke-ArConRollback',
        'Add-ArConTask', 'Invoke-ArConTaskQueue', 'Reset-ArConTaskQueue', 'Show-ArConTaskQueue',
        'Add-ArConPlanEntry', 'Show-ArConPlan', 'Invoke-ArConCommand', 'Set-ArConRegistryValue',
        'Set-ArConServiceStartup', 'Get-ArConFile', 'Test-ArConOnline', 'Confirm-ArConStep', 'Confirm-ArConWord'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{
        Tags       = @('setup', 'winget', 'optimization', 'security', 'cross-platform')
        ProjectUri = 'https://github.com/MrFedai/ArCoN'
        LicenseUri = 'https://github.com/MrFedai/ArCoN/blob/main/LICENSE'
    } }
}
