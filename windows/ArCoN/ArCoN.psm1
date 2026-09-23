# ArCoN v3.0 -- Windows module root
# Loads the private implementation files and exposes the public entry point
# (Invoke-ArCoN), which setup.ps1 calls. All state is module-scoped.

Set-StrictMode -Version Latest

$script:ArConVersion = '3.0.0'
$script:ArConRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script:ArConModule = 'core'
$script:ArConTask = $null
$script:ArConDryRun = $false
$script:ArConInteractive = $true
$script:ArConAssumeDestructive = $false
$script:ArConArgv = ''
$script:Cfg = [ordered]@{}
$script:CfgSrc = @{}
$script:Catalog = $null
$script:Hardware = $null
$script:PackageManager = $null
$script:Plan = [System.Collections.Generic.List[object]]::new()
$script:Tasks = [System.Collections.Generic.List[object]]::new()
$script:RunId = $null
$script:RunDir = $null
$script:ArConState = $null

foreach ($f in @('Logging', 'Ui', 'Config', 'Exec', 'State', 'Hardware', 'Packages', 'Modules', 'Main')) {
    . (Join-Path $PSScriptRoot "Private/$f.ps1")
}

Export-ModuleMember -Function @(
    'Invoke-ArCoN',
    # exported for the Pester suite and for interactive use
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
