$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw

# CLAUDE.md "Model selection" lifted the Opus approval gate on 2026-07-27:
# "The old rule - 'Opus and above requires explicit user approval, no exceptions' -
# no longer applies." A skill must not narrate its run as satisfying a rule that
# no longer exists.
if ($text -match 'Opus needs explicit approval') {
    throw "SKILL.md cites the Opus-approval rule lifted 2026-07-27"
}

'adversarial-review has no superseded convention references'
