# ArCoN v3.0 (Windows) -- Private/Modules.ps1
# Feature modules. Each module exposes Invoke-<Name>Wizard (questions) and
# Add-<Name>Tasks (planning). The task bodies are the only place that changes
# the system, and they all go through Invoke-ArConCommand / Set-ArConRegistryValue,
# so -DryRun is honoured everywhere.
#
# Windows equivalents of the v2.5 Linux features (see docs/FEATURE-PARITY.md):
#   base/packages  -> winget package groups from data/packages.catalog
#   gaming         -> Game Mode, GPU scheduling report, power plan
#   security       -> Defender status, Firewall, BitLocker, SmartScreen, UAC (report/enforce)
#   optimize       -> power plan, storage/temp cleanup, startup report, TRIM check
#   gnome/hyprland/blackarch/dotfiles/shell -> platform-inapplicable (documented)

# ------------------------------------------------------------------ packages
function Invoke-PackagesWizard {
    Write-ArConSection 'Package groups'
    $labels = [ordered]@{
        essentials = 'Essentials (Chrome, VLC, LibreOffice, Obsidian, 7zip, git...)'
        media      = 'Media & Creativity (OBS, GIMP, Krita, Kdenlive, Audacity...)'
        cyber      = 'Cyber Security (nmap, Wireshark, Ghidra...)'
        remote     = 'Remote & Network (AnyDesk, RustDesk, LocalSend, OpenVPN...)'
        power      = 'Power User & Dev (VS Code, Docker, Neovim, PowerToys...)'
    }
    $sel = @()
    foreach ($g in $labels.Keys) {
        $def = Test-ArConConfigListHas -Key 'PKG_GROUPS' -Item $g
        if (Confirm-ArConStep "Install $($labels[$g])" $def) { $sel += $g }
    }
    Set-ArConConfig -Key 'PKG_GROUPS' -Value ($sel -join ',') -Source 'wizard'
}

function Add-ArConPackagesTask {
    $groups = Get-ArConConfigList -Key 'PKG_GROUPS'
    $extra = Get-ArConConfigList -Key 'PKG_EXTRA'
    if (-not $groups -and -not $extra) { Write-ArConInfo 'no package groups selected'; return }
    $res = Resolve-ArConPackageSet -Groups $groups -ExtraIds $extra
    if ($res.Unavailable.Count) {
        Write-ArConWarn "$($res.Unavailable.Count) selected package(s) have no winget equivalent and will be skipped:"
        foreach ($u in $res.Unavailable) { Write-ArConWarn "  - $($u.Id) ($($u.Description))" }
    }
    if (-not $res.Available.Count) { return }
    $pkgs = $res.Available
    Add-ArConTask -Id 'packages.install' -Risk 'low' -Description "Install $($pkgs.Count) package(s) via winget" -Action {
        $r = Install-ArConPackageSet -Packages $pkgs
        if ($script:ArConDryRun) { return $true }
        Write-ArConInfo "packages: $($r.Installed.Count) installed, $($r.Present.Count) already present, $($r.Failed.Count) failed"
        if ($r.Failed.Count) { Write-ArConError "failed packages: $($r.Failed -join ', ')"; return $false }
        return $true
    }.GetNewClosure()
    if (Get-ArConConfigBool -Key 'BASE_UPGRADE' -Default $true) {
        Add-ArConTask -Id 'packages.upgrade' -Risk 'low' -Description 'Upgrade all winget packages' -Action {
            $pm = Get-ArConPackageManager
            if (-not $pm) { return 'skip' }
            if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'PKG_INSTALL' -Detail 'winget upgrade --all'; return $true }
            return $pm.UpgradeAll()
        }
    }
}

# -------------------------------------------------------------------- gaming
function Invoke-GamingWizard {
    $on = Confirm-ArConStep 'Configure Windows gaming settings (Game Mode, power plan, GPU report)' (Get-ArConConfigBool -Key 'GAMING')
    Set-ArConConfig -Key 'GAMING' -Value ($on ? 'yes' : 'no') -Source 'wizard'
}

