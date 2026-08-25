#Requires -Version 7
<#
.SYNOPSIS
    Deterministic spine of the adversarial-review panel: resolve the diff, run
    the blind review (Phase 1) and cross-examination (Phase 2) across the
    manifest's reviewers, pool and anonymise findings, and assemble the judge
    packet. Host-agnostic — runnable from Claude Code, Antigravity (`agy`), or a
    bare shell.

.DESCRIPTION
    This script does the mechanical 80% of an adversarial review that is
    identical on every host: it forwards the diff to each reviewer wrapper
    (claude-review.ps1 / codex-review.ps1 / kimi-review.ps1 / agy-review.ps1,
    selected by reviewers.json), captures their findings, strips preamble, pools and
    re-ids them anonymously, then runs the cross-examination round and lays out
    everything a judge needs.

    It deliberately STOPS at the judgment boundary. Adjudication (Phase 3),
    verification (Phase 4), and multi-chunk synthesis are left to the host
    agent, which reads the repo to settle contested mechanisms — that judgment
    is exactly what does not belong in a deterministic script. The host picks up
    from `judge-packet.md` using `briefs/phase3-adjudicate.txt`.

    Chunk-boundary selection (which files form a cohesive chunk) is also host
    judgment: this script reviews ONE diff. For a whole-repo audit the host runs
    it once per chunk, then synthesises with `briefs/synthesis.txt`.

    The vendor-diversity invariant is enforced here: if the enabled reviewer set
    spans fewer than the manifest's `minVendors`, the run aborts — a same-vendor
    panel is self-review, not an adversarial one. A reviewer whose wrapper exits
    non-zero is reported as unavailable and the run degrades (provided diversity
    still holds), never silently collapsing to one model.

.PARAMETER Target
    What to review (mirrors the skill argument before `--`):
      <empty>      current branch vs its merge-base with the default branch
      <PR number>  `gh pr diff <n>`
      audit        current state of the code: diff vs the empty tree (pair with -Pathspec)
      <ref/range>  any git ref or range, e.g. main..HEAD, a branch, a SHA

.PARAMETER Pathspec
    Git pathspec(s) forwarded verbatim to `git diff` after `--` to scope files
    (inclusion `src/Engine`, exclusion `:!**/Migrations/**`). PR targets reject
    pathspecs because `gh pr diff` cannot apply them. Strongly recommended with
    `audit`.

.PARAMETER ContextPath
    Repo files handed to the reviewers as read-only background — the
    contracts/base-types/callers the diff depends on but does not contain. Closes
    the cross-vendor reviewer's repo-blindness (see the skill, §1). Keep tight
    (~3-5 files).

.PARAMETER PreamblePath
    Brief prepended to the Phase 1 brief, replacing the default audit preamble.
    Use `briefs/system-preamble.txt` when the reviewed surface is a normative
    corpus (governance instruments, specifications, procedures) rather than
    code — it redirects the code-shaped defect classes to their corpus
    analogues and opens the engineering-system dimensions (proportion, evidence
    adequacy, executability, coverage). Applies to any target, not just `audit`,
    and fronts every phase's brief (Phase 2 gap-hunting, Phase 3 adjudication,
    Phase 4 verification), so the corpus frame survives the whole pipeline.

.PARAMETER RepoPath
    Repository root. Defaults to the git toplevel of the current directory.

.PARAMETER WorkDir
    Per-run working directory. Defaults to <temp>/adversarial-review/<UTC stamp>.

.PARAMETER ManifestPath
    reviewers.json. Defaults to the copy beside this script.

.PARAMETER MaxParallel
    Reviewer concurrency. Default 5 (one per default-panel reviewer:
    Sonnet + Fable + Codex + Kimi + Gemini).

.PARAMETER RoundTimeoutSeconds
    Wall-clock ceiling for a single round (Phase 1 or Phase 2). Default 2700 (45
    minutes). Nothing in this script or in the wrappers previously bounded a
    reviewer, so one wedged slot stalled its phase indefinitely with nothing
    marking it unavailable — contrary to the skill's stated degrade-and-continue
    behaviour, and detectable only by a human noticing the run had stopped moving.
    A stopped reviewer produces no output and falls through the existing
    "FAILED — degrading" path, so the round still completes if diversity holds.
    Sized off measurement, not guesswork: the slowest observed reviewer took
    30m30s (2026-08-17 desktop pass, Kimi Phase 1), so 45 minutes is roughly a
    50% margin. Raise it for a very large diff rather than removing it.

.OUTPUTS
    Writes all artefacts into WorkDir and prints a JSON status object plus a
    human summary. Exit 0 on a complete spine, non-zero on a fatal error
    (no git repo, empty diff, diversity invariant unmet).

.EXAMPLE
    pwsh -NoProfile -File run-review.ps1 -Target audit -Pathspec 'src/Engine',':!**/*.Designer.cs'
.EXAMPLE
    pwsh -NoProfile -File run-review.ps1            # current branch vs base
#>
[CmdletBinding()]
param(
    [string] $Target = '',
    [string[]] $Pathspec,
    [string[]] $ContextPath,
    [string] $PreamblePath,
    [string] $RepoPath,
    [string] $WorkDir,
    [string] $ManifestPath,
    [int] $MaxParallel = 5,
    [ValidateRange(60, 86400)]
    [int] $RoundTimeoutSeconds = 2700,
    # Proceed when the working tree holds paths the resolved diff cannot contain
    # (uncommitted paths on a tree-to-tree target; untracked files on any target),
    # recording the omitted paths instead of stopping. Deliberate scope decision,
    # never a default.
    [switch] $AllowDirty
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$scriptDir = Split-Path -Parent $PSCommandPath
# Finding-block splitter shared with test/verify-start-patterns.ps1 (pooling splits on
# exactly the Phase-1 admission pattern, normalises headings to '### ', and never
# splits inside a fenced code block).
. (Join-Path $scriptDir 'pool-findings.ps1')
$emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

# The canonical clean sentinel (pinned by briefs/phase1-review.txt): a reviewer whose
# entire reply is this heading PARTICIPATED and found nothing. It counts toward vendor
# diversity with issuesRaised = 0 and contributes no pooled finding. The match must be
# EXACT — anchored to the whole stripped reply, no (?m) — or a sentinel line plus
# narration (or malformed findings) would pass admission and count toward diversity.
$cleanSentinel = 'No substantive defects'
$cleanSentinelPattern = "^\s*(?:[-*+]\s+)?(?:\*\*|__)?#{1,6}(?:\*\*|__)?\s*$cleanSentinel\s*$"

# Normalize Pathspec: when called via pwsh -File from a subprocess, multi-element arrays
# can't be passed as separate tokens without binding errors. Callers join with ';' instead.
if ($Pathspec.Count -eq 1 -and $Pathspec[0] -match ';') {
    $Pathspec = $Pathspec[0] -split ';'
}

function Die([string] $msg, [int] $code = 1) {
    # -ErrorAction Continue is load-bearing: under $ErrorActionPreference='Stop' a bare
    # Write-Error is TERMINATING and throws before `exit $code` runs, collapsing every
    # distinct code (2-5) into a bare exit 1. Print non-terminating, then exit.
    Write-Error $msg -ErrorAction Continue
    exit $code
}

# Normalize and VALIDATE ContextPath before any reviewer is spawned. Two separate
# hazards, both of which have cost a full parallel round:
#
#   1. `pwsh -File` passes arguments as strings, so an inline multi-element array
#      (`-ContextPath 'a','b'`) arrives as the SINGLE token `a,b`. The ';'-join the
#      callers apply is then a no-op on one element, and every wrapper splits on ';'
#      and gets one path that cannot exist. Splitting on ',' as well as ';' recovers
#      the operator's intent instead of propagating it — but only AFTER testing the
#      whole token as a path in its own right, because a legitimate path can itself
#      contain a comma and must not be shredded. Segments split on ';' unconditionally;
#      ',' is a fallback for segments that are not themselves an existing file.
#   2. A context file that simply is not there. Each wrapper discovers this on its
#      own, one reviewer at a time, minutes into the run — five identical
#      "Context file not found" failures across four vendors, which reads like a
#      vendor outage rather than a bad argument. One Test-Path here turns that into
#      an immediate, unambiguous exit.
#
# Deliberately AFTER Die is defined and BEFORE the repo/diff resolution below: the
# whole point is to fail before anything expensive or billable starts.
if ($ContextPath) {
    $ContextPath = @(
        $ContextPath |
            Where-Object { $_ } |
            ForEach-Object {
                $whole = $_.Trim().Trim("'", '"')
                if (Test-Path -LiteralPath $whole -PathType Leaf) { $whole }
                else {
                    $whole -split ';' |
                        ForEach-Object { $_.Trim().Trim("'", '"') } |
                        Where-Object { $_ } |
                        ForEach-Object {
                            if (Test-Path -LiteralPath $_ -PathType Leaf) { $_ }
                            elseif ($_.Contains(',')) {
                                $_ -split ',' | ForEach-Object { $_.Trim().Trim("'", '"') } | Where-Object { $_ }
                            }
                            else { $_ }
                        }
                }
            }
    )
    foreach ($contextFile in $ContextPath) {
        if (-not (Test-Path -LiteralPath $contextFile -PathType Leaf)) {
            Die "Context file not found: $contextFile" 2
        }
    }
}

# --- Resolve repo --------------------------------------------------------
if (-not $RepoPath) {
    $top = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $top) {
        Die 'adversarial-review needs a git repository (could not resolve the repo root).' 2
    }
    $RepoPath = $top.Trim()
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if ((& git -C $RepoPath rev-parse --is-inside-work-tree 2>$null) -ne 'true') {
    Die "Not inside a git work tree: $RepoPath" 2
}
$repoName = Split-Path -Leaf $RepoPath

# --- Manifest ------------------------------------------------------------
if (-not $ManifestPath) { $ManifestPath = Join-Path $scriptDir 'reviewers.json' }
if (-not (Test-Path -LiteralPath $ManifestPath)) { Die "Manifest not found: $ManifestPath" 2 }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

$reviewers = @($manifest.reviewers | Where-Object { $_.enabled })
if (-not $reviewers) { Die 'No enabled reviewers in the manifest.' 2 }
$reviewerIds = @($reviewers | ForEach-Object { [string]$_.id })
$duplicateIds = @($reviewerIds | Group-Object { $_.ToUpperInvariant() } | Where-Object Count -gt 1)
if ($reviewerIds | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    Die 'Every enabled reviewer needs a non-empty id; the id binds its phase files and sidecars.' 2
}
if ($duplicateIds) {
    Die "Reviewer ids must be unique because each id owns one set of phase files and sidecars: $($duplicateIds.Name -join ', ')" 2
}
$vendorCount = ($reviewers.vendor | Sort-Object -Unique).Count
$minVendors = [int]($manifest.minVendors ?? 2)
if ($vendorCount -lt $minVendors) {
    Die ("Vendor-diversity invariant unmet: $vendorCount distinct vendor(s) enabled, $minVendors required. " +
        'A same-vendor panel is self-review, not adversarial. Enable a reviewer from another vendor.') 2
}
$repoBlindIds = @($reviewers | Where-Object { -not $_.repoAccess } | ForEach-Object id)
$repoAwareIds = @($reviewers | Where-Object repoAccess | ForEach-Object id)

function Resolve-Wrapper([object] $reviewer) {
    $file = $manifest.wrappers.($reviewer.wrapper)
    if (-not $file) { Die "Reviewer '$($reviewer.id)' names unknown wrapper '$($reviewer.wrapper)'." 2 }
    $path = Join-Path $scriptDir $file
    if (-not (Test-Path -LiteralPath $path)) { Die "Wrapper not found for '$($reviewer.id)': $path" 2 }
    $path
}

# --- Work dir ------------------------------------------------------------
if (-not $WorkDir) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $WorkDir = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'adversarial-review' $stamp)
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$diffFile = Join-Path $WorkDir 'review-diff.txt'
$pooledFile = Join-Path $WorkDir 'pooled-findings.txt'
$statusFile = Join-Path $WorkDir 'status.json'

