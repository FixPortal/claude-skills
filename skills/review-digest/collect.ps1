[CmdletBinding()]
param(
  [string]$Path = '<workdir>',
  [string]$OutFile = (Join-Path $env:TEMP 'review-digest-data.json'),
  [string]$VaultRoot = '<vault>\Claude\Adversarial Review',
  # Roots searched to resolve a vault folder whose code lives outside $Path. Only used as a
  # fallback when the report carries no file:/// links to resolve from.
  [string[]]$RepoRoots = @()
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path -PathType Container)) {
  Write-Error "Path not a folder: $Path"; exit 2
}

# Markers that identify a review/remediation commit from its subject (case-insensitive).
# Broad words in a commit body are not review evidence.
$strictReviewEvidenceRegex = '\b(?:review(?:er[- ]findings)?|adversarial[- ]audit)[- ](?:batch|run)\s*#?\d+\b'
$strictReviewTrailerRegex = '^(?:review(?:er[- ]findings)?|adversarial[- ]audit)[- ](?:batch|run):\s*#?\d+\s*$'
$markerRegex = "^(?:fix\(review\):|.*$strictReviewEvidenceRegex)"

# Web-quality sweeps (react-doctor / optimise-web / a11y) are committed with the same
# reviewer-findings marker but are NOT adversarial reviews. They must never anchor the
# review boundary, or a repo with real unreviewed feature work reports a false sinceReview=0.
$webQualityRegex = 'react-doctor|optimi[sz]e-web|web-quality|a11y|accessibilit|lighthouse|perf micro'

# Enumerate top-level git repos under $Path. If $Path is itself a repo, digest
# just that one - SKILL.md documents "a single repo name/path -> digest just that
# one repo", and without this the scan only ever looks one level down, so passing
# a repo's own directory exits 3 on the repo you just named.
if (Test-Path (Join-Path $Path '.git')) {
  $repos = @(Get-Item -LiteralPath $Path)
}
else {
  $repos = @(Get-ChildItem $Path -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName '.git')
  })
}
if (-not $repos) { Write-Error "No git repos under $Path"; exit 3 }

