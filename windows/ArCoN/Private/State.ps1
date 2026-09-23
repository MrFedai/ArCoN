# ArCoN v3.0 (Windows) -- Private/State.ps1
# Run state, plan recording, rollback journal and task execution.
#
# Layout ($env:LOCALAPPDATA\ArCoN):
#   current.txt                       id of the last unfinished run
#   runs\<id>\state.json              config + task states (atomic replace)
#   runs\<id>\rollback.json           append-only journal (JSON Lines)
#   runs\<id>\backup\                 file/registry backups (.reg exports)
#   logs\arcon-*.log

function Initialize-ArConState {
    $script:ArConState = Join-Path ($env:LOCALAPPDATA ? $env:LOCALAPPDATA : $env:TEMP) 'ArCoN'
    foreach ($d in @($script:ArConState, (Join-Path $script:ArConState 'runs'))) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    return $script:ArConState
}

function New-ArConRun {
    # Unique even for several runs started by the same process in the same second
    # (found by the Pester suite: two runs shared one journal before this fix).
    $base = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
    $id = $base; $n = 0
    while (Test-Path -LiteralPath (Join-Path $script:ArConState "runs/$id")) { $n++; $id = "$base$n" }
    $script:RunId = $id
    $script:RunDir = Join-Path $script:ArConState "runs/$($script:RunId)"
    New-Item -ItemType Directory -Path (Join-Path $script:RunDir 'backup') -Force | Out-Null
    if (-not $script:ArConDryRun) {
        Set-Content -LiteralPath (Join-Path $script:ArConState 'current.txt') -Value $script:RunId -Encoding utf8
    }
    return $script:RunId
}

function Get-ArConCurrentRun {
    $f = Join-Path $script:ArConState 'current.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $id = (Get-Content -LiteralPath $f -First 1).Trim()
    if ($id -notmatch '^\d{8}-\d{6}-\d+$') { Write-ArConWarn 'corrupted state pointer ignored'; return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $script:ArConState "runs/$id"))) { return $null }
    return $id
}

function Open-ArConRun {
    param([Parameter(Mandatory)] [string] $Id)
    $dir = Join-Path $script:ArConState "runs/$Id"
    if (-not (Test-Path -LiteralPath $dir)) { throw "unknown run id: $Id" }
    $script:RunId = $Id
    $script:RunDir = $dir
}

function Clear-ArConCurrentRun {
    if ($script:ArConDryRun) { return }
    Remove-Item -LiteralPath (Join-Path $script:ArConState 'current.txt') -Force -ErrorAction SilentlyContinue
}

function Get-ArConRunList {
    Get-ChildItem -LiteralPath (Join-Path $script:ArConState 'runs') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            $sf = Join-Path $_.FullName 'state.json'
            $tasks = @(); if (Test-Path -LiteralPath $sf) { $tasks = @((Get-Content -Raw -LiteralPath $sf | ConvertFrom-Json).Tasks) }
            [pscustomobject]@{
                RunId  = $_.Name
                Tasks  = $tasks.Count
                Done   = @($tasks | Where-Object { $_.Status -eq 'done' }).Count
                Failed = @($tasks | Where-Object { $_.Status -eq 'failed' }).Count
            }
        }
}

function Save-ArConState {
    if ($script:ArConDryRun -or -not $script:RunDir) { return }
    $obj = [pscustomobject]@{
        RunId   = $script:RunId
        Updated = (Get-Date -Format 'o')
        Config  = $script:Cfg
        Tasks   = @($script:Tasks | ForEach-Object {
            [pscustomobject]@{ Id = $_.Id; Status = $_.Status; Risk = $_.Risk; Description = $_.Description }
        })
    }
    $tmp = Join-Path $script:RunDir 'state.json.tmp'
    $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination (Join-Path $script:RunDir 'state.json') -Force
}

function Import-ArConState {
    $sf = Join-Path $script:RunDir 'state.json'
    if (-not (Test-Path -LiteralPath $sf)) { throw "run $($script:RunId) has no state.json" }
    return (Get-Content -Raw -LiteralPath $sf | ConvertFrom-Json)
}

