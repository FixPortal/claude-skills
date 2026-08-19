$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$main = Get-Content (Join-Path $root 'SKILL.md') -Raw
$words = ([regex]::Matches($main, '\b[\p{L}\p{N}][\p{L}\p{N}''.-]*\b')).Count

if ($words -gt 500) { throw "SKILL.md is $words words; templates and reference detail belong in references" }
if ($main -match 'document this estate/system') { throw 'broad architecture trigger still overlaps document-architecture' }
foreach ($needle in 'supplied findings or content', 'Do not use for discovering, mapping, or analyzing', 'document-architecture') {
    if ($main -notmatch [regex]::Escape($needle)) { throw "missing selector boundary: $needle" }
}

foreach ($name in 'conventions.md','templates.md','report-shape.md','common-mistakes.md') {
    if (-not (Test-Path (Join-Path $root "references" "$name"))) { throw "missing reference: $name" }
    # The SKILL.md -> references/ split left "above"/"below" pointers behind in files where
    # the target no longer sits above or below anything - the sub-templates moved to
    # templates.md. A deictic reference across a file boundary can only ever be wrong, so
    # they must be real links.
    $refText = Get-Content (Join-Path $root 'references' $name) -Raw
    foreach ($dangling in 'sub-template\*? below', 'sub-templates above', '§\*README sub-template\*') {
        if ($refText -match $dangling) { throw "references/$name has a dangling cross-file pointer: $dangling" }
    }
}

foreach ($needle in 'Choose the destination first', 'Core conventions', 'Compact checklist') {
    if ($main -notmatch [regex]::Escape($needle)) { throw "main router missing: $needle" }
}

$conventions = Get-Content (Join-Path $root 'references' 'conventions.md') -Raw
$mistakes = Get-Content (Join-Path $root 'references' 'common-mistakes.md') -Raw
$templates = Get-Content (Join-Path $root 'references' 'templates.md') -Raw
$reportShape = Get-Content (Join-Path $root 'references' 'report-shape.md') -Raw
$docs = $main, $conventions, $mistakes, $templates, $reportShape

if (($docs -join "`n") -match '(?i)without tags? (?:are|is) invisible in (?:the )?Obsidian graph view') {
    throw 'scaffold-doc must not claim that untagged notes are invisible in Obsidian Graph view'
}
if (($docs -join "`n") -match '(?i)(?:standalone )?GitHub(?:-only)? README may (?:use|retain) frontmatter') {
    throw 'scaffold-doc must not recommend YAML frontmatter for an ordinary GitHub README'
}
if ($conventions -notmatch '(?i)untagged notes .* graph') {
    throw 'conventions must state that untagged notes remain visible in Graph view'
}
if ($conventions -notmatch '(?is)ordinary GitHub README .* do not' -or
    $conventions -notmatch '(?is)omit it there') {
    throw 'conventions must scope frontmatter to destinations that consume it'
}
foreach ($guide in $conventions, $mistakes) {
    foreach ($needle in 'tags alone do not decide visibility', 'Graph Search', 'tag filter', 'Orphans toggle', 'excluded-file patterns') {
        if ($guide -notmatch "(?is)$([regex]::Escape($needle))") {
            throw "scaffold-doc must describe the Obsidian visibility control: $needle"
        }
    }
}
if ($reportShape -notmatch '(?is)parser-backed\s+destination') {
    throw 'report shape must make the frontmatter skeleton conditional on a parser-backed destination'
}
if ($reportShape -notmatch '(?is)ordinary repo/GitHub reports .* omit .* frontmatter') {
    throw 'report shape must omit frontmatter for ordinary repo/GitHub reports'
}

"scaffold-doc contract OK — $words words"