function Get-VaultData {
  param([string]$RepoName, [string]$VaultRoot)
  $empty = [pscustomobject]@{ exists = $false; indexPath = $null; runName = $null; reviewers = @(); judge = $null; date = $null; reviewType = $null; tally = $null; reportFiles = @(); reviewTarget = $null; reviewScope = $null; isDocumentReview = $false; subsystemPath = $null; subsystemPaths = @() }
  $repoDir = Join-Path $VaultRoot $RepoName
  if (-not (Test-Path $repoDir)) { return $empty }
  # Each run is a timestamped subfolder holding _index.md. Pick the run with the newest frontmatter date (fallback: folder mtime).
  $runs = Get-ChildItem $repoDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName '_index.md') }
  if (-not $runs) { return $empty }
  $best = $null; $bestDate = [datetime]::MinValue; $bestName = ''
  foreach ($run in $runs) {
    $idx = Join-Path $run.FullName '_index.md'
    [datetime]$fmDate = [datetime]::MinValue
    $head = Get-Content $idx -TotalCount 12
    $dm = ($head | Select-String -Pattern '^date:\s*(\d{4}-\d{2}-\d{2})').Matches
    # ISO day from frontmatter: parse exactly, culture-invariantly. A bare TryParse is
    # culture-dependent and a non-Gregorian or day-first culture can refuse or misread it.
    if ($dm.Count) { [datetime]::TryParseExact($dm[0].Groups[1].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$fmDate) | Out-Null }
    $effective = if ($fmDate -gt [datetime]::MinValue) { $fmDate } else { $run.LastWriteTime }
    # Frontmatter dates are day-granular, so two same-day runs of one repo tie. Break the tie
    # toward the later run FOLDER NAME (a sortable UTC timestamp, 20260528T221207Z) so the newest
    # run wins — not whichever Get-ChildItem happened to return first. Missing this picked an
    # earlier run whose report lacked the later run's scope sha, defeating sha resolution.
    if ($effective -gt $bestDate -or ($effective -eq $bestDate -and $run.Name -gt $bestName)) {
      $bestDate = $effective; $best = $run; $bestName = $run.Name
    }
  }
  if (-not $best) { return $empty }
  $idx = Join-Path $best.FullName '_index.md'
  $text = Get-Content $idx -Raw
  $reviewers = @(); $judge = $null; $date = $null; $reviewType = $null
  $rm = [regex]::Match($text, '(?im)^reviewers:\s*\[([^\]]*)\]')
  if ($rm.Success) { $reviewers = @($rm.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  $jm = [regex]::Match($text, '(?im)^judge:\s*(.+)$');        if ($jm.Success) { $judge = $jm.Groups[1].Value.Trim() }
  $dm2 = [regex]::Match($text, '(?im)^date:\s*(\d{4}-\d{2}-\d{2})'); if ($dm2.Success) { $date = $dm2.Groups[1].Value }
  $tm = [regex]::Match($text, '(?im)^review-type:\s*(.+)$');  if ($tm.Success) { $reviewType = $tm.Groups[1].Value.Trim() }
  # A review's TARGET distinguishes a code review from a DOCUMENT review. resumes-cv carries
  # `target: your-cv.html` — a CV, not code. Without recording this, the resolver
  # credits a document review as code coverage and the ledger keeps ranking a reviewed CV as an
  # unreviewed code repo. A target ending in a document extension is not code coverage.
  $reviewTarget = $null; $reviewScope = $null; $isDocumentReview = $false
  $gm = [regex]::Match($text, '(?im)^target:\s*(.+)$'); if ($gm.Success) { $reviewTarget = $gm.Groups[1].Value.Trim() }
  $scopeMatch = [regex]::Match($text, '(?im)^scope:\s*(.+)$'); if ($scopeMatch.Success) { $reviewScope = $scopeMatch.Groups[1].Value.Trim() }
  # Strip a surrounding matched YAML quote so `target: "report.pdf"` still hits the extension test.
  if ($reviewTarget -match '^([''"])(.*)\1$') { $reviewTarget = $Matches[2] }
  if ($reviewScope -match '^([''"])(.*)\1$') { $reviewScope = $Matches[2] }
  if ($reviewTarget -and $reviewTarget -match '\.(html?|pdf|docx?|md|txt|rtf|odt)\s*$') { $isDocumentReview = $true }
  # Tally: prefer a "## Tally" section; support inline "Label: N" and table "| Label | N |" forms.
  $tallyScope = if ($text -match '(?s)##\s*Tally[^\n]*\n(.*?)(?=\n##|\z)') { $Matches[1] } else { $text }
  $tally = $null
  $sev = @{}
  foreach ($label in 'Critical','High','Medium','Low') {
    $sm = [regex]::Match($tallyScope, "(?im)^\s*\|\s*$label\s*\|\s*(\d+)\s*\|")   # table row
    # Inline: the (?<![\w-]) lookbehind blocks substring hits inside longer words —
    # with no ## Tally section the scope is the whole document, and a bare
    # case-insensitive match read "Workflow: 5" as Low and "Non-critical: 4" as Critical.
    if (-not $sm.Success) { $sm = [regex]::Match($tallyScope, "(?im)(?<![\w-])$label\s*:\s*(\d+)") }  # inline
    if ($sm.Success) { $sev[$label] = [int]$sm.Groups[1].Value }
  }
  if ($sev.Count) { $tally = [pscustomobject]$sev }
  # A SUBSYSTEM-scoped review must not establish a REPO-WIDE boundary. review-sweep
  # mandates one-subsystem passes, so without this the boundary sha is computed over the
  # whole tree: neverReviewed flips false and sinceReviewCount reads 0 for everything the
  # panel never looked at, and the triage table then classes a never-reviewed subsystem
  # `skip` - permanently, because the next sweep sees the same repo-wide boundary.
  # Preferred source is an explicit `subsystem:` key; failing that, an `audit -- <pathspec>`
  # target names its own scope.
  $subsystemPaths = @()
  $sm2 = [regex]::Match($text, '(?im)^subsystem:[ \t]*(.*)$')
  if ($sm2.Success) {
    $inline = $sm2.Groups[1].Value.Trim()
    if ($inline -match '^\[(.*)\]$') {
      $subsystemPaths = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"', "'", '`') } | Where-Object { $_ })
    } elseif ($inline) {
      $subsystemPaths = @($inline.Trim('"', "'", '`'))
    } else {
      $tail = $text.Substring($sm2.Index + $sm2.Length)
      foreach ($line in @($tail -split '\r?\n')) {
        if (-not $line.Trim()) { continue }
        if ($line -notmatch '^\s+-\s+(.+?)\s*$') { break }
        $subsystemPaths += $Matches[1].Trim().Trim('"', "'", '`')
      }
    }
  }
  if (-not $subsystemPaths.Count -and $reviewTarget -match '(?i)^\s*audit\s+--\s+(.+?)\s*$') {
    $subsystemPaths = @($Matches[1].Trim().Trim('"', "'", '`'))
  }
  $subsystemPath = if ($subsystemPaths.Count -eq 1) { $subsystemPaths[0] } else { $null }
  $reports = @(Get-ChildItem $best.FullName -Filter 'report*.md' | Select-Object -ExpandProperty Name)
  [pscustomobject]@{ exists = $true; indexPath = $idx; runName = $best.Name; reviewers = $reviewers; judge = $judge; date = $date; reviewType = $reviewType; tally = $tally; reportFiles = $reports; reviewTarget = $reviewTarget; reviewScope = $reviewScope; isDocumentReview = $isDocumentReview; subsystemPath = $subsystemPath; subsystemPaths = @($subsystemPaths) }
}

# Resolve a vault folder to the code it actually reviewed, via the file:/// links its
# report carries. A vault folder is NOT proof of a repo: it may name a SUBSYSTEM of one
# (e.g. 'widgetservice' = host-app/Framework/Services/WidgetService). Without this, such a row
# gets an empty git side, remediation becomes undetectable, and it freezes at its original
# tally forever — which is exactly how three digests reported widgetservice's long-fixed Highs
# as outstanding. Returns the enclosing git repo + the subsystem sub-path within it.
function Resolve-VaultTarget {
  param([string]$IndexPath, [string]$FolderName, [string[]]$RepoRoots, [string]$ScanPath)
  $miss = [pscustomobject]@{ resolved = $false; repoPath = $null; repoName = $null; subsystemPath = $null }
  if (-not $IndexPath) { return $miss }
  $dir = Split-Path $IndexPath -Parent
  $files = @($IndexPath) + @(Get-ChildItem $dir -Filter 'report*.md' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  $texts = foreach ($f in $files) { $x = Get-Content $f -Raw -ErrorAction SilentlyContinue; if ($x) { $x } }

  $paths = foreach ($t in $texts) {
    # Percent-decode: a standard file:/// link encodes a space as %20, which would otherwise
    # survive into the path, fail Test-Path, and mark a valid folder unresolved. The capture
    # stops at ')', whitespace and '#' so a markdown link and its #L40-L56 fragment resolve to
    # the file itself, and a URI mentioned in prose does not swallow the sentence after it.
    # Accept BOTH shapes: file:///C:/x (drive-lettered) and file:///abs/posix/path. The
    # drive-letter-only pattern silently matched nothing on a POSIX host, so every link
    # resolved to nothing and every vault folder read as unresolved there.
    foreach ($m in [regex]::Matches($t, 'file:///([^)\s#]+)')) {
      $raw = [Uri]::UnescapeDataString($m.Groups[1].Value)
      # file:///C:/x -> 'C:/x'; file:///tmp/x -> 'tmp/x', whose real path is '/tmp/x'.
      if ($raw -notmatch '^[A-Za-z]:/') { $raw = '/' + $raw.TrimStart('/') }
      ($raw -replace '/', [IO.Path]::DirectorySeparatorChar)
    }
  }
  $paths = @($paths | Where-Object { $_ } | Select-Object -Unique)

  # (1) file:/// links → walk each up to its nearest enclosing git repo; the most-linked repo wins.
  # Strongest signal: the link points at a file the review actually touched. A stale link whose
  # path no longer exists on disk simply finds no .git and drops through to the sha/name fallback.
  if ($paths) {
    $hits = foreach ($p in $paths) {
      $cur = $p
      while ($cur -and -not (Test-Path (Join-Path $cur '.git'))) {
        $parent = Split-Path $cur -Parent
        if (-not $parent -or $parent -eq $cur) { $cur = $null; break }
        $cur = $parent
      }
      if ($cur) { $cur }
    }
    $hits = @($hits)
    if ($hits) { return (Get-SubsystemTarget -Paths $paths -Hits $hits) }
  }

  # (2) scope-sha resolution — falsifiable, so preferred over a name guess. The report's
  # `scope: <sha>..HEAD` names the boundary the panel reviewed; that commit resolves in the repo
  # whose history contains it, or in NONE. This is what survives a prefix rename (budget-tracker
  # -> personal-budget-tracker) that both the file:/// walk-up and the name search miss: the sha
  # does not care what the folder or the repo is called. The all-zero empty-tree sha of a
  # first-commit `0000000..x` diff is ignored — it resolves in every repo and proves nothing.
  # Seed each candidate root ITSELF when it holds a .git: in single-repo mode $ScanPath is the
  # repository, and enumerating only its children leaves a vault folder with no sha/name target.
  # Deduplicate on the canonical full path: if -RepoRoots contains $ScanPath, or one root sits
  # inside another, the same repo is enumerated TWICE as two DirectoryInfo objects - and the
  # uniqueness checks below then read one repository as two matches, leaving a uniquely
  # resolvable folder unresolved.
  $candidates = @(
    @(
      foreach ($root in @(@($ScanPath) + @($RepoRoots) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
        if (Test-Path (Join-Path $root '.git')) { Get-Item -LiteralPath $root }
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName '.git') }
      }
    ) | Group-Object { $_.FullName } | ForEach-Object { $_.Group[0] }
  )
  $scopeSha = $null
  foreach ($tx in $texts) {
    # Tolerate a surrounding quote as well as a backtick: `scope: "<sha>..HEAD"` is valid YAML,
    # and Get-VaultData strips it — an intolerant re-parse here fails stage 2 silently and
    # degrades to the stage-3 name guess.
    $sm = [regex]::Match($tx, '(?im)scope:\**\s*[''"`]?([0-9a-f]{7,40})\.\.')
    if ($sm.Success -and ($sm.Groups[1].Value -notmatch '^0+$')) { $scopeSha = $sm.Groups[1].Value; break }
  }
  if ($scopeSha) {
    # Collect ALL matches, not the first: a fork, mirror or worktree also contains the sha, and
    # taking the first enumeration would silently credit the review to whichever sorted earliest.
    $shaMatches = @($candidates | Where-Object {
      & git -C $_.FullName cat-file -e "$scopeSha^{commit}" 2>$null
      $LASTEXITCODE -eq 0
    })
    if ($shaMatches.Count -eq 1) {
      return [pscustomobject]@{ resolved = $true; repoPath = $shaMatches[0].FullName; repoName = $shaMatches[0].Name; subsystemPath = $null }
    }
    if ($shaMatches.Count -gt 1) {
      Write-Warning ("${FolderName}: scope sha $scopeSha resolves in $($shaMatches.Count) repos (" +
        (($shaMatches | ForEach-Object { $_.Name }) -join ', ') + ") — ambiguous, leaving unresolved.")
      return $miss
    }
  }

  # (3) name search — weakest, a plausible guess not a proof. Normalised so 'quickfixn' finds
  # 'quickfix-n'; and now suffix/substring so a PREFIX rename resolves too ('budget-tracker' ->
  # 'personal-budget-tracker'). Staged exact -> suffix -> contains, closest first. The length
  # guard keeps a short folder name from spuriously containing itself in an unrelated repo.
  $want = ($FolderName -replace '[^a-z0-9]', '').ToLowerInvariant()
  if ($want.Length -ge 4) {
    foreach ($mode in 'eq', 'suffix', 'contains') {
      # As with the sha stage above: collect every match and resolve only on a UNIQUE candidate.
      # 'service-app' vs 'ServiceApp' differ only by enumeration order, and silently taking the
      # first is how a review gets credited to the wrong repo.
      $byName = @($candidates | Where-Object {
        $n = ($_.Name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        switch ($mode) {
          'eq'       { $n -eq $want }
          'suffix'   { $want.Length -ge 5 -and $n.EndsWith($want) }
          'contains' { $want.Length -ge 5 -and $n.Contains($want) }
        }
      })
      if ($byName.Count -eq 1) {
        return [pscustomobject]@{ resolved = $true; repoPath = $byName[0].FullName; repoName = $byName[0].Name; subsystemPath = $null }
      }
      if ($byName.Count -gt 1) {
        Write-Warning ("${FolderName}: name search ($mode) matched $($byName.Count) repos (" +
          (($byName | ForEach-Object { $_.Name }) -join ', ') + ") — ambiguous, leaving unresolved.")
        return $miss
      }
    }
  }
  return $miss
}

# Derive the enclosing repo + subsystem sub-path from file:/// walk-up hits. Split out of
# Resolve-VaultTarget so the file-link branch can return early while the sha/name fallbacks stay
# flat below it.
function Get-SubsystemTarget {
  param([string[]]$Paths, [string[]]$Hits)
  $repoPath = ($hits | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
  # Deepest common directory of the linked files, relative to the repo root = the subsystem.
  # The separator boundary is load-bearing: a bare StartsWith($repoPath) also swallows SIBLING
  # repos whose name merely extends this one — e.g. `svc` and `svc-acme`, a pair that links
  # to each other. Without the boundary a sibling's path yields a relative segment like
  # '-acme\src\x.cs', which corrupts the common-prefix walk and the derived subsystem.
  # Separator-agnostic: these paths carry the HOST separator, so a hardcoded '\' made
  # $repoPrefix unmatchable on a POSIX host - every path fell out of $rels and every
  # subsystem collapsed to null, silently turning a subsystem review into a whole-repo one.
  $sep = [IO.Path]::DirectorySeparatorChar
  $repoPrefix = $repoPath.TrimEnd('\', '/') + $sep
  $rels = @($paths | Where-Object {
      $_.Equals($repoPath, [StringComparison]::OrdinalIgnoreCase) -or
      $_.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object { $_.Substring($repoPath.Length).TrimStart('\', '/') } | Where-Object { $_ })
  $sub = $null
  if ($rels) {
    $segs = @($rels | ForEach-Object { , @($_ -split '[\\/]') })
    $common = @()
    for ($i = 0; $i -lt ($segs | ForEach-Object { $_.Count } | Measure-Object -Minimum).Minimum; $i++) {
      $seg = $segs[0][$i]
      if (@($segs | Where-Object { $_[$i] -ne $seg }).Count) { break }
      $common += $seg
    }
    # Drop a trailing file name (a leaf with an extension is not a directory). The leaf must
    # not START with a dot: an unanchored '\.\w+$' also matches a dot-initial DIRECTORY segment
    # ('.github'), and when that is the sole common segment the drop nulls subsystemPath and
    # silently turns a subsystem review into a repo-wide one (links diverging directly beneath
    # '.github/' reach this shape). The Count -gt 1
    # guard is load-bearing: for a single segment, $common[0..($common.Count - 2)] is
    # $common[0..-1], and PowerShell expands 0..-1 to the range 0,-1 — indexing element 0 AND
    # the last element, which DUPLICATES the sole segment instead of dropping it. That yielded
    # subsystemPath='Program.cs\Program.cs' and isSubsystem=$true — a false subsystem, the exact
    # misclassification this function exists to prevent. Reachable whenever a report's only
    # file:/// links point at a repo-root file.
    if ($common.Count -and $common[-1] -notmatch '^\.' -and $common[-1] -match '\.\w+$') {
      $common = if ($common.Count -gt 1) { $common[0..($common.Count - 2)] } else { @() }
    }
    if ($common.Count) { $sub = ($common -join [IO.Path]::DirectorySeparatorChar) }
  }
  [pscustomobject]@{
    resolved = $true; repoPath = $repoPath
    repoName = (Split-Path $repoPath -Leaf); subsystemPath = $sub
  }
}

function Get-ValidatedSubsystemScope {
  param([string]$RepoPath, [string[]]$Paths)
  $paths = @($Paths | Where-Object { $_ })
  if (-not $paths.Count) { return [pscustomobject]@{ paths = @(); validation = 'none' } }
  foreach ($pathspec in $paths) {
    $tracked = @(& git -C $RepoPath ls-files -- $pathspec 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $tracked.Count) {
      return [pscustomobject]@{ paths = $paths; validation = 'invalid' }
    }
  }
  return [pscustomobject]@{ paths = $paths; validation = 'valid' }
}

# Compute the git side (review commits, boundary, forward scope) for a repo working tree.
# Used for both in-path repos and resolved vault-only targets, so remediation is detectable
# in BOTH cases — an outsideScanPath row must never be silently unfalsifiable.
function Get-VaultBoundary {
  param([string]$RepoPath, $Vault)
  foreach ($evidence in @($Vault.reviewTarget, $Vault.reviewScope) | Where-Object { $_ }) {
    # A single commit names the reviewed tip; a range must have two valid commit endpoints.
    # Symbolic HEAD is allowed only on the right, but a day-only record cannot make it exact.
    # Use the immutable validated base as a conservative cutoff. Surrounding prose falls back.
    $match = [regex]::Match($evidence, '(?i)^\s*(?:`|\*\*)?([0-9a-f]{7,40})(?:\.\.([0-9a-f]{7,40}|HEAD))?(?:`|\*\*)?\s*$')
    if (-not $match.Success) { continue }
    $base = $match.Groups[1].Value
    if ($match.Groups[2].Success) {
      & git -C $RepoPath cat-file -e "$base^{commit}" 2>$null
      if ($LASTEXITCODE -ne 0) { continue }
    }
    $tip = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { $base }
    if ($tip -ieq 'HEAD') {
      $resolvedBase = & git -C $RepoPath rev-parse "$base^{commit}" 2>$null
      if ($LASTEXITCODE -eq 0 -and $resolvedBase) {
        return [pscustomobject]@{ sha = "$resolvedBase".Trim(); source = 'vault-symbolic-base' }
      }
      continue
    }
    & git -C $RepoPath cat-file -e "$tip^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }
    $resolved = & git -C $RepoPath rev-parse "$tip^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $resolved) {
      return [pscustomobject]@{ sha = "$resolved".Trim(); source = 'vault-target' }
    }
  }
  return $null
}

function Get-GitSide {
  param([string]$RepoPath, $Vault, [string]$MarkerRegex, [string]$WebQualityRegex, [string[]]$SubsystemPaths, [string]$ScopeValidation = 'none')
  if ($ScopeValidation -eq 'invalid') {
    return [pscustomobject]@{
      reviewCommits = @(); lastReviewDate = $Vault.date; batchMarkers = @()
      boundarySha = $null; boundarySource = 'invalid-subsystem-scope'; vaultPredatesHistory = $false
      neverReviewed = $false; effectiveNeverReviewed = $false; sinceReview = @()
      sinceReviewCount = $null; sinceReviewFiles = $null; sinceReviewIns = $null; sinceReviewDel = $null
      daysSinceReview = $null
    }
  }
  # When the review covered a SUBSYSTEM, every evidence query must be scoped to it by pathspec.
  # Otherwise the host repo's unrelated activity is attributed to the subsystem: widgetservice would
  # report all 977 of host-app's post-boundary commits as WidgetService work, and any unrelated
  # reviewer-findings commit elsewhere in the host would read as WidgetService remediation. Detecting
  # remediation is worthless if the number attached to it is the wrong repo's.
  $pathspec = @()
  if ($SubsystemPaths.Count) { $pathspec = @('--') + @($SubsystemPaths) }
  # One git call: full log with body, ISO date, and author trailers, NUL-delimited records.
  $fmt = '%H%x1f%cI%x1f%s%x1f%b%x1e'
  $raw = & git -C $RepoPath log HEAD "--format=$fmt" @pathspec 2>$null
  if ($LASTEXITCODE -ne 0) { $raw = '' }
  $records = ($raw -join "`n") -split "`u{1e}" | Where-Object { $_.Trim() }

  $reviewCommits = foreach ($rec in $records) {
    $parts = $rec -split "`u{1f}"
    $sha = $parts[0].Trim(); $date = $parts[1].Trim(); $subject = $parts[2].Trim(); $body = if ($parts.Count -gt 3) { $parts[3] } else { '' }
    $hasReviewTrailer = $body -match "(?im)$strictReviewTrailerRegex"
    if ($subject -notmatch $MarkerRegex -and -not $hasReviewTrailer) { continue }
    $fixer = ''
    $m = [regex]::Match("$body", '(?im)^Co-Authored-By:\s*([^<]+?)\s*<')
    if ($m.Success) { $fixer = $m.Groups[1].Value.Trim() }
    $dateShort = if ($date.Length -ge 10) { $date.Substring(0,10) } else { $date }
    [pscustomobject]@{ sha = $sha; date = $dateShort; subject = $subject; body = $body.Trim(); fixerModel = $fixer }
  }
  $reviewCommits = @($reviewCommits | Group-Object sha | ForEach-Object { $_.Group[0] })

  # Strict numbered review batch/run evidence from subjects or trailers.
  $batchMarkers = @($reviewCommits | ForEach-Object {
    $bm = [regex]::Match($_.subject, "(?i)$strictReviewEvidenceRegex")
    if ($bm.Success) { $bm.Value }
    else {
      $tm = [regex]::Match($_.body, "(?im)$strictReviewTrailerRegex")
      if ($tm.Success) { $tm.Value }
    }
  } | Group-Object { ($_ -replace '\s+','').ToLowerInvariant() } | ForEach-Object { $_.Group[0] })

  # Boundary selection — the last point a genuine ADVERSARIAL review saw this tree.
  # Priority: (1) the vault adversarial-review date; (2) the newest non-web-quality git
  # review/remediation commit. A web-quality reviewer-findings commit never anchors the boundary.
  $boundarySha = $null; $lastReviewDate = $null; $boundarySource = 'none'; $vaultPredatesHistory = $false
  $targetBoundary = $null
  if ($Vault.exists) {
    $targetBoundary = Get-VaultBoundary -RepoPath $RepoPath -Vault $Vault
    if ($targetBoundary) {
      $boundarySha = $targetBoundary.sha; $lastReviewDate = $Vault.date; $boundarySource = $targetBoundary.source
    } elseif ($Vault.date) {
      # Tree the panel reviewed = last commit at/before the review's RUN time, not its day.
      # A day-granular `--until "<date> 23:59:59"` sweeps in commits that landed AFTER the
      # review on the same day and reports unreviewed work as reviewed. The run-folder name
      # is a sortable UTC timestamp (20260528T221207Z); when it does not parse, anchor at the
      # last commit BEFORE the reported day — conservative in the unreviewed-work direction.
      $until = "$($Vault.date) 00:00:00"
      if ($Vault.runName -match '^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$') {
        $until = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6]) +0000"
      }
      $bs = & git -C $RepoPath log --until="$until" -1 --format='%H' @pathspec 2>$null
      $bsExit = $LASTEXITCODE
      if ($bsExit -eq 0 -and $bs -and "$bs".Trim()) {
        $boundarySha = "$bs".Trim(); $lastReviewDate = $Vault.date; $boundarySource = 'vault-date'
      } elseif ($pathspec.Count -gt 0) {
      # SCOPED query. An empty result here does NOT mean the review predates history - it
      # usually means the subsystem was added after the review date, and a non-zero exit
      # means the pathspec is bad. Falling through to the repo-root anchor would set
      # neverReviewed=false and report an unreviewed (or malformed) scope as reviewed, which
      # is the whole failure this subsystem scoping exists to prevent. Leave it unreviewed.
        $boundarySource = if ($bsExit -ne 0) { 'scoped-query-failed' } else { 'scoped-no-history-before-review' }
        $lastReviewDate = $Vault.date
      } else {
      # Vault review predates the repo's earliest commit (e.g. an OSS re-init history squash):
      # the whole current tree is adversarially unreviewed. The root commit only MARKS that —
      # the disjunction below classes vault-predates-history as effectively never reviewed and
      # clears the boundary, so the scope is full history. Anchoring the boundary at the root
      # commit instead would omit everything the squash introduced (rootSha..HEAD excludes the
      # root) while reporting neverReviewed=false. Repo-wide only - see the scoped branch above.
        $rootSha = & git -C $RepoPath rev-list --max-parents=0 HEAD 2>$null | Select-Object -First 1
        if ($rootSha) { $boundarySha = "$rootSha".Trim() }
        $lastReviewDate = $Vault.date; $boundarySource = 'vault-predates-history'; $vaultPredatesHistory = $true
      }
    }
  }
  if (-not $Vault.exists -or (-not $targetBoundary -and -not $Vault.date)) {
    # No vault report: fall back to git markers, excluding web-quality sweeps from boundary candidacy.
    $adversarialCommits = @($reviewCommits | Where-Object { $_.subject -notmatch $WebQualityRegex })
    $lastReviewCommit = if ($adversarialCommits) { $adversarialCommits | Sort-Object date -Descending | Select-Object -First 1 } else { $null }
    if ($lastReviewCommit) { $boundarySha = $lastReviewCommit.sha; $lastReviewDate = $lastReviewCommit.date; $boundarySource = 'git-marker' }
  }
  $neverReviewed = [bool](-not $boundarySha)
  # Effectively-never-reviewed has three roads in: no boundary at all; a vault report older than
  # the repo's own history (the squash above — nothing the panel saw survives in this tree); and
  # a git marker with no strict numbered batch/run evidence. All three mean the honest scope is
  # the full history, so the false boundary is cleared and neverReviewed set.
  $effectiveNeverReviewed = [bool]($neverReviewed -or $vaultPredatesHistory -or ($boundarySource -eq 'git-marker' -and -not $batchMarkers.Count))
  if ($effectiveNeverReviewed -and ($boundarySource -eq 'git-marker' -or $boundarySource -eq 'vault-predates-history')) { $boundarySha = $null; $neverReviewed = $true }

  # Forward-looking scope: commits since the last review (the next review's candidate scope).
  $sinceReview = @(); $sinceFiles = 0; $sinceIns = 0; $sinceDel = 0; $sinceCount = 0
  if ($boundarySha) {
    $rangeFmt = '%H%x1f%cI%x1f%s%x1e'
    $rawSince = & git -C $RepoPath log "$boundarySha..HEAD" "--format=$rangeFmt" @pathspec 2>$null
    if ($LASTEXITCODE -eq 0 -and $rawSince) {
      $srecs = ($rawSince -join "`n") -split "`u{1e}" | Where-Object { $_.Trim() }
      $sinceReview = @(foreach ($rec in $srecs) {
        $p = $rec -split "`u{1f}"
        $sd = $p[1].Trim(); $sd = if ($sd.Length -ge 10) { $sd.Substring(0,10) } else { $sd }
        [pscustomobject]@{ sha = $p[0].Trim(); date = $sd; subject = $p[2].Trim() }
      })
      # The diff is its own git call with its own exit code. Unchecked, a failure here
      # left the three counters at their 0 seed, and "0 files changed since review" is a
      # statement a reader acts on - it reads as a scope that has not moved. Null is the
      # honest value for a stat that could not be taken.
      $stat = & git -C $RepoPath diff --shortstat "$boundarySha..HEAD" @pathspec 2>$null
      if ($LASTEXITCODE -ne 0) {
        $sinceFiles = $null; $sinceIns = $null; $sinceDel = $null
      }
      elseif ($stat) {
        $statStr = "$stat"
        $fm2 = [regex]::Match($statStr, '(\d+) files? changed'); if ($fm2.Success) { $sinceFiles = [int]$fm2.Groups[1].Value }
        $im2 = [regex]::Match($statStr, '(\d+) insertion');      if ($im2.Success) { $sinceIns   = [int]$im2.Groups[1].Value }
        $dm3 = [regex]::Match($statStr, '(\d+) deletion');       if ($dm3.Success) { $sinceDel   = [int]$dm3.Groups[1].Value }
      }
    }
    $sinceCount = $sinceReview.Count
  } else {
    # Never reviewed: don't dump the whole history — record full-scope commit count only.
    $rc = & git -C $RepoPath rev-list --count HEAD @pathspec 2>$null
    if ($LASTEXITCODE -eq 0 -and $rc) { $sinceCount = [int]("$rc".Trim()) }
    # Same reasoning as the stat above: a failed count is not a count of zero. Overdue
    # ranking is unaffected because neverReviewed already forces this repo overdue on
    # its own; what changes is that the report stops asserting a number it does not have.
    elseif ($LASTEXITCODE -ne 0) { $sinceCount = $null }
  }

  # Staleness in whole days (script clock; report is day-granular). SKILL.md contracts this as
  # null when never reviewed — a lastReviewDate can survive on a never-reviewed row (a cleared
  # git-marker, a vault report that predates the history), and a number there would dress up an
  # unreviewed repo as freshly reviewed. ISO parse is exact and culture-invariant (see above).
  $daysSinceReview = $null
  if ($lastReviewDate -and -not $neverReviewed) {
    [datetime]$lrd = [datetime]::MinValue
    if ([datetime]::TryParseExact($lastReviewDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$lrd)) {
      $daysSinceReview = [int]((Get-Date).Date - $lrd.Date).TotalDays
    }
  }

  [pscustomobject]@{
    reviewCommits   = $reviewCommits
    lastReviewDate  = $lastReviewDate
    batchMarkers    = $batchMarkers
    boundarySha     = $boundarySha
    boundarySource  = $boundarySource
    vaultPredatesHistory = $vaultPredatesHistory
    neverReviewed   = $neverReviewed
    effectiveNeverReviewed = $effectiveNeverReviewed
    sinceReview     = $sinceReview
    sinceReviewCount = $sinceCount
    sinceReviewFiles = $sinceFiles
    sinceReviewIns  = $sinceIns
    sinceReviewDel  = $sinceDel
    daysSinceReview = $daysSinceReview
  }
}

# Does the repo (or, for a subsystem row, its reviewed sub-path) track any source file? A repo
# with ZERO tracked source — a docs/spec repo (engineering-system), a playbook repo (qa), a CV
# repo (personal-resumes) — is not code-reviewable, so the never-reviewed floor of 100 must not
# float it above a genuinely unreviewed code repo. Exposed as hasTrackedSource; SKILL.md §4 voids
# the floor when false. Tri-state: $null means the ls-files probe itself FAILED (not a repo, bad
# pathspec, timeout) — that is UNKNOWN, never a verified "no source", and consumers must not read
# it as $false (review-sweep's runbook STOPs on unknown). When a SubsystemPath is given the query
# is pathspec-scoped to it, so a docs-only subsystem of a code-bearing host is not credited with
# the host's unrelated source.
$sourceExtRegex = '(?:\.(cs|ts|tsx|js|jsx|mjs|cjs|py|go|java|rb|rs|cpp|cc|c|h|hpp|kt|swift|php|scala|sql|ps1|psm1|sh|bicep|vue|svelte|fs|fsx|razor|cshtml|xaml|tf|proto|css|scss|sass|less)$|(?:^|/)Dockerfile(?:\..+)?$|(?:^|/)\.github/workflows/[^/]+\.ya?ml$)'
function Get-HasTrackedSource {
  param([string]$RepoPath, [string[]]$SubsystemPaths, [string]$ScopeValidation = 'none')
  if (-not $RepoPath) { return $false }
  if ($ScopeValidation -eq 'invalid') { return $null }
  $pathspec = if ($SubsystemPaths.Count) { @('--') + @($SubsystemPaths) } else { @() }
  # Materialise before filtering: Select-Object -First 1 can short-circuit the
  # native pipeline and make LASTEXITCODE unreliable on the success path.
  $out = @(& git -C $RepoPath ls-files @pathspec 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  return [bool](@($out | Where-Object { $_ -match $sourceExtRegex }).Count)
}

$results = foreach ($r in $repos) {
  $repoPath = $r.FullName
  # Vault first — its adversarial-review date is the preferred boundary (the tree a panel saw).
  $vault = Get-VaultData -RepoName $r.Name -VaultRoot $VaultRoot
  $scope = Get-ValidatedSubsystemScope -RepoPath $repoPath -Paths $vault.subsystemPaths
  # Scope the git side to the reviewed subsystem when the review declared one. Calling
  # this without -SubsystemPaths was what made a subsystem pass look repo-wide.
  $git = Get-GitSide -RepoPath $repoPath -Vault $vault -MarkerRegex $markerRegex -WebQualityRegex $webQualityRegex -SubsystemPaths $scope.paths -ScopeValidation $scope.validation

  [pscustomobject]@{
    repo = $r.Name
    git  = $git
    vault = $vault
    hasGraphify = [bool](Test-Path (Join-Path $repoPath 'graphify-out'))
    hasTrackedSource = Get-HasTrackedSource -RepoPath $repoPath -SubsystemPaths $scope.paths -ScopeValidation $scope.validation
    outsideScanPath = $false
    resolvedPath = $repoPath
    isSubsystem = [bool]$scope.paths.Count
    subsystemPath = if ($scope.paths.Count -eq 1) { $scope.paths[0] } else { $null }
    subsystemPaths = @($scope.paths)
    scopeValidation = $scope.validation
    unresolved = $false
  }
}

# Vault review folders with no matching repo under $Path. A folder here is NOT proof of a
# repo — it may name a SUBSYSTEM of one. Resolve each to real code via its report's file:///
# links and compute a genuine git side against that repo, so remediation is DETECTABLE.
# Anything that will not resolve is emitted as unresolved=true, never as a silent frozen row.
$scanned = @($results | ForEach-Object { $_.repo })
if (Test-Path $VaultRoot) {
  # Newest REVIEW first, not newest folder mtime: the dedup below keeps the first-emitted row
  # per repo+subsystem, and LastWriteTime is copy/mtime order, not review order — copying an old
  # folder into the vault refreshes its mtime and would let a stale duplicate of a renamed repo
  # win over the folder carrying the newest review. Order by the review's frontmatter date
  # (then the sortable run-folder timestamp), file time only when a run declares no date.
  $vaultOnly = @(
    foreach ($v in (Get-ChildItem $VaultRoot -Directory | Where-Object { $scanned -notcontains $_.Name })) {
      $vd = Get-VaultData -RepoName $v.Name -VaultRoot $VaultRoot
      if (-not $vd.exists) { continue }
      [pscustomobject]@{ Folder = $v; Data = $vd }
    }
  )
  $vaultOnly = @($vaultOnly | Sort-Object -Descending `
    @{ Expression = { if ($_.Data.date) { $_.Data.date } else { '' } } }, `
    @{ Expression = { $_.Data.runName } }, `
    @{ Expression = { $_.Folder.LastWriteTime } })
  # Track outside targets already emitted THIS pass, keyed on repo + subsystem, so two differently
  # named vault folders resolving to the same outside repo (a de-hyphen + a suffix match, or an old
  # and a current folder) do not both emit and double-count it. Distinct subsystems of one host
  # stay distinct (the key includes the sub-path).
  $resolvedThisPass = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $extra = @(foreach ($entry in $vaultOnly) {
    $v = $entry.Folder
    $vd = $entry.Data
    $target = Resolve-VaultTarget -IndexPath $vd.indexPath -FolderName $v.Name -RepoRoots $RepoRoots -ScanPath $Path
    if ($target.resolved) {
      # A WHOLE-REPO resolution (no subsystemPath) onto an already-scanned in-path repo is a stale
      # pre-rename duplicate (budget-tracker -> personal-budget-tracker): drop it — but if that
      # in-path row carries no vault of its own, backfill it first, so a repo whose ONLY review lives
      # under the old folder name is not left falsely never-reviewed. A resolution WITH a
      # subsystemPath is a DISTINCT subsystem of that host and must still emit its own row.
      if (-not $target.subsystemPath) {
        # Match on the resolved absolute path, not the leaf name: two same-named repos at
        # different depths of $Path are distinct, and a leaf-name key conflates them.
        $inPath = $results | Where-Object { -not $_.outsideScanPath -and $_.resolvedPath -eq $target.repoPath } | Select-Object -First 1
        if ($inPath) {
          if (-not $inPath.vault.exists -and $vd.exists) {
            # Carry the declared scope through the backfill too. Without it a scope resolved
            # by SHA or name silently became a repo-wide scan on this path only, so the row
            # reported a boundary the panel never established.
            $inPath.vault = $vd
            $scope = Get-ValidatedSubsystemScope -RepoPath $inPath.resolvedPath -Paths $vd.subsystemPaths
            $inPath.git = Get-GitSide -RepoPath $inPath.resolvedPath -Vault $vd -MarkerRegex $markerRegex -WebQualityRegex $webQualityRegex -SubsystemPaths $scope.paths -ScopeValidation $scope.validation
            $inPath.hasTrackedSource = Get-HasTrackedSource -RepoPath $inPath.resolvedPath -SubsystemPaths $scope.paths -ScopeValidation $scope.validation
            $inPath.isSubsystem = [bool]$scope.paths.Count
            $inPath.subsystemPath = if ($scope.paths.Count -eq 1) { $scope.paths[0] } else { $null }
            $inPath.subsystemPaths = @($scope.paths)
            $inPath.scopeValidation = $scope.validation
          }
          continue
        }
      }
      # Second (and later) vault folder resolving to the same outside repo+subsystem: skip. Key on
      # the canonical repoPath (not the leaf repoName) so two same-named repos under different
      # -RepoRoots are not wrongly merged. $vaultOnly was sorted newest-first above, so the row
      # that survives this dedup is the folder with the newest review.
      # One effective scope from the two sources: what the report DECLARED (`subsystem:` /
      # an `audit -- <pathspec>` target) and what its file:/// links RESOLVED to. The
      # declaration wins - it is the panel's own statement of scope - but a disagreement is
      # surfaced rather than silently resolved, because one of the two is then wrong about
      # what was reviewed.
      # Normalise before comparing: Get-SubsystemTarget joins with the host separator while a
      # declared `subsystem:` key or an `audit -- <pathspec>` target uses forward slashes
      # (git pathspecs always do). Comparing raw strings reported 'src/Foo' and 'src\Foo' as a
      # disagreement and keyed the dedup set on both, emitting two rows for one subsystem.
      $normScope = { param($s) if ($s) { ($s -replace '[\\/]+', '/').Trim('/') } else { $s } }
      $effectiveSubsystems = if ($vd.subsystemPaths.Count) { @($vd.subsystemPaths) } elseif ($target.subsystemPath) { @($target.subsystemPath) } else { @() }
      if ($vd.subsystemPaths.Count -eq 1 -and $target.subsystemPath -and
          ((& $normScope $vd.subsystemPaths[0]) -ne (& $normScope $target.subsystemPath))) {
        Write-Warning "$($v.Name): declared subsystem '$($vd.subsystemPaths[0])' disagrees with the scope its report links resolve to ('$($target.subsystemPath)'); using the declared value."
      }
      $normalisedScope = @($effectiveSubsystems | ForEach-Object { & $normScope $_ }) -join ','
      if (-not $resolvedThisPass.Add("$($target.repoPath)|$normalisedScope")) { continue }
      $scope = Get-ValidatedSubsystemScope -RepoPath $target.repoPath -Paths $effectiveSubsystems
      $git = Get-GitSide -RepoPath $target.repoPath -Vault $vd -MarkerRegex $markerRegex -WebQualityRegex $webQualityRegex -SubsystemPaths $scope.paths -ScopeValidation $scope.validation
      [pscustomobject]@{
        repo = $v.Name
        git  = $git
        vault = $vd
        hasGraphify = [bool](Test-Path (Join-Path $target.repoPath 'graphify-out'))
        hasTrackedSource = Get-HasTrackedSource -RepoPath $target.repoPath -SubsystemPaths $scope.paths -ScopeValidation $scope.validation
        outsideScanPath = $true
        resolvedPath = $target.repoPath
        # A SUBSYSTEM row is one whose reviewed code is a sub-path of the host repo
        # (widgetservice = host-app/Framework/Services/WidgetService). A mere name variance
        # (vault 'quickfixn' -> repo 'quickfix-n') is NOT a subsystem — same tree, so
        # keying this off the sub-path rather than the name keeps the two apart.
        isSubsystem = [bool]$scope.paths.Count
        subsystemPath = if ($scope.paths.Count -eq 1) { $scope.paths[0] } else { $null }
        subsystemPaths = @($scope.paths)
        scopeValidation = $scope.validation
        unresolved = $false
      }
    } else {
      [pscustomobject]@{
        repo = $v.Name
        git  = [pscustomobject]@{
          reviewCommits = @(); lastReviewDate = $vd.date; batchMarkers = @()
          boundarySha = $null; boundarySource = 'unresolved-vault-folder'; vaultPredatesHistory = $false
          # neverReviewed stays $false DESPITE the null boundarySha, and the exception is
          # deliberate. Elsewhere a null boundary means "no review ever happened"; here a review
          # demonstrably DID happen (vault.exists) — we simply cannot place the code it covered.
          # Flagging it $true would assert a falsehood and, worse, score it 100 + commits, floating
          # an unknown straight to the top of the risk rank. The state is UNKNOWN, not "never".
          # SKILL.md qualifies the neverReviewed contract accordingly and excludes unresolved rows
          # from ranking outright.
          neverReviewed = $false; effectiveNeverReviewed = $false; sinceReview = @()
          sinceReviewCount = 0; sinceReviewFiles = 0; sinceReviewIns = 0; sinceReviewDel = 0
          daysSinceReview = $null
        }
        vault = $vd
        hasGraphify = $false
        hasTrackedSource = $false
        outsideScanPath = $true
        resolvedPath = $null
        isSubsystem = $false
        subsystemPath = $null
        subsystemPaths = @()
        scopeValidation = 'unknown'
        unresolved = $true
      }
    }
  })
  $results = @($results) + @($extra)
}

# A DOCUMENT review (resumes-cv: target your-cv.html) that resolves to no code repo
# is EXPECTED to be unresolved — it reviewed a CV, not a tree — so it is not a collector defect and
# must not share the unfalsifiable-tally warning. Split the two so a genuine resolution failure
# (a code review whose repo could not be placed) still stands out.
$unresolvedRows = @($results | Where-Object { $_.unresolved -and -not $_.vault.isDocumentReview })
$docReviewRows  = @($results | Where-Object { $_.unresolved -and $_.vault.isDocumentReview })
$invalidScopeRows = @($results | Where-Object { $_.scopeValidation -eq 'invalid' })
if ($unresolvedRows) {
  Write-Warning ("UNRESOLVED vault folders (no repo found via file:/// links, scope sha, or name) — " +
    "their tallies are UNFALSIFIABLE and must NOT be reported as outstanding: " +
    (($unresolvedRows | ForEach-Object { $_.repo }) -join ', '))
}
if ($docReviewRows) {
  Write-Warning ("DOCUMENT reviews (reviewed a document, NOT code — confer no code coverage, do not " +
    "credit as a reviewed repo): " +
    (($docReviewRows | ForEach-Object { "$($_.repo) [$($_.vault.reviewTarget)]" }) -join ', '))
}
if ($invalidScopeRows) {
  Write-Warning ("INVALID subsystem scope (declared pathspec matched no tracked files) — " +
    "Git and source evidence is UNKNOWN: " +
    (($invalidScopeRows | ForEach-Object { "$($_.repo) [$(@($_.subsystemPaths) -join ', ')]" }) -join ', '))
}

$results | ConvertTo-Json -Depth 8 | Set-Content $OutFile -Encoding utf8
Write-Output "wrote $OutFile ($(@($results).Count) repos)"
