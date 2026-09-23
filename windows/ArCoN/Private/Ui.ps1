# ArCoN v3.0 (Windows) -- Private/Ui.ps1
# Console interaction. Every prompt honours -NonInteractive by returning the
# documented default instead of blocking (v2.5 had no non-interactive mode).

function Write-ArConHeader {
    param([Parameter(Mandatory)] [string] $Text)
    Write-Host ''
    Write-Host ('=' * 42) -ForegroundColor Blue
    Write-Host ("  " + $Text) -ForegroundColor Green
    Write-Host ('=' * 42) -ForegroundColor Blue
}

function Write-ArConSection {
    param([Parameter(Mandatory)] [string] $Text)
    Write-Host ''
    Write-Host "--- $Text ---" -ForegroundColor Cyan
}

function Confirm-ArConStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Question,
        [bool] $Default = $false
    )
    if (-not $script:ArConInteractive) {
        Write-ArConDebug "non-interactive: '$Question' -> $Default"
        return $Default
    }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host "  $Question $hint " -ForegroundColor Yellow -NoNewline
        $answer = Read-Host
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch ($answer.Trim().ToLowerInvariant()) {
            'y' { return $true }  'yes' { return $true }
            'n' { return $false } 'no'  { return $false }
            default { Write-Host '  Please answer y or n.' -ForegroundColor Red }
        }
    }
}

# Destructive steps require the exact word, never a bare Enter.
function Confirm-ArConWord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Question,
        [Parameter(Mandatory)] [string] $Word
    )
    if (-not $script:ArConInteractive) {
        if ($script:ArConAssumeDestructive) {
            Write-ArConWarn "non-interactive: destructive step '$Question' allowed by -IUnderstandDestructive"
            return $true
        }
        Write-ArConWarn "non-interactive: destructive step '$Question' refused (use -IUnderstandDestructive)"
        return $false
    }
    Write-Host "  $Question" -ForegroundColor Red
    Write-Host "  Type '$Word' to confirm: " -ForegroundColor Red -NoNewline
    return ((Read-Host).Trim() -ceq $Word)
}

function Select-ArConOption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [hashtable] $Options,   # value -> label
        [Parameter(Mandatory)] [string] $Default
    )
    if (-not $script:ArConInteractive) { return $Default }
    $keys = @($Options.Keys | Sort-Object)
    Write-Host ''
    Write-Host $Prompt -ForegroundColor Cyan
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $mark = if ($keys[$i] -eq $Default) { ' (default)' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $Options[$keys[$i]], $mark)
    }
    while ($true) {
        Write-Host "Select [1-$($keys.Count)]: " -ForegroundColor Yellow -NoNewline
        $answer = Read-Host
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref] $n) -and $n -ge 1 -and $n -le $keys.Count) { return $keys[$n - 1] }
        Write-Host 'Invalid option.' -ForegroundColor Red
    }
}

function Write-ArConProgressBar {
    param([int] $Current, [int] $Total, [string] $Label)
    if ($Total -le 0) { $Total = 1 }
    $pct = [math]::Floor($Current * 100 / $Total)
    Write-Progress -Activity 'ArCoN' -Status $Label -PercentComplete $pct
}

function Write-ArConTable {
    param([Parameter(Mandatory)] [object[]] $Rows)   # [pscustomobject] @{ Item=..; Status=.. }
    $Rows | Format-Table -AutoSize -Wrap | Out-String -Width 120 | Write-Host
}