# --------------------------------------------------------------------- plan
function Add-ArConPlanEntry {
    param(
        [Parameter(Mandatory)] [ValidateSet('PKG_INSTALL', 'PKG_REMOVE', 'FILE', 'REGISTRY', 'SETTING', 'SERVICE', 'OPTIMIZE', 'COMMAND')] [string] $Category,
        [Parameter(Mandatory)] [string] $Detail
    )
    $script:Plan.Add([pscustomobject]@{ Category = $Category; Task = ($script:ArConTask ? $script:ArConTask : $script:ArConModule); Detail = $Detail }) | Out-Null
    Write-ArConDebug "PLAN [$Category] $Detail"
}

function Show-ArConPlan {
    Write-ArConHeader 'DRY-RUN PLAN (no changes were made)'
    if ($script:Plan.Count -eq 0) {
        Write-Host '  (nothing to do -- the system already matches the selected profile)'
        return
    }
    $titles = [ordered]@{
        PKG_INSTALL = 'Packages to install'; PKG_REMOVE = 'Packages to remove'
        FILE = 'Files to create/modify/remove'; REGISTRY = 'Registry values to change'
        SETTING = 'Settings to change'; SERVICE = 'Services to modify'
        OPTIMIZE = 'Optimizations to apply'; COMMAND = 'Other commands'
    }
    foreach ($c in $titles.Keys) {
        $rows = @($script:Plan | Where-Object { $_.Category -eq $c })
        if (-not $rows.Count) { continue }
        Write-Host ''
        Write-Host ($titles[$c] + ':') -ForegroundColor White
        foreach ($r in $rows) { Write-Host ("  - [{0}] {1}" -f $r.Task, $r.Detail) }
    }
    Write-Host ''
}

# ----------------------------------------------------------------- rollback
function Add-ArConRollbackEntry {
    param(
        [Parameter(Mandatory)] [ValidateSet('PKG', 'FILE', 'REGISTRY', 'SERVICE', 'POWERPLAN', 'NOTE')] [string] $Type,
        [Parameter(Mandatory)] [string[]] $Data
    )
    if ($script:ArConDryRun -or -not $script:RunDir) { return }
    $entry = [pscustomobject]@{ Type = $Type; Data = $Data; At = (Get-Date -Format 'o') }
    Add-Content -LiteralPath (Join-Path $script:RunDir 'rollback.json') -Value ($entry | ConvertTo-Json -Compress) -Encoding utf8
}

function Add-ArConIrreversibleNote {
    param([Parameter(Mandatory)] [string] $Message)
    Add-ArConPlanEntry -Category 'COMMAND' -Detail "IRREVERSIBLE: $Message"
    Add-ArConRollbackEntry -Type 'NOTE' -Data @($Message)
    Write-ArConWarn "irreversible step: $Message"
}

# Backup a registry key as a .reg file so the rollback can re-import it
function Backup-ArConRegistryKey {
    param([Parameter(Mandatory)] [string] $Path)   # e.g. HKCU\Software\Microsoft\GameBar
    if ($script:ArConDryRun -or -not $script:RunDir) { return $null }
    $safe = ($Path -replace '[\\:]', '_')
    $file = Join-Path $script:RunDir "backup/$safe.reg"
    & reg.exe export $Path $file /y *> $null
    if ($LASTEXITCODE -eq 0) {
        Add-ArConRollbackEntry -Type 'REGISTRY' -Data @($Path, $file)
        return $file
    }
    # key does not exist yet -> rollback must delete it
    Add-ArConRollbackEntry -Type 'REGISTRY' -Data @($Path, 'ABSENT')
    return $null
}

