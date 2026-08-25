<#
  Contract test for audit-dependabot-coverage's matcher.
  Run: pwsh -File ~/.agents/skills/audit-dependabot-coverage/test/verify-matcher.ps1

  BACKTESTED AGAINST THE CASE THAT MOTIVATED THE SKILL, not against invented input.
  Every fixture below is the real body shape captured from <your-org>/your-learning
  in August 2026, so the matcher is exercised on the exact bug it exists to catch
  (nanoid alert #4, open four days, no PR) and on the false-positive shape that would
  make the whole check noise (brace-expansion, genuinely covered by PR #196).

  Offline and deterministic on purpose: a test that hit the live API would change
  verdict as PRs merge, and would pass or fail for reasons unrelated to the matcher.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Source the matcher without running the sweep. Dot-sourcing reconcile.ps1 would
# execute it, so the function is extracted and re-defined here from the same file --
# guarded by a check that it still exists, so this test fails loudly if the function
# is renamed rather than silently testing a stale copy.
$script:reconcile = Join-Path (Split-Path -Parent $PSScriptRoot) 'reconcile.ps1'
if (-not (Test-Path $script:reconcile)) { throw "reconcile.ps1 not found at $script:reconcile" }

$src = $script:reconcile
# Extract each function via the AST, not a regex window. A non-greedy regex stopping
# at the first line-initial '}' only works while every internal brace happens to be
# indented: a here-string, a nested scriptblock or a reformat truncates the extraction,
# and `if (-not $m.Success)` catches only total non-match -- so the truncated body would
# dot-source as a DIFFERENT function than the one that ships. A guard whose scope
# depends on formatting is not a guard. Same fix as verify-pruned-traversal.ps1.
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw "reconcile.ps1 does not parse: $($parseErrors[0].Message)" }
foreach ($fn in @('Test-DependabotPrCoversPackage', 'ConvertFrom-PrListJson', 'Get-Prop',
                  'Get-AlertTarget', 'Test-DependabotPrTargetsAlert', 'Get-RepoList')) {
    $def = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true)
    if (-not $def) {
        throw "Could not extract $fn from reconcile.ps1 - was it renamed?"
    }
    . ([scriptblock]::Create($def.Extent.Text))
}

$fail = 0
function ok  { param($m) "ok   $m" }
function bad { param($m) $script:fail = 1; "FAIL $m" }

function Assert-Match {
    param([string]$Body, [string]$Pkg, [bool]$Expected, [string]$Label)
    $got = Test-DependabotPrCoversPackage -Body $Body -PackageName $Pkg
    if ($got -eq $Expected) { ok $Label } else { bad "$Label (want $Expected, got $got)" }
}

