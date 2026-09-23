<#
.SYNOPSIS
    ArCoN v3.0 -- Windows entry point.
.DESCRIPTION
    Windows 11 (tested) / Windows 10 2004+ (best effort) setup, security
    reporting and optimization. Same profiles and package catalog as setup.sh.
.EXAMPLE
    .\setup.ps1 -DryRun
.EXAMPLE
    .\setup.ps1 -Profile Gaming
.EXAMPLE
    .\setup.ps1 -Profile Minimal -NonInteractive
.EXAMPLE
    .\setup.ps1 -Resume
.EXAMPLE
    .\setup.ps1 -Rollback -RollbackPackages
#>
[CmdletBinding()]
param(
    [switch] $DryRun,
    [ValidateSet('Minimal', 'Balanced', 'Performance', 'Gaming', 'Developer', 'Security', 'Full', 'Custom')]
    [Alias('Profile')] [string] $ProfileName,
    [switch] $Resume,
    [switch] $Rollback,
    [string] $RollbackRun,
    [switch] $RollbackPackages,
    [switch] $ListRuns,
    [switch] $ShowConfig,
    [switch] $NonInteractive,
    [switch] $IUnderstandDestructive,
    [switch] $KeepGoing,
    [string[]] $Modules,
    [string[]] $Set,
    [string] $ConfigFile,
    [string] $LogPath,
    [switch] $DebugLog,
    [switch] $Version
)

$ErrorActionPreference = 'Stop'
if ($Version) { Write-Output 'ArCoN 3.0.0'; exit 0 }

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'ArCoN v3.0 requires PowerShell 7 or newer (found Windows PowerShell ' -NoNewline -ForegroundColor Red
    Write-Host "$($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host 'Install it with:  winget install --id Microsoft.PowerShell --exact' -ForegroundColor Yellow
    Write-Host 'then run:         pwsh -File .\setup.ps1' -ForegroundColor Yellow
    exit 4
}
if (-not $IsWindows) {
    Write-Host 'setup.ps1 is the Windows entry point. On Linux/macOS use ./setup.sh' -ForegroundColor Red
    exit 4
}

Import-Module (Join-Path $PSScriptRoot 'windows/ArCoN/ArCoN.psd1') -Force

$params = @{
    DryRun = $DryRun; Resume = $Resume; Rollback = $Rollback; RollbackPackages = $RollbackPackages
    ListRuns = $ListRuns; ShowConfig = $ShowConfig; NonInteractive = $NonInteractive
    IUnderstandDestructive = $IUnderstandDestructive; KeepGoing = $KeepGoing
    LogLevel = ($DebugLog ? 'Debug' : 'Info'); Argv = ($MyInvocation.Line)
}
if ($ProfileName) { $params.ProfileName = $ProfileName.ToLowerInvariant() }
if ($RollbackRun) { $params.RollbackRun = $RollbackRun }
if ($Modules)     { $params.Modules = $Modules }
if ($Set)         { $params.Set = $Set }
if ($ConfigFile)  { $params.ConfigFile = $ConfigFile }
if ($LogPath)     { $params.LogPath = $LogPath }

$rc = Invoke-ArCoN @params
exit ([int] $rc)
