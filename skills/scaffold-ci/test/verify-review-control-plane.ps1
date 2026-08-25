$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$text = @(
    Get-Content (Join-Path $root 'SKILL.md') -Raw
    Get-ChildItem (Join-Path $root 'references') -Filter '*.md' | ForEach-Object { Get-Content $_.FullName -Raw }
) -join "`n"

# .gitignore was removed from the review-policy `high` list on 2026-08-02 and replaced
# by a CI guard. scaffold-ci/assets/review-policy.example.json says verbatim:
# "Do NOT re-add .gitignore here without first checking whether that CI guard is
# present in the repo." Scaffolding it HIGH reintroduces a superseded rule and bills a
# metered CodeRabbit review for every trivial ignore edit.
if ($text -match '`\.claude/review-policy\.json`\s*\r?\n?\s*itself, `\.coderabbit\.yaml`, and `\.gitignore`') {
    throw "SKILL.md still mandates .gitignore in the review control plane's HIGH list"
}

# The guard workflow that replaced it must be scaffolded as its own control surface.
foreach ($needle in 'review-policy-guard.yml',
                    'git check-ignore --no-index',
                    'ten control surfaces') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md missing the review-policy guard: $needle"
    }
}

# The guard and the policy example must SHIP with the skill, at the cross-CLI canonical
# path. They previously lived only under ~/.claude/resources/, which no non-Claude runtime
# can resolve - so a Codex/Kimi/Antigravity caller following this skill got an ad-hoc
# policy or none, and a repo with no policy tiers every PR NORMAL: the exact failure the
# section exists to prevent. ci-workflow.md already states the rule ("not any single
# runtime's skills root"); this holds the assets to it.
#
# The hygiene checker is on the list because the guard now delegates to it: copying the
# workflow without the script leaves the required check red on a missing file, and the
# references must say so (the copy instruction is the text check below).
$assets = Join-Path $root 'assets'
foreach ($asset in 'review-policy-guard.yml', 'review-policy.example.json', 'assert_gate_coverage.py', 'assert_workflow_hygiene.py') {
    if (-not (Test-Path -LiteralPath (Join-Path $assets $asset) -PathType Leaf)) {
        throw "scaffold-ci must ship $asset under assets/, not reference a runtime-specific path"
    }
}
if ($text -match [regex]::Escape('~/.claude/resources/')) {
    throw 'scaffold-ci cites a Claude-only asset path; use ~/.agents/skills/scaffold-ci/assets/'
}
# The references must tell the consumer to copy the checker alongside the guard workflow;
# without that instruction a scaffolded repo gets a guard whose one assertion step fails
# on a missing .github/scripts/assert_workflow_hygiene.py.
if ($text -notmatch [regex]::Escape('cp ~/.agents/skills/scaffold-ci/assets/assert_workflow_hygiene.py .github/scripts/')) {
    throw 'references must carry the copy instruction for assert_workflow_hygiene.py next to the guard copy'
}

# The guard must be COPIED, not paraphrased. An inlined snippet drifted from the asset and
# silently lost four of its checks; these are the ones that were missing.
$guard = Get-Content (Join-Path $assets 'review-policy-guard.yml') -Raw
foreach ($check in '-s "$policy"', 'jq -e . "$policy"', 'has("high")', 'permissions:') {
    if ($guard -notmatch [regex]::Escape($check)) {
        throw "the shipped review-policy guard has lost a content check: $check"
    }
}

$widePush = "branches: ['**']"
if ($text -match [regex]::Escape($widePush) -or $guard -match [regex]::Escape($widePush)) {
    throw 'scaffold-ci must not emit duplicate push and pull_request runs for PR branches'
}

