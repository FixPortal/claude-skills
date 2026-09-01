$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..'
$validator = Join-Path $root 'validate-report.ps1'
if (-not (Test-Path -LiteralPath $validator)) { throw 'adversarial-review/validate-report.ps1 is missing' }

$fixtures = Join-Path $PSScriptRoot 'fixtures' 'report-shape'
$bad = Join-Path $fixtures 'bad-run'
$wrapped = Join-Path $fixtures 'wrapped-run'
$good = Join-Path $fixtures 'clean-run'

# A guard is worth exactly what its fixture is worth. Assert the fixtures still CARRY
# the thing under test BEFORE asserting any verdict: three guards shipped green this
# week whose subject had quietly drifted out from under them, and a guard verified
# only by "the suite is green" is indistinguishable from a deleted guard.
$badReport = Get-Content (Join-Path $bad 'report.md') -Raw
if ($badReport -notmatch '\$\(\s*@\{') {
    throw 'bad fixture no longer carries the leaked subexpression; the reject test proves nothing'
}
if ($badReport -notmatch 'AppData[\\/]+Local[\\/]+Temp') {
    throw 'bad fixture no longer carries a scratch path; the reject test proves nothing'
}

# The wrapped fixture is only a test of anything while its defects actually STRADDLE a
# newline; reflow it and it silently degrades into a second copy of bad-run.
$wrappedReport = Get-Content (Join-Path $wrapped 'report.md') -Raw
if ($wrappedReport -notmatch '\$\(\r?\n\s*@\{') {
    throw 'wrapped fixture no longer splits the subexpression across a newline; the whole-file matching test is vacuous'
}
if ($wrappedReport -notmatch 'AppData\\\r?\n\s*Local') {
    throw 'wrapped fixture no longer splits the scratch path across a newline; the whole-file matching test is vacuous'
}

$goodReport = Get-Content (Join-Path $good 'report.md') -Raw
foreach ($legit in '$(TargetFramework)', '$(cat ', '@{ In=') {
    if ($goodReport -notmatch [regex]::Escape($legit)) {
        throw "clean fixture lost its legitimate snippet '$legit'; the false-positive test is vacuous"
    }
}
$transcript = Get-Content (Join-Path $good 'working' 'transcript.md') -Raw
if ($transcript -notmatch '\$\(\s*@\{' -or $transcript -notmatch 'AppData[\\/]+Local[\\/]+Temp') {
    throw 'clean fixture working/ transcript no longer carries both patterns; the working/ exclusion test is vacuous'
}

function Invoke-Validator {
    param([string] $Target)
    $output = & pwsh -NoProfile -File $validator -Path $Target 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output.Trim() }
}

$rejected = Invoke-Validator -Target $bad
if ($rejected.Code -eq 0) {
    throw "validator PASSED the malformed report - it is fail-open`n$($rejected.Output)"
}
foreach ($rule in 'leaked-interpolation', 'dead-scratch-path') {
    if ($rejected.Output -notmatch [regex]::Escape($rule)) {
        throw "validator did not report rule '$rule' on the malformed report`n$($rejected.Output)"
    }
}

$wrappedResult = Invoke-Validator -Target $wrapped
if ($wrappedResult.Code -eq 0) {
    throw "validator PASSED a leak word-wrapped across a newline`n$($wrappedResult.Output)"
}
foreach ($rule in 'leaked-interpolation', 'dead-scratch-path') {
    if ($wrappedResult.Output -notmatch [regex]::Escape($rule)) {
        throw "validator did not report rule '$rule' on the wrapped report`n$($wrappedResult.Output)"
    }
}

$accepted = Invoke-Validator -Target $good
if ($accepted.Code -ne 0) {
    throw "validator rejected a legitimate report (or failed to exclude working/)`n$($accepted.Output)"
}

