@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Interactive console tool: coloured Write-Host output is the UI, by design.
        'PSAvoidUsingWriteHost',
        # Module-internal helper names follow the ArCoN verb-noun scheme; several
        # (e.g. Add-ArConTask) intentionally do not implement ShouldProcess because
        # -DryRun is the documented, tested preview mechanism (docs/ARCHITECTURE.md).
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
