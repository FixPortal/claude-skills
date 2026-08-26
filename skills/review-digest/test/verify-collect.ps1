$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..' 'collect.ps1'
$out = Join-Path ([IO.Path]::GetTempPath()) 'review-digest-data.test.json'

# Repos-root to exercise collect.ps1 against. NOTE: the sanitised public mirror
# rewrites this to a `<workdir>` placeholder, and the repo identifiers further down
# to `<your-...-repo>` placeholders — substitute all of them for your own estate.
# Guard for an un-substituted `<...>` token and fail with a clear message — otherwise
# collect.ps1 just exits non-zero on the bogus path and the "bad path exits non-zero"
# assertion below becomes a tautology of that same failure rather than a real test.
$reposRoot = '<workdir>'
if ($reposRoot -match '[<>]') {
    throw "verify-collect.ps1: `$reposRoot is still the placeholder '$reposRoot'. Set it to a real repos-root path before running this test."
}

# Host-independent first, so the skip below cannot take it with it: an invalid -Path must
# exit non-zero. This needs no estate and therefore must still run on CI.
& pwsh -NoProfile -File $script -Path (Join-Path ([IO.Path]::GetTempPath()) 'NoSuchFolderXYZ') -OutFile $out 2>$null
if ($LASTEXITCODE -eq 0) { throw "bad path should exit non-zero" }

# Everything below drives collect.ps1 against the LIVE estate and asserts on real repos and
# a real vault, so it can only run on a machine that has BOTH. That is a legitimate
# integration test, not a portable one - on any other host it is skipped with the reason
# stated, and the hermetic resolver coverage lives in verify-resolver-fixtures.ps1 so CI
# still exercises the production resolution path.
# The vault root is part of the predicate: from line 52 on, the assertions read the live
# vault, so a host with the repos root but no vault would FAIL rather than skip.
$liveVault = '<vault>\Claude\Adversarial Review'
if (-not (Test-Path -LiteralPath $reposRoot -PathType Container)) {
    Write-Host "SKIP: live estate repos-root not present on this host - $reposRoot"
    return
}
if (-not (Test-Path -LiteralPath $liveVault -PathType Container)) {
    Write-Host "SKIP: live adversarial-review vault not present on this host - $liveVault"
    return
}

& pwsh -NoProfile -File $script -Path $reposRoot -OutFile $out
if ($LASTEXITCODE -ne 0) { throw "collect.ps1 exited $LASTEXITCODE" }
$data = Get-Content $out -Raw | ConvertFrom-Json

# git side: engine must have review commits with a parsed fixer model and a last-review date
$engine = $data | Where-Object { $_.repo -eq '<your-engine-repo>' }
if (-not $engine) { throw "<your-engine-repo> absent from output" }
if ($engine.git.reviewCommits.Count -lt 1) { throw "engine has no review commits" }
if (-not ($engine.git.reviewCommits | Where-Object { $_.fixerModel })) { throw "no fixer model parsed on engine" }
if (-not $engine.git.lastReviewDate) { throw "engine missing lastReviewDate" }

# a repo with no reviews must still appear (coverage gap), with empty reviewCommits.
# Which repo(s) currently have zero reviews is live, mutable state (any repo can
# gain a reviewer-findings commit at any time), so pick one dynamically rather
# than pinning to a repo name — a structural check of the "unreviewed" shape,
# not an assertion about which specific repo is unreviewed today.
$neverReviewed = @($data | Where-Object { -not $_.outsideScanPath -and $_.git.neverReviewed -and $_.git.reviewCommits.Count -eq 0 })
if ($neverReviewed.Count -eq 0) { throw "no never-reviewed repo found in output (coverage-gap listing not exercised)" }
$gap = $neverReviewed[0]
if ($gap.git.reviewCommits -isnot [array]) { throw "$($gap.repo): reviewCommits must be an array even when empty" }
if (-not $gap.git.neverReviewed) { throw "$($gap.repo): zero reviewCommits but neverReviewed flag not set" }