# --- Resolve the diff (§0) ----------------------------------------------
# Context depth: audit and PR reviews use -U15 for rich surrounding context.
# Drift and range reviews default to -U6 — the change is forward-only and
# does not need deep context; heavy context inflates total diff size 2–3×
# and pushes into the cross-vendor reviewers' transport limits (§0a).
$isAudit = $false
$isPR    = $false
$resolvedTargetIdentity = $null
# Uncommitted paths deliberately excluded from a tree-to-tree target. Recorded in
# status.json and the judge packet so "reviewed" never silently means "reviewed except
# for whatever was uncommitted at the time".
$dirtyPaths = @()
$baseDiffArgs = $null   # ref + context args WITHOUT pathspec; stored for compact-diff regeneration
if ($Target -match '^\d+$') {
    if ($Pathspec) { Die 'PR targets do not support pathspecs; review the PR as-is or use an explicit git ref/range with -Pathspec.' 2 }
    $isPR = $true
    Write-Host "Resolving PR #$Target via gh..."
    $raw = (& gh pr diff $Target 2>&1)
    if ($LASTEXITCODE -ne 0) { Die "gh pr diff $Target failed:`n$raw" }
    $resolvedTargetIdentity = "pr:$Target"
}
else {
    # SKILL.md pre-flight step 4 mandates a deliberate scope decision on a dirty tree.
    # Nothing enforced it, so an `audit` or an explicit A..B range - both tree-to-tree -
    # excluded uncommitted work with no warning, and the run then reported coverage of a
    # target the reviewers had never fully seen. A bare branch/SHA target diffs against
    # the working tree and picks up uncommitted EDITS to tracked files — but
    # `git diff <base>` never includes UNTRACKED files at all, so the working-tree
    # shapes are gated for those too (new files would otherwise be invisible while
    # status.json reported full coverage).
    # Classify by what git ACTUALLY expands the target to, not by spotting '..' in the
    # string. Observed: `git diff HEAD^!` shows only the committed change and NOT an
    # uncommitted edit, so it is tree-to-tree while matching no '..' pattern. rev-parse
    # emits one revision for a working-tree-inclusive target and two or more (the second
    # negated) for a tree-to-tree one.
    $targetRevisions = @(& git -C $RepoPath rev-parse --revs-only --no-flags $Target 2>$null | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0) { Die "git rev-parse failed for target '$Target'; cannot establish review scope." }
    $isTreeToTree = ($Target -eq 'audit') -or ($targetRevisions.Count -gt 1)
    if ($isTreeToTree) {
        $porcelain = @(& git -C $RepoPath status --porcelain 2>$null | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { Die 'git status --porcelain failed; cannot establish whether the tree is clean.' }
        if ($porcelain.Count -gt 0) {
            $script:dirtyPaths = @($porcelain | ForEach-Object { $_.Substring(3) })
            if (-not $AllowDirty) {
                Die (
                    "Working tree is dirty ($($porcelain.Count) path(s)) and the '$Target' target is " +
                    "tree-to-tree, so none of it would reach a reviewer:`n  " +
                    (($dirtyPaths | Select-Object -First 20) -join "`n  ") +
                    "`nCommit or stash it, or re-run with -AllowDirty to review the committed tree " +
                    'and have the omitted paths recorded in status.json and the judge packet.'
                ) 4
            }
            Write-Warning "Reviewing a DIRTY tree with a tree-to-tree target: $($dirtyPaths.Count) uncommitted path(s) are NOT under review."
        }
    }
    else {
        # Working-tree target: tracked edits are in the diff, untracked files never are.
        $untracked = @(& git -C $RepoPath ls-files --others --exclude-standard 2>$null | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0) { Die 'git ls-files failed; cannot establish review scope.' }
        if ($untracked.Count -gt 0) {
            $script:dirtyPaths = @($untracked)
            if (-not $AllowDirty) {
                Die (
                    "Working tree has $($untracked.Count) untracked path(s) and a working-tree target's " +
                    "diff never includes untracked files, so none of them would reach a reviewer:`n  " +
                    (($dirtyPaths | Select-Object -First 20) -join "`n  ") +
                    "`nAdd or stash them, or re-run with -AllowDirty to have the omitted paths " +
                    'recorded in status.json and the judge packet.'
                ) 4
            }
            Write-Warning "Reviewing with $($dirtyPaths.Count) untracked path(s) excluded: a working-tree diff never contains them, so they are NOT under review."
        }
    }

    if ($Target -eq 'audit') {
        $isAudit = $true
        $resolvedTargetIdentity = "audit:$((& git -C $RepoPath rev-parse HEAD).Trim())"
        if (-not $Pathspec) {
            Write-Warning 'audit with no -Pathspec reviews the WHOLE repo as one diff — this dilutes findings and overruns the cross-vendor reviewer. Scope it to one cohesive area.'
        }
        $baseDiffArgs = @('-U15', $emptyTree, 'HEAD')
    }
    elseif ($Target) {
        $baseDiffArgs = @('-U6', $Target)
        $resolvedTargetIdentity = "git:$($targetRevisions -join ',')"
    }
    else {
        # symbolic-ref yields the REMOTE-TRACKING ref ('origin/main'). Merge-base against
        # exactly that: stripping the prefix and merging against LOCAL 'main' throws
        # (`.Trim()` on $null) where no local main exists — worktrees, fresh clones —
        # and silently diffed against a stale local main everywhere else. The 'origin/'
        # prefix is stripped only for display.
        $defaultBranch = (& git -C $RepoPath symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $defaultBranch) {
            $defaultBranch = @('origin/main', 'origin/master', 'main', 'master') | Where-Object {
                (& git -C $RepoPath rev-parse --verify --quiet $_ 2>$null); $LASTEXITCODE -eq 0
            } | Select-Object -First 1
        }
        if (-not $defaultBranch) { Die 'Could not detect a default branch (no origin/HEAD, no origin/main, no main/master).' }
        $defaultBranch = ([string]$defaultBranch).Trim()
        $displayBranch = $defaultBranch -replace '^origin/', ''
        $base = (& git -C $RepoPath merge-base $defaultBranch HEAD 2>$null)
        $base = if ($base) { ([string]$base).Trim() } else { $null }
        if (-not $base) { Die "Could not find merge-base of $displayBranch and HEAD." }
        $baseDiffArgs = @('-U6', $base)
        $resolvedTargetIdentity = "branch:$base..$((& git -C $RepoPath rev-parse HEAD).Trim())"
    }

    $diffArgs = if ($Pathspec) { $baseDiffArgs + @('--') + $Pathspec } else { $baseDiffArgs }
    $raw = (& git -C $RepoPath diff @diffArgs 2>&1)
    if ($LASTEXITCODE -ne 0) { Die "git diff failed:`n$raw" }
}

$diffIdentityText = @($raw) -join "`n"
if ([string]::IsNullOrWhiteSpace($diffIdentityText)) { Die 'The resolved diff is empty — nothing to review.' 3 }
$diffSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($diffIdentityText))).ToLowerInvariant()
$identityInput = "$RepoPath`n$resolvedTargetIdentity`n$diffSha256"
$runIdentity = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identityInput))).ToLowerInvariant()

