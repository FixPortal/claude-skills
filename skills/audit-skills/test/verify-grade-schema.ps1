$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot '..'
$skill = Get-Content -LiteralPath (Join-Path $root 'SKILL.md') -Raw
$brief = Get-Content -LiteralPath (Join-Path $root 'audit-brief.md') -Raw

# Closed vocabulary: changing a glyph, dropping yellow polish, or adding a fifth value
# must fail the worker contract rather than producing incomparable audit results.
$grades = '🟩|🟨|🟧|🟥'
$expectedResultSchema = "`"grades`": { `"reach`": `"$grades`", `"impl`": `"$grades`", `"correctness`": `"$grades`", `"utility`": `"$grades`" }"

if ($brief -notmatch [regex]::Escape($expectedResultSchema)) {
    throw 'Worker result grades must use the closed four-glyph vocabulary on every axis.'
}

if ($skill -notmatch [regex]::Escape('Every worker result uses the closed grade vocabulary: 🟩, 🟨, 🟧, 🟥.')) {
    throw 'Skill must require the same closed grade vocabulary as the worker result.'
}

'audit-skills grade schema OK'