function Add-ArConGamingTask {
    if (-not (Get-ArConConfigBool -Key 'GAMING')) { return }
    Add-ArConTask -Id 'gaming.gamemode' -Risk 'low' -Description 'Enable Windows Game Mode' -Action {
        $p = 'HKCU:\Software\Microsoft\GameBar'
        $ok = Set-ArConRegistryValue -Path $p -Name 'AllowAutoGameMode' -Value 1 -Description 'Game Mode: AllowAutoGameMode=1'
        $ok = (Set-ArConRegistryValue -Path $p -Name 'AutoGameModeEnabled' -Value 1 -Description 'Game Mode: AutoGameModeEnabled=1') -and $ok
        return $ok
    }
    Add-ArConTask -Id 'gaming.gpu_report' -Risk 'low' -Description 'Report GPU driver and hardware-accelerated GPU scheduling state' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'COMMAND' -Detail 'report GPU driver version and HAGS state (read-only)'; return $true }
        $hw = Get-ArConHardware
        foreach ($g in @(Get-ArConCimInstance -ClassName Win32_VideoController)) {
            Write-Host ("  GPU: {0} -- driver {1} ({2})" -f $g.Name, $g.DriverVersion, $g.DriverDate)
        }
        $hags = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
        Write-Host ("  Hardware-accelerated GPU scheduling: {0}" -f (@{ 1 = 'disabled'; 2 = 'enabled' }[[int]$hags] ?? 'not configured'))
        Write-Host '  ArCoN does not promise FPS gains; GPU drivers must come from the vendor or Windows Update.' -ForegroundColor DarkGray
        if ($hw.GpuVendors -contains 'nvidia') { Write-Host '  NVIDIA driver downloads: https://www.nvidia.com/Download/index.aspx' -ForegroundColor DarkGray }
        if ($hw.GpuVendors -contains 'amd')    { Write-Host '  AMD driver downloads: https://www.amd.com/en/support' -ForegroundColor DarkGray }
        return $true
    }
}

# ------------------------------------------------------------------ security
function Invoke-SecurityWizard {
    $mode = Select-ArConOption -Prompt '=== WINDOWS SECURITY ===' -Default (Get-ArConConfig -Key 'WIN_DEFENDER' -Default 'report') -Options ([ordered]@{
        report  = 'Report only (show Defender/Firewall/BitLocker/UAC state, change nothing)'
        enforce = 'Enforce recommended settings (enable Defender realtime protection + firewall)'
        skip    = 'Skip the security module'
    })
    Set-ArConConfig -Key 'WIN_DEFENDER' -Value $mode -Source 'wizard'
}

