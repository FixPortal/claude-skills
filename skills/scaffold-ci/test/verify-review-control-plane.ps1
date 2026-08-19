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
$assets = Join-Path $root 'assets'
foreach ($asset in 'review-policy-guard.yml', 'review-policy.example.json', 'assert_gate_coverage.py') {
    if (-not (Test-Path -LiteralPath (Join-Path $assets $asset) -PathType Leaf)) {
        throw "scaffold-ci must ship $asset under assets/, not reference a runtime-specific path"
    }
}
if ($text -match [regex]::Escape('~/.claude/resources/')) {
    throw 'scaffold-ci cites a Claude-only asset path; use ~/.agents/skills/scaffold-ci/assets/'
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
foreach ($assertion in '[0-9a-f]{40}', 'pull_request_target', 'write-all') {
    if ($guard -notmatch [regex]::Escape($assertion)) {
        throw "the guard has lost the workflow-hygiene assertion that replaced the high glob: $assertion"
    }
}
# Scoped to third-party owners on purpose: a gate on all owners would have failed 27 of 28
# estate repos, since every unpinned ref measured was actions/*.
if ($guard -notmatch [regex]::Escape('actions/*)')) {
    throw 'the guard must exempt first-party actions/* from the pin FAILURE, or it reddens the estate'
}
# Required status check across the estate; renaming it detaches the branch rule silently.
if ($guard -notmatch [regex]::Escape('name: Review policy intact')) {
    throw 'the guard job must stay named "Review policy intact" - it is a required status check'
}

# THE GUARD MUST NOT FLAG ITSELF. It greps .github/workflows, and it is installed INTO
# .github/workflows, so its own prose falls in scope of its own patterns. The first
# version shipped a write-all grep that matched the comment EXPLAINING the write-all rule,
# so the guard failed in every repo it was installed into - found on a one-repo pilot,
# after code review had passed it clean.
#
# Patterns are extracted from the file rather than restated here: a restated copy drifts
# from the grep it is meant to be testing, which is exactly how the inlined-snippet drift
# happened before.
foreach ($line in ($guard -split "`r?`n")) {
    if ($line -notmatch "grep -rEn '([^']+)'") { continue }
    $pattern = $Matches[1]
    $net = $pattern -replace '\[\[:space:\]\]', '\s'   # POSIX class -> .NET, enough for these
    $offenders = @(($guard -split "`r?`n") | Where-Object { $_ -match $net })
    if ($offenders.Count -gt 0) {
        throw "the guard's own text matches its own pattern '$pattern' ($($offenders.Count) line(s)) and would fail in every repo. First: $($offenders[0].Trim())"
    }
}

'scaffold-ci review control plane OK'
