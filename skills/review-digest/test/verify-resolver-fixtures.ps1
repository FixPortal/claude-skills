$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..' 'collect.ps1'

# Hermetic half of the review-digest suite. Split out of verify-collect.ps1, which drives
# collect.ps1 against the LIVE estate repos-root and therefore cannot run anywhere but this
# machine. These checks build their own git repos and their own vault under the temp
# directory, so they run everywhere - including the CI runner, which is where the resolver
# regressions they defend would otherwise go unnoticed.
#
# Resolve-VaultTarget is reached only through collect.ps1, so it is driven there rather than
# against an inlined copy of its logic: a copy tests the copy, and the tell is that "verifying
# it red" requires editing the test instead of the product.
#   - a link to a REPO-ROOT file -> one path segment -> drop yields EMPTY -> not a subsystem.
#     With the 0..-1 bug this returns 'README.md\README.md' and isSubsystem=$true.
#   - a link to a NESTED file    -> drop yields the containing directory -> a real subsystem.
# One GUID-keyed root, created by this run and deleted whole. A $PID-suffixed name is
# predictable and PIDs are reused, so an interrupted earlier run plus a recycled PID would
# point `Remove-Item -Recurse -Force` at pre-existing content.
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "review-digest-fixture-$([guid]::NewGuid().ToString('N'))"
$fixtureVault = Join-Path $fixtureRoot 'vault'
$fixtureOut = Join-Path $fixtureRoot 'out.json'
$fixtureRepos = Join-Path $fixtureRoot 'repos'
# The link-target repos must live OUTSIDE the scanned root. A whole-repo resolution onto an
# already-scanned in-path repo is deliberately dropped as a stale pre-rename duplicate, so
# scanning the link targets would make the repo-root fixture emit no row at all. The scan
# root therefore holds one unrelated repo - collect.ps1 exits 3 on a root with none.
$scanRoot = Join-Path $fixtureRoot 'scan'
$scanRepo = Join-Path $scanRoot 'placeholder'
$scopeRepo = Join-Path $scanRoot 'scope-quoted'
$markerRepo = Join-Path $scanRoot 'marker-only'
$sourceFixtures = @(
    @{ name = 'source-razor';    file = 'Pages/Index.razor' },
    @{ name = 'source-xaml';     file = 'App.xaml' },
    @{ name = 'source-terraform'; file = 'main.tf' },
    @{ name = 'source-protobuf'; file = 'service.proto' },
    @{ name = 'source-style';    file = 'site.css' },
    @{ name = 'source-workflow'; file = '.github/workflows/ci.yml' },
    @{ name = 'source-docker';   file = 'Dockerfile' }
)
foreach ($fixture in $sourceFixtures) { $fixture.path = Join-Path $scanRoot $fixture.name }

# Throwaway git repos for the resolver fixes that real-estate paths cannot exercise: a repo
# whose path contains a SPACE (for %20 decoding), and a SIBLING pair whose names overlap by
# prefix. Only a .git directory is needed - Resolve-VaultTarget's walk tests for it and never
# reads the tree - so `git init` is enough and no commit is required.
$linkRepo = Join-Path $fixtureRepos 'linked'
$spacedRepo = Join-Path $fixtureRepos 'spaced repo'
$appRepo = Join-Path $fixtureRepos 'app'
$appOldRepo = Join-Path $fixtureRepos 'app-old'
# Sha-resolution target reached ONLY via a quoted `scope: "<sha>..HEAD"` line - no file:/// link
# and a folder name matching no directory, so stage 2 must tolerate the quote or it degrades
# silently to the stage-3 name guess (which here finds nothing).
$quotedRepo = Join-Path $fixtureRepos 'quoted-target'
# A vault review older than the repo's own history (the OSS re-init squash shape): effectively
# never reviewed, full-history scope, no false root-commit boundary.
$predateRepo = Join-Path $scanRoot 'predates'
# A .git FILE with a bogus gitdir makes every git probe fail: hasTrackedSource must come back
# null (UNKNOWN), never a false that reads as a verified empty repo.
$brokenRepo = Join-Path $scanRoot 'broken-git'

