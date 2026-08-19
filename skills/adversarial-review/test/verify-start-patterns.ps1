#Requires -Version 7
$ErrorActionPreference = 'Stop'

# Contract test for run-review.ps1's ROUND CONTRACT: the Phase 1 / Phase 2 start patterns that
# decide whether a reviewer counted as participating, and the round timeout that stops one wedged
# slot from stalling a phase forever.
#
# Why this exists: the strict line-initial patterns discarded substantive, repository-backed
# reviews TWICE on formatting alone -- 2026-08-16 (`**F1** ... AGREE`, three anthropic reviews)
# and 2026-08-17 (`**F1: FALSE POSITIVE**`). Both times the reviewer was dropped from the
# participating-vendor count, so every consensus tally for that chunk was wrong. Widening the
# pattern then risks the opposite failure -- admitting narration as a verdict block -- so both
# directions are pinned here.

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-review.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw "run-review.ps1 not found at $scriptPath" }
$source = Get-Content -LiteralPath $scriptPath -Raw

function Get-InvokeRoundPattern([string] $phase) {
    # Pull the literal the script actually passes, rather than restating it here -- a copy would
    # drift and the test would pass while the driver used something else.
    $match = [regex]::Match($source, "(?m)^\`$${phase}ok = Invoke-Round '$phase' '(?<pattern>.+?)'\s")
    if (-not $match.Success) { throw "could not find the Invoke-Round call for phase '$phase'" }
    $match.Groups['pattern'].Value
}

$failures = @()
function Check([string] $label, [string] $pattern, [string] $line, [bool] $expected) {
    $actual = [bool]($line -match $pattern)
    if ($actual -ne $expected) {
        $script:failures += "[$label] '$line' -> match=$actual, expected=$expected"
    }
}

# --- Phase 1: findings are '### ' headings -----------------------------------
$p1 = Get-InvokeRoundPattern 'p1'
Check 'p1' $p1 '### Missing JSON serialization metadata' $true
Check 'p1' $p1 '  ### Indented heading' $true
Check 'p1' $p1 '- ### Heading in a list item' $true
Check 'p1' $p1 '#### Deeper heading' $true
Check 'p1' $p1 'I will now review the diff.' $false
Check 'p1' $p1 'Here are my findings:' $false

# --- Phase 2: per-finding verdicts, however the reviewer emphasises them ------
$p2 = Get-InvokeRoundPattern 'p2'

# MUST match. Each of these was emitted by a real reviewer; the first two are the exact forms
# that were wrongly discarded on 2026-08-17 and 2026-08-16 respectively.
Check 'p2' $p2 '**F1: FALSE POSITIVE**' $true
Check 'p2' $p2 '**F12** ... AGREE' $true
Check 'p2' $p2 'F1: AGREE - real' $true
Check 'p2' $p2 '__F7__ REFUTED' $true
Check 'p2' $p2 '- **F3.** disagree' $true
Check 'p2' $p2 'F9) needs evidence' $true
Check 'p2' $p2 '### Verdicts' $true

# MUST NOT match. Narration and prose that merely mentions an F-number is not a verdict block;
# admitting it would count a reviewer that contributed nothing as a participating vendor.
Check 'p2' $p2 'F12 and F13 both agree with this' $false
Check 'p2' $p2 'F5 findings were raised in total' $false
Check 'p2' $p2 'I will now review the diff.' $false
Check 'p2' $p2 'Adversarial verdict pass. Skills not applicable' $false
Check 'p2' $p2 'FIXME: this is prose' $false

# --- Round timeout -----------------------------------------------------------
if ($source -notmatch '\[int\]\s*\$RoundTimeoutSeconds\s*=\s*(?<default>\d+)') {
    $failures += 'RoundTimeoutSeconds parameter is missing: a wedged reviewer would stall its phase indefinitely.'
} elseif ([int]$Matches['default'] -lt 1800) {
    $failures += "RoundTimeoutSeconds default $($Matches['default']) is below the slowest observed reviewer (30m30s) plus margin."
}
if ($source -notmatch '-TimeoutSeconds\s+\$RoundTimeoutSeconds') {
    $failures += 'the parallel reviewer round does not pass -TimeoutSeconds, so the parameter would not bound anything.'
}
# -ErrorAction is NOT accepted in the Parallel parameter set. The script-level 'Stop' must be
# relaxed around the call instead, or the timeout's non-terminating error aborts the whole phase.
if ($source -match "ForEach-Object[^\r\n]*-Parallel[^\r\n]*-ErrorAction") {
    $failures += '-ErrorAction is passed to ForEach-Object -Parallel, which that parameter set rejects at runtime.'
}
if ($source -notmatch "\`$ErrorActionPreference = 'Continue'") {
    $failures += "the round does not relax \$ErrorActionPreference, so a timeout would abort the phase instead of degrading."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    Write-Error "run-review start-pattern/timeout contract FAILED ($($failures.Count) issue(s))" -ErrorAction Continue
    exit 1
}

Write-Host 'run-review start-pattern and round-timeout contract OK - emphasis tolerated, narration still rejected, round bounded'
