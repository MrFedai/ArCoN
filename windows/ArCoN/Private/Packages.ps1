# ArCoN v3.0 (Windows) -- Private/Packages.ps1
# PackageManager abstraction as real PowerShell classes (mission requirement:
# "PowerShell: proper modules/objects", not a pile of if/else).
#
#   [ArConPackageManager]          abstract contract
#   [ArConWingetPackageManager]    winget implementation
#
# winget specifics handled here:
#   * exit code 0x8A150061 (APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED)
#     and 0x8A15002B (NO_APPLICABLE_UPGRADE) are SUCCESS for our purposes
#   * --accept-source-agreements / --accept-package-agreements are required for
#     unattended runs, otherwise winget blocks on a prompt
#   * `winget list --id` is used for detection (exact id), never text scraping

class ArConPackageManager {
    [string] $Name = 'abstract'
    [bool] Test()                                     { throw 'not implemented' }
    [bool] IsInstalled([string] $id)                  { throw 'not implemented' }
    [bool] Install([string] $id)                      { throw 'not implemented' }
    [bool] Remove([string] $id)                       { throw 'not implemented' }
    [bool] UpdateDatabase()                           { throw 'not implemented' }
    [bool] UpgradeAll()                               { throw 'not implemented' }
    [object[]] Search([string] $query)                { throw 'not implemented' }
}

class ArConWingetPackageManager : ArConPackageManager {
    [string] $Name = 'winget'
    # winget exit codes that mean "already in the desired state"
    static [int[]] $BenignCodes = @(
        -1978335135,  # 0x8A150061 package already installed
        -1978335189   # 0x8A15002B no applicable upgrade
    )

    [bool] Test() {
        return [bool] (Get-Command winget -ErrorAction SilentlyContinue)
    }

    [bool] IsInstalled([string] $id) {
        $out = & winget list --id $id --exact --accept-source-agreements 2>&1
        return ($LASTEXITCODE -eq 0 -and ($out -join "`n") -match [regex]::Escape($id))
    }

    [bool] Install([string] $id) {
        & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
            ForEach-Object { Write-ArConDebug "winget: $_" }
        $code = $LASTEXITCODE
        if ($code -eq 0) { return $true }
        if ([ArConWingetPackageManager]::BenignCodes -contains $code) {
            Write-ArConInfo "winget reports '$id' is already installed / up to date (exit 0x$('{0:X}' -f $code))"
            return $true
        }
        Write-ArConError "winget install '$id' failed with exit code 0x$('{0:X}' -f $code)"
        return $false
    }

    [bool] Remove([string] $id) {
        & winget uninstall --id $id --exact --silent --accept-source-agreements --disable-interactivity 2>&1 |
            ForEach-Object { Write-ArConDebug "winget: $_" }
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-ArConError "winget uninstall '$id' failed with exit code 0x$('{0:X}' -f $LASTEXITCODE)"
        return $false
    }

    [bool] UpdateDatabase() {
        & winget source update 2>&1 | ForEach-Object { Write-ArConDebug "winget: $_" }
        return ($LASTEXITCODE -eq 0)
    }

    [bool] UpgradeAll() {
        & winget upgrade --all --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 |
            ForEach-Object { Write-ArConDebug "winget: $_" }
        $code = $LASTEXITCODE
        if ($code -eq 0 -or [ArConWingetPackageManager]::BenignCodes -contains $code) { return $true }
        Write-ArConError "winget upgrade --all failed with exit code 0x$('{0:X}' -f $code)"
        return $false
    }

    [object[]] Search([string] $query) {
        $out = & winget search $query --accept-source-agreements 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($out)
    }
}

function Get-ArConPackageManager {
    if ($script:PackageManager) { return $script:PackageManager }
    $source = Get-ArConConfig -Key 'WIN_PACKAGE_SOURCE' -Default 'winget'
    if ($source -eq 'skip') { return $null }
    $pm = [ArConWingetPackageManager]::new()
    if (-not $pm.Test()) {
        Write-ArConError 'winget (App Installer) was not found. Install it from the Microsoft Store ("App Installer") or https://aka.ms/getwinget'
        return $null
    }
    $script:PackageManager = $pm
    Write-ArConDebug "package manager: $($pm.Name)"
    return $pm
}

# Install a set of catalog ids; returns a result object (never silently "success")
function Install-ArConPackageSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Packages)
    $pm = Get-ArConPackageManager
    if (-not $pm) { return [pscustomobject]@{ Installed = @(); Present = @(); Failed = @($Packages.Id) } }

    $installed = @(); $present = @(); $failed = @()
    $i = 0
    foreach ($p in $Packages) {
        $i++
        Write-ArConProgressBar -Current $i -Total $Packages.Count -Label "$($p.Id) ($($p.Winget))"
        if ($script:ArConDryRun) {
            Add-ArConPlanEntry -Category 'PKG_INSTALL' -Detail "$($p.Winget)  (via winget)"
            continue
        }
        if ($pm.IsInstalled($p.Winget)) { $present += $p.Id; Write-ArConDebug "already installed: $($p.Winget)"; continue }
        if ($pm.Install($p.Winget)) {
            $installed += $p.Id
            Add-ArConRollbackEntry -Type 'PKG' -Data @($pm.Name, $p.Winget)
        } else { $failed += $p.Id }
    }
    Write-Progress -Activity 'ArCoN' -Completed
    return [pscustomobject]@{ Installed = $installed; Present = $present; Failed = $failed }
}