# status.json is the existing durable run sidecar. Refuse cross-run reuse before
# replacing any evidence in WorkDir; a retry of the same resolved inputs is allowed.
if (Test-Path -LiteralPath $statusFile) {
    try { $priorStatus = Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json }
    catch { Die "WorkDir contains an unreadable status.json; its evidence identity cannot be trusted: $statusFile" 5 }
    if (-not $priorStatus.runIdentity -or $priorStatus.runIdentity -cne $runIdentity) {
        Die "WorkDir contains evidence for a different run identity; use a fresh WorkDir instead of mixing repo/ref/diff evidence: $WorkDir" 5
    }
}

# --- Pre-flight gate ------------------------------------------------------
# The host is required to run each enabled wrapper's PREFLIGHT_COMMAND (see the
# wrapper headers and the skill's pre-flight step) BEFORE starting the panel, and to
# record the outcome as preflight.json. Until such a sentinel existed the driver
# proceeded identically whether pre-flight had run or not, and an unauthenticated
# CLI was discovered mid-round, inside the paid fan-out. Contract: preflight.json is
# a JSON object mapping wrapper name to its result (e.g. { "claude": "pass" }),
# written into the run root — this WorkDir for a single run, or its PARENT directory
# for a batch chunk (batch-review.ps1 runs the spine with WorkDir=<RunRoot>/<id>, so
# one preflight.json at RunRoot covers every chunk). Its content is echoed into
# status.json for provenance; the driver does not re-run the probes itself.
$preflightFile = Join-Path $WorkDir 'preflight.json'
if (-not (Test-Path -LiteralPath $preflightFile)) {
    $parentPreflight = Join-Path (Split-Path -Parent $WorkDir) 'preflight.json'
    if (Test-Path -LiteralPath $parentPreflight) { $preflightFile = $parentPreflight }
}
if (-not (Test-Path -LiteralPath $preflightFile)) {
    Die ("No preflight.json in $WorkDir or its parent. Run each enabled wrapper's PREFLIGHT_COMMAND " +
        '(see the wrapper headers and the skill''s pre-flight step) and record the results as ' +
        'preflight.json in the run root before starting the panel — an unauthenticated CLI must be ' +
        'caught before the paid fan-out, not inside it.') 2
}
try { $preflight = Get-Content -LiteralPath $preflightFile -Raw | ConvertFrom-Json }
catch { Die "preflight.json is not valid JSON ($($_.Exception.Message)): $preflightFile" 2 }
if ($preflight -isnot [System.Management.Automation.PSCustomObject]) {
    Die "preflight.json must be a JSON object mapping wrapper name to pre-flight result: $preflightFile" 2
}
# An object that merely parses is not evidence. Every wrapper this run can invoke —
# each enabled reviewer's primary AND its declared fallbackWrapper — must carry an
# explicit 'pass' record, or the paid fan-out discovers the dead CLI mid-round, one
# reviewer at a time (the failure mode preflight.json exists to prevent).
$requiredPreflightWrappers = @(
    @($reviewers | ForEach-Object { [string]$_.wrapper }) +
    @($reviewers | Where-Object { $_.fallbackWrapper } | ForEach-Object { [string]$_.fallbackWrapper }) |
        Sort-Object -Unique
)
$preflightGaps = @(
    $requiredPreflightWrappers | Where-Object {
        $preflight.PSObject.Properties.Name -notcontains $_ -or
        [string]$preflight.$_ -ne 'pass'
    }
)
if ($preflightGaps) {
    Die ("preflight.json does not record a passing pre-flight for required wrapper(s): $($preflightGaps -join ', ') " +
        "(file: $preflightFile). Run each enabled wrapper's PREFLIGHT_COMMAND and record the result before " +
        'starting the panel — a missing or non-pass record is not evidence the CLI works.') 2
}

Set-Content -LiteralPath $diffFile -Value $raw -Encoding utf8
$diffText = Get-Content -LiteralPath $diffFile -Raw
[ordered]@{
    state = 'running'; runIdentity = $runIdentity; repoPath = $RepoPath
    target = $Target; resolvedTarget = $resolvedTargetIdentity; diffSha256 = $diffSha256
} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $statusFile -Encoding utf8

# --- Size check and compact-diff generation (§0a) -----------------------
$diffLines  = Get-Content -LiteralPath $diffFile
$addedLines = @($diffLines | Where-Object { $_.StartsWith('+') -and -not $_.StartsWith('+++') }).Count
$totalLines = $diffLines.Count
$estTokens  = [int]($totalLines * 12)   # ≈12 tokens/line for code diffs

if ($addedLines -gt 2000) {
    Write-Warning ("Diff has $addedLines added lines (> 2000). The panel degrades past ~2,000 lines. " +
        'Consider splitting into cohesive chunks and running this driver once per chunk, then synthesising.')
}

# Transport gate: OpenAI has a ~30k tokens-per-request cap. Keep 25k as a
# headroom margin and a comprehension bound. When over the gate,
# generate a compact (-U4) diff for manifest-declared repo-blind reviewers;
# repo-aware reviewers keep the full diff.
$tokenGate      = 25000
$compactDiffFile = $null
if ($estTokens -gt $tokenGate) {
    if ($isPR) {
        Write-Warning ("PR diff ~$estTokens est. tokens exceeds the $tokenGate-token gate. Cannot regenerate " +
            'at lower context. Cross-vendor reviewers will receive the full diff; monitor for 429 / Gemini hang.')
    }
    elseif ($baseDiffArgs) {
        $compactArgs = @('-U4') + $baseDiffArgs[1..($baseDiffArgs.Count - 1)]
        if ($Pathspec) { $compactArgs += @('--') + $Pathspec }
        $compactRaw = (& git -C $RepoPath diff @compactArgs 2>&1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($compactRaw)) {
            $compactDiffFile = Join-Path $WorkDir 'review-diff-compact.txt'
            Set-Content -LiteralPath $compactDiffFile -Value $compactRaw -Encoding utf8
            Write-Warning ("Diff ~$estTokens est. tokens exceeds $tokenGate-token gate. " +
                "Compact diff (-U4) written to review-diff-compact.txt — $($repoBlindIds -join '+') will use it; $($repoAwareIds -join '+') keep the full diff.")
        }
    }
}

# --- Compose the Phase 1 brief ------------------------------------------
$briefDir = Join-Path $scriptDir 'briefs'
function Read-Brief([string] $name) {
    $p = Join-Path $briefDir $name
    if (-not (Test-Path -LiteralPath $p)) { Die "Brief not found: $p" 2 }
    Get-Content -LiteralPath $p -Raw
}
# An explicit -PreamblePath REPLACES the audit preamble (a corpus is not code, so
# the code-shaped calibration would be the wrong frame) and applies to any target.
# Unlike the audit preamble it also fronts Phase 2: the gap task there ("what did
# the pooled set miss") is exactly where the wider system dimensions surface, and a
# reviewer handed only the code-shaped brief in Phase 2 reverts to hunting code.
$preamble = $null
if ($PreamblePath) {
    # Resolve against $scriptDir, NOT the ambient CWD: the documented form is
    # `briefs/<name>.txt`, and batch-review.ps1 forwards this verbatim into parallel
    # runspaces whose working directory is not ours to assume.
    $p = if ([System.IO.Path]::IsPathRooted($PreamblePath)) { $PreamblePath }
         else { Join-Path $scriptDir $PreamblePath }
    if (-not (Test-Path -LiteralPath $p)) { Die "Preamble not found: $p" 2 }
    $preamble = Get-Content -LiteralPath $p -Raw
}
elseif ($isAudit) { $preamble = Read-Brief 'audit-preamble.txt' }

$phase1 = Read-Brief 'phase1-review.txt'
if ($preamble) { $phase1 = $preamble + "`n`n" + $phase1 }
$phase1BriefFile = Join-Path $WorkDir 'phase1-brief.txt'
Set-Content -LiteralPath $phase1BriefFile -Value $phase1 -Encoding utf8

$phase2 = Read-Brief 'phase2-cross-examine.txt'
if ($PreamblePath) { $phase2 = $preamble + "`n`n" + $phase2 }
$phase2BriefFile = Join-Path $WorkDir 'phase2-brief.txt'
Set-Content -LiteralPath $phase2BriefFile -Value $phase2 -Encoding utf8

# Copy the adjudication and verification briefs into the work dir so the judge
# packet is self-contained. An explicit -PreamblePath fronts them exactly as it
# fronts Phase 2: a judge/verifier handed only the code-shaped brief reverts to
# code-shaped adjudication of a corpus (wrong severity calibration, wrong defect
# classes) — the frame must survive all four phases, not stop at the pooled rounds.
$phase3 = Read-Brief 'phase3-adjudicate.txt'
if ($PreamblePath) { $phase3 = $preamble + "`n`n" + $phase3 }
Set-Content -LiteralPath (Join-Path $WorkDir 'phase3-brief.txt') -Value $phase3 -Encoding utf8

$phase4 = Read-Brief 'phase4-verify.txt'
if ($PreamblePath) { $phase4 = $preamble + "`n`n" + $phase4 }
Set-Content -LiteralPath (Join-Path $WorkDir 'phase4-brief.txt') -Value $phase4 -Encoding utf8

