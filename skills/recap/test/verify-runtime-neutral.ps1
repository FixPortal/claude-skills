$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path (Join-Path $PSScriptRoot '..') 'SKILL.md') -Raw
$flat = $text -replace '\s+', ' '

if ($text -match '(?i)~[/\\]\.claude') {
    throw 'Shared recap must not read or write Claude-specific paths'
}
foreach ($needle in '~/.agents/recap/', 'active runtime''s user-level instruction file',
                     'explicitly delegates', 'icm.exe', 'on `PATH`',
                     'No runtime-level instruction file for this host',
                     'Actionable Now', 'Deferred', 'Unverifiable',
                     'Operator Gated', 'Information Only') {
    if ($flat -notmatch [regex]::Escape($needle)) {
        throw "Shared recap missing host-neutral contract: $needle"
    }
}

$words = ([regex]::Matches($text, '\b[\w/-]+\b')).Count
if ($words -ge 1200) { throw "recap/SKILL.md is $words words; keep detailed rules in references" }
if ($text -match 'split by \*\*actionability\*\*.*three buckets') {
    throw 'recap overview still claims only three buckets'
}
foreach ($ref in 'classification.md', 'journal.md') {
    $references = Join-Path (Join-Path $PSScriptRoot '..') 'references'
    if (-not (Test-Path (Join-Path $references $ref) -PathType Leaf)) {
        throw "recap missing reference: $ref"
    }
}

foreach ($needle in '../close/references/topic-key.ps1',
                     'Get-RepositoryTopicInfo',
                     '$repoRoot', '$repoDisplayName', '$repoTopicKey',
                     '$contextTopic', '$decisionsTopic',
                     'Before selecting a memory provider') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "recap missing collision-resistant topic derivation: $needle"
    }
}
foreach ($needle in '$recipePath = (Resolve-Path (Join-Path $PSScriptRoot ''..\close\references\topic-key.ps1'')).Path',
                     '. $recipePath',
                     '$topicInfo = Get-RepositoryTopicInfo -RepositoryRoot $repoRoot',
                     '$repoDisplayName = $topicInfo.DisplayName',
                     '$repoTopicKey = $topicInfo.TopicKey',
                     '$contextTopic = $topicInfo.ContextTopic',
                     '$decisionsTopic = $topicInfo.DecisionsTopic') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "recap must load and assign the shared topic recipe: $needle"
    }
}
# recap is the READ side of the topic contract, so it is where the 2026-08-12 key change
# actually did its damage: the hash suffix landed with no migration, and recap kept reading
# only the new topic. Measured that day - context-.claude held 27 memories, the derived
# context-.claude-<sha> held 1, and recap could see only the 1. Enumerating the legacy
# topics alongside is what makes the pre-change history reachable again.
# recap must read the recipe's deduplicated set rather than assembling topics by hand.
# Hand-assembly is what produced this defect twice over: the hashed pair was added and the
# unsuffixed pair silently dropped, and the remote-named pair was never in the list at all.
if ($text -notmatch [regex]::Escape('$topicInfo.ReadTopics')) {
    throw 'recap must read $topicInfo.ReadTopics, not a hand-assembled topic list'
}
$recallInvocation = [regex]::Match($text, 'recall-icm-topics\.ps1"?\s+-Topics\s+[^\r\n]*')
if (-not $recallInvocation.Success) {
    throw 'recap does not pass -Topics to the ICM recall helper'
}
if ($recallInvocation.Value -notmatch [regex]::Escape('ReadTopics')) {
    throw "recap recall call does not enumerate the derived read set: $($recallInvocation.Value.Trim())"
}
# A literal topic in the call is a hard-coded channel that silently stops matching the
# recipe the next time the key format moves - which is precisely how this broke.
if ($recallInvocation.Value -match '"context-|"decisions-') {
    throw "recap recall call hard-codes a topic name: $($recallInvocation.Value.Trim())"
}
# The remote name has to come from somewhere, or ReadTopics is only ever the 4-topic form
# and the remote-named topic entries stay unreachable.
if ($text -notmatch [regex]::Escape('-RemoteName')) {
    throw 'recap never supplies -RemoteName, so remote-named topics are never derived'
}