function Add-ArConSecurityTask {
    $mode = Get-ArConConfig -Key 'WIN_DEFENDER' -Default 'report'
    if ($mode -eq 'skip') { return }

    Add-ArConTask -Id 'security.report' -Risk 'low' -Description 'Report Defender, Firewall, BitLocker, SmartScreen and UAC state' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'COMMAND' -Detail 'read-only security report'; return $true }
        $rows = @()
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $rows += [pscustomobject]@{ Item = 'Defender realtime protection'; Status = $mp.RealTimeProtectionEnabled }
            $rows += [pscustomobject]@{ Item = 'Defender antivirus enabled';   Status = $mp.AntivirusEnabled }
            $rows += [pscustomobject]@{ Item = 'Defender signature age (days)'; Status = $mp.AntivirusSignatureAge }
        } catch { $rows += [pscustomobject]@{ Item = 'Defender'; Status = "query failed: $($_.Exception.Message)" } }
        try {
            foreach ($p in Get-NetFirewallProfile -ErrorAction Stop) {
                $rows += [pscustomobject]@{ Item = "Firewall profile $($p.Name)"; Status = ($p.Enabled ? 'enabled' : 'DISABLED') }
            }
        } catch { $rows += [pscustomobject]@{ Item = 'Firewall'; Status = 'query failed' } }
        try {
            foreach ($v in Get-BitLockerVolume -ErrorAction Stop) {
                $rows += [pscustomobject]@{ Item = "BitLocker $($v.MountPoint)"; Status = $v.ProtectionStatus }
            }
        } catch { $rows += [pscustomobject]@{ Item = 'BitLocker'; Status = 'not available (requires admin / supported edition)' } }
        $uac = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -ErrorAction SilentlyContinue).EnableLUA
        $rows += [pscustomobject]@{ Item = 'UAC (EnableLUA)'; Status = ($uac -eq 1 ? 'enabled' : 'DISABLED -- re-enable it') }
        $hw = Get-ArConHardware
        $rows += [pscustomobject]@{ Item = 'Secure Boot'; Status = $hw.SecureBoot }
        Write-ArConTable -Rows $rows
        foreach ($r in $rows) { Write-ArConDebug "security: $($r.Item) = $($r.Status)" }
        return $true
    }

    if ($mode -ne 'enforce') { return }

    Add-ArConTask -Id 'security.defender' -Risk 'medium' -Description 'Enable Defender real-time protection' -Action {
        try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { Write-ArConWarn 'Defender is not available (third-party AV?)'; return 'skip' }
        if ($mp.RealTimeProtectionEnabled) { Write-ArConInfo 'Defender real-time protection is already enabled'; return $true }
        return Invoke-ArConCommand -Category 'SETTING' -Description 'Set-MpPreference -DisableRealtimeMonitoring $false' -RequiresAdmin -Action {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        } -Verify { (Get-MpComputerStatus).RealTimeProtectionEnabled }
    }

    Add-ArConTask -Id 'security.firewall' -Risk 'medium' -Description 'Enable the Windows Firewall for all profiles' -Action {
        try { $profiles = @(Get-NetFirewallProfile -ErrorAction Stop) } catch { Write-ArConWarn 'firewall cmdlets unavailable'; return 'skip' }
        $off = @($profiles | Where-Object { -not $_.Enabled })
        if (-not $off.Count) { Write-ArConInfo 'firewall is already enabled for all profiles'; return $true }
        return Invoke-ArConCommand -Category 'SERVICE' -Description "enable firewall for: $($off.Name -join ', ')" -RequiresAdmin -Action {
            Set-NetFirewallProfile -Name $off.Name -Enabled True -ErrorAction Stop
        }.GetNewClosure() -Verify { -not (@(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count) }
    }

    Add-ArConTask -Id 'security.bitlocker_report' -Risk 'low' -Description 'Check BitLocker status (encryption is never started automatically)' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'COMMAND' -Detail 'report BitLocker status (read-only)'; return $true }
        try { $vols = @(Get-BitLockerVolume -ErrorAction Stop) } catch { Write-ArConWarn 'BitLocker status unavailable (edition/admin)'; return 'skip' }
        foreach ($v in $vols) {
            Write-Host ("  {0} protection: {1}, method: {2}" -f $v.MountPoint, $v.ProtectionStatus, $v.EncryptionMethod)
        }
        Write-Host '  Enabling BitLocker changes disk encryption and recovery keys; ArCoN leaves that decision to you.' -ForegroundColor DarkGray
        return $true
    }
}

# ------------------------------------------------------------------ optimize
function Invoke-OptimizeWizard {
    $lvl = Select-ArConOption -Prompt '=== OPTIMIZATION LEVEL ===' -Default (Get-ArConConfig -Key 'OPT_PROFILE' -Default 'minimal') -Options ([ordered]@{
        minimal     = 'Minimal (reports only)'
        balanced    = 'Balanced (temp cleanup + reports)'
        performance = 'Performance (high performance power plan + cleanup)'
        gaming      = 'Gaming (performance plan + Game Mode)'
        developer   = 'Developer (cleanup + startup report)'
        security    = 'Security (reports only)'
    })
    Set-ArConConfig -Key 'OPT_PROFILE' -Value $lvl -Source 'wizard'
}