function Invoke-ArConRollback {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RunId, [switch] $IncludePackages)
    Open-ArConRun -Id $RunId
    $j = Join-Path $script:RunDir 'rollback.json'
    if (-not (Test-Path -LiteralPath $j)) { Write-ArConError "no rollback journal in run $RunId"; return $false }
    $entries = @(Get-Content -LiteralPath $j | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    Write-ArConInfo "rolling back $($entries.Count) journal entries from run $RunId"
    $ok = 0; $fail = 0
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        try {
            switch ($e.Type) {
                'PKG' {
                    if (-not $IncludePackages) {
                        Write-ArConInfo "package '$($e.Data[1])' kept (use -RollbackPackages to remove it)"
                    } else {
                        $pm = Get-ArConPackageManager
                        if (-not $pm) { throw 'no package manager available' }
                        if (-not $pm.Remove($e.Data[1])) { throw "could not remove $($e.Data[1])" }
                    }
                }
                'FILE' {
                    if ($e.Data[1] -eq 'ABSENT') {
                        # idempotent: a file that is already gone is the desired end state
                        if (Test-Path -LiteralPath $e.Data[0]) { Remove-Item -LiteralPath $e.Data[0] -Recurse -Force -ErrorAction Stop }
                    }
                    else { Copy-Item -LiteralPath $e.Data[1] -Destination $e.Data[0] -Recurse -Force -ErrorAction Stop }
                }
                'REGISTRY' {
                    if ($e.Data[1] -eq 'ABSENT') { & reg.exe delete $e.Data[0] /f *> $null }
                    else { & reg.exe import $e.Data[1] *> $null; if ($LASTEXITCODE -ne 0) { throw "reg import failed for $($e.Data[1])" } }
                }
                'SERVICE' {
                    Set-Service -Name $e.Data[0] -StartupType $e.Data[1] -ErrorAction Stop
                }
                'POWERPLAN' {
                    & powercfg.exe /setactive $e.Data[0] *> $null
                    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive $($e.Data[0]) failed" }
                }
                'NOTE' { Write-ArConWarn "cannot be undone automatically: $($e.Data[0])" }
            }
            $ok++
        } catch {
            $fail++
            Write-ArConError "rollback step failed ($($e.Type) $($e.Data -join ' ')): $($_.Exception.Message)"
        }
    }
    Write-ArConInfo "rollback finished: $ok ok, $fail failed"
    return ($fail -eq 0)
}

# --------------------------------------------------------------------- tasks
function Reset-ArConTaskQueue { $script:Tasks = [System.Collections.Generic.List[object]]::new() }

function Add-ArConTask {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [ValidateSet('low', 'medium', 'high')] [string] $Risk,
        [Parameter(Mandatory)] [string] $Description,
        [Parameter(Mandatory)] [scriptblock] $Action
    )
    $script:Tasks.Add([pscustomobject]@{
        Id = $Id; Risk = $Risk; Description = $Description; Action = $Action
        Module = ($Id -split '\.')[0]; Status = 'pending'
    }) | Out-Null
}

function Show-ArConTaskQueue {
    $i = 0
    foreach ($t in $script:Tasks) {
        $i++
        Write-Host ("  {0,2}. [{1,-8}] {2,-7} {3,-30} {4}" -f $i, $t.Status, $t.Risk, $t.Id, $t.Description)
    }
}

# Task actions return $true (done), $false (failed) or the string 'skip'.
function Invoke-ArConTaskQueue {
    [CmdletBinding()]
    param([switch] $KeepGoing)
    $failures = 0
    $total = $script:Tasks.Count
    $i = 0
    Save-ArConState
    foreach ($t in $script:Tasks) {
        $i++
        if ($t.Status -in @('done', 'skipped')) { Write-ArConInfo "[$i/$total] $($t.Id) already $($t.Status) -- skipping"; continue }
        $script:ArConModule = $t.Module
        $script:ArConTask = $t.Id
        Write-ArConProgressBar -Current ($i - 1) -Total $total -Label $t.Description
        Write-ArConInfo "[$i/$total] $($t.Description)"
        $t.Status = 'running'; Save-ArConState
        $result = $false
        try { $result = & $t.Action }
        catch { Write-ArConError "task $($t.Id) threw: $($_.Exception.Message)"; $result = $false }
        if ($result -is [string] -and $result -eq 'skip') {
            $t.Status = 'skipped'; Write-ArConResult -Operation $t.Id -Result SKIP
        } elseif ($result) {
            $t.Status = 'done'; Write-ArConResult -Operation $t.Id -Result PASS
        } else {
            $t.Status = 'failed'; $failures++
            Write-ArConResult -Operation $t.Id -Result FAIL 'see log'
            if (-not $KeepGoing) {
                if ($script:ArConInteractive) {
                    if (-not (Confirm-ArConStep "Task '$($t.Id)' failed. Continue with the remaining tasks" $true)) {
                        Write-ArConError 'aborting on user request; resume later with -Resume'; Save-ArConState; break
                    }
                } else {
                    Write-ArConError 'aborting (non-interactive; use -KeepGoing to continue after failures)'; Save-ArConState; break
                }
            }
        }
        Save-ArConState
    }
    Write-Progress -Activity 'ArCoN' -Completed
    $script:ArConTask = $null; $script:ArConModule = 'core'
    return $failures
}
