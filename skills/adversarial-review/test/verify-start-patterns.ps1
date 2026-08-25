#Requires -Version 7
$ErrorActionPreference = 'Stop'

# Contract test for run-review.ps1's ROUND CONTRACT: the Phase 1 / Phase 2 start patterns that
# decide whether a reviewer counted as participating, the admission patterns that decide whether
# a matched section actually CONTAINS the phase's contract content, the finding-block pooler, and
# the round timeout that stops one wedged slot from stalling a phase forever.
#
# Why this exists: the strict line-initial patterns discarded substantive, repository-backed
# reviews TWICE on formatting alone -- 2026-08-16 (`**F1** ... AGREE`, three anthropic reviews)
# and 2026-08-17 (`**F1: FALSE POSITIVE**`). Both times the reviewer was dropped from the
# participating-vendor count, so every consensus tally for that chunk was wrong. Widening the
# pattern then risks the opposite failure -- admitting narration as a verdict block -- so both
# directions are pinned here. And a start-pattern match alone must not admit: '### Verdicts'
# plus prose counted a vendor that delivered no verdict at all (start pattern LOCATES the
# section; the admission pattern proves the content), and the pooler must split on exactly the
# admission form instead of the literal '^### '.

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-review.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw "run-review.ps1 not found at $scriptPath" }
$source = Get-Content -LiteralPath $scriptPath -Raw

# The pooler lives in pool-findings.ps1 precisely so this test can drive the SAME code the
# driver runs. Dot-source it (defines $script:FindingHeadingPattern and Split-FindingBlocks).
$poolerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'pool-findings.ps1'
if (-not (Test-Path -LiteralPath $poolerPath)) { throw "pool-findings.ps1 not found at $poolerPath" }
. $poolerPath
if ($source -notmatch [regex]::Escape(". (Join-Path `$scriptDir 'pool-findings.ps1')")) {
    throw 'run-review.ps1 must dot-source pool-findings.ps1 rather than carry its own pooler'
}

$failures = @()
function Check([string] $label, [string] $pattern, [string] $line, [bool] $expected) {
    $actual = [bool]($line -match $pattern)
    if ($actual -ne $expected) {
        $script:failures += "[$label] '$line' -> match=$actual, expected=$expected"
    }
}
function Get-SourcePattern([string] $assignment) {
    # Pull the literal the script actually assigns, rather than restating it here -- a copy would
    # drift and the test would pass while the driver used something else.
    $match = [regex]::Match($source, [regex]::Escape($assignment) + "'(?<pattern>.+?)'")
    if (-not $match.Success) { throw "could not find the pattern assignment: $assignment" }
    $match.Groups['pattern'].Value
}

# --- Phase 1: findings are '### ' headings -----------------------------------
$p1 = Get-SourcePattern "`$p1ok = Invoke-Round 'p1' "
Check 'p1' $p1 '### Missing JSON serialization metadata' $true
Check 'p1' $p1 '  ### Indented heading' $true
Check 'p1' $p1 '- ### Heading in a list item' $true
Check 'p1' $p1 '#### Deeper heading' $true
Check 'p1' $p1 'I will now review the diff.' $false
Check 'p1' $p1 'Here are my findings:' $false

# The pooler must split on EXACTLY the Phase-1 start pattern: previously it opened a block only
# on the literal '^### ', so admitted forms ('#### ', '  ### ', '- ### ') pooled zero findings
# while the vendor still counted toward minVendors.
if ($p1 -cne $FindingHeadingPattern) {
    $failures += "the pooler pattern (pool-findings.ps1) drifted from the Phase-1 start pattern: '$FindingHeadingPattern' vs '$p1'"
}

# --- Phase 1 admission: a structured finding field or the clean sentinel ------
# A heading plus prose ('### Analysis') is not participation. Admission requires a structured
# field ('**Severity:**') or the canonical clean sentinel ('### No substantive defects').
$sentinel = Get-SourcePattern '$cleanSentinel = '
$sentinelPattern = ([regex]::Match($source, '\$cleanSentinelPattern = "(?<p>.+?)"').Groups['p'].Value).Replace('$cleanSentinel', [regex]::Escape($sentinel))
$p1Admission = ([regex]::Match($source, '\$p1Admission = "(?<p>.+?)"').Groups['p'].Value).Replace('$cleanSentinelPattern', $sentinelPattern)
Check 'p1-admission' $p1Admission '- **Severity:** High' $true
Check 'p1-admission' $p1Admission '### No substantive defects' $true
Check 'p1-admission' $p1Admission ("### Analysis`n`nSome prose without any structured field.") $false
Check 'p1-admission' $p1Admission 'I will now review the diff.' $false