# --- real fixture: single-dep PR #196 ---------------------------------------
# Verbatim first line of the real body, plus the commit list that follows it.
$single = @'
Bumps [brace-expansion](https://github.com/juliangruber/brace-expansion) from 5.0.8 to 5.0.9.
<details>
<summary>Commits</summary>
<ul>
<li><a href="https://github.com/juliangruber/brace-expansion/commit/fbcf8ec"><code>fbcf8ec</code></a> 5.0.9</li>
</ul>
</details>
'@

Assert-Match -Body $single -Pkg 'brace-expansion' -Expected $true `
    -Label 'real single-dep body matches its own package (PR #196)'

# --- real fixture: grouped PR #212 ------------------------------------------
# Verbatim from the real body. The branch for this PR is
# dependabot/npm_and_yarn/web/npm-minor-and-patch-eff5aeb2ab and names NO package,
# which is why matching reads the body and not the branch.
$grouped = @'
Bumps the npm-minor-and-patch group with 6 updates in the /web directory:
Updates `@azure/msal-browser` from 5.17.3 to 5.18.0
Updates `@azure/msal-react` from 5.5.4 to 5.5.5
Updates `swr` from 2.4.2 to 2.5.0
Updates `@testing-library/user-event` from 14.6.1 to 14.6.3
Updates `globals` from 17.8.0 to 17.9.0
Updates `typescript-eslint` from 8.65.0 to 8.66.0
'@

Assert-Match -Body $grouped -Pkg '@azure/msal-browser' -Expected $true `
    -Label 'grouped body matches a scoped package (PR #212)'
Assert-Match -Body $grouped -Pkg 'swr' -Expected $true `
    -Label 'grouped body matches an unscoped package'

# THE REGRESSION THAT DEFINES THE SKILL. nanoid alert #4 was open for four days while
# PR #212 was the only open npm PR for /web. If the matcher counts #212 as covering
# nanoid, the sweep reports the repo clean and reproduces the exact silent miss.
Assert-Match -Body $grouped -Pkg 'nanoid' -Expected $false `
    -Label 'grouped body does NOT cover nanoid (the 2026-08-08 silent miss)'

# --- the dangerous false positive -------------------------------------------
# Dependabot embeds release notes and changelogs that name many unrelated packages.
# An unanchored substring match would treat every one as fixed, suppressing real
# findings -- the same silent-absence failure the skill exists to catch.
$withReleaseNotes = @'
Bumps [vite](https://github.com/vitejs/vite) from 8.2.0 to 8.2.1.
<details>
<summary>Release notes</summary>
<blockquote>
<h2>What's Changed</h2>
<ul>
<li>fix: bump nanoid to patch a CVE in the postcss dependency chain</li>
<li>chore: update swr and globals in the example app</li>
</ul>
</blockquote>
</details>
'@

Assert-Match -Body $withReleaseNotes -Pkg 'vite' -Expected $true `
    -Label 'body matches the package it actually bumps'
Assert-Match -Body $withReleaseNotes -Pkg 'nanoid' -Expected $false `
    -Label 'a package named only in RELEASE NOTES is not counted as fixed'
Assert-Match -Body $withReleaseNotes -Pkg 'swr' -Expected $false `
    -Label 'nor one named in a changelog bullet'

# --- regex-safety -----------------------------------------------------------
# A package name is interpolated into a pattern, so an unescaped name would let its
# metacharacters match. `.` is the one that actually occurs across this estate
# (Scalar.AspNetCore, Microsoft.Extensions.*), and it would match ANY character.
$nuget = 'Bumps [Scalar.AspNetCore](https://github.com/scalar/scalar) from 2.16.17 to 2.16.18.'
Assert-Match -Body $nuget -Pkg 'Scalar.AspNetCore' -Expected $true `
    -Label 'a dotted NuGet package matches itself'
Assert-Match -Body $nuget -Pkg 'ScalarXAspNetCore' -Expected $false `
    -Label 'the dot is escaped, not treated as any-char'

# --- degenerate input -------------------------------------------------------
# A PR whose body failed to fetch must never read as coverage: empty body plus a real
# package is precisely the shape an API hiccup produces, and counting it as a match
# would mark every alert in the repo covered.
Assert-Match -Body '' -Pkg 'nanoid' -Expected $false `
    -Label 'an empty body covers nothing'
Assert-Match -Body $single -Pkg '' -Expected $false `
    -Label 'an empty package name matches nothing'

# --- unreadable PR list must NOT read as "no PRs" ---------------------------
# THE FALSE-POSITIVE FLOOD PATH, and the one my own validation could not have caught.
# If a failed PR query is treated as an empty list, every alert in that repo has nothing
# to match against and every one is reported uncovered -- noise indistinguishable from
# real findings. The live run could not have exposed it either: the estate currently has
# zero open alerts, so nothing was ever compared.
#
# Raised in review of PR #59. Its stated cause was wrong -- `--author app/dependabot`
# does filter correctly (224 PRs total vs 71 filtered on your-repo, with
# non-Dependabot authors excluded) -- but the uncovered code path was real.
function Assert-PrList {
    param($Raw, [bool]$ExpectNull, [string]$Label)
    $got = ConvertFrom-PrListJson -Raw $Raw
    $isNull = ($null -eq $got)
    if ($isNull -eq $ExpectNull) { ok $Label } else { bad "$Label (expected null=$ExpectNull, got null=$isNull)" }
}

Assert-PrList -Raw $null           -ExpectNull $true  -Label 'a failed PR query is UNREADABLE, not an empty list'
Assert-PrList -Raw ''              -ExpectNull $true  -Label 'empty output is unreadable, not an empty list'
Assert-PrList -Raw '   '           -ExpectNull $true  -Label 'whitespace-only output is unreadable'
Assert-PrList -Raw 'not json {'    -ExpectNull $true  -Label 'unparseable output is unreadable'
Assert-PrList -Raw '[]'            -ExpectNull $false -Label 'a genuine empty array IS a readable result'
Assert-PrList -Raw '[{"number":1,"body":"Bumps [x](u) from 1 to 2."}]' -ExpectNull $false `
    -Label 'a populated array is readable'

# --- multi-page gh output shape ----------------------------------------------
# CodeRabbit claimed `gh api --paginate` emits each page as a SEPARATE JSON document,
# so without --slurp ConvertFrom-Json would fail on any multi-page response. Settled
# by live probe (gh 2.87.3, 2026-08-25): REST array pages are MERGED into ONE array
# document -- 90 PRs fetched at per_page=1 arrived as a single 90-element array that
# parses cleanly. The danger it alleged (a multi-page repo silently reading as empty
# or unreadable) therefore does not exist on current gh. Pin the shape gh actually
# emits -- one compact array spanning what were separate pages -- so a gh regression
# to separate documents fails loudly here instead of silently in the sweep.
$mergedPages = '[{"number":1,"body":"Bumps [a](u) from 1 to 2."},{"number":2,"body":"Bumps [b](u) from 3 to 4."}]'
$pageSet = ConvertFrom-PrListJson -Raw $mergedPages
if ($null -ne $pageSet -and @($pageSet).Count -eq 2) { ok 'a merged multi-page array parses as every page' }
else { bad 'a merged multi-page array parses as every page' }
# And if gh ever DID emit separate documents, the safe direction is UNREADABLE
# (skip the repo), never a partial or empty read: assert that shape is not parsed.
Assert-PrList -Raw ("[{`"number`":1}]" + "`n" + '[{"number":2}]') -ExpectNull $true `
    -Label 'separate JSON documents per page would be UNREADABLE, never a partial read'

# And the readable-empty case must survive as an enumerable, or a repo with alerts and
# genuinely no Dependabot PRs would crash rather than report.
$emptySet = ConvertFrom-PrListJson -Raw '[]'
if (@($emptySet).Count -eq 0) { ok 'a readable empty result enumerates as zero PRs' }
else { bad 'a readable empty result enumerates as zero PRs' }

# --- Get-Prop: the safe accessor --------------------------------------------
# Load-bearing defensive code on every alert field, so a regression here would blind
# the tool to malformed payloads silently. Raised in review of PR #59.
#
# Fixtures come from ConvertFrom-Json rather than hand-built hashtables, because that
# is the only shape it is ever given -- Get-Prop reads PSObject.Properties, which does
# NOT enumerate hashtable keys, so a hashtable fixture would test behaviour the tool
# never relies on and would pass or fail for the wrong reason.
$alertLike = '{"number":4,"dependency":{"package":{"name":"nanoid"},"scope":"development"},
  "security_vulnerability":{"first_patched_version":{"identifier":"3.3.17"}}}' | ConvertFrom-Json
$noFix     = '{"number":9,"security_vulnerability":{"first_patched_version":null}}' | ConvertFrom-Json

function Assert-Prop {
    param($Object, [string[]]$Path, $Default, $Expected, [string]$Label)
    $got = Get-Prop $Object $Path $Default
    if ($got -eq $Expected) { ok $Label } else { bad "$Label (want '$Expected', got '$got')" }
}

Assert-Prop -Object $alertLike -Path @('number') -Expected 4 `
    -Label 'Get-Prop reads a top-level value'
Assert-Prop -Object $alertLike -Path @('dependency', 'package', 'name') -Expected 'nanoid' `
    -Label 'Get-Prop walks a nested path'
Assert-Prop -Object $alertLike -Path @('security_vulnerability', 'first_patched_version', 'identifier') `
    -Expected '3.3.17' -Label 'Get-Prop reads a present patched version'

# THE CASE IT WAS WRITTEN FOR. A null intermediate is what a no-fix-available advisory
# looks like, and StrictMode throws on property access through it -- which crashed the
# live run before this existed. 'none' is the meaningful rendering, not absence.
Assert-Prop -Object $noFix -Path @('security_vulnerability', 'first_patched_version', 'identifier') `
    -Default 'none' -Expected 'none' `
    -Label 'a null intermediate yields the default, not a crash (no fix available)'

Assert-Prop -Object $alertLike -Path @('nope') -Default 'fallback' -Expected 'fallback' `
    -Label 'a missing property yields the default'
Assert-Prop -Object $alertLike -Path @('dependency', 'nope', 'deeper') -Default 'fallback' `
    -Expected 'fallback' -Label 'a missing intermediate yields the default'
Assert-Prop -Object $null -Path @('anything') -Default 'fallback' -Expected 'fallback' `
    -Label 'a null object yields the default'

# No explicit Default means $null, and it must not become the string 'null' or throw.
$implicit = Get-Prop $alertLike @('nope')
if ($null -eq $implicit) { ok 'a missing property with no Default yields $null' }
else { bad "a missing property with no Default yields `$null (got '$implicit')" }

# --- directory + ecosystem agreement -------------------------------------------
# A package-name body match is not coverage in a monorepo: a PR bumping a package in
# /web must not mark the same package's /api alert covered. The PR's target comes
# from its branch (dependabot/<ecosystem>/<directory...>/<update>); when it cannot
# be established, the alert stays unmatched -- unresolvable is not covered.
$alertWeb = Get-AlertTarget -Alert ('{"dependency":{"manifest_path":"web/package-lock.json","package":{"ecosystem":"npm"}}}' | ConvertFrom-Json)
$alertApi = Get-AlertTarget -Alert ('{"dependency":{"manifest_path":"api/package-lock.json","package":{"ecosystem":"npm"}}}' | ConvertFrom-Json)
$prWeb   = '{"head":{"ref":"dependabot/npm_and_yarn/web/npm-minor-and-patch-eff5aeb2ab"}}' | ConvertFrom-Json
$prRoot  = '{"head":{"ref":"dependabot/npm_and_yarn/brace-expansion-5.0.9"}}' | ConvertFrom-Json
$prNuget = '{"head":{"ref":"dependabot/nuget/web/Scalar.AspNetCore-2.16.18"}}' | ConvertFrom-Json
$prOdd   = '{"head":{"ref":"feature/no-dependabot-shape"}}' | ConvertFrom-Json

function Assert-Target {
    param($Pr, $Target, [bool]$Expected, [string]$Label)
    $got = Test-DependabotPrTargetsAlert -Pr $Pr -AlertTarget $Target
    if ($got -eq $Expected) { ok $Label } else { bad "$Label (want $Expected, got $got)" }
}

Assert-Target -Pr $prWeb -Target $alertWeb -Expected $true `
    -Label 'a PR targets the directory and ecosystem its branch names'
Assert-Target -Pr $prWeb -Target $alertApi -Expected $false `
    -Label 'a /web PR does NOT cover the same package alert in /api'
Assert-Target -Pr $prRoot -Target (Get-AlertTarget -Alert ('{"dependency":{"manifest_path":"package-lock.json","package":{"ecosystem":"npm"}}}' | ConvertFrom-Json)) -Expected $true `
    -Label 'a root single-dep branch targets the root manifest'
Assert-Target -Pr $prNuget -Target $alertWeb -Expected $false `
    -Label 'an npm alert is not covered by a nuget PR in the same directory'
Assert-Target -Pr $prOdd -Target $alertWeb -Expected $false `
    -Label 'a non-Dependabot branch shape is unresolvable, not covered'
if ($null -eq (Get-AlertTarget -Alert ('{"dependency":{"package":{"ecosystem":"npm"}}}' | ConvertFrom-Json))) {
    ok 'an alert without a manifest path has no establishable target'
} else {
    bad 'an alert without a manifest path has no establishable target'
}

# --- owner-type routing in Get-RepoList ----------------------------------------
# -Org is documented to accept an organisation OR a user, but `orgs/{o}/repos` 404s on
# a user owner. Get-RepoList must resolve the owner type first and pick the endpoint.
# Invoke-Gh is stubbed so the routing is exercised offline; the stub records the args.
$script:ghCalls = [System.Collections.Generic.List[object]]::new()
function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $script:ghCalls.Add(@($Arguments))
    if ($Arguments -contains '--paginate') { return @('acme/widget') }
    return 'Organization'
}
$null = @(Get-RepoList -Orgs @('acme') -Explicit $null)
$paginated = @($script:ghCalls | Where-Object { $_ -contains '--paginate' })
if ($paginated.Count -eq 1 -and ($paginated[0] -join ' ') -match '^api --paginate orgs/acme/repos\?per_page=100') {
    ok 'an Organization owner routes to orgs/{o}/repos'
} else { bad "an Organization owner routes to orgs/{o}/repos (got '$($paginated | ForEach-Object { $_ -join ' ' })')" }

$script:ghCalls.Clear()
function Invoke-Gh {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $script:ghCalls.Add(@($Arguments))
    if ($Arguments -contains '--paginate') { return @('someone/widget') }
    return 'User'
}
$null = @(Get-RepoList -Orgs @('someone') -Explicit $null)
$paginated = @($script:ghCalls | Where-Object { $_ -contains '--paginate' })
if ($paginated.Count -eq 1 -and ($paginated[0] -join ' ') -match '^api --paginate users/someone/repos\?per_page=100') {
    ok 'a User owner routes to users/{o}/repos, not the 404ing orgs endpoint'
} else { bad "a User owner routes to users/{o}/repos, not the 404ing orgs endpoint (got '$($paginated | ForEach-Object { $_ -join ' ' })')" }

# --- red check --------------------------------------------------------------
# A suite that cannot fail is not a suite. This asserts a deliberately false
# expectation is reported as a failure, then repairs the counter.
$before = $script:fail
$script:fail = 0
$null = Assert-Match -Body $single -Pkg 'brace-expansion' -Expected $false -Label 'red-check probe'
if ($script:fail -eq 1) { $script:fail = $before; ok 'red check: a false expectation is reported as a failure' }
else { $script:fail = 1; bad 'red check: a false expectation is reported as a failure' }

''
if ($script:fail -eq 0) {
    # The suite's deliberately-failing probes (and the gh/git calls of dot-sourced
    # helpers) can leave a nonzero LASTEXITCODE behind; ci.yml's shared loop would
    # otherwise read this PASS as a failure.
    $global:LASTEXITCODE = 0
    'PASS'
    exit 0
} else { 'FAILURES ABOVE'; exit 1 }
