# ArCoN v3.0 (Windows) -- Private/Hardware.ps1
# HardwareDetector for Windows, built on CIM/WMI + native APIs only (no parsing
# of localised command output). Mockable: every CIM call goes through
# Get-ArConCimInstance, which Pester replaces in unit tests, and
# $env:ARCON_HW_MOCK (KEY=VALUE file) overrides the result completely.

function Get-ArConCimInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ClassName, [string] $Namespace = 'root/cimv2')
    Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop
}

function Get-ArConHardware {
    [CmdletBinding()]
    param([switch] $Force)
    if ($script:Hardware -and -not $Force) { return $script:Hardware }

    $hw = [ordered]@{
        Os = 'unknown'; OsVersion = 'unknown'; OsBuild = 'unknown'; OsEdition = 'unknown'
        Arch = 'unknown'; CpuVendor = 'unknown'; CpuModel = 'unknown'; CpuCores = 0; CpuThreads = 0
        GpuVendors = @(); GpuNames = @(); RamMb = 0
        DiskType = 'unknown'; DiskFreeGb = 0; RootFs = 'unknown'
        NetAdapters = @(); Virtualization = 'unknown'; SecureBoot = 'unknown'
        IsLaptop = $false; Power = 'unknown'; IsAdmin = $false; PowerShell = $PSVersionTable.PSVersion.ToString()
    }

    if ($env:ARCON_HW_MOCK) {
        foreach ($kv in (Read-ArConConfFile -Path $env:ARCON_HW_MOCK).GetEnumerator()) {
            $key = ($kv.Key -replace '^HW_', '')
            $name = ($key.ToLowerInvariant() -split '_' | ForEach-Object { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }) -join ''
            if ($hw.Contains($name)) { $hw[$name] = $kv.Value }
        }
        $script:Hardware = [pscustomobject] $hw
        Write-ArConDebug "hardware from mock: $($env:ARCON_HW_MOCK)"
        return $script:Hardware
    }

    try {
        $os = Get-ArConCimInstance -ClassName Win32_OperatingSystem
        $hw.Os        = $os.Caption
        $hw.OsVersion = $os.Version
        $hw.OsBuild   = $os.BuildNumber
        $hw.OsEdition = $os.OperatingSystemSKU
        $hw.Arch      = $os.OSArchitecture
    } catch { Write-ArConWarn "Win32_OperatingSystem query failed: $($_.Exception.Message)" }

    try {
        $cs = Get-ArConCimInstance -ClassName Win32_ComputerSystem
        $hw.RamMb = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        # PCSystemType: 2 = Mobile/laptop
        $hw.IsLaptop = ($cs.PCSystemType -eq 2)
        switch -Regex ($cs.Model) {
            'Virtual Machine|Hyper-V'      { $hw.Virtualization = 'hyper-v' }
            'VMware'                       { $hw.Virtualization = 'vmware' }
            'VirtualBox'                   { $hw.Virtualization = 'virtualbox' }
            'KVM|QEMU'                     { $hw.Virtualization = 'kvm' }
            default                        { $hw.Virtualization = 'none' }
        }
    } catch { Write-ArConWarn "Win32_ComputerSystem query failed: $($_.Exception.Message)" }

    try {
        $cpu = @(Get-ArConCimInstance -ClassName Win32_Processor)[0]
        $hw.CpuModel   = $cpu.Name.Trim()
        $hw.CpuCores   = [int] $cpu.NumberOfCores
        $hw.CpuThreads = [int] $cpu.NumberOfLogicalProcessors
        $hw.CpuVendor  = switch -Regex ($cpu.Manufacturer) {
            'Intel'        { 'intel' }
            'AMD|Advanced' { 'amd' }
            'Qualcomm|ARM' { 'arm' }
            default        { 'unknown' }
        }
    } catch { Write-ArConWarn "Win32_Processor query failed: $($_.Exception.Message)" }

    try {
        $vendors = @(); $names = @()
        foreach ($gpu in @(Get-ArConCimInstance -ClassName Win32_VideoController)) {
            $names += $gpu.Name
            switch -Regex ($gpu.Name) {
                'NVIDIA|GeForce|Quadro|RTX|GTX' { $vendors += 'nvidia' }
                'AMD|Radeon|ATI'                { $vendors += 'amd' }
                'Intel'                         { $vendors += 'intel' }
                'Microsoft Basic|Hyper-V|VMware|VirtualBox' { $vendors += 'virtual' }
                default                         { $vendors += 'unknown' }
            }
        }
        $hw.GpuVendors = @($vendors | Select-Object -Unique)
        $hw.GpuNames   = $names
    } catch { Write-ArConWarn "Win32_VideoController query failed: $($_.Exception.Message)" }

    try {
        $sysDrive = ($env:SystemDrive ? $env:SystemDrive : 'C:')
        $vol = Get-ArConCimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $sysDrive }
        if ($vol) {
            $hw.DiskFreeGb = [math]::Round($vol.FreeSpace / 1GB)
            $hw.RootFs = $vol.FileSystem
        }
        # MSFT_PhysicalDisk.MediaType: 3 = HDD, 4 = SSD, 5 = SCM; BusType 17 = NVMe
        $pd = @(Get-ArConCimInstance -ClassName MSFT_PhysicalDisk -Namespace 'root/microsoft/windows/storage')
        if ($pd.Count) {
            $primary = $pd | Sort-Object DeviceId | Select-Object -First 1
            $hw.DiskType = switch ([int] $primary.MediaType) {
                3 { 'hdd' } 4 { if ([int] $primary.BusType -eq 17) { 'nvme' } else { 'ssd' } } 5 { 'scm' } default { 'unknown' }
            }
        }
    } catch { Write-ArConDebug "storage query incomplete: $($_.Exception.Message)" }

    try {
        $hw.NetAdapters = @(Get-ArConCimInstance -ClassName Win32_NetworkAdapter |
            Where-Object { $_.PhysicalAdapter -and $_.NetEnabled } | ForEach-Object { $_.Name })
    } catch { Write-ArConDebug 'network adapter query failed' }

    try {
        $hw.SecureBoot = (Confirm-SecureBootUEFI) ? 'enabled' : 'disabled'
    } catch {
        # Confirm-SecureBootUEFI throws on legacy BIOS systems and without admin rights
        $hw.SecureBoot = if ($_.Exception.Message -match 'not supported') { 'unsupported-bios' } else { 'unknown' }
    }

    try {
        $bat = @(Get-ArConCimInstance -ClassName Win32_Battery)
        if ($bat.Count) {
            $hw.IsLaptop = $true
            # BatteryStatus 2 = on AC
            $hw.Power = ([int] $bat[0].BatteryStatus -eq 2) ? 'ac' : 'battery'
        } else { $hw.Power = 'ac' }
    } catch { Write-ArConDebug 'battery query failed' }

    $hw.IsAdmin = Test-ArConAdmin
    $script:Hardware = [pscustomobject] $hw
    Write-ArConDebug ("hardware: " + (($hw.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
    return $script:Hardware
}

function Test-ArConAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Write-ArConHardwareSummary {
    $hw = Get-ArConHardware
    Write-Host ("  OS:     {0} (build {1}, {2})" -f $hw.Os, $hw.OsBuild, $hw.Arch)
    Write-Host ("  CPU:    {0} [{1}] {2}C/{3}T" -f $hw.CpuModel, $hw.CpuVendor, $hw.CpuCores, $hw.CpuThreads)
    Write-Host ("  GPU:    {0} -- {1}" -f (($hw.GpuVendors -join ' ')), ($hw.GpuNames -join '; '))
    Write-Host ("  RAM:    {0} GB" -f [math]::Round($hw.RamMb / 1024))
    Write-Host ("  Disk:   {0} ({1}), {2} GB free on {3}" -f $hw.DiskType, $hw.RootFs, $hw.DiskFreeGb, $env:SystemDrive)
    Write-Host ("  Virt:   {0}   SecureBoot: {1}   Laptop: {2}   Admin: {3}" -f $hw.Virtualization, $hw.SecureBoot, $hw.IsLaptop, $hw.IsAdmin)
}

# Windows 11 = build >= 22000; Windows 10 = 10240..21999 (supported where practical)
function Get-ArConWindowsTier {
    $hw = Get-ArConHardware
    $build = 0
    [void][int]::TryParse([string] $hw.OsBuild, [ref] $build)
    if ($build -ge 22000) { return 'tested' }        # Windows 11
    if ($build -ge 19041) { return 'experimental' }  # Windows 10 2004+
    return 'unsupported'
}