# `.github/workflows/**` left the policy's high list on 2026-08-19 and is asserted in the
# guard instead. Scaffolding it HIGH again reinstates a superseded rule and re-spends a
# metered CodeRabbit review on every workflow edit - measured at four actionable comments
# across 27 config-only HIGH PRs in a month, while 45 of 100 HIGH PRs were throttled out
# entirely. The example policy carries the same instruction in its own $comment block.
$policyExample = Get-Content (Join-Path $assets 'review-policy.example.json') -Raw
$policy = $policyExample | ConvertFrom-Json
if ($policy.high -contains '.github/workflows/**') {
    throw "the example policy tiers .github/workflows/** HIGH again; the guard's assertions replaced it"
}
# The trade only holds while the assertions that replaced the glob are actually shipped.
# They live in the structural checker now, not in the guard: the line-anchored greps were
# bypassable by ordinary block-style YAML (a value on the line after its key), so the
# guard delegates to a YAML parse. The checker must carry all three rules.
$checkerPath = Join-Path $assets 'assert_workflow_hygiene.py'
$checker = Get-Content $checkerPath -Raw
# The checker ships in two places that must stay byte-identical: this asset, which a
# scaffolded repo copies from, and the live copy gating THIS repository. A text check on
# the asset alone certifies nothing about the copy that actually runs here - compare
# bytes, so the two cannot drift apart silently.
$liveCheckerPath = Join-Path (Join-Path (Join-Path (Join-Path $root '..') '..') '.github') (Join-Path 'scripts' 'assert_workflow_hygiene.py')
if (-not (Test-Path -LiteralPath $liveCheckerPath -PathType Leaf)) {
    throw 'live hygiene checker missing at .github/scripts/assert_workflow_hygiene.py; the asset has no live copy to stay in parity with'
}
if ((Get-FileHash $checkerPath).Hash -ne (Get-FileHash $liveCheckerPath).Hash) {
    throw 'assets/assert_workflow_hygiene.py and .github/scripts/assert_workflow_hygiene.py have drifted; edit both together'
}
foreach ($assertion in 'SHA_LEN = 40', 'pull_request_target', 'write-all') {
    if ($checker -notmatch [regex]::Escape($assertion)) {
        throw "the shipped hygiene checker has lost the assertion that replaced the high glob: $assertion"
    }
}
# ...and the guard must actually invoke it, or the checker ships but never runs.
if ($guard -notmatch [regex]::Escape('python3 .github/scripts/assert_workflow_hygiene.py')) {
    throw 'the shipped review-policy guard no longer invokes the structural hygiene checker'
}
# Scoped to third-party owners on purpose: a gate on all owners would have failed 27 of 28
# estate repos, since every unpinned ref measured was actions/* -- and the house standard
# gives first-party actions the major tag, so a tag-pinned actions/* ref is conformant.
if ($checker -notmatch [regex]::Escape('startswith("actions/")')) {
    throw 'the checker must exempt first-party actions/* from the pin FAILURE, or it reddens the estate'
}
# The exemption must not carry the superseded "pin it when convenient / flip to a failure"
# framing: the house standard is the inverse (audit-ci grades a SHA-pinned first-party
# action as drift), so the notice told repos to do the wrong thing.
foreach ($stale in 'pin it when convenient', 'Flip this to a failure', 'Flip it to a failure') {
    if ($checker -match [regex]::Escape($stale) -or $guard -match [regex]::Escape($stale)) {
        throw "superseded first-party pinning instruction still present: $stale"
    }
}
# Required status check across the estate; renaming it detaches the branch rule silently.
if ($guard -notmatch [regex]::Escape('name: Review policy intact')) {
    throw 'the guard job must stay named "Review policy intact" - it is a required status check'
}

# The required context is produced by the PR's OWN copy of the guard, so the guard and its
# checker must themselves tier HIGH in the example policy - otherwise a PR neutering them
# (assertion steps replaced with `run: true`) reports green under the lighter review.
foreach ($controlPlane in '.github/workflows/review-policy-guard.yml', '.github/scripts/assert_workflow_hygiene.py') {
    if ($policy.high -notcontains $controlPlane) {
        throw "the example policy must tier its own control plane HIGH: $controlPlane"
    }
    if ($guard -notmatch [regex]::Escape($controlPlane)) {
        throw "the guard's required-paths loop no longer asserts $controlPlane stays HIGH"
    }
}