# --- Phase 2: per-finding verdicts, however the reviewer emphasises them ------
$p2Verdict = Get-SourcePattern '$p2VerdictPattern = '
$p2 = "$p2Verdict|$p1"
# The driver must build the Phase-2 start pattern from exactly these two pieces -- the verdict
# form and the heading form -- so the admission pattern below cannot drift from what locates
# the section.
if ($source -notmatch [regex]::Escape("`$p2ok = Invoke-Round 'p2' `"`$p2VerdictPattern|")) {
    $failures += 'the Phase-2 Invoke-Round call no longer starts from $p2VerdictPattern; admission and start patterns can drift apart.'
}

# MUST match. Each of these was emitted by a real reviewer; the first two are the exact forms
# that were wrongly discarded on 2026-08-17 and 2026-08-16 respectively.
Check 'p2' $p2 '**F1: FALSE POSITIVE**' $true
Check 'p2' $p2 '**F12** ... AGREE' $true
Check 'p2' $p2 'F1: AGREE - real' $true
Check 'p2' $p2 '__F7__ REFUTED' $true
Check 'p2' $p2 '- **F3.** disagree' $true
Check 'p2' $p2 'F9) needs evidence' $true
Check 'p2' $p2 '### Verdicts' $true   # LOCATES the section only; admission below rejects it

# MUST NOT match. Narration and prose that merely mentions an F-number is not a verdict block;
# admitting it would count a reviewer that contributed nothing as a participating vendor.
Check 'p2' $p2 'F12 and F13 both agree with this' $false
Check 'p2' $p2 'F5 findings were raised in total' $false
Check 'p2' $p2 'I will now review the diff.' $false
Check 'p2' $p2 'Adversarial verdict pass. Skills not applicable' $false
Check 'p2' $p2 'FIXME: this is prose' $false

# --- Phase 2 admission: at least one valid F# verdict --------------------------
# The negative half of the '### Verdicts' pin: with findings on the table, a heading alone must
# NOT admit -- one valid F# verdict is required before the reply counts toward minVendors.
$p2Admission = "(?m)$p2Verdict"
if ($source -notmatch [regex]::Escape('$p2Admission = "(?m)$p2VerdictPattern"')) {
    $failures += 'the Phase-2 admission pattern is not the verdict pattern; a heading-plus-prose reply would count as a vendor.'
}
Check 'p2-admission' $p2Admission '### Verdicts' $false
Check 'p2-admission' $p2Admission ("### Analysis`n`nOverall the change looks reasonable.") $false
Check 'p2-admission' $p2Admission '**F1: FALSE POSITIVE**' $true
Check 'p2-admission' $p2Admission 'F3. disagree' $true

# --- The pooler: divergent admitted forms and fenced code blocks ---------------
# Feed the DIVERGENT inputs through the actual pooler, not just the admission regex.
$poolInput = @'
Some narration before the first finding (dropped).

#### Deeper heading
- **Severity:** High
- **Issue:** first

```text
### this heading is INSIDE a fenced code block and must not split the finding
```

  ### Indented heading
- **Severity:** Low
- **Issue:** second
'@
# Assign BEFORE wrapping: @(Split-FindingBlocks ...) captures the returned array as
# ONE element instead of its blocks (the single-array pipeline quirk).
$splitBlocks = Split-FindingBlocks $poolInput
$blocks = @($splitBlocks)
if ($blocks.Count -ne 2) {
    $failures += "pooler split the divergent input into $($blocks.Count) block(s), expected 2 (fence state ignored, or '#### '/'  ### ' forms not recognised)"
} else {
    if (-not $blocks[0].StartsWith('### Deeper heading')) {
        $failures += "pooler did not normalise '#### Deeper heading' to canonical '### ': got '$($blocks[0].Split([char]10)[0])'"
    }
    if ($blocks[0] -notmatch [regex]::Escape('### this heading is INSIDE a fenced code block')) {
        $failures += 'the fenced ### line was lost from the first finding instead of kept as content'
    }
    if (-not $blocks[1].StartsWith('### Indented heading')) {
        $failures += "pooler did not normalise '  ### Indented heading' to canonical '### ': got '$($blocks[1].Split([char]10)[0])'"
    }
}
# The clean sentinel must never pool as a finding.
$sentinelSplit = Split-FindingBlocks '### No substantive defects'
$sentinelBlocks = @($sentinelSplit)
if ($sentinelBlocks.Count -ne 1 -or $sentinelBlocks[0].Trim() -notmatch '(?m)^\s*###\s*No substantive defects\s*$') {
    $failures += 'the clean sentinel must survive pooling as one recognisable block (the driver filters it before assigning an F-id)'
}

# --- Round timeout -----------------------------------------------------------
if ($source -notmatch '\[int\]\s*\$RoundTimeoutSeconds\s*=\s*(?<default>\d+)') {
    $failures += 'RoundTimeoutSeconds parameter is missing: a wedged reviewer would stall its phase indefinitely.'
} elseif ([int]$Matches['default'] -lt 1830) {
    $failures += "RoundTimeoutSeconds default $($Matches['default']) is below the slowest observed reviewer (30m30s = 1830s) plus margin."
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
# ...and the relaxation must be RESTORED afterwards, or the rest of the script silently runs
# with 'Continue' and every later guard loses its terminating semantics.
if ($source -notmatch '(?s)\$previousErrorAction\s*=\s*\$ErrorActionPreference.+?finally\s*\{\s*\$ErrorActionPreference\s*=\s*\$previousErrorAction') {
    $failures += 'the round does not restore $ErrorActionPreference in a finally block after relaxing it.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    Write-Error "run-review start-pattern/admission/pooler/timeout contract FAILED ($($failures.Count) issue(s))" -ErrorAction Continue
    exit 1
}

Write-Host 'run-review round contract OK - emphasis tolerated, narration and heading-only replies rejected, pooler shares the admission pattern and tracks fences, round bounded'