function Add-ArConOptimizeTask {
    $p = Get-ArConConfig -Key 'OPT_PROFILE' -Default 'minimal'

    Add-ArConTask -Id 'optimize.startup_report' -Risk 'low' -Description 'Report startup programs and slow boot contributors' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail 'report startup programs (read-only)'; return $true }
        $rows = @()
        foreach ($k in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')) {
            $item = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($prop in $item.PSObject.Properties) {
                if ($prop.Name -like 'PS*') { continue }
                $rows += [pscustomobject]@{ Hive = ($k -split ':')[0]; Name = $prop.Name; Command = $prop.Value }
            }
        }
        if ($rows.Count) { Write-ArConTable -Rows $rows } else { Write-Host '  no Run-key startup entries found' }
        Write-Host '  ArCoN does not disable startup entries automatically: that would break installed software.' -ForegroundColor DarkGray
        return $true
    }

    if ($p -in @('performance', 'gaming')) {
        Add-ArConTask -Id 'optimize.power_plan' -Risk 'medium' -Description 'Activate the High performance power plan' -Action {
            $hw = Get-ArConHardware
            if ($hw.IsLaptop -and $hw.Power -eq 'battery') { Write-ArConInfo 'laptop on battery -- power plan unchanged'; return 'skip' }
            $target = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # High performance (built-in GUID)
            $out = & powercfg.exe /getactivescheme 2>&1
            $current = ([regex]::Match(($out -join ' '), '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')).Value
            if ($current -eq $target) { Write-ArConInfo 'High performance plan is already active'; return $true }
            if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail "power plan $current -> High performance ($target)"; return $true }
            Add-ArConRollbackEntry -Type 'POWERPLAN' -Data @($current)
            & powercfg.exe /setactive $target *> $null
            if ($LASTEXITCODE -ne 0) { Write-ArConError "powercfg /setactive failed (exit $LASTEXITCODE)"; return $false }
            $after = ([regex]::Match((& powercfg.exe /getactivescheme 2>&1) -join ' ', '([0-9a-f-]{36})')).Value
            if ($after -ne $target) { Write-ArConError 'power plan did not change'; return $false }
            Write-ArConResult -Operation 'power plan' -Result PASS "$current -> $target"
            return $true
        }
    }

    if ($p -in @('balanced', 'performance', 'gaming', 'developer')) {
        Add-ArConTask -Id 'optimize.temp_cleanup' -Risk 'low' -Description 'Delete temporary files older than 7 days (user + Windows TEMP)' -Action {
            $targets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
            $cut = (Get-Date).AddDays(-7)
            $files = @()
            foreach ($t in $targets) {
                $files += Get-ChildItem -LiteralPath $t -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -lt $cut }
            }
            $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
            if (-not $files.Count) { Write-ArConInfo 'no temporary files older than 7 days'; return $true }
            if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail "delete $($files.Count) temp file(s), $mb MB"; return $true }
            Add-ArConIrreversibleNote "deleted $($files.Count) temporary files ($mb MB)"
            $removed = 0
            foreach ($f in $files) {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++ } catch { Write-ArConDebug "in use, kept: $($f.FullName)" }
            }
            Write-ArConResult -Operation 'temp cleanup' -Result PASS "$removed of $($files.Count) files removed ($mb MB)"
            return $true
        }
    }

    Add-ArConTask -Id 'optimize.trim_report' -Risk 'low' -Description 'Report storage optimization (TRIM / defrag) state' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail 'report TRIM/defrag schedule (read-only)'; return $true }
        $hw = Get-ArConHardware
        $dt = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'DisableDeleteNotify' -ErrorAction SilentlyContinue).DisableDeleteNotify
        Write-Host ("  System disk type: {0}; TRIM (DisableDeleteNotify): {1}" -f $hw.DiskType, ($dt -eq 0 ? 'enabled' : "$dt"))
        $task = Get-ScheduledTask -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
        Write-Host ("  Scheduled 'Optimize Drives' task: {0}" -f ($task ? $task.State : 'not found'))
        return $true
    }
}