# THE SHIPPED CHECKER MUST CATCH WHAT THE GREPS MISSED. The greps were replaced because
# ordinary block-style YAML bypassed them: a value may sit on the line after its key, so
# `permissions:` with an indented `write-all`, or a `uses:` split the same way, resolved
# to a violation while matching no pattern. Asserting the guard's TEXT carries the rules
# certifies nothing about that; the divergent input has to be fed to the shipped checker
# and must FAIL it. A clean fixture guards the other direction.
#
# The checker resolves .github/workflows relative to the working directory, so each
# fixture runs from its own temp root. Exit code, not a thrown error: a failing child
# process is the EXPECTED outcome of the negative fixtures, and $ErrorActionPreference
# does not intercept native exit codes.
$fixtures = @(
    @{
        Name     = 'clean fixture passes'
        WantExit = 0
        Workflow = @(
            'name: ok'
            'on: [push]'
            'permissions:'
            '  contents: read'
            'jobs:'
            '  build:'
            '    runs-on: ubuntu-latest'
            '    steps:'
            '      - uses: actions/checkout@v7'
            '      - uses: third/party@0123456789abcdef0123456789abcdef01234567'
        ) -join "`n"
    },
    @{
        Name     = 'block-style write-all fails'
        WantExit = 1
        Workflow = @(
            'name: bad'
            'on: [push]'
            'permissions:'
            '  write-all'
            'jobs:'
            '  build:'
            '    runs-on: ubuntu-latest'
            '    steps: []'
        ) -join "`n"
    },
    @{
        Name     = 'split uses ref fails'
        WantExit = 1
        Workflow = @(
            'name: bad'
            'on: [push]'
            'jobs:'
            '  build:'
            '    runs-on: ubuntu-latest'
            '    steps:'
            '      - uses:'
            '          third/party@v1'
        ) -join "`n"
    },
    @{
        # `on:` spelled as a YAML MAPPING: the trigger rule is otherwise only
        # string-asserted against the checker's source, while the two rules above
        # already prove themselves against the shipped checker. YAML 1.1 reads the
        # bare key as boolean True, so this also exercises the True-key lookup.
        Name     = 'mapping-style pull_request_target fails'
        WantExit = 1
        Workflow = @(
            'name: bad'
            'on:'
            '  pull_request_target:'
            '    branches: [main]'
            'jobs:'
            '  build:'
            '    runs-on: ubuntu-latest'
            '    steps: []'
        ) -join "`n"
    },
    @{
        # The first-party exemption is the vN major tag, not any ref: a branch ref is
        # mutable and must fail the same way an unpinned third-party action does.
        Name     = 'first-party branch ref fails'
        WantExit = 1
        Workflow = @(
            'name: bad'
            'on: [push]'
            'jobs:'
            '  build:'
            '    runs-on: ubuntu-latest'
            '    steps:'
            '      - uses: actions/checkout@main'
        ) -join "`n"
    }
)

$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host 'SKIP: python3 not on PATH; hygiene checker fixtures not run'
} else {
    foreach ($fixture in $fixtures) {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("hygiene-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp '.github/workflows') -Force | Out-Null
        # WriteAllText, not Set-Content: the fixture must be LF-only and encoding-exact.
        [IO.File]::WriteAllText((Join-Path $tmp '.github/workflows/fixture.yml'), $fixture.Workflow + "`n")
        Push-Location $tmp
        try {
            & python3 $checkerPath *>$null
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
            Remove-Item $tmp -Recurse -Force
        }
        if ($code -ne $fixture.WantExit) {
            throw "hygiene checker fixture '$($fixture.Name)': expected exit $($fixture.WantExit), got $code"
        }
    }
}

'scaffold-ci review control plane OK'

# The last hygiene fixture may deliberately exit nonzero — asserted, not fatal. Clear
# its native status so a caller that checks $LASTEXITCODE after a PASS does not read it.
$global:LASTEXITCODE = 0