# Vault-side compatibility shape. Panel composition and tally are mutable live data; the
# hermetic fixture owns parsing correctness.
if (-not $engine.vault.exists) { throw "engine vault not detected" }
if ($null -eq $engine.vault.PSObject.Properties['reviewers']) { throw "engine vault missing reviewers property" }
if ($null -eq $engine.vault.PSObject.Properties['judge']) { throw "engine vault missing judge property" }
if ($null -ne $engine.vault.judge -and $engine.vault.judge -isnot [string]) { throw "engine vault judge, when present, must be a string" }
if ($null -eq $engine.vault.PSObject.Properties['tally']) { throw "engine vault missing tally property" }
"collect.ps1 live compatibility OK — engine scopeValidation=$($engine.scopeValidation)"

# ci-frontend uses a Markdown-table tally format; it must still parse a High count
$cif = $data | Where-Object { $_.repo -eq '<your-table-tally-repo>' }
if (-not $cif) { throw "<your-table-tally-repo> absent" }
if (-not $cif.vault.exists) { throw "ci-frontend vault not detected" }
if ($null -eq $cif.vault.tally) { throw "ci-frontend tally not parsed (table format)" }
if ($null -eq $cif.vault.tally.High) { throw "ci-frontend tally.High not parsed (table format)" }

# --- vault-only rows must resolve to real code, so remediation is FALSIFIABLE ---
# This block previously asserted "widgetservice should have no git commits in this folder",
# which encoded the defect rather than testing behaviour: widgetservice is not a repo, it is a
# SUBSYSTEM of host-app (Framework/Services/WidgetService). The old row had an empty git side
# by construction, so remediation could never show — three digests reported its long-fixed
# Highs as outstanding because no evidence could contradict them. An empty git side here is
# the bug, not the expectation.
$qf = $data | Where-Object { $_.repo -eq 'widgetservice' }
if (-not $qf) { throw "widgetservice (vault-only, outside path) absent" }
if (-not $qf.vault.exists) { throw "widgetservice should carry vault data" }
if (-not $qf.outsideScanPath) { throw "widgetservice should be flagged outsideScanPath" }
if ($qf.unresolved) { throw "widgetservice must resolve to its host repo, not come back unresolved" }
if (-not $qf.resolvedPath) { throw "widgetservice must carry a resolvedPath (its host repo)" }
if ($qf.resolvedPath -notmatch 'host-app$') { throw "widgetservice should resolve to host-app, got '$($qf.resolvedPath)'" }
if (-not $qf.isSubsystem) { throw "widgetservice is a subsystem of host-app and must be flagged as one" }
if ($qf.subsystemPath -ne 'Framework\Services\WidgetService') { throw "widgetservice subsystemPath wrong: '$($qf.subsystemPath)'" }
# The falsifiability guarantee itself: a resolved row MUST be able to show remediation.
# reviewCommits is the real invariant — it proves the git side is wired to the resolved repo.
# sinceReviewCount is only shape-checked: a correctly resolved repo whose latest review
# boundary sits at HEAD legitimately has 0 commits since, so asserting > 0 would pin live,
# mutable state and fail the day widgetservice is re-reviewed.
if ($qf.git.reviewCommits.Count -eq 0) { throw "widgetservice resolved but has no review commits — the git side is still unfalsifiable" }
if ($qf.git.sinceReviewCount -isnot [int] -and $qf.git.sinceReviewCount -isnot [long]) { throw "widgetservice sinceReviewCount must be an integer" }
if ($qf.git.sinceReviewCount -lt 0) { throw "widgetservice sinceReviewCount must be non-negative" }
"collect.ps1 resolution OK — widgetservice -> $($qf.resolvedPath) \ $($qf.subsystemPath), $($qf.git.sinceReviewCount) commit(s) since boundary"

