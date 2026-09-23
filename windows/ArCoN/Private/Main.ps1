# ArCoN v3.0 (Windows) -- Private/Main.ps1
# Orchestrator: detect -> validate -> plan -> show -> confirm -> apply -> verify.
# Mirrors core/main.sh so both platforms behave identically from the user's side.

function Show-ArConBanner {
    Write-Host ''
    Write-Host '    ___         ______      _   __' -ForegroundColor Cyan
    Write-Host ('   /   |  _____/ ____/___  / | / /     ArCoN v{0}' -f $script:ArConVersion) -ForegroundColor Cyan
    Write-Host '  / /| | / ___/ /   / __ \/  |/ /      cross-platform setup & hardening' -ForegroundColor Cyan
    Write-Host ('  / ___ |/ /  / /___/ /_/ / /|  /       log: {0}' -f (Get-ArConLogFile)) -ForegroundColor Cyan
    Write-Host ' /_/  |_/_/   \____/\____/_/ |_/' -ForegroundColor Cyan
    Write-Host ''
    Write-ArConHardwareSummary
    if ($script:ArConDryRun) { Write-Host "`nDRY-RUN MODE -- nothing will be changed" -ForegroundColor Yellow }
    Write-Host ''
}

function Test-ArConPreflight {
    $hw = Get-ArConHardware
    $tier = Get-ArConWindowsTier
    if ($tier -eq 'unsupported') {
        Write-ArConError "unsupported Windows version: $($hw.Os) build $($hw.OsBuild) (Windows 10 2004 / build 19041 or newer is required)"
        return $false
    }
    if ($tier -eq 'experimental') {
        Write-ArConWarn "Windows 10 (build $($hw.OsBuild)) is supported on a best-effort basis; ArCoN's CI validates Windows 11 only"
        if ($script:ArConInteractive -and -not (Confirm-ArConStep 'Continue anyway' $false)) { return $false }
    }
    if (-not $hw.IsAdmin) {
        Write-ArConWarn 'not running as Administrator: package installation and system settings will fail'
        Write-ArConWarn 'start an elevated PowerShell ("Run as administrator") and re-run .\setup.ps1'
        if ($script:ArConInteractive -and -not (Confirm-ArConStep 'Continue without administrator rights' $false)) { return $false }
    }
    $minGb = [int] (Get-ArConConfig -Key 'MIN_DISK_GB' -Default '10')
    if ($hw.DiskFreeGb -gt 0 -and $hw.DiskFreeGb -lt $minGb) {
        Write-ArConWarn "only $($hw.DiskFreeGb) GB free on $($env:SystemDrive) (recommended: $minGb GB)"
        if ($script:ArConInteractive -and -not (Confirm-ArConStep 'Continue with low disk space' $false)) { return $false }
    }
    if (-not (Test-ArConOnline)) {
        Write-ArConError 'no internet connectivity -- winget operations would fail'
        if (-not ($script:ArConInteractive -and (Confirm-ArConStep 'Continue offline anyway (most tasks will fail)' $false))) { return $false }
    }
    if ((Get-ArConConfig -Key 'WIN_PACKAGE_SOURCE' -Default 'winget') -ne 'skip' -and -not (Get-ArConPackageManager)) {
        return $false
    }
    if ($hw.IsLaptop -and $hw.Power -eq 'battery') {
        Write-ArConWarn 'the machine is running on battery; a long installation may be interrupted'
    }
    return $true
}

$script:ArConModuleOrder = @('packages', 'gaming', 'security', 'optimize', 'cleanup')

function Get-ArConSelectedModule {
    $sel = Get-ArConConfigList -Key 'MODULES'
    return @($script:ArConModuleOrder | Where-Object { $sel -contains $_ })
}

function Invoke-ArConWizard {
    if (-not $script:ArConInteractive) { return }
    foreach ($m in Get-ArConSelectedModule) {
        $fn = "Invoke-$((Get-Culture).TextInfo.ToTitleCase($m))Wizard"
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            Write-ArConSection $m.ToUpperInvariant()
            & $fn
        }
    }
}

function Add-ArConModuleTask {
    foreach ($m in Get-ArConSelectedModule) {
        $fn = "Add-ArCon$((Get-Culture).TextInfo.ToTitleCase($m))Task"
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            $script:ArConModule = $m
            & $fn
        } else {
            Write-ArConWarn "module '$m' has no Windows implementation -- see docs/FEATURE-PARITY.md"
        }
    }
    $script:ArConModule = 'core'
}

function Show-ArConPlanAndConfirm {
    Write-ArConHeader 'EXECUTION PLAN'
    Show-ArConTaskQueue
    if ($script:Tasks.Count -eq 0) {
        Write-Host 'Nothing to do -- the system already matches the selected configuration.' -ForegroundColor Green
        return $false
    }
    $risky = @($script:Tasks | Where-Object { $_.Risk -eq 'high' }).Count
    if ($risky) { Write-Host "`n$risky high-risk task(s) are included; each asks for confirmation before it runs." -ForegroundColor Yellow }
    Write-Host ''
    if ($script:ArConDryRun) { return $true }
    return (Confirm-ArConStep "Proceed with these $($script:Tasks.Count) task(s)" $true)
}

