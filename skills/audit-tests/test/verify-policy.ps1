$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$main = Get-Content (Join-Path $root 'SKILL.md') -Raw
$axis = Get-Content (Join-Path $root 'references' 'axis-brief.md') -Raw
$stack = Get-Content (Join-Path $root 'references' 'stack-conventions.md') -Raw
# orchestration.md is READ, not merely existence-checked. The SKILL.md -> references/
# refactor moved the bulk of the policy prose here, so a check that never opened it
# reported "audit-tests policy OK" over exactly the file most likely to hold stale text.
$orchestrationPath = Join-Path $root 'references' 'orchestration.md'
$orchestration = if (Test-Path $orchestrationPath) { Get-Content $orchestrationPath -Raw } else { '' }
$words = ([regex]::Matches($main, '\b[\p{L}\p{N}][\p{L}\p{N}''.-]*\b')).Count

if ($words -gt 500) { throw "SKILL.md is $words words" }
if (-not (Test-Path $orchestrationPath)) { throw 'missing orchestration reference' }
# The HOST-UNVERIFIED branch was deleted once while verify-refute.md still produced the
# verdict, which routed an unexamined downstream risk into "effectively covered".
# Dash-agnostic on purpose: pinning one glyph is how a stale-text guard becomes
# unfireable (an ASCII hyphen in the needle against an en dash in the prose matches
# nothing and the check silently never fires).
foreach ($needle in 'HOST-UNVERIFIED', 'Unsettled\s*[-‐-―]\s*host evidence required', 'cites \*\*no test\*\*') {
    if ($orchestration -notmatch $needle) {
        throw "orchestration.md lost the HOST-UNVERIFIED handling: $needle"
    }
}
foreach ($stale in 'poll with a timeout', 'task.WaitAsync(5s)',
                    'DateTime.UtcNow.AddDays(n)` used as test data such as an expiry or settlement date. The distinction') {
    if (($axis + "`n" + $stack) -match [regex]::Escape($stale)) { throw "stale timing policy remains: $stale" }
}
foreach ($needle in 'scaffold-tests/references/async-and-timing.md',
                    'Conservative scheduling or disabled parallelism',
                    'Aggressive or unknown scheduling', 'WaitAsync(TimeSpan)',
                    'linked token with `CancelAfter`',
                    '**timing-defect** finding',
                    'separate `suite-hygiene` finding', 'NodaTime `LocalDate`') {
    if (($main + "`n" + $axis + "`n" + $stack) -notmatch [regex]::Escape($needle)) { throw "missing timing contract: $needle" }
}

# The delegation target must EXIST, not merely be named. Checking the string only proves
# the sentence is present; it cannot tell a live pointer from a dangling one, and the
# whole timing policy is delegated through it.
$timingPolicy = Join-Path (Split-Path $root -Parent) 'scaffold-tests' 'references' 'async-and-timing.md'
if (-not (Test-Path -LiteralPath $timingPolicy)) {
    throw "audit-tests delegates its timing rules to a file that does not exist: $timingPolicy"
}
# ...and it must actually carry the policy the delegation promises, so a gutted or
# renamed-away target is caught rather than silently followed into nothing.
$timingText = Get-Content -LiteralPath $timingPolicy -Raw
foreach ($needle in 'WaitAsync', 'CancelAfter', 'Conservative') {
    if ($timingText -notmatch [regex]::Escape($needle)) {
        throw "the canonical timing policy no longer carries '$needle'; audit-tests' delegation is empty"
    }
}

$budgetPolicy = Join-Path (Split-Path $root -Parent) 'scaffold-tests' 'references' 'ci-test-budgets.md'
if (-not (Test-Path -LiteralPath $budgetPolicy)) {
    throw "audit-tests delegates CI eligibility to a file that does not exist: $budgetPolicy"
}
$budgetText = Get-Content -LiteralPath $budgetPolicy -Raw
foreach ($needle in '30 seconds', '10 minutes', '15 aggregate runner-minutes', '45 minutes') {
    if ($budgetText -notmatch [regex]::Escape($needle)) { throw "canonical CI budget lost '$needle'" }
}
foreach ($needle in 'scaffold-tests/references/ci-test-budgets.md',
                    'recent CI run', 'TRX per-test durations', 'aggregate runner-minutes',
                    '30-second PR ceiling', '10-minute PR job ceiling',
                    '45-minute extended-job ceiling', 'weekly/manual extended lane') {
    if (($main + "`n" + $axis) -notmatch [regex]::Escape($needle)) { throw "missing CI cost audit contract: $needle" }
}
if ($axis -notmatch '(?is)suite-hygiene.*test.*30-second PR ceiling') {
    throw 'misplaced slow tests are not routed to suite-hygiene'
}
if ($axis -notmatch '(?is)measurement.*workflow.*aggregate runner-minutes') {
    throw 'workflow fan-out and budget controls are not routed to measurement'
}

# Delta mode is not executable without these. The "Audit modes" body was deleted in the
# SKILL.md -> references/ split while orchestration.md's Phase 0 step 7 still said
# "validate the baseline above" and the failure table still gated on the terms it defined
# - so the operator improvised baseline validity while the report claimed Delta legitimacy.
foreach ($needle in '## Audit modes', 'exactly one existing verified', 'mechanically complete') {
    if ($orchestration -notmatch [regex]::Escape($needle)) {
        throw "orchestration.md lost the delta-baseline definition: $needle"
    }
}
if ($orchestration.IndexOf('## Audit modes') -gt $orchestration.IndexOf('## Phase 0')) {
    throw '"Audit modes" must appear ABOVE Phase 0 - step 7 says "validate the baseline above"'
}
# Operator-misconception guidance, dropped once with no successor.
if ($orchestration -notmatch '(?m)^## Common mistakes') { throw 'orchestration.md lost its Common mistakes section' }
# Worker H cannot open the canonical policy unless the orchestrator resolves it into the
# run context; the brief's only path anchor is the AUDITED repo.
if ($orchestration -notmatch 'Canonical timing policy:') {
    throw 'worker H run-context does not carry the resolved canonical timing policy path'
}
if ($orchestration -match 'all four classes below') {
    throw 'row H still names the four-class taxonomy this skill removed'
}

# A build and passing tests leave formatter, analyzer, and lint regressions invisible;
# they cannot by themselves authorise a fix-pass push.
if ($orchestration -notmatch 'Build and tests\s+alone never authorize a push') {
    throw 'full local gate lets build and tests alone authorize a push'
}
if ($orchestration -notmatch 'repository-configured formatter, analyzer, and lint command') {
    throw 'full local gate does not require configured formatter, analyzer, and lint commands'
}
if ($orchestration -notmatch [regex]::Escape('record the configuration inspected and its absence')) {
    throw 'full local gate does not require absence evidence for an unconfigured tool class'
}

"audit-tests policy OK — $words words"