# --- Build a per-reviewer job spec --------------------------------------
# Introspect each wrapper so we only pass -Effort / -RepoPath to wrappers that
# actually declare them (Copilot/Gemini do not expose a reasoning-effort flag).
function Build-Args([object] $r, [string] $wrapper, [string] $instruction, [bool] $withFindings, [string] $phaseLabel, [switch] $Fallback) {
    $caps = (Get-Command $wrapper).Parameters.Keys
    # A reviewer marked repoAccess:false gets the compact diff; a repo-aware one keeps the
    # full diff. But the decision follows the EFFECTIVE wrapper, not the manifest entry -
    # which describes the PRIMARY only. A wrapper that cannot even accept -RepoPath is
    # repo-blind by construction, so deriving it from the wrapper's own signature stays
    # correct for any future fallback without a second flag to keep in sync.
    #
    # Degrading from a repo-aware CLI to a repo-blind metered API used to keep sending the
    # full -U15 diff, on the one path most likely to hit a non-retryable 429 - turning an
    # outage into a lost vendor.
    $repoAware = [bool]$r.repoAccess -and ($caps -contains 'RepoPath')
    $thisDiff = if ($compactDiffFile -and -not $repoAware) { $compactDiffFile } else { $diffFile }
    $a = @('-Instruction', $instruction, '-DiffPath', $thisDiff, '-Model', $r.model)
    if ($withFindings) { $a += @('-FindingsPath', $pooledFile) }
    # One ';'-joined token, never a repeated flag: the child runs under `pwsh -File`,
    # whose binder rejects a parameter named twice ("specified more than once").
    # Every wrapper splits -ContextPath on ';'.
    $ctx = @($ContextPath | Where-Object { $_ }) -join ';'
    if ($ctx) { $a += @('-ContextPath', $ctx) }
    if ($caps -contains 'Effort' -and $r.effort) { $a += @('-Effort', $r.effort) }
    if ($caps -contains 'RepoPath' -and $repoAware) { $a += @('-RepoPath', $RepoPath) }
    # Wrappers that expose -UsageSidecarPath (G, X) write exact {inputTokens,
    # outputTokens,costUsd} per call; one sidecar per reviewer per phase so the
    # metrics writer can sum P1+P2. Claude (B) has no sidecar — its cost is
    # estimated downstream from the blended rate.
    # A FALLBACK call gets a '-fallback' suffix: derived from reviewer id + phase
    # alone, the API fallback's sidecar would overwrite the primary's — and a
    # primary that billed and THEN exited non-zero would lose its record entirely.
    # The metrics reader sums both when present.
    if ($caps -contains 'UsageSidecarPath') {
        $sidecarName = "usage-{0}-{1}{2}.json" -f $r.id, $phaseLabel, ($Fallback ? '-fallback' : '')
        $a += @('-UsageSidecarPath', (Join-Path $WorkDir $sidecarName))
    }
    , $a
}

function Strip-Preamble([string] $text, [string] $startPattern) {
    # Returns the stripped body AND whether the contract's start pattern was ever found.
    # It used to return the whole text unchanged on no match, which made narration, a
    # refusal, or an apology indistinguishable from findings: the caller admitted the
    # reviewer, and the run then reported a vendor that had contributed nothing to the
    # pool the judge was handed.
    $lines = $text -split "`r?`n"
    $idx = ($lines | Select-String -Pattern $startPattern | Select-Object -First 1).LineNumber
    if (-not $idx) { return [pscustomobject]@{ Matched = $false; Text = $text.Trim() } }
    [pscustomobject]@{ Matched = $true; Text = ($lines[($idx - 1)..($lines.Count - 1)] -join "`n").Trim() }
}

# Reviewer output that failed the contract's start-pattern check. Kept SEPARATE from
# $ok on purpose: an off-contract reply must never count as a participating vendor
# (that guard is why Strip-Preamble reports Matched at all). But withholding it from
# the JUDGE is a different question, and the answer is no — measured 2026-08-16, a run
# discarded three substantive anthropic reviews on formatting alone (prose lead-in, and
# verdicts written `**F1** ... AGREE` instead of line-initial `F1:`), which left that
# chunk's cross-examination with no anthropic vote at all. The judge gets the text,
# clearly labelled and excluded from every tally.
$script:offContract = @()

# Per-participating-reviewer Phase-2 coverage: which pooled F-ids got a verdict and
# which were silently passed over. Recorded so the packet/status can distinguish a
# considered silence (reviewer saw F3 and chose not to contest it) from ABSENCE —
# an [unanimous] tag must never rest on one vote plus untracked silence.
$script:p2Coverage = @{}

function Stop-LeftoverReviewerProcesses {
    # ForEach-Object -Parallel -TimeoutSeconds stops the timed-out ITERATION, not the
    # child processes it spawned: the wrapper's pwsh.exe and the vendor CLI beneath it
    # survive as orphans. Nothing tracked them, so a wedged reviewer kept running (and
    # billing) after its round was declared over. Sweep by command line: every wrapper
    # invocation this round launched carries this run's WorkDir on its command line
    # (via -DiffPath / -FindingsPath / -UsageSidecarPath), which no unrelated process
    # shares. The trailing separator/quote guard keeps a sibling batch chunk whose id
    # merely EXTENDS ours ('C1' vs 'C1x') from matching. Best-effort: a sweep failure
    # must never fail the review.
    if ($IsWindows -eq $false) { return }
    try {
        $needle = [regex]::Escape($WorkDir) + '[\\/"\s]'
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop |
            Select-Object ProcessId, ParentProcessId, Name, CommandLine)
        $roots = @($all | Where-Object {
            $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -match $needle
        })
        if (-not $roots) { return }
        $childrenOf = @{}
        foreach ($p in $all) {
            if (-not $childrenOf.ContainsKey($p.ParentProcessId)) { $childrenOf[$p.ParentProcessId] = @() }
            $childrenOf[$p.ParentProcessId] += $p
        }
        $toKill = [System.Collections.Generic.HashSet[int]]::new()
        $queue = [System.Collections.Generic.Queue[int]]::new()
        foreach ($r in $roots) { [void]$toKill.Add([int]$r.ProcessId); $queue.Enqueue([int]$r.ProcessId) }
        while ($queue.Count -gt 0) {
            $parent = $queue.Dequeue()
            foreach ($child in @($childrenOf[$parent])) {
                if ($toKill.Add([int]$child.ProcessId)) { $queue.Enqueue([int]$child.ProcessId) }
            }
        }
        foreach ($target in $toKill) {
            Stop-Process -Id $target -Force -ErrorAction SilentlyContinue
        }
        Write-Warning "Swept $($toKill.Count) leftover reviewer process(es) still running after the round ended (PIDs: $(@($toKill) -join ', '))."
    }
    catch {
        Write-Warning "Leftover reviewer process sweep failed ($($_.Exception.Message)); a timed-out reviewer's processes may still be running."
    }
}