function Invoke-ArCoN {
    [CmdletBinding()]
    param(
        [switch] $DryRun,
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
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')] [string] $LogLevel = 'Info',
        [string] $Argv = ''
    )

    $script:ArConDryRun = [bool] $DryRun
    $script:ArConInteractive = -not $NonInteractive
    $script:ArConAssumeDestructive = [bool] $IUnderstandDestructive
    $script:ArConArgv = $Argv
    $script:Plan = [System.Collections.Generic.List[object]]::new()
    Reset-ArConTaskQueue

    Initialize-ArConState | Out-Null
    Initialize-ArConLog -Path $LogPath -Level $LogLevel | Out-Null
    Write-ArConInfo "ArCoN $($script:ArConVersion) starting (dry_run=$($script:ArConDryRun) interactive=$($script:ArConInteractive))"

    try { Initialize-ArConConfig -ProfileName $ProfileName -UserConfig $ConfigFile -Set $Set }
    catch { Write-ArConError $_.Exception.Message; return 2 }
    if ($Modules) { Set-ArConConfig -Key 'MODULES' -Value ($Modules -join ',') -Source 'cli' }

    if ($ListRuns) {
        Write-ArConHeader 'PREVIOUS RUNS'
        $runs = @(Get-ArConRunList)
        if (-not $runs.Count) { Write-Host '  (none)' } else { Write-ArConTable -Rows $runs }
        $cur = Get-ArConCurrentRun
        if ($cur) { Write-Host "`nunfinished run: $cur  (.\setup.ps1 -Resume)" -ForegroundColor Yellow }
        return 0
    }
    if ($ShowConfig) {
        Show-ArConBanner
        Write-ArConHeader 'EFFECTIVE CONFIGURATION'
        Write-ArConTable -Rows @(Get-ArConConfigTable)
        return 0
    }

    Show-ArConBanner

    if ($Rollback) {
        $id = $RollbackRun
        if (-not $id) { $id = Get-ArConCurrentRun }
        if (-not $id) { $id = @(Get-ArConRunList)[-1].RunId }
        if (-not $id) { Write-ArConError 'no run found to roll back'; return 3 }
        Write-ArConHeader "ROLLBACK OF RUN $id"
        return ((Invoke-ArConRollback -RunId $id -IncludePackages:$RollbackPackages) ? 0 : 1)
    }

    if (-not (Test-ArConPreflight)) { Write-ArConError 'preflight checks failed'; return 5 }

    $resumed = $false
    if ($Resume) {
        $id = Get-ArConCurrentRun
        if (-not $id) { Write-ArConError 'no interrupted run to resume (see -ListRuns)'; return 3 }
        Open-ArConRun -Id $id
        $state = Import-ArConState
        foreach ($p in $state.Config.PSObject.Properties) { Set-ArConConfig -Key $p.Name -Value $p.Value -Source "resume/$id" }
        foreach ($s in @($Set)) { if ($s -match '=') { $kv = $s -split '=', 2; Set-ArConConfig -Key $kv[0] -Value $kv[1] -Source 'cli' } }
        if ($Modules) { Set-ArConConfig -Key 'MODULES' -Value ($Modules -join ',') -Source 'cli' }
        Test-ArConConfig
        Write-ArConInfo "resuming run $id"
        $resumed = $true
    } else {
        New-ArConRun | Out-Null
        Invoke-ArConWizard
    }

    Add-ArConModuleTask

    if ($resumed) {
        $state = Import-ArConState
        foreach ($t in $script:Tasks) {
            $old = @($state.Tasks | Where-Object { $_.Id -eq $t.Id })
            if (-not $old.Count) { continue }
            switch ($old[0].Status) {
                'done'    { $t.Status = 'done' }
                'skipped' { $t.Status = 'skipped' }
                'running' { Write-ArConWarn "resume: task $($t.Id) was interrupted -- it will be re-run" }
                default   { }
            }
        }
    }

    if (-not (Show-ArConPlanAndConfirm)) {
        if ($script:ArConDryRun) { Show-ArConPlan }
        Clear-ArConCurrentRun
        return 0
    }

    if ($script:ArConDryRun) {
        foreach ($t in $script:Tasks) {
            $script:ArConTask = $t.Id
            try { & $t.Action | Out-Null } catch { Write-ArConDebug "dry-run of $($t.Id): $($_.Exception.Message)" }
        }
        $script:ArConTask = $null
        Show-ArConPlan
        Write-Host 'Nothing above was applied. Re-run without -DryRun to apply it.' -ForegroundColor DarkGray
        return 0
    }

    $failures = Invoke-ArConTaskQueue -KeepGoing:$KeepGoing
    Show-ArConSummary
    if ($failures -eq 0) {
        Clear-ArConCurrentRun
        return 0
    }
    Write-ArConError "$failures task(s) failed -- the run is kept so it can be resumed (.\setup.ps1 -Resume)"
    return 1
}