# Subsystem evidence must be PATHSPEC-SCOPED to the sub-path, not the whole host repo.
# Unscoped, widgetservice reported all of host-app's post-boundary activity as WidgetService work
# (977 commits), and any unrelated reviewer-findings commit elsewhere in the host read as
# WidgetService remediation. Detecting remediation is worthless if the number is another repo's.
# Ungated on purpose: a skip here is indistinguishable from a pass, and a vacuous scoping
# check is how the unscoped count survived review in the first place. Every precondition is
# an assertion, and a failed/garbled git call fails the test rather than quietly skipping it.
$emsRow = $data | Where-Object { $_.repo -eq 'host-app' }
if (-not $emsRow) { throw "host-app row absent — cannot verify widgetservice's pathspec scoping against its host" }
if ($emsRow.unresolved) { throw "host-app must resolve; widgetservice's scoping is verified against it" }
if ($qf.resolvedPath -ne $emsRow.resolvedPath) { throw "widgetservice and host-app must share a host repo, got '$($qf.resolvedPath)' vs '$($emsRow.resolvedPath)'" }
if (-not $qf.git.boundarySha) { throw "widgetservice has no boundarySha — cannot compare scoped vs host-wide range" }
$hostAll = & git -C $qf.resolvedPath rev-list --count "$($qf.git.boundarySha)..HEAD" 2>$null
if ($LASTEXITCODE -ne 0) { throw "git rev-list failed on '$($qf.resolvedPath)' — pathspec scoping unverified" }
if (-not ("$hostAll".Trim() -match '^\d+$')) { throw "git rev-list returned non-numeric output '$hostAll' — pathspec scoping unverified" }
$hostCount = [long]("$hostAll".Trim())
# EQUALITY against git's own scoped count, not merely "smaller than the host". A `<` check
# passes for any wrong-but-smaller number (a mis-derived subtree still looks scoped), and it
# would wrongly FAIL if every commit in the range happened to touch WidgetService. Recompute what
# the pathspec should yield and demand collect.ps1 match it exactly.
$scopedAll = & git -C $qf.resolvedPath rev-list --count "$($qf.git.boundarySha)..HEAD" -- $qf.subsystemPath 2>$null
if ($LASTEXITCODE -ne 0) { throw "git rev-list failed for scoped path '$($qf.subsystemPath)' — pathspec scoping unverified" }
if (-not ("$scopedAll".Trim() -match '^\d+$')) { throw "scoped git rev-list returned non-numeric output '$scopedAll'" }
$scopedCount = [long]("$scopedAll".Trim())
if ($qf.git.sinceReviewCount -ne $scopedCount) {
    throw "widgetservice sinceReviewCount ($($qf.git.sinceReviewCount)) differs from git's own scoped count for '$($qf.subsystemPath)' ($scopedCount) — the pathspec is missing or wrong"
}
# Belt and braces: the scoped count must also be distinguishable from the host-wide count,
# otherwise this whole assertion could pass on an unscoped run that happens to agree.
if ($hostCount -gt 0 -and $scopedCount -eq $hostCount) {
    "collect.ps1 pathspec — scoped equals host-wide ($hostCount) for this range; every commit touches '$($qf.subsystemPath)', so scoping is exact but not discriminating here"
} else {
    "collect.ps1 pathspec OK — widgetservice scoped to $($qf.subsystemPath): $($qf.git.sinceReviewCount) == git's scoped $scopedCount, vs host-wide $hostCount"
}

# A NAME VARIANCE is not a subsystem. quickfixn resolves to the quickfix-n repo by
# normalised name search; isSubsystem keys off subsystemPath, not the name, so the whole
# tree was reviewed and there is no sub-path to scope to. The row is a vault fixture, so its
# absence is a real failure, not a skip.
$qn = $data | Where-Object { $_.repo -eq 'quickfixn' }
if (-not $qn) { throw "quickfixn resolution row is absent" }
if ($qn.unresolved) { throw "quickfixn should resolve to quickfix-n via the name-search fallback" }
if ((Split-Path $qn.resolvedPath -Leaf) -ne 'quickfix-n') { throw "quickfixn resolved to the wrong repository: '$($qn.resolvedPath)'" }
if ($qn.isSubsystem) { throw "quickfixn is a name variance of quickfix-n, NOT a subsystem" }
if ($qn.subsystemPath) { throw "quickfixn must have no subsystemPath (whole tree reviewed)" }