function Invoke-Round([string] $phaseLabel, [string] $startPattern, [bool] $withFindings, [string[]] $ExpectedFIds = @(),
    [string] $AdmissionPattern = '', [string] $AdmissionDescription = '') {
    $jobs = foreach ($r in $reviewers) {
        $wrapper = Resolve-Wrapper $r
        $instruction = if ($withFindings) { $phase2 } else { $phase1 }
        # Subscription-first, API-fallback: if the reviewer declares a
        # fallbackWrapper (e.g. codex -> openai), resolve it and pre-build its
        # args so the parallel round can retry through it when the primary
        # (sub-backed CLI) exits non-zero — sub down / not logged in / lapsed.
        $fbWrapper = $null; $fbArgs = $null
        if ($r.fallbackWrapper) {
            $fbFile = $manifest.wrappers.($r.fallbackWrapper)
            if ($fbFile) {
                $fbPath = Join-Path $scriptDir $fbFile
                if (Test-Path -LiteralPath $fbPath) {
                    $fbWrapper = $fbPath
                    $fbArgs = (Build-Args $r $fbPath $instruction $withFindings $phaseLabel -Fallback)
                } else {
                    Write-Warning "Reviewer '$($r.id)' fallbackWrapper '$($r.fallbackWrapper)' not found at $fbPath — no fallback."
                }
            }
        }
        [pscustomobject]@{
            Id             = $r.id
            Label          = $r.label
            Vendor         = $r.vendor
            Wrapper        = $wrapper
            Args           = (Build-Args $r $wrapper $instruction $withFindings $phaseLabel)
            FallbackWrapper = $fbWrapper
            FallbackArgs   = $fbArgs
            OutFile        = Join-Path $WorkDir ("{0}-{1}.txt" -f $phaseLabel, $r.id)
            RunIdentity    = $runIdentity
            PhaseLabel     = $phaseLabel
        }
    }

    # A reused WorkDir must not lend this round evidence from an earlier attempt.
    foreach ($j in $jobs) {
        Remove-Item -LiteralPath $j.OutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $WorkDir ("usage-{0}-{1}.json" -f $j.Id, $phaseLabel)) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $WorkDir ("usage-{0}-{1}-fallback.json" -f $j.Id, $phaseLabel)) -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[$phaseLabel] running $($jobs.Count) reviewers: $(($jobs.Label) -join ', ') (timeout ${RoundTimeoutSeconds}s)"
    # -TimeoutSeconds bounds the round. Reviewers that have already returned are kept; any still
    # running when it expires are stopped, produce no output, and fall through the existing
    # "FAILED - degrading" branch below. Errors from stopped iterations are collected rather than
    # thrown so one wedged slot degrades to unavailable instead of aborting the whole phase.
    # -ErrorAction is NOT accepted in the Parallel parameter set (nor WarningAction,
    # InformationAction or PipelineVariable), so the script-level 'Stop' has to be relaxed around
    # the call instead: a timeout raises a non-terminating error that would otherwise abort the
    # whole phase, which is the opposite of degrade-and-continue.
    $timeoutErrors = @()
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $results = $jobs | ForEach-Object -ThrottleLimit $MaxParallel -TimeoutSeconds $RoundTimeoutSeconds -ErrorVariable +timeoutErrors -Parallel {
        $j = $_
        $a = $j.Args
        # Per-reviewer wall-clock for the metrics sidecar (telemetry duration).
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $out = (& pwsh -NoProfile -File $j.Wrapper @a 2>&1 | Out-String)
        $ec = $LASTEXITCODE
        $degraded = $false
        # Fall back to the API wrapper if the sub-backed primary failed.
        if (($ec -ne 0 -or [string]::IsNullOrWhiteSpace($out)) -and $j.FallbackWrapper) {
            $fb = $j.FallbackArgs
            $out = (& pwsh -NoProfile -File $j.FallbackWrapper @fb 2>&1 | Out-String)
            $ec = $LASTEXITCODE
            $degraded = $true
        }
        $sw.Stop()
        $evidenceInput = "$($j.RunIdentity)`n$($j.Id)`n$($j.Vendor)`n$($j.PhaseLabel)`n$($j.OutFile)`n$out"
        $evidenceFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($evidenceInput))).ToLowerInvariant()
        [pscustomobject]@{ Id = $j.Id; Label = $j.Label; Vendor = $j.Vendor; OutFile = $j.OutFile; Out = $out; Exit = $ec; ElapsedMs = $sw.ElapsedMilliseconds; Degraded = $degraded; RunIdentity = $j.RunIdentity; EvidenceFingerprint = $evidenceFingerprint }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    # Whether or not the round timed out, no wrapper child of THIS run should still be
    # alive once the round returns — sweep any that are (see the function for why).
    Stop-LeftoverReviewerProcesses

    # Say so loudly. A timed-out reviewer is indistinguishable downstream from one that failed
    # fast, and the difference matters: it means the round was cut short, not that a vendor
    # declined. Name the slots that never reported so the shortfall is attributable.
    if ($timeoutErrors.Count -gt 0) {
        $reported = @($results | ForEach-Object { $_.Id })
        $missing = @($jobs | Where-Object { $_.Id -notin $reported } | ForEach-Object { "$($_.Id) ($($_.Label))" })
        Write-Warning ("[$phaseLabel] round hit the ${RoundTimeoutSeconds}s timeout; " +
            "$($missing.Count) reviewer(s) did not report: $($missing -join ', '). " +
            'They are treated as unavailable. Raise -RoundTimeoutSeconds if the diff is genuinely large.')
    }

    # A fast-failed reviewer leaves a '[reviewer unavailable]' marker in its phase
    # file; a timed-out one used to leave NOTHING — same unavailability, no evidence.
    # Synthesise the identical result record for every job that never reported, so
    # both paths through the failure branch below leave the same marker.
    # @() first: the pipeline returns a bare scalar when exactly one reviewer
    # reported, and a scalar does not support +=.
    $results = @($results)
    $reportedIds = @($results | ForEach-Object { $_.Id })
    foreach ($j in @($jobs | Where-Object { $_.Id -notin $reportedIds })) {
        $evidenceInput = "$($j.RunIdentity)`n$($j.Id)`n$($j.Vendor)`n$($j.PhaseLabel)`n$($j.OutFile)`n"
        $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($evidenceInput))).ToLowerInvariant()
        $results += [pscustomobject]@{ Id = $j.Id; Label = $j.Label; Vendor = $j.Vendor; OutFile = $j.OutFile; Out = ''; Exit = -1; ElapsedMs = 0; Degraded = $false; RunIdentity = $j.RunIdentity; EvidenceFingerprint = $fingerprint }
    }

    $ok = @()
    foreach ($res in $results) {
        $owner = @($jobs | Where-Object { $_.Id -ceq $res.Id -and $_.Vendor -ceq $res.Vendor })
        $expectedOutFile = Join-Path $WorkDir ("{0}-{1}.txt" -f $phaseLabel, $res.Id)
        $evidenceInput = "$runIdentity`n$($res.Id)`n$($res.Vendor)`n$phaseLabel`n$($res.OutFile)`n$($res.Out)"
        $expectedEvidenceFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($evidenceInput))).ToLowerInvariant()
        if ($owner.Count -ne 1 -or $res.OutFile -cne $expectedOutFile -or
            $res.RunIdentity -cne $runIdentity -or $res.EvidenceFingerprint -cne $expectedEvidenceFingerprint) {
            Write-Warning "[$phaseLabel] rejected output with mismatched run/reviewer/vendor/phase provenance: $($res.Id)/$($res.Vendor) -> $($res.OutFile)"
            continue
        }
        if ($res.Exit -ne 0 -or [string]::IsNullOrWhiteSpace($res.Out)) {
            Write-Warning "[$phaseLabel] reviewer $($res.Id) ($($res.Label)) FAILED (exit $($res.Exit)) — degrading."
            Set-Content -LiteralPath $res.OutFile -Value "[reviewer unavailable: exit $($res.Exit)]`n$($res.Out)" -Encoding utf8
        }
        else {
            if ($res.Degraded) {
                Write-Warning "[$phaseLabel] reviewer $($res.Id) ($($res.Label)) degraded to API fallback — the subscription-backed CLI failed."
            }
            $stripped = Strip-Preamble $res.Out $startPattern
            Set-Content -LiteralPath $res.OutFile -Value $stripped.Text -Encoding utf8
            if (-not $stripped.Matched) {
                Write-Warning ("[$phaseLabel] reviewer $($res.Id) ($($res.Label)) produced output with no '$startPattern' " +
                    'section — narration, a refusal or an off-contract reply. NOT counted as a participating vendor; ' +
                    'text still forwarded to the judge as unpooled.')
                Set-Content -LiteralPath $res.OutFile -Value "[reviewer off-contract: no '$startPattern' match]`n$($stripped.Text)" -Encoding utf8
                $script:offContract += [pscustomobject]@{
                    Phase = $phaseLabel; Id = $res.Id; Label = $res.Label
                    Vendor = $res.Vendor; Text = $stripped.Text
                }
                continue
            }
            # The start pattern alone is necessary but not SUFFICIENT: it only proves a
            # section exists. '### Analysis' plus prose used to admit a reply that
            # contained no finding and no verdict, and the pooled-coverage check merely
            # warned while $ok grew — so a vendor that contributed nothing still counted
            # toward minVendors. Admission additionally requires the phase's contract
            # content: a structured finding field or the clean sentinel (Phase 1), at
            # least one F# verdict (Phase 2, when there is anything to vote on).
            if ($AdmissionPattern -and -not ($stripped.Text -match $AdmissionPattern)) {
                Write-Warning ("[$phaseLabel] reviewer $($res.Id) ($($res.Label)) matched the start pattern but produced no " +
                    "$AdmissionDescription — narration under a heading is not participation. NOT counted as a " +
                    'participating vendor; text still forwarded to the judge as unpooled.')
                Set-Content -LiteralPath $res.OutFile -Value "[reviewer off-contract: no $AdmissionDescription]`n$($stripped.Text)" -Encoding utf8
                $script:offContract += [pscustomobject]@{
                    Phase = $phaseLabel; Id = $res.Id; Label = $res.Label
                    Vendor = $res.Vendor; Text = $stripped.Text
                }
                continue
            }
            # The clean sentinel is a whole-reply contract: a reply that contains it AND
            # anything else (a Severity field, narration) is mixed, and admitting it via
            # the other alternation branch would let a hedging reviewer count as clean.
            if ($phaseLabel -eq 'p1' -and
                $stripped.Text -match "(?im)$([regex]::Escape($cleanSentinel))" -and
                -not ($stripped.Text -match $cleanSentinelPattern)) {
                Write-Warning ("[p1] reviewer $($res.Id) ($($res.Label)) mixed the clean sentinel with other content — " +
                    'the sentinel is the whole-reply clean contract. NOT counted as a participating vendor; ' +
                    'text still forwarded to the judge as unpooled.')
                Set-Content -LiteralPath $res.OutFile -Value "[reviewer off-contract: clean sentinel mixed with other content]`n$($stripped.Text)" -Encoding utf8
                $script:offContract += [pscustomobject]@{
                    Phase = $phaseLabel; Id = $res.Id; Label = $res.Label
                    Vendor = $res.Vendor; Text = $stripped.Text
                }
                continue
            }
            # Phase 2 coverage is advisory, not a gate: a reviewer may legitimately have
            # nothing to say about some pooled findings. Surface the number so a reply
            # covering 3 of 17 is visible rather than indistinguishable from a full one.
            # The uncovered ids are ALSO recorded per reviewer (status.json and the
            # judge packet) as explicit abstentions, so the judge can tell a considered
            # silence from absence and never rests [unanimous] on one vote plus silence.
            if ($ExpectedFIds -and $ExpectedFIds.Count -gt 0) {
                # Coverage is derived from PARSED verdict lines only — a bare mention
                # of an F-id in prose ("F12 and F13 both agree") is not a verdict, and
                # counting it would read silence as a considered abstention.
                $verdictedIds = @(
                    [regex]::Matches($stripped.Text, "(?im)$p2VerdictLine") |
                        ForEach-Object { ([regex]::Match($_.Value, 'F\d+')).Value.ToUpperInvariant() } |
                        Sort-Object -Unique
                )
                $coveredIds = @($ExpectedFIds | Where-Object { $_ -in $verdictedIds })
                # A verdict must name an EXPECTED finding id: 'F999: AGREE' satisfies the
                # line pattern while voting on nothing in the pool, so with zero expected
                # ids covered the reply is off-contract, not participation.
                if ($coveredIds.Count -eq 0) {
                    Write-Warning ("[$phaseLabel] reviewer $($res.Id) ($($res.Label)) verdicts named no pooled finding id " +
                        "(expected $($ExpectedFIds -join ', ')) — voting outside the pool is not participation. " +
                        'NOT counted as a participating vendor; text still forwarded to the judge as unpooled.')
                    Set-Content -LiteralPath $res.OutFile -Value "[reviewer off-contract: no verdict for any pooled finding id]`n$($stripped.Text)" -Encoding utf8
                    $script:offContract += [pscustomobject]@{
                        Phase = $phaseLabel; Id = $res.Id; Label = $res.Label
                        Vendor = $res.Vendor; Text = $stripped.Text
                    }
                    continue
                }
                $script:p2Coverage[$res.Id] = [ordered]@{
                    covered   = $coveredIds
                    abstained = @($ExpectedFIds | Where-Object { $_ -notin $coveredIds })
                }
                if ($coveredIds.Count -lt [math]::Ceiling($ExpectedFIds.Count / 2)) {
                    Write-Warning "[$phaseLabel] reviewer $($res.Id) ($($res.Label)) addressed only $($coveredIds.Count) of $($ExpectedFIds.Count) pooled findings."
                }
            }
            $ok += $res
        }
    }
    , $ok
}

