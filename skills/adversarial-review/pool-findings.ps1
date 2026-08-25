#Requires -Version 7
# Shared finding-block splitter, dot-sourced by run-review.ps1 (pooling) and by
# test/verify-start-patterns.ps1 (contract test). Lives in its own file precisely so
# the test exercises the SAME code the driver runs — a restated copy would drift and
# the test would pass while the driver pooled something else.

# The Phase-1 admission start pattern. Pooling splits on exactly the pattern that
# admitted the reviewer: previously the pooler opened a block only on the literal
# '^### ', so admitted forms ('## ', '#### ', '- ### ', '  ### ', '**###**') pooled
# ZERO findings while the vendor still counted toward minVendors.
$script:FindingHeadingPattern = '^\s*(?:[-*+]\s+)?(?:\*\*|__)?#{1,6}\s'

function Split-FindingBlocks([string] $Text) {
    # Returns one string per finding block in a reviewer's stripped Phase-1 output,
    # each normalised to open with the canonical '### ' heading. Two rules beyond the
    # split itself:
    #   - every matched heading line is rewritten to '### ' before storing, so
    #     downstream counts (issuesRaised) and the judge see one canonical form;
    #   - a '#'-line inside a fenced code block (``` or ~~~) is CONTENT, not a
    #     finding boundary — fence state is tracked so it never splits a finding.
    $blocks = @()
    $current = $null
    $inFence = $false
    foreach ($ln in ($Text -split "`r?`n")) {
        if ($ln -match '^\s*(`{3,}|~{3,})') { $inFence = -not $inFence }
        $isHeading = (-not $inFence) -and ($ln -match $script:FindingHeadingPattern)
        if ($isHeading) {
            if ($current) { $blocks += , ($current -join "`n") }
            $current = [System.Collections.Generic.List[string]]::new()
            $ln = $ln -replace $script:FindingHeadingPattern, '### '
        }
        if ($isHeading -or $current) { $current.Add($ln) }
    }
    if ($current) { $blocks += , ($current -join "`n") }
    # ,$blocks keeps a single block from unrolling to a scalar and an empty result
    # from arriving at the caller as $null.
    return , $blocks
}
