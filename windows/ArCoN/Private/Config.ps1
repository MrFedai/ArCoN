# ArCoN v3.0 (Windows) -- Private/Config.ps1
# Reads the SAME data files as the POSIX core: config/defaults.conf,
# config/platform/windows.conf, profiles/<name>.conf and data/packages.catalog.
# KEY=VALUE files are parsed, never executed (no Invoke-Expression anywhere).

function Read-ArConConfFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $n = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $n++
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $m = [regex]::Match($t, '^([A-Z][A-Z0-9_]*)\s*=\s*(.*)$')
        if (-not $m.Success) { throw "invalid configuration syntax at ${Path}:${n}: $line" }
        $v = $m.Groups[2].Value.Trim()
        if ($v.StartsWith('#')) { $v = '' }                       # comment-only value = unset
        elseif ($v -match '\s#') { $v = ($v -split '\s#')[0].Trim() }
        if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $result[$m.Groups[1].Value] = $v
    }
    return $result
}

function Initialize-ArConConfig {
    [CmdletBinding()]
    param(
        [string] $ProfileName,
        [string] $UserConfig,
        [string[]] $Set
    )
    $script:Cfg = [ordered]@{}
    $script:CfgSrc = @{}
    $layers = @(
        @{ Path = (Join-Path $script:ArConRoot 'config/defaults.conf');          Label = 'defaults';        Required = $true }
        @{ Path = (Join-Path $script:ArConRoot 'config/platform/windows.conf');  Label = 'platform/windows'; Required = $true }
    )
    if ($ProfileName) {
        $pf = Join-Path $script:ArConRoot "profiles/$ProfileName.conf"
        if (-not (Test-Path -LiteralPath $pf)) {
            $avail = (Get-ChildItem (Join-Path $script:ArConRoot 'profiles') -Filter '*.conf' | ForEach-Object BaseName) -join ', '
            throw "unknown profile '$ProfileName' (available: $avail)"
        }
        $layers += @{ Path = $pf; Label = "profile/$ProfileName"; Required = $true }
    }
    $layers += @{ Path = (Join-Path $env:APPDATA 'ArCoN/arcon.conf'); Label = 'user'; Required = $false }
    if ($UserConfig) { $layers += @{ Path = $UserConfig; Label = 'cli-config'; Required = $true } }

    foreach ($l in $layers) {
        if ($l.Required -and -not (Test-Path -LiteralPath $l.Path)) { throw "configuration file not found: $($l.Path)" }
        $kv = Read-ArConConfFile -Path $l.Path
        foreach ($k in $kv.Keys) { $script:Cfg[$k] = $kv[$k]; $script:CfgSrc[$k] = $l.Label }
        Write-ArConDebug "loaded config layer $($l.Label)"
    }
    foreach ($s in @($Set)) {
        if (-not $s) { continue }
        if ($s -notmatch '=') { throw "-Set expects KEY=VALUE, got: $s" }
        $k, $v = $s -split '=', 2
        Set-ArConConfig -Key $k.Trim() -Value $v -Source 'cli'
    }
    Test-ArConConfig
}

function Get-ArConConfig {
    param([Parameter(Mandatory)] [string] $Key, [string] $Default = '')
    if ($script:Cfg.Contains($Key)) { return [string] $script:Cfg[$Key] }
    return $Default
}

function Set-ArConConfig {
    param([Parameter(Mandatory)] [string] $Key, [string] $Value, [string] $Source = 'runtime')
    if ($Key -notmatch '^[A-Z][A-Z0-9_]*$') { throw "invalid configuration key: $Key" }
    $script:Cfg[$Key] = $Value
    $script:CfgSrc[$Key] = $Source
}

function Get-ArConConfigBool {
    param([Parameter(Mandatory)] [string] $Key, [bool] $Default = $false)
    $v = Get-ArConConfig -Key $Key -Default ($Default ? 'yes' : 'no')
    return @('yes', 'true', '1', 'on', 'y') -contains $v.ToLowerInvariant()
}

