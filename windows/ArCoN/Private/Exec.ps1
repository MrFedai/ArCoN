# ArCoN v3.0 (Windows) -- Private/Exec.ps1
# Single execution gate: in dry-run mode nothing runs, everything is recorded.
# Registry and service changes always journal their previous value first.

function Invoke-ArConCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('PKG_INSTALL', 'PKG_REMOVE', 'FILE', 'REGISTRY', 'SETTING', 'SERVICE', 'OPTIMIZE', 'COMMAND')] [string] $Category,
        [Parameter(Mandatory)] [string] $Description,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [scriptblock] $Verify,
        [switch] $RequiresAdmin
    )
    if ($script:ArConDryRun) {
        Add-ArConPlanEntry -Category $Category -Detail $Description
        return $true
    }
    if ($RequiresAdmin -and -not (Test-ArConAdmin)) {
        Write-ArConError "administrator rights are required: $Description"
        return $false
    }
    Write-ArConDebug "exec: $Description"
    try {
        $out = & $Action 2>&1
        if ($out) { $out | ForEach-Object { Write-ArConDebug "  | $_" } }
    } catch {
        Write-ArConError "$Description -- $($_.Exception.Message)"
        return $false
    }
    if ($Verify) {
        $vr = $false
        try { $vr = & $Verify } catch { $vr = $false }
        if (-not $vr) { Write-ArConError "verification failed after: $Description"; return $false }
        Write-ArConDebug "verified: $Description"
    }
    return $true
}

# Set-ArConRegistryValue: idempotent, journalled, verified.
function Set-ArConRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,          # PowerShell path: HKCU:\Software\...
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')] [string] $Type = 'DWord',
        [string] $Description
    )
    $desc = $Description ? $Description : "$Path\$Name = $Value"
    $current = $null
    try { $current = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $current = $null }
    if ($null -ne $current -and "$current" -eq "$Value") {
        Write-ArConDebug "registry already correct: $desc"
        return $true
    }
    if ($script:ArConDryRun) {
        Add-ArConPlanEntry -Category 'REGISTRY' -Detail ("$desc" + ($null -eq $current ? ' (new value)' : " (was $current)"))
        return $true
    }
    # journal: export the key (or mark it absent) before touching it
    $regPath = ($Path -replace '^HKCU:\\', 'HKCU\') -replace '^HKLM:\\', 'HKLM\'
    Backup-ArConRegistryKey -Path $regPath | Out-Null
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-ArConError "could not set $desc -- $($_.Exception.Message)"
        return $false
    }
    $after = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ("$after" -ne "$Value") { Write-ArConError "registry value did not stick: $desc"; return $false }
    Write-ArConDebug "registry set: $desc"
    return $true
}

function Set-ArConServiceStartup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Automatic', 'Manual', 'Disabled')] [string] $StartupType,
        [switch] $Start
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-ArConWarn "service '$Name' does not exist on this system"; return 'skip' }
    $prev = (Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue).StartMode
    if ($script:ArConDryRun) {
        Add-ArConPlanEntry -Category 'SERVICE' -Detail "$Name startup: $prev -> $StartupType$($Start ? ' (and start)' : '')"
        return $true
    }
    $map = @{ Auto = 'Automatic'; Manual = 'Manual'; Disabled = 'Disabled' }
    Add-ArConRollbackEntry -Type 'SERVICE' -Data @($Name, ($map[$prev] ? $map[$prev] : 'Manual'))
    try {
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        if ($Start) { Start-Service -Name $Name -ErrorAction Stop }
    } catch {
        Write-ArConError "could not configure service '$Name': $($_.Exception.Message)"
        return $false
    }
    return $true
}

# Download with TLS + SHA256 verification (never curl|iex, never unverified code)
function Get-ArConFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $OutFile,
        [string] $Sha256
    )
    if ($Uri -notmatch '^https://') { Write-ArConError "refusing non-HTTPS download: $Uri"; return $false }
    if ($script:ArConDryRun) { Add-ArConPlanEntry -Category 'FILE' -Detail "download $Uri -> $OutFile"; return $true }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-ArConError "download failed ($Uri): $($_.Exception.Message)"
        return $false
    }
    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            Write-ArConError "checksum mismatch for $Uri (expected $Sha256, got $actual) -- file discarded"
            return $false
        }
        Write-ArConInfo "checksum verified for $(Split-Path -Leaf $OutFile)"
    }
    return $true
}

function Test-ArConOnline {
    if ($script:ArConDryRun) { return $true }
    foreach ($u in @('https://github.com', 'https://winget.azureedge.net')) {
        try {
            $r = Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -lt 500) { return $true }
        } catch { continue }
    }
    return $false
}
