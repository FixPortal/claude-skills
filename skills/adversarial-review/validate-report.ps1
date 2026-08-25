#requires -Version 7
<#
.SYNOPSIS
  Rejects the shape defects that have actually reached a persisted adversarial-review
  deliverable, plus any Critical/High finding block with no **Verification** line.

.DESCRIPTION
  `report.md` is assembled by the host agent, not by a script, so nothing checked its
  shape until a run shipped three Phase 4 lines reading

      **Verifier** - $(@{id=C001; title=...; verifier=claude:sonnet; ...}.verifier)

  an unevaluated PowerShell subexpression written verbatim into markdown, each one
  also embedding an absolute scratch path that no longer exists. It survived a full
  remediation pass unnoticed.

  The two rules below are deliberately narrow, and the narrowness is evidence-backed:
  a sweep of every report in the vault found ZERO legitimate occurrences of either
  pattern, while the wider candidates ("no `$(` anywhere", "no `@{` anywhere") match a
  dozen real MSBuild and PowerShell snippets quoted inside Fix suggestions
  (`$(TargetFramework)`, `$(DefineConstants)`, `@{ In=...; Out=... }`). A check that
  cries wolf on a dozen good reports is a check reviewers learn to skip.

  Deliverables only. `working/` holds raw transcripts and reviewer diffs, which
  legitimately contain both patterns and are not what anyone reads later.

.EXAMPLE
  pwsh -File validate-report.ps1 -Path '<vault>\Claude\Adversarial Review\<repo>\<RunId>'
#>
[CmdletBinding()]
param(
    # A run folder (recursed, `working/` excluded) or individual markdown files.
    [Parameter(Mandatory)]
    [string[]] $Path
)

$ErrorActionPreference = 'Stop'

$rules = @(
    @{
        Name    = 'leaked-interpolation'
        Pattern = '\$\(\s*@\{'
        Message = 'unevaluated PowerShell subexpression written verbatim into markdown'
    }
    @{
        Name    = 'dead-scratch-path'
        # Both separators: the same class of bug shipped twice this week from a
        # single-separator pattern that never matched on the other host. `\s*` at each
        # seam so a path word-wrapped across two lines cannot slip through - the file is
        # matched whole, not line by line, precisely so `\s` can span the newline.
        Pattern = 'AppData\s*[\\/]+\s*Local\s*[\\/]+\s*Temp'
        Message = 'absolute scratch path, dead the moment the run directory is pruned'
    }
)

$files = @(
    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) { throw "no such path: $p" }
        if (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -Recurse -File -Filter *.md |
                Where-Object { $_.FullName -notmatch '[\\/]working[\\/]' }
        } else {
            Get-Item -LiteralPath $p
        }
    }
)

# An empty file set is the fail-open shape this whole check exists to avoid: a clean
# exit over nothing reads identically to a clean exit over a validated report.
if (-not $files) { throw "no markdown deliverables found under: $($Path -join ', ')" }

# Matched against the whole file, not line by line. Markdown gets word-wrapped, and a
# per-line match cannot see a leak whose `$(` and `@{` land either side of a newline -
# it would report clean on the very defect it exists to catch. Both patterns tolerate
# whitespace at their seams, and `\s` spans a newline only when the text is matched whole.
$violations = foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if (-not $text) { continue }
    foreach ($rule in $rules) {
        foreach ($match in [regex]::Matches($text, $rule.Pattern)) {
            $window = $text.Substring($match.Index, [Math]::Min(160, $text.Length - $match.Index))
            [pscustomobject]@{
                File    = $file.FullName
                # Derived from the match offset: a match may span lines, so there is no
                # single "matching line" to report - this is where it starts.
                Line    = ($text.Substring(0, $match.Index) -split "`n").Count
                Rule    = $rule.Name
                Message = $rule.Message
                Text    = ($window -replace '\s+', ' ').Trim()
            }
        }
    }
}

if ($violations) {
    foreach ($v in $violations) {
        $snippet = if ($v.Text.Length -gt 140) { $v.Text.Substring(0, 140) + '...' } else { $v.Text }
        Write-Host "$($v.File):$($v.Line): $($v.Rule) - $($v.Message)"
        Write-Host "  $snippet"
    }
    Write-Host ''
    Write-Host "$(@($violations).Count) report-shape violation(s) across $($files.Count) deliverable(s)."
    exit 1
}

# A Phase-4-covered finding (every Critical, every High, every contested) must carry a
# **Verification** line, or a REFUTED verdict has no home and the tally keeps counting a
# dead finding. Anchored on the house-style severity line (`**High** · [...]`) so tally
# tables and prose mentions of a severity do not trip it. A [contested] tag anywhere in
# the block triggers the same requirement regardless of severity — the phase-3 brief
# mandates Verification on every contested finding, including a contested Medium/Low.
$unverified = foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    if (-not $text) { continue }
    $blocks = [regex]::Matches($text, '(?ms)^### .+?(?=^### |\z)')
    foreach ($block in $blocks) {
        $verificationRequired = $block.Value -match '(?m)^\*\*(Critical|High)\*\*\s*·' -or
            $block.Value -match '\[contested\]'
        if ($verificationRequired -and $block.Value -notmatch '\*\*Verification\*\*') {
            [pscustomobject]@{
                File  = $file.FullName
                Line  = ($text.Substring(0, $block.Index) -split "`n").Count
                Title = (($block.Value -split "`n")[0]).Trim()
            }
        }
    }
}

if ($unverified) {
    foreach ($u in $unverified) {
        Write-Host "$($u.File):$($u.Line): missing-verification - Critical/High/contested finding block has no **Verification** line"
        Write-Host "  $($u.Title)"
    }
    Write-Host ''
    Write-Host "$(@($unverified).Count) unverified Critical/High/contested finding(s) across $($files.Count) deliverable(s)."
    exit 1
}

"report shape OK - $($files.Count) deliverable(s) checked"