# --- Phase 1 -------------------------------------------------------------
# Start patterns tolerate leading whitespace, list markers and markdown emphasis. The strict
# line-initial forms discarded substantive reviews on formatting alone -- twice now. The comment
# above $offContract records 2026-08-16 (three anthropic reviews, `**F1** ... AGREE`); it happened
# again on 2026-08-17, when a reviewer wrote `**F1: FALSE POSITIVE**` and its whole
# repository-backed cross-examination was excluded from the participating-vendor count, leaving
# status.json reporting four Phase-2 vendors where five reviewers had taken part. Forwarding the
# text to the judge limited the damage but left every consensus tally wrong for that chunk.
$p1Admission = "(?:\*\*Severity:\*\*)|$cleanSentinelPattern"
$p1ok = Invoke-Round 'p1' '^\s*(?:[-*+]\s+)?(?:\*\*|__)?#{1,6}(?:\*\*|__)?\s' $false @() $p1Admission 'structured finding field or the clean sentinel'
if (-not $p1ok) { Die 'No reviewer produced Phase 1 findings; cannot continue.' }
$p1Vendors = ($p1ok.Vendor | Sort-Object -Unique).Count
if ($p1Vendors -lt $minVendors) {
    # Below minVendors this is NOT an adversarial panel — a single-vendor round is
    # self-review, and the whole value of the exercise is uncorrelated error across
    # vendors. This used to be a Write-Warning and the script still exited 0, so a
    # batched caller recorded the chunk as clean and the run reported success on a
    # panel that never happened. Fail loudly instead: the caller must be able to
    # tell "reviewed by one vendor" from "reviewed properly".
    Die "Only $p1Vendors vendor(s) produced Phase 1 findings (min $minVendors) — this is not an adversarial panel. Re-run this chunk; do not judge it."
}

# --- Pool + anonymise + assign F-ids ------------------------------------
# Split each participating reviewer's stripped Phase-1 output with the SAME pattern
# that admitted it (Split-FindingBlocks, pool-findings.ps1): the old pooler opened a
# block only on the literal '^### ', so admitted forms ('## ', '#### ', '- ### ',
# '  ### ') pooled ZERO findings while the vendor still counted toward minVendors,
# and a '### ' line inside a fenced code block split a finding in two. The splitter
# normalises every heading to canonical '### ' and tracks fence state.
# Per-reviewer raised counts come from the pooled blocks themselves (off the
# normalised form), and pooled-map.json records F# -> {id, vendor} so an adjudicated
# finding has a machine-readable backlink to whoever raised it.
$findingId = 0
$raisedById = @{}
$pooledMap = [ordered]@{}
$pool = [System.Text.StringBuilder]::new()
[void]$pool.AppendLine('# Pooled findings (attribution removed)')
[void]$pool.AppendLine()
foreach ($res in $p1ok) {
    $text = Get-Content -LiteralPath $res.OutFile -Raw
    $before = $findingId
    # Assign BEFORE wrapping: @(Split-FindingBlocks ...) captures the returned array
    # as ONE element instead of its blocks (the single-array pipeline quirk).
    $findingBlocks = Split-FindingBlocks $text
    foreach ($finding in @($findingBlocks)) {
        $body = $finding.Trim()
        if (-not $body) { continue }
        # The canonical clean sentinel is PARTICIPATION, not a finding: a reviewer
        # whose reply is '### No substantive defects' counts toward vendor diversity
        # with issuesRaised = 0 and contributes nothing to the pool.
        if ($body -match "(?m)^\s*###\s*$cleanSentinel\s*$") { continue }
        $findingId++
        $fid = "F$findingId"
        # Trim a trailing horizontal-rule separator a reviewer may have placed
        # between its own findings, so it does not bleed into the pooled block.
        $body = $body -replace '(\r?\n\s*-{3,}\s*)+$', ''
        [void]$pool.AppendLine("## $fid")
        [void]$pool.AppendLine($body.Trim())
        [void]$pool.AppendLine()
        $pooledMap[$fid] = [ordered]@{ id = $res.Id; vendor = $res.Vendor }
    }
    $raisedById[$res.Id] = $findingId - $before
}
Set-Content -LiteralPath $pooledFile -Value ($pool.ToString().TrimEnd()) -Encoding utf8
$pooledMapFile = Join-Path $WorkDir 'pooled-map.json'
$pooledMap | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $pooledMapFile -Encoding utf8
Write-Host "Pooled $findingId findings into $(Split-Path -Leaf $pooledFile)"

# --- Phase 2 -------------------------------------------------------------
# `1..0` is a DESCENDING range in PowerShell, not an empty one, so an empty pool would
# yield @('F1','F0') and warn about findings that do not exist.
$expectedFIds = if ($findingId -gt 0) { @(1..$findingId | ForEach-Object { "F$_" }) } else { @() }
# A BARE F-number must be followed by punctuation (`F1:`, `F3.`, `F9)`); only an EMPHASISED one
# may be separated by whitespace, which is what `**F12** ... AGREE` needs. Allowing bare
# `F\d+\s` matched prose such as "F12 and F13 both agree" and "F5 findings were raised", which
# would admit narration as though it were a verdict block.
$p2VerdictPattern = '^\s*(?:[-*+]\s+)?(?:\*\*|__|\*|_)?F\d+(?:(?:\*\*|__|\*|_)\s*[:.\)\s]|\s*[:.\)])'
# An F-id followed by arbitrary text is not a verdict. The contract vocabulary
# (briefs/phase2-cross-examine.txt) is AGREE | FALSE POSITIVE | NEEDS EVIDENCE, with
# NEEDS REPO the brief's explicit no-repo-access answer; admission and coverage key
# on a verdict line carrying one of those keywords, never on the F-id alone.
# Word-bounded on BOTH sides: without the leading \b, 'disagree' contains 'AGREE'
# and arbitrary text after an F-id would still pass as a verdict.
$p2VerdictKeyword = '\b(?:AGREE|FALSE\s+POSITIVE|NEEDS\s+EVIDENCE|NEEDS\s+REPO)\b'
$p2VerdictLine = "$p2VerdictPattern[^\r\n]*?$p2VerdictKeyword"
if ($findingId -eq 0) {
    # Every participating reviewer returned the clean sentinel (or nothing poolable):
    # the pool is EMPTY but the panel DID convene. That is a clean chunk, not a
    # failure — terminate cleanly with zero findings instead of running a Phase 2 over
    # an empty pool. batch-review.ps1 tells this apart from a failed chunk via
    # status.json's pooledCount.
    Write-Host 'All participating reviewers reported no substantive defects — the pool is empty; skipping Phase 2 and terminating cleanly.'
    $p2ok = @()
    $p2Vendors = 0
}
else {
    # Admission requires at least one valid F# verdict: with findings on the table, a
    # heading plus prose ('### Analysis') is not cross-examination and must not count
    # toward minVendors. The verdict LINE pattern (F-id + contract keyword) is what
    # counts — the bare F-id pattern only LOCATES the section.
    $p2Admission = "(?im)$p2VerdictLine"
    $p2ok = Invoke-Round 'p2' "$p2VerdictPattern|^\s*(?:[-*+]\s+)?(?:\*\*|__)?#{1,6}(?:\*\*|__)?\s" $true $expectedFIds $p2Admission 'F# verdict'
    if (-not $p2ok) { Die 'No reviewer produced Phase 2 cross-examinations; cannot continue.' }
    $p2Vendors = ($p2ok.Vendor | Sort-Object -Unique).Count
    if ($p2Vendors -lt $minVendors) {
        Die "Only $p2Vendors vendor(s) produced Phase 2 cross-examinations (min $minVendors) — this is not an adversarial panel. Re-run this chunk; do not judge it."
    }
}

