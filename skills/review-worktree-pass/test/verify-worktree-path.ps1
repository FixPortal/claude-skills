$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw

# ~/.codex/AGENTS.md and ~/.kimi-code/AGENTS.md both state the worktree directory
# "is `.claude` regardless of which agent you are, and is not a Codex config path".
# A per-runtime example splits what is meant to be one shared worktree per project.
foreach ($pattern in '\.Codex\\+worktrees', 'under the running runtime''s') {
    if ($text -match $pattern) {
        throw "SKILL.md contradicts the AGENTS.md worktree-path correction: $pattern"
    }
}

foreach ($needle in 'regardless of which agent', '.claude\worktrees\reviewer-passes') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md missing the corrected worktree-path rule: $needle"
    }
}

# A third superseded pattern, naming a private project code, is omitted from this
# public mirror; the two below carry the same regression contract.
foreach ($pattern in 'remote branch gone \+ matching commit titles,\s*or an empty', 'Covers which checkout') {
    if ($text -match $pattern) { throw "SKILL.md retains a superseded worktree contract: $pattern" }
}

foreach ($needle in 'both', 'remote branch is gone', 'commit titles match', 'supplemental evidence', 'outside the review worktree') {
    if ($text -notmatch [regex]::Escape($needle)) { throw "SKILL.md missing safe teardown contract: $needle" }
}

if ($text -notmatch '(?m)^description:.*selecting or implementing remediation actions') {
    throw 'SKILL.md selector must target remediation actions'
}

if ($text -notmatch '(?m)^description:.*Do not use for read-only review, review-digest, or audit requests') {
    throw 'SKILL.md selector must exclude read-only review, digest, and audit requests'
}

$normalized = $text -replace '\s+', ' '
$fetch = $normalized.IndexOf('`git fetch --prune`', [System.StringComparison]::Ordinal)
$batch = $normalized.IndexOf('select the next batch number', [System.StringComparison]::Ordinal)
$origin = $normalized.IndexOf('create the branch from `origin/main`', [System.StringComparison]::Ordinal)
if ($fetch -lt 0 -or $batch -lt 0 -or $origin -lt 0 -or $fetch -gt $batch -or $fetch -gt $origin) {
    throw 'SKILL.md must require discrete git fetch --prune before batch selection and origin/main branching'
}

$absentWorktree = [regex]::Match($normalized, 'If the review worktree is absent.*?verified primary checkout.*?`git fetch --prune`.*?select the next batch number.*?`git worktree add`.*?`origin/main`')
if (-not $absentWorktree.Success) {
    throw 'SKILL.md must recreate an absent review worktree from refreshed origin/main after fetching in the verified primary checkout'
}

$existingWorktree = [regex]::Match($normalized, 'If the review worktree already exists.*?`git fetch --prune`.*?before any new branch choice')
if (-not $existingWorktree.Success) {
    throw 'SKILL.md must fetch inside an existing review worktree before branch selection'
}

'review-worktree-pass worktree path OK'
