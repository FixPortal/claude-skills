$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..'
$main = Get-Content (Join-Path $root 'SKILL.md') -Raw
$runbook = Get-Content (Join-Path $root 'references' 'runbook.md') -Raw
$text = $main + "`n" + $runbook

# collect.ps1 emits sinceReviewFiles as an INTEGER file count parsed from
# `git diff --shortstat` (collect.ps1 ~L335, initialised 0 at ~L447). No field in the
# JSON exposes changed file NAMES, so a docs-only test cannot read one off it.
if ($text -match 'sinceReviewFiles`?\s*contains') {
    throw "SKILL.md treats sinceReviewFiles as a file list; collect.ps1 emits an integer count"
}

# The triage fields are nested under a per-repo `.git` object, not top level.
foreach ($needle in 'diff --name-only',
                    '.git.sinceReviewCount',
                    'file count, not a list',
                    'UNKNOWN', 'STOP', 'unresolved', 'outsideScanPath',
                    'isDocumentReview', 'resolvedPath', 'exactly one admissible row') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md missing corrected triage guidance: $needle"
    }
}

# Replacing the collector's eligibility decision with raw neverReviewed, or auditing a
# docs-only repo, must fail this contract. The rows are independently hand-derived from
# review-digest's emitted fields; this test never recreates marker/boundary inference.
$triageCases = @(
    @{ Name = 'reviewed drift'; Required = @('hasTrackedSource = true', 'effectiveNeverReviewed = false', 'boundary set; later commits', 'drift') },
    @{ Name = 'true never-reviewed code'; Required = @('hasTrackedSource = true', 'effectiveNeverReviewed = true', 'audit') },
    @{ Name = 'no tracked source'; Required = @('hasTrackedSource = false', 'skip/void') }
)
foreach ($case in $triageCases) {
    foreach ($needle in $case.Required) {
        if ($text -notmatch [regex]::Escape($needle)) {
            throw "Triage case '$($case.Name)' missing required contract: $needle"
        }
    }
}

$triageTable = [regex]::Match($runbook, '(?s)\| Evidence \| Class \| Action \|.*?(?=\r?\n\r?\n`sinceReviewFiles`)')
if (-not $triageTable.Success -or $triageTable.Value -notmatch '(?m)^\| `hasTrackedSource=true`; `effectiveNeverReviewed=true` \| audit \|') {
    throw 'Triage table must map tracked effectiveNeverReviewed=true to audit in one row'
}

foreach ($needle in '`effectiveNeverReviewed` is authoritative', 'Do not use `.git.neverReviewed`') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "Triage contract missing prose-only marker guidance: $needle"
    }
}

foreach ($needle in 'effectiveNeverReviewed', 'hasTrackedSource=false', 'unknown is STOP') {
    if ($main -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md must surface the collector triage contract: $needle"
    }
}

# Discovery either states the finite exclusions it applies or makes none. An undefined
# exclusion promise silently changes which repositories spend reviewer budget.
if ($text -match 'applying exact\s+leaf-name exclusions') {
    throw 'Discovery promises leaf-name exclusions without defining the finite list.'
}

'review-sweep triage fields OK'
