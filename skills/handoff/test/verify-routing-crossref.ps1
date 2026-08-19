$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path (Join-Path $PSScriptRoot '..') 'SKILL.md') -Raw

# model-routing-traps.md entry 1 was corrected 2026-08-02: the Codex-CLI-on-Windows
# sandbox failure was "not reproduced on Codex v0.146.0", and the entry explicitly
# warns against generalising one broken build into a permanent capability claim.
# This skill restated that claim one sentence after instructing the reader not to
# restate it - so the restatement is both self-contradictory and now false.
if ($text -match 'Codex CLI cannot be\s+driven from another agent') {
    throw "SKILL.md restates the Codex-CLI claim model-routing-traps.md retracted on 2026-08-02"
}

if ($text -notmatch 'do not assume it still\*{0,2}\s+means what it meant') {
    throw "SKILL.md missing the pointer-not-restatement guard"
}

if ($text -notmatch 'Join-Path') {
    throw "SKILL.md must use Join-Path so the handoff procedure remains PowerShell 5.1 compatible"
}

'handoff routing cross-reference OK'