# --- Per-chunk reviewer metrics (telemetry) -----------------------------
# Write metrics.json so a batched run can be aggregated per participant across
# chunks (aggregate-and-emit.ps1). Covers the THREE reviewers' deterministic
# outcome: issuesRaised (### count) + cost/duration. The judge (synthesis) and
# issuesAccepted are products of adjudication and are recorded separately in
# aggregate-verdict.json at synthesis time. Best-effort: a failure here must
# never fail the review, so the whole block is guarded.
$modelRegistryPath = Join-Path (Split-Path $scriptDir -Parent) 'model-registry' 'registry.json'
$modelPriceHelper = Join-Path (Split-Path $modelRegistryPath -Parent) 'price.ps1'
$modelPriceAvailable = Test-Path -LiteralPath $modelPriceHelper
if ($modelPriceAvailable) { . $modelPriceHelper }
$modelPriceOn = $env:MODEL_REGISTRY_EFFECTIVE_DATE ?? (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
# Every resolution failure below WARNS naming the alias, vendor and registry path. Each
# one used to fail silently, so a stale, corrupt or unpriced registry reproduced the
# fragmenting-alias dashboard bug this resolution exists to fix, with no log line saying
# why. The contract permits these outcomes; it does not permit the silence.
$modelRegistry = if (Test-Path -LiteralPath $modelRegistryPath) {
    try { Get-Content -LiteralPath $modelRegistryPath -Raw | ConvertFrom-Json -AsHashtable }
    catch {
        # A corrupt registry must not read as an absent one.
        Write-Warning "Model registry at $modelRegistryPath is unreadable ($($_.Exception.Message)); telemetry will record configured aliases and unknown cost."
        $null
    }
} else {
    Write-Warning "Model registry not found at $modelRegistryPath; telemetry will record configured aliases and unknown cost."
    $null
}
function Resolve-TelemetryModel([object] $reviewer) {
    $configured = [string]$reviewer.model
    if ($reviewer.vendor -ne 'anthropic' -or $configured -notin @('opus', 'sonnet', 'haiku', 'fable') -or -not $modelRegistry) {
        return $configured
    }
    $prefix = "claude-$configured-"
    $match = $modelRegistry.models.GetEnumerator() |
        Where-Object { $_.Key.StartsWith($prefix) -and $_.Value.availability.cli -eq 'available' -and -not $_.Value.retired } |
        Sort-Object { [int]($_.Value.rank ?? [int]::MaxValue) }, Key |
        Select-Object -First 1
    if (-not $match) {
        # Returning the bare alias is what fragments the dashboard into one row per alias.
        Write-Warning "No available, non-retired '$prefix*' entry in $modelRegistryPath for reviewer '$($reviewer.id)' (vendor $($reviewer.vendor)); falling back to the bare alias '$configured', which will fragment its Observatory rows."
        return $configured
    }
    return [string]$match.Key
}
function Get-BlendedRatePerMillion([string] $model) {
    if (-not $modelPriceAvailable -or -not $modelRegistry) { return $null }
    if (-not $modelRegistry.models.ContainsKey($model)) {
        Write-Warning "Model '$model' is absent from $modelRegistryPath; cost is UNKNOWN, not zero."
        return $null
    }
    $facts = $modelRegistry.models[$model]
    $price = Get-ModelRegistryPrice -Facts $facts -Channel api -On $modelPriceOn
    if ($null -eq $price) {
        Write-Warning "Model '$model' has no sourced API price effective $modelPriceOn in $modelRegistryPath; cost is UNKNOWN, not zero."
        return $null
    }
    return (0.75 * [double]$price.price_in) + (0.25 * [double]$price.price_out)
}
# Exact where the split is KNOWN. A blended rate is a stand-in for an unknown in/out mix;
# applying it to ($inTok + $outTok) when both are tracked separately charges every input
# token at 0.25 x price_out. Returns $null when the model is unpriced so the caller can
# record unknown rather than 0.0.
function Get-ExactCostUsd([string] $model, [long] $inTok, [long] $outTok) {
    if (-not $modelPriceAvailable -or -not $modelRegistry -or -not $modelRegistry.models.ContainsKey($model)) { return $null }
    $facts = $modelRegistry.models[$model]
    return Get-ModelRegistryCost -Facts $facts -InputTokens $inTok -OutputTokens $outTok -Channel api -On $modelPriceOn
}
function Read-UsageSidecar([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $null }
}
try {
    $participants = foreach ($r in $reviewers) {
        $p1res = $p1ok | Where-Object { $_.Id -eq $r.id } | Select-Object -First 1
        $p2res = $p2ok | Where-Object { $_.Id -eq $r.id } | Select-Object -First 1
        $durationMs = [long](($p1res.ElapsedMs ?? 0) + ($p2res.ElapsedMs ?? 0))
        # Record whether this reviewer's sub-backed primary failed and the API
        # fallback carried the phase, in either phase — so degraded-to-API state
        # is durable in metrics.json, not just a transient warning.
        $degraded = [bool](($p1res.Degraded) -or ($p2res.Degraded))

        $p1File = Join-Path $WorkDir ("p1-{0}.txt" -f $r.id)
        # Raised counts come from the pooling pass itself (the normalised '### '
        # blocks), not from re-counting the literal heading in the phase file — the
        # old count missed every admitted non-'### ' heading form and would count a
        # clean-sentinel heading as a finding.
        $raised = [int]($raisedById[$r.id] ?? 0)

        # Sidecars are read UNCONDITIONALLY: a fallback call's spend lives in
        # usage-<id>-<phase>-fallback.json (summed alongside the primary's), and an
        # off-contract reviewer may still have billed real tokens before its reply
        # was rejected — hard-coding zeros on that branch would erase real spend.
        $sidecars = @(
            (Read-UsageSidecar (Join-Path $WorkDir ("usage-{0}-p1.json" -f $r.id)))
            (Read-UsageSidecar (Join-Path $WorkDir ("usage-{0}-p1-fallback.json" -f $r.id)))
            (Read-UsageSidecar (Join-Path $WorkDir ("usage-{0}-p2.json" -f $r.id)))
            (Read-UsageSidecar (Join-Path $WorkDir ("usage-{0}-p2-fallback.json" -f $r.id)))
        ) | Where-Object { $_ }

        # A reviewer that produced NO usable output in either phase AND left no usage
        # sidecar ran nothing. It must record zeros, not an estimate. The old code
        # fell straight into the sidecar-less branch below and billed it
        # $estTokens * 2 — the DIFF's own token estimate — so a dead reviewer was
        # indistinguishable from a live one, and a chunk whose OpenAI call 401'd
        # logged the exact same figure as the two Claude reviewers (observed: 23760
        # three times over). Fabricated metrics for a reviewer that never spoke are
        # worse than no metrics: they make a broken panel read as a working one.
        # But the zero branch used to fire on $phasesRun alone, BEFORE any sidecar
        # was read — a reviewer whose reply went off-contract after a billed call
        # (or whose primary billed and only the fallback failed) had that real spend
        # overwritten with zeros and no costUnknown key at all. Zeros are now forced
        # only when nothing ran AND nothing billed.
        $phasesRun = @(@($p1res, $p2res) | Where-Object { $_ }).Count
        $telemetryModel = Resolve-TelemetryModel $r

        if ($phasesRun -eq 0 -and -not $sidecars) {
            [ordered]@{
                reviewer         = $r.vendor
                role             = 'reviewer'
                model            = $telemetryModel
                inputTokens      = 0
                outputTokens     = 0
                costUsd          = 0.0
                costEstimated    = $false
                costUnknown      = $false
                failed           = $true
                degraded         = $degraded
                reviewDurationMs = $durationMs
                issuesRaised     = 0
            }
        }
        else {
            # "Cost unknown" and "cost measured as ~0" are different facts and must not
            # both render as 0.0. Sidecars measure tokens; registry pricing may be unknown.
            $costUnknown = $false
            if ($sidecars) {
                $inTok  = [long]($sidecars | Measure-Object -Property inputTokens  -Sum).Sum
                $outTok = [long]($sidecars | Measure-Object -Property outputTokens -Sum).Sum
                $cost   = [double]($sidecars | Measure-Object -Property costUsd     -Sum).Sum
                $costUnknown = @($sidecars | Where-Object { $_.costUnknown }).Count -gt 0
                # Exact only when every phase the reviewer ran produced a sidecar. A
                # partial set (a phase failed, or its wrapper wrote none) still sums
                # the real figures it has but is flagged putative rather than exact,
                # so the missing phase's cost is not silently presented as complete.
                $estimated = ($sidecars.Count -lt $phasesRun)
                # A sidecar that reports zero tokens (e.g. Kimi — its stream-json
                # carries no usage) is not exact usage, it is unavailable: flag it
                # estimated so the dashboard does not present a flat-rate ~0 as a
                # measured figure.
                if ($inTok -eq 0 -and $outTok -eq 0) { $estimated = $true }
            } else {
                # No sidecar (Claude wrapper) — estimate from proxies and the blended
                # rate. Input ≈ the diff once per phase ACTUALLY RUN (P1 full, P2 with
                # pooled findings); output ≈ chars in this reviewer's P1+P2 text / 4.
                # Scale by $phasesRun, not a hardcoded 2: a reviewer that only
                # survived P1 must not be billed for a P2 it never made.
                $inTok  = [long]($estTokens * $phasesRun)
                $outChars = 0
                foreach ($f in @($p1res.OutFile, $p2res.OutFile)) {
                    if ($f -and (Test-Path -LiteralPath $f)) { $outChars += (Get-Content -LiteralPath $f -Raw).Length }
                }
                $outTok = [long][Math]::Ceiling($outChars / 4.0)
                # Both counts are proxies, but they ARE tracked separately, so price them
                # separately. The blended rate is only a stand-in for an unknown split.
                $cost = Get-ExactCostUsd $telemetryModel $inTok $outTok
                if ($null -eq $cost) {
                    $rate = Get-BlendedRatePerMillion $telemetryModel
                    if ($null -ne $rate) { $cost = ($inTok + $outTok) * $rate / 1e6 }
                }
                $costUnknown = ($null -eq $cost)
                if ($costUnknown) { $cost = 0.0 }
                $estimated = $true
            }

            [ordered]@{
                reviewer         = $r.vendor
                role             = 'reviewer'
                model            = $telemetryModel
                inputTokens      = $inTok
                outputTokens     = $outTok
                costUsd          = [Math]::Round($cost, 6)
                costEstimated    = $estimated
                costUnknown      = $costUnknown
                # A reviewer that billed (sidecar present) but never made the
                # participating set — off-contract in both phases — still failed
                # the round; its spend is real either way and is recorded above.
                failed           = ($phasesRun -eq 0)
                degraded         = $degraded
                reviewDurationMs = $durationMs
                issuesRaised     = $raised
            }
        }
    }
    $metrics = [ordered]@{
        chunkId      = (Split-Path -Leaf $WorkDir)
        repo         = $repoName
        writtenBy    = 'run-review.ps1'
        participants = @($participants)
    }
    $metrics | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $WorkDir 'metrics.json') -Encoding utf8
}
catch {
    Write-Warning "metrics.json not written ($_). Telemetry aggregation will fall back to estimates for this chunk."
}

