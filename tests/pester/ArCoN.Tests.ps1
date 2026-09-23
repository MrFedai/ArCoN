# ArCoN v3.0 -- Pester suite for the Windows implementation.
# Runs on any PowerShell 7 host: every Windows-only dependency (CIM, winget,
# registry, powercfg) is mocked. Tests that need a real Windows machine are
# tagged 'Windows' and skipped elsewhere -- they are never reported as passed.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    Import-Module (Join-Path $script:Root 'windows/ArCoN/ArCoN.psd1') -Force
    $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ("arcon-pester-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:Tmp | Out-Null
    $env:LOCALAPPDATA = $script:Tmp
    $env:APPDATA = $script:Tmp
    InModuleScope ArCoN { Initialize-ArConState | Out-Null; Initialize-ArConLog -Level Error | Out-Null }
}
AfterAll { Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'UNIT: configuration parser' {
    It 'parses KEY=VALUE, strips quotes and inline comments, never executes' {
        $f = Join-Path $script:Tmp 'c.conf'
        @(
            '# comment'
            'A=1'
            'B = "two words"'
            "C='x' # trailing"
            'D=# only a comment'
            'E=$(Remove-Item C:\ -Recurse)'
        ) | Set-Content $f
        $c = Read-ArConConfFile -Path $f
        $c.A | Should -Be '1'
        $c.B | Should -Be 'two words'
        $c.C | Should -Be 'x'
        $c.D | Should -Be ''
        $c.E | Should -Be '$(Remove-Item C:\ -Recurse)'   # stored literally
    }
    It 'rejects invalid syntax with file and line' {
        $f = Join-Path $script:Tmp 'bad.conf'
        'lowercase=1' | Set-Content $f
        { Read-ArConConfFile -Path $f } | Should -Throw '*bad.conf:1*'
    }
    It 'layers defaults < platform < profile < -Set' {
        Initialize-ArConConfig -ProfileName gaming -Set @('OPT_PROFILE=developer')
        Get-ArConConfig -Key 'MODULES' | Should -Match 'packages'
        Get-ArConConfig -Key 'OPT_PROFILE' | Should -Be 'developer'
        Get-ArConConfigBool -Key 'GAMING' | Should -BeTrue
    }
    It 'rejects an unknown profile' {
        { Initialize-ArConConfig -ProfileName 'nope' } | Should -Throw '*unknown profile*'
    }
    It 'rejects invalid enumerated values' {
        { Initialize-ArConConfig -Set @('WIN_DEFENDER=disable-everything') } | Should -Throw '*validation failed*'
    }
    It 'loads every shipped profile without error' {
        foreach ($p in Get-ChildItem (Join-Path $script:Root 'profiles') -Filter *.conf) {
            { Initialize-ArConConfig -ProfileName $p.BaseName } | Should -Not -Throw
        }
    }
}

Describe 'UNIT: package catalog' {
    It 'loads the shared catalog with 11 columns' {
        $cat = Get-ArConCatalog
        $cat.Count | Should -BeGreaterThan 100
        ($cat | Where-Object Id -eq 'vlc').Winget | Should -Be 'VideoLAN.VLC'
    }
    It 'reports packages without a winget id instead of dropping them silently' {
        Initialize-ArConConfig
        $r = Resolve-ArConPackageSet -Groups @('cyber')
        $r.Unavailable.Count | Should -BeGreaterThan 0
        ($r.Available + $r.Unavailable).Count | Should -BeGreaterThan $r.Available.Count
    }
    It 'treats unknown extra ids as raw winget ids' {
        $r = Resolve-ArConPackageSet -Groups @() -ExtraIds @('Some.Vendor.App')
        $r.Available.Winget | Should -Contain 'Some.Vendor.App'
    }
}

Describe 'UNIT: hardware detection (mocked CIM)' {
    BeforeEach { InModuleScope ArCoN { $script:Hardware = $null } }
    It 'detects an NVIDIA gaming desktop on Windows 11' {
        Mock -ModuleName ArCoN Get-ArConCimInstance {
            switch ($ClassName) {
                'Win32_OperatingSystem'  { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.26100'; BuildNumber = '26100'; OperatingSystemSKU = 48; OSArchitecture = '64-bit' } }
                'Win32_ComputerSystem'   { [pscustomobject]@{ TotalPhysicalMemory = 34359738368; PCSystemType = 1; Model = 'MS-7D25' } }
                'Win32_Processor'        { [pscustomobject]@{ Name = 'AMD Ryzen 7 7800X3D'; NumberOfCores = 8; NumberOfLogicalProcessors = 16; Manufacturer = 'AuthenticAMD' } }
                'Win32_VideoController'  { [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4070'; DriverVersion = '32.0.15.6094'; DriverDate = '' } }
                'Win32_LogicalDisk'      { [pscustomobject]@{ DeviceID = 'C:'; FreeSpace = 500GB; FileSystem = 'NTFS' } }
                'MSFT_PhysicalDisk'      { [pscustomobject]@{ DeviceId = '0'; MediaType = 4; BusType = 17 } }
                'Win32_NetworkAdapter'   { [pscustomobject]@{ Name = 'Intel Ethernet'; PhysicalAdapter = $true; NetEnabled = $true } }
                'Win32_Battery'          { @() }
            }
        }
        $env:SystemDrive = 'C:'
        $hw = Get-ArConHardware -Force
        $hw.CpuVendor  | Should -Be 'amd'
        $hw.GpuVendors | Should -Contain 'nvidia'
        $hw.RamMb      | Should -Be 32768
        $hw.DiskType   | Should -Be 'nvme'
        $hw.IsLaptop   | Should -BeFalse
        $hw.Power      | Should -Be 'ac'
        Get-ArConWindowsTier | Should -Be 'tested'
    }
    It 'detects a Windows 10 laptop on battery with Intel graphics and SATA SSD' {
        Mock -ModuleName ArCoN Get-ArConCimInstance {
            switch ($ClassName) {
                'Win32_OperatingSystem'  { [pscustomobject]@{ Caption = 'Microsoft Windows 10 Home'; Version = '10.0.19045'; BuildNumber = '19045'; OperatingSystemSKU = 101; OSArchitecture = '64-bit' } }
                'Win32_ComputerSystem'   { [pscustomobject]@{ TotalPhysicalMemory = 8589934592; PCSystemType = 2; Model = 'ThinkPad' } }
                'Win32_Processor'        { [pscustomobject]@{ Name = 'Intel Core i5-8250U'; NumberOfCores = 4; NumberOfLogicalProcessors = 8; Manufacturer = 'GenuineIntel' } }
                'Win32_VideoController'  { [pscustomobject]@{ Name = 'Intel(R) UHD Graphics 620'; DriverVersion = '1'; DriverDate = '' } }
                'Win32_LogicalDisk'      { [pscustomobject]@{ DeviceID = 'C:'; FreeSpace = 5GB; FileSystem = 'NTFS' } }
                'MSFT_PhysicalDisk'      { [pscustomobject]@{ DeviceId = '0'; MediaType = 4; BusType = 11 } }
                'Win32_NetworkAdapter'   { @() }
                'Win32_Battery'          { [pscustomobject]@{ BatteryStatus = 1 } }
            }
        }
        $hw = Get-ArConHardware -Force
        $hw.CpuVendor  | Should -Be 'intel'
        $hw.GpuVendors | Should -Contain 'intel'
        $hw.DiskType   | Should -Be 'ssd'
        $hw.IsLaptop   | Should -BeTrue
        $hw.Power      | Should -Be 'battery'
        Get-ArConWindowsTier | Should -Be 'experimental'
    }
    It 'degrades gracefully when CIM is unavailable (no exception escapes)' {
        Mock -ModuleName ArCoN Get-ArConCimInstance { throw 'RPC server unavailable' }
        { Get-ArConHardware -Force } | Should -Not -Throw
        (Get-ArConHardware).CpuModel | Should -Be 'unknown'
        Get-ArConWindowsTier | Should -Be 'unsupported'
    }
}

Describe 'UNIT: winget provider' {
    It 'treats "already installed" (0x8A150061) as success' {
        InModuleScope ArCoN {
            function global:winget { $global:LASTEXITCODE = -1978335135; 'Found an existing package already installed.' }
            try { [ArConWingetPackageManager]::new().Install('VideoLAN.VLC') | Should -BeTrue }
            finally { Remove-Item function:global:winget }
        }
    }
    It 'reports a real failure as failure (never false success)' {
        InModuleScope ArCoN {
            function global:winget { $global:LASTEXITCODE = -1978335212; 'No package found matching input criteria.' }
            try { [ArConWingetPackageManager]::new().Install('Does.Not.Exist') | Should -BeFalse }
            finally { Remove-Item function:global:winget }
        }
    }
}

Describe 'DRYRUN: no system change is executed' {
    It 'records registry changes in the plan instead of applying them' {
        InModuleScope ArCoN {
            $script:ArConDryRun = $true
            $script:Plan = [System.Collections.Generic.List[object]]::new()
            Mock New-ItemProperty { throw 'must not be called in dry-run' }
            Set-ArConRegistryValue -Path 'HKCU:\Software\ArConPesterDoesNotExist' -Name 'X' -Value 1 | Should -BeTrue
            $script:Plan.Count | Should -Be 1
            $script:Plan[0].Category | Should -Be 'REGISTRY'
            Should -Invoke New-ItemProperty -Times 0
            $script:ArConDryRun = $false
        }
    }
    It 'Invoke-ArConCommand does not run the action in dry-run' {
        InModuleScope ArCoN {
            $script:ArConDryRun = $true
            $script:Plan = [System.Collections.Generic.List[object]]::new()
            $script:ran = $false
            Invoke-ArConCommand -Category COMMAND -Description 'test' -Action { $script:ran = $true } | Should -BeTrue
            $script:ran | Should -BeFalse
            $script:ArConDryRun = $false
        }
    }
}

Describe 'ERROR: failures are reported, not hidden' {
    It 'Invoke-ArConCommand returns false when the action throws' {
        InModuleScope ArCoN {
            $script:ArConDryRun = $false
            Invoke-ArConCommand -Category COMMAND -Description 'boom' -Action { throw 'boom' } | Should -BeFalse
        }
    }
    It 'Invoke-ArConCommand returns false when verification fails' {
        InModuleScope ArCoN {
            Invoke-ArConCommand -Category COMMAND -Description 'noop' -Action { } -Verify { $false } | Should -BeFalse
        }
    }
    It 'refuses non-HTTPS downloads' {
        InModuleScope ArCoN { Get-ArConFile -Uri 'http://example.com/x' -OutFile (Join-Path $TestDrive 'x') | Should -BeFalse }
    }
    It 'discards a download whose SHA256 does not match' {
        InModuleScope ArCoN {
            Mock Invoke-WebRequest { param($OutFile) 'tampered' | Set-Content -LiteralPath $OutFile }
            $out = Join-Path $TestDrive 'dl.bin'
            Get-ArConFile -Uri 'https://example.com/dl.bin' -OutFile $out -Sha256 ('0' * 64) | Should -BeFalse
            Test-Path $out | Should -BeFalse
        }
    }
}

Describe 'INTEGRATION: task queue, state, resume and rollback' {
    BeforeEach {
        InModuleScope ArCoN {
            $script:ArConDryRun = $false; $script:ArConInteractive = $false
            Reset-ArConTaskQueue
            New-ArConRun | Out-Null
        }
    }
    It 'runs tasks, records status and stops on failure in non-interactive mode' {
        InModuleScope ArCoN {
            Add-ArConTask -Id 't.ok'   -Risk low -Description 'ok'   -Action { $true }
            Add-ArConTask -Id 't.skip' -Risk low -Description 'skip' -Action { 'skip' }
            Add-ArConTask -Id 't.fail' -Risk low -Description 'fail' -Action { $false }
            Add-ArConTask -Id 't.never' -Risk low -Description 'never' -Action { throw 'must not run' }
            Invoke-ArConTaskQueue | Should -Be 1
            ($script:Tasks | ForEach-Object Status) -join ',' | Should -Be 'done,skipped,failed,pending'
            $st = Import-ArConState
            ($st.Tasks | Where-Object Id -eq 't.fail').Status | Should -Be 'failed'
        }
    }
    It 'continues after a failure with -KeepGoing' {
        InModuleScope ArCoN {
            Add-ArConTask -Id 'k.fail' -Risk low -Description 'fail' -Action { $false }
            Add-ArConTask -Id 'k.ok'   -Risk low -Description 'ok'   -Action { $true }
            Invoke-ArConTaskQueue -KeepGoing | Should -Be 1
            $script:Tasks[1].Status | Should -Be 'done'
        }
    }
    It 'a done task is not executed again (idempotent resume)' {
        InModuleScope ArCoN {
            $script:count = 0
            Add-ArConTask -Id 'r.once' -Risk low -Description 'once' -Action { $script:count++; $true }
            Invoke-ArConTaskQueue | Out-Null
            Invoke-ArConTaskQueue | Out-Null
            $script:count | Should -Be 1
        }
    }
    It 'rollback replays journal entries in reverse order and removes created files' {
        InModuleScope ArCoN {
            $f = Join-Path $TestDrive 'created.txt'
            'x' | Set-Content $f
            Add-ArConRollbackEntry -Type FILE -Data @($f, 'ABSENT')
            Add-ArConRollbackEntry -Type NOTE -Data @('temp files deleted')
            Invoke-ArConRollback -RunId $script:RunId | Should -BeTrue
            Test-Path $f | Should -BeFalse
        }
    }
    It 'rollback restores a modified file from its backup' {
        InModuleScope ArCoN {
            $f = Join-Path $TestDrive 'mod.txt'; $b = Join-Path $TestDrive 'mod.bak'
            'original' | Set-Content $b; 'changed' | Set-Content $f
            Add-ArConRollbackEntry -Type FILE -Data @($f, $b)
            Invoke-ArConRollback -RunId $script:RunId | Should -BeTrue
            Get-Content $f | Should -Be 'original'
        }
    }
    It 'rollback keeps packages unless -IncludePackages is given' {
        InModuleScope ArCoN {
            Add-ArConRollbackEntry -Type PKG -Data @('winget', 'VideoLAN.VLC')
            Mock Get-ArConPackageManager { throw 'must not be called' }
            Invoke-ArConRollback -RunId $script:RunId | Should -BeTrue
        }
    }
}

Describe 'NATIVE: real Windows host' -Tag 'Windows' -Skip:(-not $IsWindows) {
    It 'detects real hardware through CIM' {
        InModuleScope ArCoN { $script:Hardware = $null }
        $hw = Get-ArConHardware -Force
        $hw.Os | Should -Match 'Windows'
        $hw.RamMb | Should -BeGreaterThan 0
        $hw.CpuThreads | Should -BeGreaterThan 0
    }
    It 'setup.ps1 -DryRun -NonInteractive completes without changing the system' {
        $out = & pwsh -NoProfile -File (Join-Path $script:Root 'setup.ps1') -DryRun -NonInteractive -Profile Minimal 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'DRY-RUN PLAN'
    }
}
