$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw
$root = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$scaffoldRoot = Join-Path $root 'scaffold-ci'
$scaffoldSkill = Get-Content (Join-Path $scaffoldRoot 'SKILL.md') -Raw
$ciContract = Get-Content (Join-Path $scaffoldRoot 'references' 'ci-workflow.md') -Raw
$securityContract = Get-Content (Join-Path $scaffoldRoot 'references' 'dependencies-and-security.md') -Raw
$secretSweep = Get-Content (Join-Path $scaffoldRoot 'assets' 'secret-sweep.yml') -Raw

# audit-ci consumes the shipped scaffold contract; it must not retain a second,
# independently-maintained baseline that will drift when scaffold-ci changes.
foreach ($reference in 'scaffold-ci/SKILL.md',
                       'scaffold-ci/references/ci-workflow.md',
                       'scaffold-ci/references/dependencies-and-security.md',
                       'scaffold-ci/assets/secret-sweep.yml') {
    if ($text -notmatch [regex]::Escape($reference)) {
        throw "SKILL.md must reference the authoritative scaffold-ci contract: $reference"
    }
}

if ($scaffoldSkill -notmatch [regex]::Escape('The ten control surfaces are')) {
    throw 'scaffold-ci no longer declares the control-surface baseline audit-ci consumes'
}
if ($ciContract -notmatch '(?s)push.*mainline.*tags `v\*`') {
    throw 'scaffold-ci no longer declares the narrow mainline-and-tag push baseline'
}
if ($secretSweep -notmatch 'actions/checkout@[0-9a-f]{40}\s+# v7') {
    throw 'scaffold-ci secret-sweep no longer carries the reviewed first-party SHA-pin exception'
}
$privateGateMatch = [regex]::Match($securityContract, '(?s)### The gate.*?```yaml\r?\n(?<yaml>.*?)\r?\n```')
if (-not $privateGateMatch.Success) {
    throw 'scaffold-ci private secret gate snippet is missing'
}
$privateGate = $privateGateMatch.Groups['yaml'].Value
if ($privateGate -notmatch '(?m)^\s*- uses: actions/checkout@v7$') {
    throw 'scaffold-ci private secret gate must use the house first-party checkout tag'
}
if ($privateGate -match 'actions/checkout@[0-9a-f]{40}') {
    throw 'scaffold-ci private secret gate incorrectly duplicates the sweep-only SHA-pin exception'
}

$secretSweepSurface = [regex]::Match($text, '(?m)^\| \*\*Secret scanning\*\* \|.*$')
if (-not $secretSweepSurface.Success) {
    throw 'audit-ci does not explicitly audit secret-sweep.yml as a scaffold control surface'
}
foreach ($needle in 'scaffold-ci/assets/secret-sweep.yml',
                    'scaffold-ci/references/dependencies-and-security.md',
                    'trigger',
                    'pin',
                    'detector',
                    'install') {
    if ($secretSweepSurface.Value -notmatch [regex]::Escape($needle)) {
        throw "audit-ci secret-scanning surface must delegate its $needle contract to scaffold-ci"
    }
}

foreach ($needle in 'push to mainline + tags `v*`',
                    'reviewed exception',
                    'blacksmith-<N>vcpu-ubuntu-2404') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md missing current scaffold-ci guidance: $needle"
    }
}

# Blacksmith guidance verified against docs.blacksmith.sh/blacksmith-caching/docker-builds
# on 2026-08-03. Each forbidden string below was factually wrong at that date.
foreach ($pattern in 'setup-docker-builder@<full-commit-sha> # v1',
                     'blacksmith-<N>vcpu-ubuntu-2204',
                     'Do not assume a\s+vendor-specific notes path') {
    if ($text -match $pattern) {
        throw "SKILL.md carries guidance refuted by the vendor docs: $pattern"
    }
}

# `max-cache-size-mb` does not exist as an input. The name may still appear, but ONLY
# on a line that marks it as refuted — never as a recommendation or a drift check.
$lines = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md')
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'max-cache-size-mb' -and
        $lines[$i] -notmatch 'invented|corrected|refuted|does not exist') {
        throw "SKILL.md line $($i + 1) treats max-cache-size-mb as real: $($lines[$i].Trim())"
    }
}

# cache-key is a REQUIRED input on setup-docker-builder and appears in every
# official @v2 example; the swap table must carry it.
foreach ($needle in 'cache-key',
                    'setup-docker-builder@<full-commit-sha> # v2',
                    '~/.agents/notes/deploy-and-ci-traps.md',
                    'time-based garbage collection') {
    if ($text -notmatch [regex]::Escape($needle)) {
        throw "SKILL.md missing corrected Blacksmith guidance: $needle"
    }
}

'audit-ci Blacksmith guidance OK'