# --- Assemble the judge packet ------------------------------------------
$packet = [System.Text.StringBuilder]::new()
[void]$packet.AppendLine("# Judge packet — $repoName")
[void]$packet.AppendLine()
$compactNote = if ($compactDiffFile) { " · compact diff: $($repoBlindIds -join '+')" } else { '' }
[void]$packet.AppendLine("Target: ``$($Target ? $Target : '(branch vs base)')`` · added lines: $addedLines · total lines: $totalLines · est. tokens: $estTokens$compactNote · audit: $isAudit")
if ($dirtyPaths.Count -gt 0) {
    [void]$packet.AppendLine("NOT REVIEWED — $($dirtyPaths.Count) uncommitted/untracked path(s) the resolved diff cannot contain: $(($dirtyPaths | Select-Object -First 30) -join ', ')")
}
[void]$packet.AppendLine("Reviewers (Phase 1): $(($p1ok.Label) -join ', ')")
[void]$packet.AppendLine()
[void]$packet.AppendLine('Adjudicate with `briefs/phase3-adjudicate.txt` (copied here as `phase3-brief.txt`).')
[void]$packet.AppendLine('Then verify every Critical, every High and every contested finding with `briefs/phase4-verify.txt` (Phase 4, copied here as `phase4-brief.txt`) before publishing.')
[void]$packet.AppendLine('If you run the optional Phase-3.5 judge audit (`briefs/phase3.5-judge-audit.txt`), hand the auditor THIS PACKET as well as the adjudicated report — the attributed Phase-1 section below is what lets it catch a [majority] tag on a single-vendor finding.')
[void]$packet.AppendLine('The diff under review is `review-diff.txt`; read the repo to settle contested mechanisms.')
[void]$packet.AppendLine()
[void]$packet.AppendLine('---')
[void]$packet.AppendLine('## Phase 1 — blind findings (per reviewer)')
foreach ($res in $p1ok) {
    [void]$packet.AppendLine()
    [void]$packet.AppendLine("### Reviewer $($res.Id) — $($res.Label)")
    [void]$packet.AppendLine()
    [void]$packet.AppendLine((Get-Content -LiteralPath $res.OutFile -Raw).TrimEnd())
}
[void]$packet.AppendLine()
[void]$packet.AppendLine('---')
[void]$packet.AppendLine('## Pooled findings (anonymised, F-ids)')
[void]$packet.AppendLine()
[void]$packet.AppendLine((Get-Content -LiteralPath $pooledFile -Raw).TrimEnd())
[void]$packet.AppendLine()
[void]$packet.AppendLine('---')
[void]$packet.AppendLine('## Phase 2 — cross-examination (per reviewer)')
if ($findingId -eq 0) {
    [void]$packet.AppendLine()
    [void]$packet.AppendLine('Every participating reviewer reported the clean sentinel — there was nothing to cross-examine, so Phase 2 did not run.')
}
foreach ($res in $p2ok) {
    [void]$packet.AppendLine()
    [void]$packet.AppendLine("### Reviewer $($res.Id) — $($res.Label)")
    $cov = $script:p2Coverage[$res.Id]
    if ($cov -and $cov.abstained.Count -gt 0) {
        # Explicit abstention: this reviewer saw these pooled findings and recorded
        # no verdict on them. Considered silence, not absence — do not read an
        # [unanimous] or [majority] tag as carrying this vendor's vote on these ids.
        [void]$packet.AppendLine()
        [void]$packet.AppendLine("Abstained (no verdict recorded): $($cov.abstained -join ', ')")
    }
    [void]$packet.AppendLine()
    [void]$packet.AppendLine((Get-Content -LiteralPath $res.OutFile -Raw).TrimEnd())
}
if ($script:offContract.Count -gt 0) {
    [void]$packet.AppendLine()
    [void]$packet.AppendLine('---')
    [void]$packet.AppendLine('## Unpooled — off-contract reviewer output')
    [void]$packet.AppendLine()
    [void]$packet.AppendLine('These replies failed the round''s start-pattern check, so they are NOT counted')
    [void]$packet.AppendLine('as participating vendors anywhere in this run and their findings carry no')
    [void]$packet.AppendLine('F-ids. That is a FORMATTING verdict, not a content one. Read them, weigh them')
    [void]$packet.AppendLine('on their merits, and fold anything substantive into the adjudication — but')
    [void]$packet.AppendLine('never promote a pooled finding to unanimous or contested on their strength,')
    [void]$packet.AppendLine('and never treat one as a second vendor vote.')
    foreach ($oc in $script:offContract) {
        [void]$packet.AppendLine()
        [void]$packet.AppendLine("### Unpooled $($oc.Phase) — Reviewer $($oc.Id) ($($oc.Label), $($oc.Vendor))")
        [void]$packet.AppendLine()
        [void]$packet.AppendLine($oc.Text.TrimEnd())
    }
}
$packetFile = Join-Path $WorkDir 'judge-packet.md'
Set-Content -LiteralPath $packetFile -Value ($packet.ToString().TrimEnd()) -Encoding utf8

# --- Status --------------------------------------------------------------
$status = [ordered]@{
    state           = 'complete'
    runIdentity     = $runIdentity
    resolvedTarget  = $resolvedTargetIdentity
    diffSha256      = $diffSha256
    repo            = $repoName
    repoPath        = $RepoPath
    target          = $Target
    audit           = $isAudit
    uncommittedExcluded = $dirtyPaths
    addedLines      = $addedLines
    totalLines      = $totalLines
    estTokens       = $estTokens
    compactDiff     = $compactDiffFile
    workDir         = $WorkDir
    diffFile        = $diffFile
    pooledFile      = $pooledFile
    pooledMap       = $pooledMapFile
    judgePacket     = $packetFile
    pooledCount     = $findingId
    preflight       = $preflight
    offContract     = @($script:offContract | ForEach-Object { @{ phase = $_.Phase; id = $_.Id; vendor = $_.Vendor } })
    phase1Reviewers = @($p1ok | ForEach-Object { @{ id = $_.Id; label = $_.Label; vendor = $_.Vendor } })
    phase2Reviewers = @($p2ok | ForEach-Object { @{ id = $_.Id; label = $_.Label; vendor = $_.Vendor } })
    # Per participating Phase-2 reviewer, the pooled ids it recorded NO verdict on.
    # An explicit abstention is considered silence; without this record a consensus
    # tag could rest on one vote plus untracked absence.
    phase2Abstentions = @($p2ok | ForEach-Object {
            $cov = $script:p2Coverage[$_.Id]
            @{ id = $_.Id; vendor = $_.Vendor; abstained = @($cov ? $cov.abstained : @()) }
        })
    vendorsP1       = $p1Vendors
    nextSteps       = @('adjudicate (phase3-brief.txt)', 'verify every Critical, every High and every contested finding (phase4-brief.txt)', 'optionally judge-audit with briefs/phase3.5-judge-audit.txt fed judge-packet.md', 'synthesise if multi-chunk', 'persist to vault')
}
$status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusFile -Encoding utf8

Write-Host ''
Write-Host '==== adversarial-review spine complete ===='
Write-Host "Work dir:     $WorkDir"
Write-Host "Pooled:       $findingId findings ($pooledFile)"
Write-Host "Judge packet: $packetFile"
Write-Host "Next: adjudicate -> verify -> [synthesise] -> persist (see status.json / SKILL.md)."
$status | ConvertTo-Json -Depth 6

# Observatory telemetry: wrapper sidecars carry usage where available and
# explicit zeros where a subscription CLI (agy/kimi) does not expose it.
