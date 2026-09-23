# Parses every PowerShell file in the repository and fails on any syntax error.
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1, *.psd1 -File |
    Where-Object { $_.FullName -notmatch '[\\/](legacy|\.git)[\\/]' }
$bad = 0
foreach ($f in $files) {
    $errors = $null; $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) {
        $bad++
        Write-Host "PARSE ERRORS in $($f.FullName)" -ForegroundColor Red
        $errors | ForEach-Object { "  line $($_.Extent.StartLineNumber): $($_.Message)" }
    }
}
Write-Host ("{0} file(s) parsed, {1} with errors" -f $files.Count, $bad)
exit ([int]($bad -gt 0))
