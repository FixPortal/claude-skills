$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..' 'SKILL.md'
$text = Get-Content $path -Raw
$fm = [regex]::Match($text, '(?s)^---(.+?)---')
if (-not $fm.Success) { throw "no frontmatter" }
$block = $fm.Groups[1].Value
$nameOk = $block -match '(?im)^name:\s*review-digest\s*$'
if (-not $nameOk) { throw "name must be review-digest" }
$desc = [regex]::Match($block, '(?im)^description:\s*(.+)$')
if (-not $desc.Success) { throw "no description" }
if ($desc.Groups[1].Value.Length -gt 1024) { throw "description >1024 chars (Copilot limit)" }
foreach ($needle in 'collect.ps1','themes.json','Review Ledger','propose','coverage gap',
                     'handoff','risk','graphify','boundarySha','since the last review') {
  if ($text -notmatch [regex]::Escape($needle)) { throw "SKILL.md missing reference: $needle" }
}
# Output files are UTC-timestamped and never overwritten (a bare yyyy-MM-dd name collides on a
# same-day re-run and silently destroys the first run's report). Pin both halves of the rule.
foreach ($needle in 'New-Item -ItemType File -ErrorAction Stop','Never overwrite',
                     'YYYY-MM-DDTHH-mm-ss.fffffffZ') {
  if ($text -notmatch [regex]::Escape($needle)) { throw "SKILL.md missing never-overwrite output convention: $needle" }
}
if ($text -match [regex]::Escape('<today>')) { throw "SKILL.md still names outputs by bare date - same-day re-runs overwrite each other" }
if ($text -match '(?i)\.claude[\\/]+skills[\\/]+review-digest') {
  throw "SKILL.md must resolve support files from its loaded skill directory"
}
"SKILL.md OK — description $($desc.Groups[1].Value.Length) chars"