# Emitted subsystem paths use the host separator, so assert on a normalised form rather than
# pinning a backslash - a literal 'src\Foo' passes on Windows and fails on the runner.
function Normalize([string] $path) { ($path -replace '\\', '/') }

function New-FixtureCommit {
    param([string]$Repo, [string]$File, [string]$Subject, [string]$Body = '')
    $filePath = Join-Path $Repo $File
    New-Item -ItemType Directory -Force -Path (Split-Path $filePath -Parent) | Out-Null
    Set-Content -LiteralPath $filePath -Value $Subject
    & git -C $Repo add -- $File
    if ($LASTEXITCODE -ne 0) { throw "git add failed for fixture '$Repo'" }
    if ($Body) { & git -C $Repo commit --quiet -m $Subject -m $Body }
    else { & git -C $Repo commit --quiet -m $Subject }
    if ($LASTEXITCODE -ne 0) { throw "git commit failed for fixture '$Repo'" }
    $sha = & git -C $Repo rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed for fixture '$Repo'" }
    return "$sha".Trim()
}

# The try opens BEFORE the repos are created: setup can throw (New-Item, a nonzero git init,
# the .git assertion), and anything thrown outside it would bypass finally and strand the
# fixture directories on disk.
try {
    foreach ($r in @($linkRepo, $spacedRepo, $appRepo, $appOldRepo, $scanRepo, $scopeRepo, $markerRepo, $quotedRepo, $predateRepo) + @($sourceFixtures | ForEach-Object path)) {
        New-Item -ItemType Directory -Force -Path $r | Out-Null
        & git init --quiet $r 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git init failed (exit $LASTEXITCODE) for fixture repo '$r'" }
        if (-not (Test-Path (Join-Path $r '.git'))) { throw "failed to create fixture git repo at '$r'" }
        # Checked for the same reason as `git init` above: an unconfigured identity makes
        # every later New-FixtureCommit fail, and the assertions then run against a repo
        # with no commits - a fixture that proves nothing while reporting success.
        & git -C $r config user.email 'fixture@example.test'
        if ($LASTEXITCODE -ne 0) { throw "git config user.email failed (exit $LASTEXITCODE) for fixture repo '$r'" }
        & git -C $r config user.name 'Review Digest Fixture'
        if ($LASTEXITCODE -ne 0) { throw "git config user.name failed (exit $LASTEXITCODE) for fixture repo '$r'" }
    }

    $baseSha = New-FixtureCommit -Repo $scanRepo -File 'README.md' -Subject 'chore: initial fixture'
    $reviewedTip = New-FixtureCommit -Repo $scanRepo -File 'src/Reviewed.cs' -Subject 'feat: reviewed change'
    $proseSha = New-FixtureCommit -Repo $scanRepo -File 'notes.md' -Subject 'docs: ordinary notes' -Body 'This prose mentions adversarial work but is not a review marker.'
    $strictMarkerSha = New-FixtureCommit -Repo $scanRepo -File 'src/Fixed.cs' -Subject 'reviewer-findings batch 7: fix fixture'
    $auditMarkerSha = New-FixtureCommit -Repo $scanRepo -File 'src/AuditFixed.cs' -Subject 'adversarial-audit batch 8: fix fixture'
    if (-not (Test-Path (Join-Path $scanRepo '.git'))) { throw "placeholder fixture lost its .git directory" }

    $scopeBaseSha = New-FixtureCommit -Repo $scopeRepo -File 'README.md' -Subject 'chore: initial fixture'
    $scopeReviewedTip = New-FixtureCommit -Repo $scopeRepo -File 'src/Reviewed.cs' -Subject 'feat: reviewed change'
    New-FixtureCommit -Repo $scopeRepo -File 'src/Later.cs' -Subject 'feat: later change' | Out-Null

    New-FixtureCommit -Repo $markerRepo -File 'README.md' -Subject 'chore: initial fixture' | Out-Null
    New-FixtureCommit -Repo $markerRepo -File 'notes.md' -Subject 'fix(review): record follow-up' | Out-Null

    # Subjects carry the repo name: identical subject+content+timestamp would produce the SAME
    # commit sha in every fixture repo, and the sha-resolution fixture below then matches
    # multiple repos (correctly reported ambiguous) instead of resolving uniquely.
    $quotedBaseSha = New-FixtureCommit -Repo $quotedRepo -File 'README.md' -Subject 'chore: initial quoted-target fixture'
    New-FixtureCommit -Repo $quotedRepo -File 'src/Reviewed.cs' -Subject 'feat: quoted-target reviewed change' | Out-Null

    New-FixtureCommit -Repo $predateRepo -File 'README.md' -Subject 'chore: squashed initial import' | Out-Null
    New-FixtureCommit -Repo $predateRepo -File 'src/Main.cs' -Subject 'feat: post-squash work' | Out-Null

    # Not in the git-init loop: the point is that .git is a FILE whose gitdir resolves nowhere.
    New-Item -ItemType Directory -Force -Path $brokenRepo | Out-Null
    Set-Content -LiteralPath (Join-Path $brokenRepo '.git') -Value 'gitdir: /nonexistent-fixture-target'
    foreach ($fixture in $sourceFixtures) {
        New-FixtureCommit -Repo $fixture.path -File $fixture.file -Subject "feat: add $($fixture.name)" | Out-Null
    }
    $linkUri = 'file:///' + ($linkRepo -replace '\\', '/')
    # %20-encoded link - a standard file:/// URI encodes the space in 'spaced repo'.
    $spacedUri = 'file:///' + (($spacedRepo -replace '\\', '/') -replace ' ', '%20')
    $appUri = 'file:///' + ($appRepo -replace '\\', '/')
    $appOldUri = 'file:///' + ($appOldRepo -replace '\\', '/')

    foreach ($f in @(
        @{ name = 'zz-fixture-rootfile'; links = @("$linkUri/README.md") },
        @{ name = 'zz-fixture-subsystem'; links = @("$linkUri/src/Foo/Bar.cs") },
        # No file:/// link at all, and a name that matches no directory under -RepoRoots:
        # nothing can place it, so it MUST come back unresolved rather than as a frozen row.
        @{ name = 'zz-fixture-unresolvable'; links = @() },
        # %20 in the path. Undecoded, the literal 'spaced%20repo' fails the .git walk and the
        # folder is wrongly reported unresolved.
        @{ name = 'zz-fixture-encoded'; links = @("$spacedUri/src/Foo/Bar.cs") },
        # Sibling boundary: 'app-old' shares a prefix with 'app'. Two links win 'app' as the
        # repo; the third points into the sibling. Without a separator boundary, the sibling's
        # path passes StartsWith('...\app') and contributes the relative segment '-old\...',
        # which poisons the common-prefix walk and collapses subsystemPath to null.
        @{ name = 'zz-fixture-sibling'; links = @("$appUri/src/Foo/a.cs", "$appUri/src/Foo/b.cs", "$appOldUri/src/Foo/c.cs") }
    )) {
        $runDir = Join-Path $fixtureVault "$($f.name)" "20260101T000000Z"
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        @(
            '---', "project: $($f.name)", 'review-type: adversarial-review',
            'date: 2026-01-01', 'reviewers: [Fixture]', '---', '', '# Fixture', ''
        ) | Set-Content (Join-Path $runDir '_index.md')
        $body = @("# Fixture report", "")
        if (@($f.links).Count) { foreach ($l in $f.links) { $body += "Reviewed [target]($l)." } }
        else { $body += "Prose-only report with no file link at all." }
        $body += ""
        $body | Set-Content (Join-Path $runDir 'report.md')
    }

    # The date intentionally falls after every fixture commit. A date-only resolver would
    # choose $strictMarkerSha; the exact range must instead anchor at $reviewedTip.
    $mainRun = Join-Path $fixtureVault 'placeholder' '20300101T000000Z'
    New-Item -ItemType Directory -Force -Path $mainRun | Out-Null
    @(
        '---', 'project: placeholder', 'review-type: adversarial-review',
        'date: 2030-01-01', "target: $baseSha..$reviewedTip", 'reviewers: [Fixture]', '---', '', '# Fixture', ''
    ) | Set-Content (Join-Path $mainRun '_index.md')
    $scopeRun = Join-Path $fixtureVault 'scope-quoted' '20300101T000000Z'
    New-Item -ItemType Directory -Force -Path $scopeRun | Out-Null
    @(
        '---', 'project: scope-quoted', 'review-type: adversarial-review',
        'date: 2030-01-01', "scope: `"$scopeBaseSha..$scopeReviewedTip`"", 'reviewers: [Fixture]', '---', '', '# Fixture', ''
    ) | Set-Content (Join-Path $scopeRun '_index.md')

    # Same quoted scope shape, but in a vault-ONLY folder so it flows through
    # Resolve-VaultTarget's own raw-text re-parse (stage 2) rather than Get-VaultData's
    # quote-stripped reviewScope - the two paths must tolerate the quote equally.
    $quotedScopeRun = Join-Path $fixtureVault 'zz-fixture-quoted-scope' '20300101T000000Z'
    New-Item -ItemType Directory -Force -Path $quotedScopeRun | Out-Null
    @(
        '---', 'project: zz-fixture-quoted-scope', 'review-type: adversarial-review',
        'date: 2030-01-01', "scope: `"$quotedBaseSha..HEAD`"", 'reviewers: [Fixture]', '---', '', '# Fixture', ''
    ) | Set-Content (Join-Path $quotedScopeRun '_index.md')
    @('# Fixture report', '', 'Prose-only report with no file link at all.', '') |
        Set-Content (Join-Path $quotedScopeRun 'report.md')

    # Review date (and run-folder timestamp) older than every fixture commit: the squash shape.
    $predateRun = Join-Path $fixtureVault 'predates' '20200101T000000Z'
    New-Item -ItemType Directory -Force -Path $predateRun | Out-Null
    @(
        '---', 'project: predates', 'review-type: adversarial-review',
        'date: 2020-01-01', 'reviewers: [Fixture]', '---', '', '# Fixture', ''
    ) | Set-Content (Join-Path $predateRun '_index.md')

    # Scan a temp root, not the estate: that is what makes this runnable on CI. -RepoRoots is
    # pinned too - it defaults to real estate paths, so on a developer machine the live
    # repositories would enter the SHA and name-search candidate lists and the
    # zz-fixture-unresolvable assertions would depend on estate contents rather than on the
    # fixture. Pinning it is what makes "hermetic" true rather than merely intended.
    & pwsh -NoProfile -File $script -Path $scanRoot -OutFile $fixtureOut -VaultRoot $fixtureVault -RepoRoots $fixtureRepos 2>$null
    if ($LASTEXITCODE -ne 0) { throw "collect.ps1 exited $LASTEXITCODE on the fixture vault" }
    $fx = Get-Content $fixtureOut -Raw | ConvertFrom-Json

    $main = $fx | Where-Object { $_.repo -eq 'placeholder' }
    if (-not $main) { throw "fixture 'placeholder' produced no row" }
    if ($main.git.boundarySha -ne $reviewedTip) { throw "exact vault target must anchor at reviewed tip '$reviewedTip', got '$($main.git.boundarySha)'" }
    if ($main.git.boundarySource -ne 'vault-target') { throw "exact vault target boundarySource should be 'vault-target', got '$($main.git.boundarySource)'" }
    if (@($main.git.reviewCommits | Where-Object { $_.sha -eq $proseSha }).Count) { throw "arbitrary prose/body word 'adversarial' must not create a git review marker" }
    if (@($main.git.reviewCommits | Where-Object { $_.sha -eq $strictMarkerSha }).Count -ne 1) { throw "strict numbered reviewer-findings batch subject must create one git review marker" }
    if (@($main.git.batchMarkers | Where-Object { $_ -match 'reviewer-findings batch 7' }).Count -ne 1) { throw "strict numbered reviewer-findings batch subject must emit its batch marker" }
    if (@($main.git.reviewCommits | Where-Object { $_.sha -eq $auditMarkerSha }).Count -ne 1) { throw "strict numbered adversarial-audit batch subject must create one git review marker" }
    if (@($main.git.batchMarkers | Where-Object { $_ -match 'adversarial-audit batch 8' }).Count -ne 1) { throw "strict numbered adversarial-audit batch subject must emit its batch marker" }

    $quotedScope = $fx | Where-Object { $_.repo -eq 'scope-quoted' }
    if (-not $quotedScope) { throw "fixture 'scope-quoted' produced no row" }
    if ($quotedScope.git.boundarySha -ne $scopeReviewedTip) { throw "quoted scope range must anchor at reviewed tip '$scopeReviewedTip', got '$($quotedScope.git.boundarySha)'" }
    if ($quotedScope.git.boundarySource -ne 'vault-target') { throw "quoted scope range boundarySource should be 'vault-target', got '$($quotedScope.git.boundarySource)'" }

    $markerOnly = $fx | Where-Object { $_.repo -eq 'marker-only' }
    if (-not $markerOnly) { throw "fixture 'marker-only' produced no row" }
    if ($markerOnly.git.boundarySource -ne 'git-marker') { throw "marker-only fixture should retain git-marker evidence, got '$($markerOnly.git.boundarySource)'" }
    if ($markerOnly.git.boundarySha) { throw "git-marker without strict batch evidence must clear its false boundary, got '$($markerOnly.git.boundarySha)'" }
    if (-not $markerOnly.git.effectiveNeverReviewed) { throw "git-marker without strict batch evidence must be effectively never reviewed" }
    if (-not $markerOnly.git.neverReviewed) { throw "cleared false marker boundary must also set neverReviewed=true" }
    if ($markerOnly.git.sinceReviewCount -ne 2) { throw "effectively never-reviewed marker fixture must use full-history scope (2 commits), got '$($markerOnly.git.sinceReviewCount)'" }
    # SKILL.md contracts daysSinceReview as null when never reviewed; a cleared git-marker still
    # carries lastReviewDate, and a number here would dress an unreviewed repo up as fresh.
    if ($null -ne $markerOnly.git.daysSinceReview) { throw "never-reviewed repo must report daysSinceReview=null, got '$($markerOnly.git.daysSinceReview)'" }

    # Vault review predating the repo's history (the squash shape): effectively never reviewed,
    # boundary cleared, scope = full history (2 commits) - not rootSha..HEAD, which would omit
    # everything the squash introduced.
    $pre = $fx | Where-Object { $_.repo -eq 'predates' }
    if (-not $pre) { throw "fixture 'predates' produced no row" }
    if ($pre.git.boundarySource -ne 'vault-predates-history') { throw "predates fixture boundarySource should be 'vault-predates-history', got '$($pre.git.boundarySource)'" }
    if (-not $pre.git.vaultPredatesHistory) { throw "predates fixture must set vaultPredatesHistory=true" }
    if (-not $pre.git.effectiveNeverReviewed) { throw "a vault review older than the repo's history must be effectively never reviewed" }
    if (-not $pre.git.neverReviewed) { throw "vault-predates-history must also set neverReviewed=true" }
    if ($pre.git.boundarySha) { throw "vault-predates-history must clear the root-commit boundary, got '$($pre.git.boundarySha)'" }
    if ($pre.git.sinceReviewCount -ne 2) { throw "predates fixture must use full-history scope (2 commits), got '$($pre.git.sinceReviewCount)'" }
    if ($null -ne $pre.git.daysSinceReview) { throw "never-reviewed predates fixture must report daysSinceReview=null, got '$($pre.git.daysSinceReview)'" }

    # A quoted scope line must survive Resolve-VaultTarget's raw-text stage 2: no file:/// link,
    # no name match, so only the sha can place it.
    $qscope = $fx | Where-Object { $_.repo -eq 'zz-fixture-quoted-scope' }
    if (-not $qscope) { throw "fixture 'zz-fixture-quoted-scope' produced no row" }
    if ($qscope.unresolved) { throw "a quoted scope sha must resolve through Resolve-VaultTarget stage 2 - the raw re-parse is not quote-tolerant" }
    if ($qscope.resolvedPath -ne $quotedRepo) { throw "quoted-scope fixture resolved to '$($qscope.resolvedPath)', expected '$quotedRepo'" }

    # A failing git probe is UNKNOWN (null), never a verified-empty $false.
    $broken = $fx | Where-Object { $_.repo -eq 'broken-git' }
    if (-not $broken) { throw "fixture 'broken-git' produced no row" }
    $htsProp = $broken.PSObject.Properties['hasTrackedSource']
    if ($null -eq $htsProp) { throw "broken-git row is missing hasTrackedSource entirely" }
    if ($null -ne $htsProp.Value) { throw "a failed ls-files probe must yield hasTrackedSource=null (UNKNOWN), got '$($htsProp.Value)'" }

    foreach ($fixture in $sourceFixtures) {
        $source = $fx | Where-Object { $_.repo -eq $fixture.name }
        if (-not $source) { throw "fixture '$($fixture.name)' produced no row" }
        if (-not $source.hasTrackedSource) { throw "tracked source detection must include '$($fixture.file)'" }
    }

    $root = $fx | Where-Object { $_.repo -eq 'zz-fixture-rootfile' }
    if (-not $root) { throw "fixture 'zz-fixture-rootfile' produced no row" }
    if ($root.unresolved) { throw "fixture rootfile should resolve via its file:/// link" }
    if ($root.resolvedPath -ne $linkRepo) { throw "fixture rootfile resolved to '$($root.resolvedPath)', expected '$linkRepo'" }
    if ($root.subsystemPath) { throw "a repo-ROOT file must yield NO subsystemPath, got '$($root.subsystemPath)' - the trailing-filename drop is duplicating a lone segment (0..-1)" }
    if ($root.isSubsystem) { throw "a repo-ROOT file must not be flagged isSubsystem - false subsystem regression" }

    $nested = $fx | Where-Object { $_.repo -eq 'zz-fixture-subsystem' }
    if (-not $nested) { throw "fixture 'zz-fixture-subsystem' produced no row" }
    if ($nested.unresolved) { throw "fixture subsystem should resolve via its file:/// link" }
    # Assert WHICH repo it picked, not just the subsystem fields: a regression that selects the
    # wrong repository would otherwise still satisfy the isSubsystem/subsystemPath checks.
    if ($nested.resolvedPath -ne $linkRepo) { throw "fixture subsystem resolved to '$($nested.resolvedPath)', expected '$linkRepo'" }
    if (-not $nested.isSubsystem) { throw "a NESTED file must be flagged isSubsystem" }
    if ((Normalize $nested.subsystemPath) -ne 'src/Foo') { throw "fixture subsystem path should be 'src/Foo', got '$($nested.subsystemPath)'" }

    # The unresolved contract, held by a fixture rather than by whatever the estate happens to
    # contain today. Without this a shape-only loop passes vacuously and a regression that
    # stopped emitting `unresolved` - reviving the silent frozen row - would ship green.
    $unres = $fx | Where-Object { $_.repo -eq 'zz-fixture-unresolvable' }
    if (-not $unres) { throw "fixture 'zz-fixture-unresolvable' produced no row - an unplaceable vault folder must still be emitted, never dropped" }
    if (-not $unres.unresolved) { throw "a vault folder with no file:/// link and no matching repo MUST be flagged unresolved, got unresolved=$($unres.unresolved) resolvedPath='$($unres.resolvedPath)'" }
    if ($unres.resolvedPath) { throw "unresolved fixture must have a null resolvedPath, got '$($unres.resolvedPath)'" }
    if ($unres.isSubsystem) { throw "unresolved fixture cannot be a subsystem" }
    if ($unres.subsystemPath) { throw "unresolved fixture must have no subsystemPath" }
    if (-not $unres.outsideScanPath) { throw "unresolved fixture must be flagged outsideScanPath" }
    if ($unres.git.boundarySource -ne 'unresolved-vault-folder') { throw "unresolved fixture boundarySource should be 'unresolved-vault-folder', got '$($unres.git.boundarySource)'" }
    # Deliberate exception to the neverReviewed contract - a review DID happen, we just cannot
    # place it. Flagging it $true would assert a falsehood AND score it 100 + commits, floating
    # an unknown to the top of the risk rank. See SKILL.md.
    #
    # Assert an explicit Boolean $false, not mere falsiness: a truthiness check also passes for
    # a MISSING or null property, so a regression that dropped `neverReviewed` altogether would
    # slip through. This property is the contract being defended here, so it is asserted exactly.
    $nrProp = $unres.git.PSObject.Properties['neverReviewed']
    if ($null -eq $nrProp) { throw "unresolved fixture is missing the neverReviewed property entirely" }
    if ($nrProp.Value -isnot [bool]) { throw "unresolved fixture neverReviewed must be a Boolean, got '$($nrProp.Value)'" }
    if ($nrProp.Value) { throw "unresolved fixture must explicitly set neverReviewed=false - its state is UNKNOWN, not 'never'" }
    $enrProp = $unres.git.PSObject.Properties['effectiveNeverReviewed']
    if ($null -eq $enrProp -or $enrProp.Value -isnot [bool] -or $enrProp.Value) { throw "unresolved fixture must explicitly set effectiveNeverReviewed=false" }

    # %20 decoding. Undecoded, 'spaced%20repo' is not a real directory, the .git walk finds
    # nothing, and a perfectly valid vault folder is reported unresolved.
    $enc = $fx | Where-Object { $_.repo -eq 'zz-fixture-encoded' }
    if (-not $enc) { throw "fixture 'zz-fixture-encoded' produced no row" }
    if ($enc.unresolved) { throw "a %20-encoded file:/// link must resolve - the URI is not being percent-decoded" }
    if ($enc.resolvedPath -ne $spacedRepo) { throw "encoded fixture resolved to '$($enc.resolvedPath)', expected '$spacedRepo'" }
    if ((Normalize $enc.subsystemPath) -ne 'src/Foo') { throw "encoded fixture subsystemPath should be 'src/Foo', got '$($enc.subsystemPath)'" }

    # Sibling-prefix boundary. Without it, 'app-old' passes StartsWith('...\app'), yields the
    # relative segment '-old\src\Foo\c.cs', and the common-prefix walk collapses to nothing.
    $sib = $fx | Where-Object { $_.repo -eq 'zz-fixture-sibling' }
    if (-not $sib) { throw "fixture 'zz-fixture-sibling' produced no row" }
    if ($sib.unresolved) { throw "sibling fixture should resolve to the most-linked repo" }
    if ($sib.resolvedPath -ne $appRepo) { throw "sibling fixture resolved to '$($sib.resolvedPath)', expected '$appRepo'" }
    if ((Normalize $sib.subsystemPath) -ne 'src/Foo') { throw "sibling fixture subsystemPath should be 'src/Foo', got '$($sib.subsystemPath)' - a prefix-overlapping sibling ('app-old') is being treated as part of 'app'" }

    "collect.ps1 resolver regression OK - root-file -> no subsystem; nested -> '$($nested.subsystemPath)'; unplaceable -> unresolved; %20 -> '$($enc.subsystemPath)'; sibling-boundary -> '$($sib.subsystemPath)' (all via production Resolve-VaultTarget)"
}
finally {
    Remove-Item $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