$recipeIndex = $text.IndexOf('Get-RepositoryTopicInfo', [System.StringComparison]::Ordinal)
$branchIndex = $text.IndexOf("Now use the runtime's native project-memory recall", [System.StringComparison]::Ordinal)
if ($recipeIndex -lt 0 -or $branchIndex -lt 0 -or $recipeIndex -gt $branchIndex) {
    throw 'recap initializes repository topics only after selecting the memory provider'
}
if ($text -notmatch [regex]::Escape('references/recall-icm-topics.ps1')) {
    throw 'recap does not use the executable exact-topic ICM recall contract'
}

$recallScript = Join-Path (Join-Path $PSScriptRoot '..') 'references\recall-icm-topics.ps1'
if (-not (Test-Path $recallScript -PathType Leaf)) {
    throw 'recap missing executable exhaustive ICM recall helper'
}
$icmCalls = [Collections.Generic.List[object]]::new()
$recall = @(& $recallScript -Topics @('context-repo-a', 'decisions-repo-a') -InvokeIcm {
    param([string[]]$Arguments)
    $icmCalls.Add(@($Arguments))
    $topic = $Arguments[2]
    @(1..6 | ForEach-Object { [pscustomobject]@{ topic = $topic; summary = "body-$topic-$_" } }) | ConvertTo-Json
})
if ($recall.Count -ne 2 -or $recall[0].Bodies.Count -ne 6 -or $recall[1].Bodies.Count -ne 6) {
    throw 'recap exhaustive ICM recall dropped a topic body'
}
if ($icmCalls.Count -ne 2 -or @($icmCalls | Where-Object { $_ -notcontains '--all' -or $_ -contains '--limit' }).Count -ne 0) {
    throw 'recap ICM recall can fall back to a truncated result set'
}

$workingStateScript = Join-Path (Join-Path $PSScriptRoot '..') 'references\get-working-state.ps1'
if (-not (Test-Path $workingStateScript -PathType Leaf)) {
    throw 'recap missing executable working-state helper'
}
$repo = Join-Path ([IO.Path]::GetTempPath()) "recap-working-state-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $repo | Out-Null
    # Every setup call is checked: a failed init or add leaves an empty repo, and the
    # staged-only assertion below would then be measuring nothing while passing.
    git -C $repo init --quiet
    if ($LASTEXITCODE -ne 0) { throw "fixture git init failed (exit $LASTEXITCODE)" }
    git -C $repo config user.email recap-test@example.invalid
    if ($LASTEXITCODE -ne 0) { throw "fixture git config user.email failed (exit $LASTEXITCODE)" }
    git -C $repo config user.name recap-test
    if ($LASTEXITCODE -ne 0) { throw "fixture git config user.name failed (exit $LASTEXITCODE)" }
    Set-Content (Join-Path $repo 'staged-only.txt') 'staged only'
    git -C $repo add staged-only.txt
    if ($LASTEXITCODE -ne 0) { throw "fixture git add failed (exit $LASTEXITCODE)" }
    $state = & $workingStateScript -RepositoryRoot $repo
    if ([string]::IsNullOrWhiteSpace($state.StagedStat) -or -not [string]::IsNullOrWhiteSpace($state.UnstagedStat)) {
        throw 'recap working-state gathering omits staged-only changes or conflates them with unstaged changes'
    }

    # A failed git call must not read as a clean tree. $ErrorActionPreference = 'Stop'
    # does NOT trip on a native nonzero exit, so an unchecked `git status` in a path that
    # is not a repository returns empty output - and empty status, empty staged stat and
    # empty unstaged stat is exactly what a genuinely clean repo looks like. Recap would
    # then reconstruct "nothing in progress" from a lookup that never ran.
    $notARepo = Join-Path ([IO.Path]::GetTempPath()) "recap-not-a-repo-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $notARepo | Out-Null
    try {
        $threw = $false
        try { & $workingStateScript -RepositoryRoot $notARepo | Out-Null }
        catch { $threw = $true }
        if (-not $threw) {
            throw 'recap working-state gathering reports a failed git lookup as a clean working tree'
        }
    } finally {
        Remove-Item -Recurse -Force $notARepo
    }
} finally {
    # Recursive force-delete, so prove the target is the fixture this run created and is
    # under the temp root before removing it. A mistyped or empty $repo would otherwise
    # make this line delete whatever the relative path happened to resolve to.
    $safeTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($repo -and (Test-Path -LiteralPath $repo) -and
        [IO.Path]::GetFullPath($repo).StartsWith($safeTemp, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -Recurse -Force -LiteralPath $repo
    }
}

"recap runtime-neutral contract OK - $words words"