# ------------------------------------------------------------------- cleanup
function Add-ArConCleanupTask {
    if (-not (Get-ArConConfigBool -Key 'CLEANUP')) { return }
    Add-ArConTask -Id 'cleanup.winget_cache' -Risk 'low' -Description 'Remove the winget installer download cache' -Action {
        $cache = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\tempDownloads'
        if (-not (Test-Path -LiteralPath $cache)) { Write-ArConInfo 'no winget download cache present'; return 'skip' }
        $files = @(Get-ChildItem -LiteralPath $cache -Recurse -File -ErrorAction SilentlyContinue)
        $mb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        if (-not $files.Count) { return 'skip' }
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail "remove winget cache ($($files.Count) files, $mb MB)"; return $true }
        Add-ArConIrreversibleNote "removed winget download cache ($mb MB)"
        Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }
    Add-ArConTask -Id 'cleanup.recycle_report' -Risk 'low' -Description 'Report Recycle Bin size (never emptied automatically)' -Action {
        if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'OPTIMIZE' -Detail 'report Recycle Bin size (read-only)'; return $true }
        try {
            $shell = New-Object -ComObject Shell.Application
            $bin = $shell.Namespace(0xA)
            $size = 0; $n = 0
            foreach ($i in $bin.Items()) { $size += $i.Size; $n++ }
            Write-Host ("  Recycle Bin: {0} item(s), {1} MB" -f $n, [math]::Round($size / 1MB, 1))
        } catch { Write-ArConWarn 'could not read the Recycle Bin' }
        return $true
    }
}

# ------------------------------------------------------------------- summary
function Show-ArConSummary {
    Write-ArConHeader 'INSTALLATION SUMMARY'
    $hw = Get-ArConHardware
    $status = {
        param($prefix)
        $t = @($script:Tasks | Where-Object { $_.Id -like "$prefix*" })
        if (-not $t.Count) { return 'Not selected' }
        if (@($t | Where-Object { $_.Status -eq 'failed' }).Count) { return 'FAILED (see log)' }
        if (@($t | Where-Object { $_.Status -eq 'done' }).Count) { return 'Applied' }
        if (@($t | Where-Object { $_.Status -eq 'skipped' }).Count) { return 'Skipped' }
        return 'Not completed'
    }
    $rows = @(
        [pscustomobject]@{ Item = 'OS';            Status = "$($hw.Os) build $($hw.OsBuild) ($(Get-ArConWindowsTier))" }
        [pscustomobject]@{ Item = 'Packages';      Status = (& $status 'packages.') }
        [pscustomobject]@{ Item = 'Gaming';        Status = (& $status 'gaming.') }
        [pscustomobject]@{ Item = 'Security';      Status = (& $status 'security.') }
        [pscustomobject]@{ Item = 'Optimizations'; Status = (& $status 'optimize.') }
        [pscustomobject]@{ Item = 'Cleanup';       Status = (& $status 'cleanup.') }
        [pscustomobject]@{ Item = 'GPU';           Status = ($hw.GpuNames -join '; ') }
        [pscustomobject]@{ Item = 'Log file';      Status = (Get-ArConLogFile) }
        [pscustomobject]@{ Item = 'Run directory'; Status = $script:RunDir }
    )
    Write-ArConTable -Rows $rows
    $failed = @($script:Tasks | Where-Object { $_.Status -eq 'failed' }).Count
    if ($failed -eq 0) { Write-Host 'Installation complete.' -ForegroundColor Green }
    else { Write-Host "Finished with $failed failed step(s). Fix the cause and re-run with -Resume, or undo with -Rollback." -ForegroundColor Red }
}