# Shape check over whatever live rows happen to be unresolved. On its own this loop passes
# VACUOUSLY when nothing is unresolved, so a regression that stops emitting `unresolved`
# entirely would go undetected — it is backed by a controlled fixture below, which is what
# actually holds the behaviour.
foreach ($row in @($data | Where-Object { $_.unresolved })) {
    if ($row.resolvedPath) { throw "$($row.repo): unresolved rows must have a null resolvedPath" }
    if ($row.isSubsystem) { throw "$($row.repo): unresolved rows cannot be subsystems" }
    if (-not $row.outsideScanPath) { throw "$($row.repo): only vault-only rows can be unresolved" }
}

# No resolved row may carry a subsystemPath whose last two segments repeat (the 0..-1 shape).
foreach ($row in @($data | Where-Object { $_.subsystemPath })) {
    $segs = @($row.subsystemPath -split '\\')
    if ($segs.Count -ge 2 -and $segs[-1] -eq $segs[-2]) { throw "$($row.repo): subsystemPath has a duplicated trailing segment — '$($row.subsystemPath)'" }
}

# The hermetic Resolve-VaultTarget fixture block lives in verify-resolver-fixtures.ps1:
# it builds its own git repos and vault under temp, so it runs on CI where this file cannot.

# --- forward-looking scope field compatibility ---
if ($null -eq $engine.git.PSObject.Properties['boundarySha']) { throw "engine missing git.boundarySha" }
if ($null -eq $engine.git.PSObject.Properties['sinceReview']) { throw "engine missing git.sinceReview" }
if ($null -eq $engine.git.PSObject.Properties['sinceReviewCount']) { throw "engine missing git.sinceReviewCount" }
if ($null -eq $engine.git.PSObject.Properties['daysSinceReview']) { throw "engine missing git.daysSinceReview" }
if ($null -eq $engine.PSObject.Properties['hasGraphify']) { throw "engine missing hasGraphify flag" }
if ($engine.scopeValidation -eq 'invalid') {
    if ($engine.git.boundarySha) { throw "invalid engine scope must not emit a boundary" }
    if ($null -ne $engine.git.sinceReviewCount) { throw "invalid engine scope must emit unknown/null sinceReviewCount" }
    if ($engine.git.neverReviewed -or $engine.git.effectiveNeverReviewed) { throw "invalid engine scope is UNKNOWN, not never reviewed" }
} elseif ($null -ne $engine.git.sinceReviewCount -and $engine.git.sinceReviewCount -lt 0) {
    throw "engine sinceReviewCount must be null or non-negative"
}

# a never-reviewed repo: null/empty boundary, flagged neverReviewed, well-typed commit count
if ($gap.git.boundarySha) { throw "$($gap.repo) (unreviewed) must have a null/empty boundarySha" }
if (-not $gap.git.neverReviewed) { throw "$($gap.repo) must be flagged neverReviewed" }
if ($gap.git.sinceReviewCount -isnot [int] -and $gap.git.sinceReviewCount -isnot [long]) {
    $gotType = if ($null -eq $gap.git.sinceReviewCount) { '<null>' } else { $gap.git.sinceReviewCount.GetType().Name }
    throw "$($gap.repo) sinceReviewCount must be an integer (got $gotType)"
}
if ($gap.git.sinceReviewCount -lt 0) { throw "$($gap.repo) sinceReviewCount must be a non-negative int" }
"collect.ps1 scope-side compatibility OK — engine scopeValidation=$($engine.scopeValidation)"

"collect.ps1 git-side OK — $($data.Count) repos"