$coverageRoot = Join-Path ([IO.Path]::GetTempPath()) "adversarial-coverage-$([guid]::NewGuid().ToString('N'))"
try {
    $repo = Join-Path $coverageRoot 'repo'
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    & git init --quiet $repo
    & git -C $repo config user.email 'fixture@example.test'
    & git -C $repo config user.name 'Coverage Fixture'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'src'), (Join-Path $repo 'tests') | Out-Null
    Set-Content (Join-Path $repo 'README.md') 'base'
    & git -C $repo add README.md
    & git -C $repo commit --quiet -m 'base'
    $baseSha = (& git -C $repo rev-parse HEAD).Trim()
    Set-Content (Join-Path $repo 'src/App.cs') 'reviewed'
    Set-Content (Join-Path $repo 'tests/AppTests.cs') 'excluded'
    & git -C $repo add src/App.cs tests/AppTests.cs
    & git -C $repo commit --quiet -m 'tip'
    $tipSha = (& git -C $repo rev-parse HEAD).Trim()

    function New-CoverageRun([string] $Name, [string[]] $IndexLines) {
        $run = Join-Path $coverageRoot $Name
        New-Item -ItemType Directory -Force -Path $run | Out-Null
        $IndexLines | Set-Content (Join-Path $run '_index.md')
        '# report' | Set-Content (Join-Path $run 'report.md')
        return $run
    }

    $goodCoverage = New-CoverageRun 'good-coverage' @(
        '---', 'project: fixture', 'review-type: adversarial-review', 'date: 2026-01-01',
        'scope-kind: repository', "target: $baseSha..$tipSha", 'reviewed-paths:', '  - src/**',
        'excluded-paths:', '  - tests/**', 'disposition: remediated', "remediation-tip: $tipSha", '---'
    )
    $symbolicCoverage = New-CoverageRun 'symbolic-coverage' @(
        '---', 'project: fixture', 'review-type: adversarial-review', 'date: 2026-01-01',
        'scope-kind: repository', "target: $baseSha..HEAD", 'disposition: remediated', "remediation-tip: $tipSha", '---'
    )
    $uncoveredCoverage = New-CoverageRun 'uncovered-coverage' @(
        '---', 'project: fixture', 'review-type: adversarial-review', 'date: 2026-01-01',
        'scope-kind: repository', "target: $baseSha..$tipSha", 'reviewed-paths:', '  - src/**',
        'disposition: remediated', "remediation-tip: $tipSha", '---'
    )

    $goodCoverageResult = & pwsh -NoProfile -File $validator -Path $goodCoverage -RepoPath $repo 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "validator rejected complete machine-readable coverage`n$goodCoverageResult" }
    $symbolicResult = & pwsh -NoProfile -File $validator -Path $symbolicCoverage -RepoPath $repo 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $symbolicResult -notmatch 'exact immutable target') { throw "validator accepted symbolic HEAD coverage`n$symbolicResult" }
    $uncoveredResult = & pwsh -NoProfile -File $validator -Path $uncoveredCoverage -RepoPath $repo 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $uncoveredResult -notmatch 'uncovered path') { throw "validator accepted incomplete repository coverage`n$uncoveredResult" }
}
finally {
    Remove-Item -LiteralPath $coverageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# An unreferenced validator never fires. The persist step is the only place that can
# catch this, because the report is hand-assembled rather than rendered by a script.
$skill = Get-Content (Join-Path $root 'SKILL.md') -Raw
if ($skill -notmatch 'validate-report\.ps1') {
    throw 'SKILL.md never invokes validate-report.ps1, so nothing runs it at persist time'
}

# Opportunistic sweep of what is actually persisted. Host-specific by nature, so it
# skips rather than fails when the vault is unreachable - the fixture contract above
# is the part CI enforces, and it ran.
$vault = $env:OBSIDIAN_VAULT
if (-not $vault) {
    'SKIP: vault sweep - set OBSIDIAN_VAULT to also sweep persisted reports'
} else {
    $reviews = Join-Path $vault 'Claude' 'Adversarial Review'
    if (-not (Test-Path -LiteralPath $reviews)) {
        "SKIP: vault sweep - '$reviews' is not present on this host"
    } else {
        $sweep = Invoke-Validator -Target $reviews
        if ($sweep.Code -ne 0) { throw "persisted reports violate the shape contract`n$($sweep.Output)" }
    }
}

'adversarial-review report shape contract OK'
