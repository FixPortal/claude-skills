$ErrorActionPreference = 'Stop'
$skill = Get-Content -Raw -LiteralPath (Join-Path (Join-Path $PSScriptRoot '..') 'SKILL.md')

$required = @(
    '/handoff kimi',
    '/handoff copilot',
    "git log '@{u}..HEAD' --oneline",
    '`mechanical`',
    '`workhorse`',
    '`frontier`',
    '`estate`',
    '`low`',
    '`medium`',
    '`high`',
    'model-registry/resolve.py --tier',
    'model-routing-traps.md',
    'No repository is in scope',
    'Join-Path',
    '[System.IO.File]::Move',
    '[System.IO.File]::Replace',
    'Get-FileHash',
    'latest.md differs from the dated brief',
    'dated brief is authoritative'
)
$forbidden = @(
    '| cheapest |',
    '| mid |',
    '| top |',
    'models_cache.json',
    'grep for `slug`'
)

foreach ($value in $required) {
    if (-not $skill.Contains($value)) { throw "Missing handoff contract: $value" }
}
foreach ($value in $forbidden) {
    if ($skill.Contains($value)) { throw "Stale handoff contract: $value" }
}
if ($skill -match '(?<![\w-])medium-high(?![\w-])') {
    throw 'Invalid handoff reasoning effort: medium-high'
}

$step2Start = $skill.IndexOf('### 2. Gather git state')
$step3Start = $skill.IndexOf('### 3. Establish the task')
if ($step2Start -lt 0 -or $step3Start -le $step2Start) {
    throw 'Handoff procedure is missing ordered steps 2 and 3'
}
$step2 = $skill.Substring($step2Start, $step3Start - $step2Start)
foreach ($value in @(
    'If no repository is in scope',
    'skip Git and PR discovery',
    'Repository: `estate`',
    'Branch: `none`',
    'Worktree: `none`',
    'Working tree: `N/A`',
    'Unpushed commits: `N/A`',
    'Open PR: `N/A`'
)) {
    if (-not $step2.Contains($value)) { throw "Estate handoff branch is missing: $value" }
}

$step6Start = $skill.IndexOf('### 6. Write the brief and hand off')
$ignoredCheckStart = $skill.IndexOf('Briefs are session ephemera', $step6Start)
if ($step6Start -lt 0 -or $ignoredCheckStart -le $step6Start) {
    throw 'Handoff procedure is missing the bounded publication step'
}
$publication = $skill.Substring($step6Start, $ignoredCheckStart - $step6Start)
$lastIndex = -1
foreach ($value in @(
    '$datedBrief = Join-Path',
    '$datedTemp = Join-Path',
    '$latestTemp = Join-Path',
    'Set-Content -LiteralPath $datedTemp',
    '[System.IO.File]::Move($datedTemp, $datedBrief)',
    'Copy-Item -LiteralPath $datedBrief -Destination $latestTemp',
    'if (Test-Path -LiteralPath $latestBrief)',
    '[System.IO.File]::Replace($latestTemp, $latestBrief, $null)',
    '[System.IO.File]::Move($latestTemp, $latestBrief)',
    'Get-FileHash -LiteralPath $datedBrief',
    'repeat only the pointer update',
    'The dated brief is authoritative'
)) {
    $index = $publication.IndexOf($value)
    if ($index -le $lastIndex) { throw "Handoff publication is missing or out of order: $value" }
    $lastIndex = $index
}
foreach ($value in @(
    'Join-Path $estateHome (Join-Path',
    'Join-Path $repoRoot (Join-Path'
)) {
    if (-not $publication.Contains($value)) { throw "Handoff path join is not PowerShell 5.1 portable: $value" }
}

'handoff contract OK'
