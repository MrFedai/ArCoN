# ArCoN v3.0 (Windows) -- Private/Logging.ps1
# Structured logging with the same record format as the POSIX core:
#   2026-09-23T18:00:00+03:00 [LEVEL] [module] message

$script:LogFile = $null
$script:LogLevel = 'Info'
$script:LevelRank = @{ Debug = 10; Info = 20; Warn = 30; Error = 40 }

function Initialize-ArConLog {
    [CmdletBinding()]
    param(
        [string] $Path,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')] [string] $Level = 'Info'
    )
    $script:LogLevel = $Level
    if (-not $Path) {
        $dir = Join-Path $script:ArConState 'logs'
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $Path = Join-Path $dir ("arcon-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID)
        # keep the last 20 logs only
        Get-ChildItem -LiteralPath $dir -Filter 'arcon-*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 20 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $script:LogFile = $Path
    @(
        "# ArCoN $($script:ArConVersion) log (Windows)"
        "# started: $(Get-Date -Format 'o')"
        "# argv: $($script:ArConArgv)"
        "# host: PowerShell $($PSVersionTable.PSVersion) on $([System.Environment]::OSVersion.VersionString)"
    ) | Set-Content -LiteralPath $script:LogFile -Encoding utf8
    return $script:LogFile
}

function Get-ArConLogFile { $script:LogFile }

function Write-ArConLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Debug', 'Info', 'Warn', 'Error')] [string] $Level,
        [Parameter(Mandatory)] [string] $Message,
        [string] $Module = $script:ArConModule
    )
    $stamp = Get-Date -Format 'o'
    $line = "{0} [{1,-5}] [{2}] {3}" -f $stamp, $Level.ToUpperInvariant(), ($Module ? $Module : 'core'), $Message
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8 }
    if ($script:LevelRank[$Level] -lt $script:LevelRank[$script:LogLevel]) { return }
    switch ($Level) {
        'Debug' { Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray }
        'Info'  { Write-Host "[INFO] $Message" -ForegroundColor Blue }
        'Warn'  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'Error' { Write-Host "[ERROR] $Message" -ForegroundColor Red }
    }
}

function Write-ArConDebug { param([string] $Message) Write-ArConLog -Level Debug -Message $Message }
function Write-ArConInfo  { param([string] $Message) Write-ArConLog -Level Info  -Message $Message }
function Write-ArConWarn  { param([string] $Message) Write-ArConLog -Level Warn  -Message $Message }
function Write-ArConError { param([string] $Message) Write-ArConLog -Level Error -Message $Message }

# Result of a verifiable operation: PASS / FAIL / SKIP (never "success" on failure)
function Write-ArConResult {
    param(
        [Parameter(Mandatory)] [string] $Operation,
        [Parameter(Mandatory)] [ValidateSet('PASS', 'FAIL', 'SKIP')] [string] $Result,
        [string] $Detail = ''
    )
    $msg = "{0} {1}{2}" -f $Result, $Operation, ($Detail ? " -- $Detail" : '')
    switch ($Result) {
        'PASS' { Write-ArConLog -Level Info -Message $msg; Write-Host "  [OK] $Operation" -ForegroundColor Green }
        'SKIP' { Write-ArConLog -Level Info -Message $msg; Write-Host "  [SKIP] $Operation $Detail" -ForegroundColor DarkGray }
        'FAIL' { Write-ArConLog -Level Error -Message $msg; Write-Host "  [FAIL] $Operation $Detail" -ForegroundColor Red }
    }
}