function Get-ArConConfigList {
    param([Parameter(Mandatory)] [string] $Key)
    $v = Get-ArConConfig -Key $Key
    if (-not $v) { return @() }
    return @($v -split '[,\s]+' | Where-Object { $_ })
}

function Test-ArConConfigListHas {
    param([Parameter(Mandatory)] [string] $Key, [Parameter(Mandatory)] [string] $Item)
    return (Get-ArConConfigList -Key $Key) -contains $Item
}

function Get-ArConConfigTable {
    $script:Cfg.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{ Key = $_; Value = $script:Cfg[$_]; Source = $script:CfgSrc[$_] }
    }
}

# Enumerated keys are validated before anything is executed.
function Test-ArConConfig {
    $enums = @{
        WIN_PACKAGE_SOURCE   = @('winget', 'skip')
        WIN_POWER_PLAN       = @('balanced', 'high-performance', 'ultimate', 'skip')
        WIN_DEFENDER         = @('report', 'enforce', 'skip')
        OPT_PROFILE          = @('minimal', 'balanced', 'performance', 'gaming', 'developer', 'security', 'custom')
    }
    $problems = 0
    foreach ($k in $enums.Keys) {
        $v = Get-ArConConfig -Key $k
        if (-not $v) { continue }
        if ($enums[$k] -notcontains $v) {
            Write-ArConError "config $k='$v' is invalid (allowed: $($enums[$k] -join ' ')) [$($script:CfgSrc[$k])]"
            $problems++
        }
    }
    $disk = Get-ArConConfig -Key 'MIN_DISK_GB' -Default '10'
    if ($disk -notmatch '^\d+$') { Write-ArConError 'MIN_DISK_GB must be an integer'; $problems++ }
    if ($problems -gt 0) { throw "configuration validation failed ($problems problem(s))" }
    Write-ArConDebug 'configuration validated'
}

# ------------------------------------------------------------------ catalog
function Get-ArConCatalog {
    if ($script:Catalog) { return $script:Catalog }
    $path = Join-Path $script:ArConRoot 'data/packages.catalog'
    if (-not (Test-Path -LiteralPath $path)) { throw "package catalog missing: $path" }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { continue }
        $f = $line -split '\|'
        if ($f.Count -lt 11) { Write-ArConWarn "catalog line ignored (needs 11 fields): $line"; continue }
        $rows.Add([pscustomobject]@{
            Id          = $f[0].Trim()
            Groups      = @($f[1].Trim() -split ',' | Where-Object { $_ })
            Winget      = $f[8].Trim()
            Description = $f[10].Trim()
        })
    }
    $script:Catalog = $rows
    return $script:Catalog
}

# Resolve selected group ids to winget package ids; unsupported ones are reported,
# never silently dropped (mission rule: no silent feature removal).
function Resolve-ArConPackageSet {
    [CmdletBinding()]
    param([string[]] $Groups, [string[]] $ExtraIds)
    $cat = Get-ArConCatalog
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $cat) {
        if ($Groups -and ($row.Groups | Where-Object { $Groups -contains $_ })) { $selected.Add($row) }
        elseif ($ExtraIds -and $ExtraIds -contains $row.Id) { $selected.Add($row) }
    }
    $available = @(); $unavailable = @()
    foreach ($row in $selected) {
        if ($row.Winget -and $row.Winget -ne '-') { $available += $row } else { $unavailable += $row }
    }
    # ids given with --Set PKG_EXTRA that are not in the catalog are treated as raw winget ids
    foreach ($e in @($ExtraIds)) {
        if (-not ($cat | Where-Object { $_.Id -eq $e })) {
            $available += [pscustomobject]@{ Id = $e; Groups = @(); Winget = $e; Description = 'raw winget id' }
        }
    }
    return [pscustomobject]@{ Available = $available; Unavailable = $unavailable }
}
